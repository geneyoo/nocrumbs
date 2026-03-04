# NoCrumbs Architecture

> Detailed architecture reference. Auto-updated via `/sync-docs`.

## Data Flow

```
Claude Code hooks (unified event + legacy dual-hook)
    ↓ Any hook event              ↓ Legacy: UserPromptSubmit / PostToolUse
nocrumbs event                nocrumbs capture-prompt / capture-change
    ↓ stdin JSON parsing         ↓ stdin JSON parsing
    ↓ session_id links prompts to file changes
    └──────────┬───────────────┘
               ↓ JSON via Unix domain socket or TCP (remote)
    NoCrumbs.app SocketServer (POSIX, actor — Unix + TCP listeners)
               ↓
    Database.shared (raw SQLite3 C API, WAL mode)
               ↓ @Observable properties (in-memory cache)
    SwiftUI Views (time-grouped sidebar, diff detail, session summary)
               ↓ on-demand
    git/hg CLI via Process (derive diffs, never store them)
               ↓
    DiffParser → [FileDiff] → side-by-side line pairs
               ↓
    DiffTextView (NSTextView via NSViewRepresentable)

Commit annotation:
    git prepare-commit-msg hook
        → nocrumbs annotate-commit $1
            → query-prompts via socket (request/response)
            → response includes content toggles (show_prompt_list, show_file_count_per_prompt,
              show_session_id, deep_link_enabled) read from UserDefaults
            → if active template: render with TemplateRenderer
            → else: use built-in default format
            → append to commit message
            → respects annotation_enabled + granular content toggles from app

File descriptions:
    nocrumbs describe (stdin JSON: session_id + [{file_path, description}])
        → socket fire-and-forget to app
        → app updates fileChanges.description column for matching session + path

Deep links:
    nocrumbs://session/{8-char-id}[/event/{uuid}]
        → registered via CFBundleURLTypes in Info.plist
        → AppDelegate handles Apple URL event → DeepLinkRouter.shared
        → ContentView consumes pending navigation on appear

Session export:
    SessionSummaryView → copy to clipboard (markdown)
        → SessionMarkdownFormatter builds structured markdown
        → includes per-file descriptions when available

Template management:
    nocrumbs template add/list/set/remove/preview
        → socket request/response to app
        → app stores templates in commitTemplates table
        → Settings UI shows templates, click to activate, right-click to delete

Remote dev server:
    nocrumbs setup-remote <host> (run from Mac)
        → scp CLI binary to remote ~/.local/bin/nocrumbs
        → ssh: set NOCRUMBS_HOST=localhost in remote shell profile
        → ssh: nocrumbs install --remote (configures Claude Code hooks)
        → local: add RemoteForward 19876 to ~/.ssh/config
        → local: defaults write remoteTCPPort 19876 (enable TCP listener)
        → Remote CLI → localhost:19876 → SSH RemoteForward → Mac TCP listener → SocketServer
```

## Directory Structure

```
NoCrumbs/
├── App/
│   ├── AppDelegate.swift       # NSApplicationDelegate — owns SocketServer + Database lifecycle
│   │                           #   Sparkle updater, launch at login, activation policy
│   │                           #   30s watchdog auto-restarts dead socket server
│   ├── ContentView.swift       # NavigationSplitView — time-grouped sidebar with session/event tree
│   │                           #   SidebarItem (.timePeriodHeader, .projectHeader, .session, .event)
│   │                           #   NSEvent key monitor for Option+Arrow
│   └── NoCrumbsApp.swift       # @main entry, Window + Settings + MenuBarExtra scenes
│                               #   Injects Database, ThemeManager, AppScale, HookHealthChecker
│                               #   Cmd+/- zoom commands, "Check for Updates…" (Sparkle)
│
├── Core/
│   ├── Database/
│   │   └── Database.swift      # @Observable @MainActor singleton, raw SQLite3, WAL, migrations v1-v9
│   │                           #   In-memory caches: sessions, recentEvents, fileChangesCache,
│   │                           #   recentHookEvents, commitTemplates
│   ├── IPC/
│   │   ├── SocketClient.swift  # Connect + write JSON to Unix socket (app-side, also has makeUnixAddr helper)
│   │   ├── SocketServer.swift  # POSIX socket actor: Unix + TCP accept loops, parse JSON, dispatch to Database
│   │   │                       #   Handles: "event", "prompt", "change", "file-descriptions",
│   │   │                       #            "session-rename", "query-prompts", "template"
│   │   │                       #   TCP listener: localhost-only, enabled via remoteTCPPort UserDefaults
│   │   │                       #   Resilient accept loop: continue on transient errors, break only on stop()
│   │   │                       #   isHealthy: computed property (listening && serverFD >= 0)
│   │   └── TransportEndpoint.swift # Shared endpoint enum: .unix(path) / .tcp(host, port) with env-based resolution
│   ├── Models/
│   │   ├── CommitTemplate.swift   # name (PK), body, isActive, createdAt
│   │   ├── DiffStat.swift         # Per-file, per-prompt, and aggregated diff statistics
│   │   ├── FileChange.swift       # id, eventID, filePath, toolName, timestamp, description?
│   │   ├── FileDiff.swift         # FileDiff, DiffHunk, DiffLine — diff parsing output models
│   │   ├── HookEvent.swift        # id, sessionID, hookEventName, projectPath, timestamp, payload (JSON)
│   │   ├── PromptEvent.swift      # id, sessionID, projectPath, promptText?, timestamp, vcs?, baseCommitHash?, sequenceID?
│   │   ├── Session.swift          # id, projectPath, startedAt, lastActivityAt, customName?
│   │   ├── TemplateRenderer.swift # Renders {{placeholder}} templates with TemplateContext data
│   │   └── VCSType.swift          # enum: .git, .mercurial, .sapling
│   ├── Debug/
│   │   ├── DebugConfiguration.swift  # Launch arg check: -debugMockData flag
│   │   └── MockDataGenerator.swift   # @MainActor: populates Database with realistic mock data for UI development
│   ├── Extensions/
│   │   └── String+TaskNotification.swift # .isTaskNotification, .displayPromptText — strip XML noise from sidebar
│   ├── Utilities/
│   │   ├── DeepLinkRouter.swift    # @Observable @MainActor: handles nocrumbs:// URLs, pending navigation
│   │   ├── HookHealthChecker.swift # @Observable: checks CLI installed (Homebrew + bundle + PATH), hooks configured,
│   │   │                          #   socket active (real POSIX connect probe, not just file existence)
│   │   ├── SecretRedactor.swift     # Regex-based secret scrubbing (API keys, tokens, JWTs, credentials)
│   │   ├── SessionMarkdownFormatter.swift # Formats session data as markdown for clipboard export
│   │   └── ShellEnvironment.swift  # Captures user's login shell env at launch for VCS subprocesses
│   └── VCS/
│       ├── DiffParser.swift       # Parses unified git/hg diff output → [FileDiff]
│       ├── GitProvider.swift      # VCSProvider impl — shells out to /usr/bin/git via Process
│       ├── MercurialProvider.swift # VCSProvider impl — shells out to hg via resolved path + ShellEnvironment
│       ├── SaplingProvider.swift  # VCSProvider impl — shells out to sl via resolved path + ShellEnvironment
│       ├── RemoteURLParser.swift  # Parses git remote URLs (SSH/HTTPS) → web commit URLs
│       ├── VCSBinaryResolver.swift # Resolves VCS binary paths for GUI apps with no PATH
│       ├── VCSDetector.swift      # Static: walk up directory tree checking for .git/.hg/.sl
│       │                          #   normalizePath(): resolves symlinks + strips trailing slashes
│       └── VCSProvider.swift      # Protocol + makeProvider(for:) factory
│
├── Features/
│   ├── DiffViewer/
│   │   ├── DiffDetailView.swift     # Main diff layout: header + DiffSplitView (file list + side-by-side panes)
│   │   ├── DiffSplitView.swift      # NSSplitView wrapper (NSViewRepresentable) — native AppKit resize for file list / diff panes
│   │   ├── DiffViewModel.swift      # @Observable: loads diffs via injected VCSProvider, builds side-by-side line pairs
│   │   ├── DiffTextView.swift       # NSViewRepresentable wrapping NSTextView (TextKit 1)
│   │   ├── DiffScrollSync.swift     # Syncs scroll position between left + right panes
│   │   └── SyntaxHighlighter.swift  # Regex-based syntax highlighting for 20+ languages
│   ├── SessionSummary/
│   │   ├── SessionSummaryView.swift       # Rich summary: prompt timeline with clickable commit SHAs, diffstat bars
│   │   └── SessionSummaryViewModel.swift  # Aggregates session data, resolves commit SHAs via git log
│   ├── Settings/
│   │   └── SettingsView.swift  # Hook status, annotation toggle + content sub-toggles + template list, diff theme picker
│   │                           #   Database debug panel (NavigationLink push): record counts, activity dates, schema, size, path
│   └── Setup/
│       └── SetupView.swift     # First-run guide: brew install cask, configure hooks, start session + docs link
│
├── Resources/
│   ├── Assets.xcassets         # App icon (16–1024px, Apple squircle mask)
│   ├── Info.plist              # CFBundleURLTypes for nocrumbs://, LSUIElement, Sparkle (SUFeedURL, SUPublicEDKey)
│   ├── NoCrumbs.entitlements   # Hardened runtime: Apple Events entitlement
│   └── Themes/                 # 18 bundled JSON color themes
│       ├── ayu-dark.json       ├── catppuccin-latte.json
│       ├── catppuccin-mocha.json ├── dracula.json
│       ├── everforest-dark.json ├── github-light.json
│       ├── gruvbox-dark.json   ├── kanagawa.json
│       ├── monokai.json        ├── nightfox.json
│       ├── nord.json           ├── one-dark-pro.json
│       ├── one-light.json      ├── rose-pine.json
│       ├── rose-pine-dawn.json ├── solarized-dark.json
│       ├── solarized-light.json └── tokyo-night.json
│
├── UI/
│   ├── Components/
│   │   ├── CheckForUpdatesView.swift  # Sparkle "Check for Updates…" menu item (KVO bridge)
│   │   └── SessionStateIndicator.swift  # Live/paused/stale session status indicator
│   ├── StyleGuide/
│   │   ├── AppColors.swift     # Semantic color tokens (addition, deletion, modified, muted variants)
│   │   ├── AppFonts.swift      # Semantic font tokens (filePath, numeric, sectionHeader, diffEditor)
│   │   ├── AppScale.swift      # @Observable singleton — Cmd+/- zoom (0.6–2.0×), persisted to UserDefaults
│   │   └── LayoutGuide.swift   # Spacing/padding/size constants (XS–XXL scale, named component sizes)
│   └── Themes/
│       ├── DiffTheme.swift     # Codable color palette (diff + syntax colors, hex→NSColor)
│       └── ThemeManager.swift  # @Observable singleton — loads bundled JSON themes, persists selection
│
NoCrumbsTests/                      # Test target (hosted by app)
├── DatabaseTests.swift            # DB CRUD, migrations, cascade delete, sequenceID
├── DiffParserTests.swift          # 14 tests — pure unit, parses diff strings
├── DiffViewModelTests.swift       # 11 tests — MockVCSProvider injection
├── GitProviderTests.swift         # 8 tests — real temp git repos via GitTestRepo helper
├── MercurialProviderTests.swift   # 6 tests — hg provider command construction + output parsing
├── RemoteURLParserTests.swift     # 12 tests — SSH/HTTPS remote URL → commit URL parsing
├── SaplingProviderTests.swift     # 6 tests — sl provider command construction + output parsing
├── SecretRedactorTests.swift      # 20 tests — API key, token, JWT, credential redaction
├── SequenceBoundaryTests.swift    # 5 tests — prompt sequence grouping logic
├── SocketPipelineTests.swift      # 4 tests — E2E socket → actor → DB pipeline (catches v0.5.6 deadlock class)
├── SocketTransportTests.swift     # 9 tests — TCP + Unix socket transport, endpoint resolution
├── TemplateTests.swift            # 14 tests — TemplateRenderer + DB template CRUD
├── TransportEndpointTests.swift   # 12 tests — endpoint resolution from env vars
└── VCSDetectorTests.swift         # 10 tests — filesystem with temp VCS markers

VERSION                            # Single source of truth for app + CLI version (e.g. "0.4.2")

CLI/
├── Package.swift               # Swift 5.9, macOS 14+, zero dependencies
└── Sources/nocrumbs/
    ├── main.swift              # Subcommand dispatch: event, capture-*, annotate-commit, install*, describe, template, rename, setup-remote
    ├── Version.swift           # Auto-generated from VERSION file — `let version = "x.y.z"`
    ├── CaptureEventCommand.swift  # Unified hook event → JSON to socket (v3+)
    ├── CapturePromptCommand.swift # (legacy) Parse UserPromptSubmit stdin → JSON to socket
    ├── CaptureChangeCommand.swift # (legacy) Parse PostToolUse stdin → JSON to socket
    ├── AnnotateCommitCommand.swift # Query prompts via socket → render template → append to commit message
    │                              #   ContentFlags: showPromptList, showFileCountPerPrompt, showSessionID
    ├── DescribeCommand.swift      # Pipe per-file change descriptions to app via socket
    ├── RenameSessionCommand.swift # nocrumbs rename-session <session_id> <name>
    ├── TemplateCommand.swift      # nocrumbs template add/list/set/remove/preview
    ├── InstallCommand.swift       # Write hook config to ~/.claude/settings.json + install git hooks
    ├── InstallRemoteCommand.swift # Write hook config for remote servers (Linux socket paths)
    ├── SetupRemoteCommand.swift   # One-command remote setup: scp binary, env vars, hooks, SSH tunnel, TCP listener
    ├── Models.swift               # Minimal Codable structs (duplicated — CLI can't link app target)
    └── SocketClient.swift         # Connect + write/read to Unix socket or TCP (CLI-side, includes sendAndReceive)

scripts/
├── generate_icon.swift         # Generates macOS app icon sizes with Apple squircle mask
├── release.sh                  # Release pipeline: build (app+CLI) → sign → notarize → staple → appcast → cask
│                               #   Auto-bumps version (patch default, --minor, --major)
│                               #   Reads secrets from scripts/.env.local (gitignored)
└── sync-version.sh             # Derives Info.plist, CLI Version.swift, cask template from VERSION file

.githooks/
└── pre-commit                  # Gitleaks pre-commit hook: scans staged changes for secrets

docs-site/                      # Docusaurus v3 site (https://nocrumbs.ai)
├── docusaurus.config.js        # Site config, dark mode default, GitHub/Dracula syntax themes
├── docs/                       # Markdown content: getting-started, how-it-works, CLI usage, remote setup, FAQ
├── src/pages/index.js          # Landing page
├── src/css/custom.css          # Brand styles
└── static/                     # CNAME, logo, hero SVG

.github/workflows/
├── ci.yml                      # Build + test on PRs and pushes to main (macOS runner)
├── deploy-docs.yml             # Auto-deploy docs-site to GitHub Pages on push to main (path-filtered)
└── secret-scan.yml             # Gitleaks scan on PRs
```

## Database Schema

**Storage:** `~/Library/Application Support/NoCrumbs/nocrumbs.sqlite`
**Engine:** Raw SQLite3 C API (no ORM) — WAL journal mode, foreign keys ON
**Schema version:** 9 (tracked via `PRAGMA user_version`)

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,          -- Claude Code session_id (UUID string)
    projectPath TEXT NOT NULL,
    startedAt REAL NOT NULL,
    lastActivityAt REAL NOT NULL,
    customName TEXT               -- [v8] user-defined session name
);

CREATE TABLE promptEvents (
    id TEXT PRIMARY KEY,          -- UUID
    sessionID TEXT NOT NULL,
    projectPath TEXT NOT NULL,
    promptText TEXT,              -- NULL for orphaned file changes
    timestamp REAL NOT NULL,
    vcs TEXT,                     -- "git" or "mercurial", NULL if not in repo
    baseCommitHash TEXT,          -- git HEAD at prompt time (diff baseline) [v2]
    sequenceID TEXT,              -- groups prompts into change sequences [v9]
    FOREIGN KEY(sessionID) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE TABLE fileChanges (
    id TEXT PRIMARY KEY,          -- UUID
    eventID TEXT NOT NULL,
    filePath TEXT NOT NULL,
    toolName TEXT NOT NULL,       -- "Write" or "Edit"
    timestamp REAL NOT NULL,
    description TEXT,             -- [v7] AI-generated change description
    FOREIGN KEY(eventID) REFERENCES promptEvents(id) ON DELETE CASCADE,
    UNIQUE(eventID, filePath)     -- [v4] deduplication constraint
);

CREATE TABLE hookEvents (         -- [v3] raw hook event storage
    id TEXT PRIMARY KEY,
    sessionID TEXT NOT NULL,
    hookEventName TEXT NOT NULL,   -- e.g. "UserPromptSubmit", "PostToolUse", "SessionEnd", "Stop"
    projectPath TEXT NOT NULL,
    timestamp REAL NOT NULL,
    payload TEXT,                  -- JSON: prompt, tool_name, tool_input, agent_id, etc.
    FOREIGN KEY(sessionID) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE TABLE commitTemplates (    -- [v6] customizable commit annotation templates
    name TEXT PRIMARY KEY,
    body TEXT NOT NULL,            -- Template body with {{placeholder}} syntax
    isActive INTEGER NOT NULL DEFAULT 0,
    createdAt REAL NOT NULL
);

-- Indexes
CREATE INDEX idx_promptEvents_sessionID ON promptEvents(sessionID);
CREATE INDEX idx_promptEvents_timestamp ON promptEvents(timestamp);
CREATE INDEX idx_fileChanges_eventID ON fileChanges(eventID);
CREATE INDEX idx_fileChanges_filePath ON fileChanges(filePath);
CREATE INDEX idx_hookEvents_sessionID ON hookEvents(sessionID);
CREATE INDEX idx_hookEvents_timestamp ON hookEvents(timestamp);
CREATE INDEX idx_hookEvents_hookEventName ON hookEvents(hookEventName);
CREATE INDEX idx_promptEvents_sequenceID ON promptEvents(sequenceID);
```

**Design decision:** `fileChanges` is a separate table (not a JSON array) so a single prompt that touches 100+ files scales with indexed queries. Enables "show all prompts that touched file X" lookups.

Foreign key cascade: deleting a session cascades to its promptEvents, which cascades to their fileChanges. Also cascades hookEvents.

## Database Singleton

```swift
@Observable
@MainActor
final class Database {
    static let shared = Database()

    private(set) var sessions: [Session] = []
    private(set) var recentEvents: [PromptEvent] = []       // Last 500, desc by timestamp
    private(set) var fileChangesCache: [UUID: [FileChange]]  // In-memory join cache
    private(set) var recentHookEvents: [HookEvent] = []     // Last 200
    private(set) var sessionStateCache: [String: SessionState] = [:]  // Derived from hookEvents
    private(set) var commitTemplates: [CommitTemplate] = []  // All templates, ordered by createdAt
    var diffStatCache: [UUID: PromptDiffStat] = [:]          // Computed, not persisted, clears on restart

    var activeTemplate: CommitTemplate? {                    // Computed from cache
        commitTemplates.first(where: \.isActive)
    }

    // Debug info (used by Settings → Database panel)
    var path: String { dbPath }
    var fileSize: Int64 { FileManager attributes }
    var schemaVersion: Int32 { userVersion() }

    // Raw SQLite3 via OpaquePointer
    // WAL journal mode, foreign keys enabled
    // CRUD: upsertSession, insertPromptEvent, insertFileChange(s), deleteSession
    //       insertHookEvent, saveCommitTemplate, deleteCommitTemplate, setActiveTemplate
    //       updateFileDescription(_:sessionID:filePath:)
    // Queries: eventsForSession, recentEvents(forProject:since:), fileChangeCount, totalFileCount
    // Cache refreshed after each write
    // backfillBaseCommitHashes() — async, fills NULL baseCommitHash via git log --before
}
```

### Migrations

- **v1**: Initial schema (sessions, promptEvents, fileChanges with indexes)
- **v2**: `ALTER TABLE promptEvents ADD COLUMN baseCommitHash TEXT`
- **v3**: `hookEvents` table for raw Claude Code hook event storage
- **v4**: Deduplicate fileChanges — `UNIQUE(eventID, filePath)` constraint, table rebuild
- **v5**: Merge orphan prompt events (promptText IS NULL) into next real prompt in same session
- **v6**: `commitTemplates` table for customizable commit annotation templates
- **v7**: `ALTER TABLE fileChanges ADD COLUMN description TEXT` (AI-generated change descriptions)
- **v8**: `ALTER TABLE sessions ADD COLUMN customName TEXT` (user-defined session names)
- **v9**: `ALTER TABLE promptEvents ADD COLUMN sequenceID TEXT` + index (prompt sequence grouping)

### Backfill

On startup, `Database.backfillBaseCommitHashes()` runs async:
- Finds events with NULL `baseCommitHash` and any non-nil VCS type (git, mercurial, sapling)
- Uses `makeProvider(for: vcs).headBefore(timestamp)` to find what HEAD was at prompt time
- Updates each event with the resolved hash
- Caches by `projectPath|vcsType|timestamp` to avoid redundant VCS calls

### Injection Pattern

```swift
@main
struct NoCrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var database = Database.shared
    @State private var themeManager = ThemeManager.shared
    @State private var appScale = AppScale.shared
    @State private var healthChecker = HookHealthChecker.shared
    @State private var deepLinkRouter = DeepLinkRouter.shared

    var body: some Scene {
        Window("NoCrumbs", id: "main") {
            ContentView()
                .environment(database)
                .environment(themeManager)
                .environment(appScale)
                .environment(healthChecker)
                .environment(deepLinkRouter)
                .onAppear { themeManager.loadBundledThemes() }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appDelegate.updaterController.updater)
            }
            CommandGroup(after: .toolbar) {
                // Cmd+/- zoom, Cmd+0 reset
            }
        }

        Settings {
            SettingsView()
                .environment(themeManager)
        }

        MenuBarExtra("NoCrumbs", systemImage: "doc.text.magnifyingglass") {
            // Show NoCrumbs (Cmd+Shift+N), Settings (Cmd+,), Quit (Cmd+Q)
        }
    }
}

// Child views
struct ContentView: View {
    @Environment(Database.self) private var database
}
```

### Write Pattern

```swift
// All writes through Database methods — cache auto-refreshes
try database.upsertSession(session)
try database.insertPromptEvent(event)
try database.insertFileChange(change)
try database.insertFileChanges(changes)  // Batch insert in single transaction
try database.deleteSession(id: sessionID)  // Cascade deletes events + file changes
try database.insertHookEvent(event)
try database.saveCommitTemplate(name: name, body: body)  // Upsert
try database.setActiveTemplate(name: name)  // Sets one active, clears others
try database.deleteCommitTemplate(name: name)
try database.updateFileDescription("what changed", sessionID: id, filePath: path)
try database.updateSessionName(sessionID: id, name: "my session")  // [v8]
```

## IPC: Unix Domain Socket + TCP

```
Unix socket: ~/Library/Application Support/NoCrumbs/nocrumbs.sock
TCP listener: 127.0.0.1:19876 (when remoteTCPPort > 0 in UserDefaults)
```

**Server** (`SocketServer`): Swift actor, POSIX `socket()/bind()/listen()/accept()`.
- Testable: `init(path:database:)` accepts optional `Database` injection (nil falls through to `Database.shared`)
- Unix socket accept loop in detached Task — resilient: `continue` on transient `accept()` errors, only `break` on intentional `stop()`
- `isHealthy` computed property: `listening && serverFD >= 0` — used by AppDelegate watchdog
- Optional TCP listener on localhost for remote connections via SSH/ET tunnel
  - Enabled via `remoteTCPPort` UserDefaults key (set by Settings or `nocrumbs setup-remote`)
  - Binds to `127.0.0.1` only — remote access requires SSH `RemoteForward` tunnel
- Reads full message, parses JSON, dispatches by `"type"` field
- `"event"` → unified hook event handler; stores HookEvent, bridges to legacy prompt/change tables (fire-and-forget)
- `"prompt"` → (legacy) captures VCS HEAD as baseCommitHash via `captureHead()`, upserts session + inserts PromptEvent
- `"change"` → (legacy) finds most recent event for session, attaches FileChange (or creates orphan event)
- All handlers normalize `cwd` and `filePath` via `VCSDetector.normalizePath()` (resolves symlinks, strips trailing slashes)
- `captureHead(vcs:at:)` helper replaces raw `try?` — logs actual error before returning nil
- `"file-descriptions"` → updates `description` column on fileChanges matching session + path (fire-and-forget)
- `"session-rename"` → updates session customName (fire-and-forget)
- `"query-prompts"` → returns recent prompts + file counts + annotation/content toggle flags + active template body (request/response)
- `"template"` → CRUD for commit annotation templates: add, list, set, remove, preview (request/response)

**Client** (`SocketClient` — CLI-side):
- `send(_ data: Data)` — fire-and-forget
- `sendAndReceive(_ data: Data)` — request/response for query-prompts + template
- Endpoint resolution via `resolveEndpoint()`: `NOCRUMBS_SOCK` → Unix, `NOCRUMBS_HOST` → TCP, else platform default
- Supports both Unix domain socket and TCP connections (POSIX)

**TransportEndpoint** (app-side shared type):
- Same resolution logic as CLI `SocketClient.Endpoint` for consistency
- Used by app-side code and tests

**Protocol:**
```json
// Unified event (fire-and-forget) — v3+
{"type": "event", "session_id": "abc", "hook_event_name": "UserPromptSubmit", "cwd": "/path",
 "prompt": "...", "tool_name": "Write", "tool_input": {...}}

// Legacy prompt (fire-and-forget)
{"type": "prompt", "session_id": "abc", "prompt": "...", "cwd": "/path"}

// Legacy change (fire-and-forget)
{"type": "change", "session_id": "abc", "file_path": "/path/file.swift", "tool_name": "Write", "cwd": "/path"}

// File descriptions (fire-and-forget)
{"type": "file-descriptions", "session_id": "abc",
 "descriptions": [{"file_path": "/abs/path", "description": "what changed"}]}

// Query prompts (request/response)
{"type": "query-prompts", "cwd": "/path"}
// Response:
{"prompts": [{"text": "...", "file_count": 3}], "session_id": "abc", "total_files": 12,
 "annotation_enabled": true, "deep_link_enabled": true,
 "show_prompt_list": true, "show_file_count_per_prompt": true, "show_session_id": true,
 "template": "---\n{{summary_line}}"}

// Template management (request/response)
{"type": "template", "action": "add", "name": "my-template", "body": "---\n{{summary_line}}"}
{"type": "template", "action": "list"}
{"type": "template", "action": "set", "name": "my-template"}
{"type": "template", "action": "remove", "name": "my-template"}
{"type": "template", "action": "preview", "cwd": "/path"}
```

- Fire-and-forget: CLI exits 0 even on failure (never blocks Claude Code)
- No retry, no queue — if app not running, message is lost silently

## CLI Hook Integration

The `nocrumbs` CLI (v0.4.0) is invoked by Claude Code hooks.

**`nocrumbs event`** (preferred, v3+) — unified hook event handler:
- Reads stdin JSON from any Claude Code hook
- Sends `type: "event"` with full payload to socket
- App-side bridges to legacy prompt/change tables automatically

**Legacy commands** (still supported):
- `nocrumbs capture-prompt` — `UserPromptSubmit` hook
- `nocrumbs capture-change` — `PostToolUse` hook (matcher: Write|Edit)

**`nocrumbs install`** writes hook config to `~/.claude/settings.json`, merging with existing settings.

**`nocrumbs install --remote`** (or `install-remote`) — same hook config but for remote servers:
- Creates Linux socket directory (`/tmp/nocrumbs-$USER/`) with restricted permissions
- Prints connection options: SSH socket forwarding, TCP tunnel, or direct TCP

**`nocrumbs setup-remote <host>`** — one-command remote setup from Mac:
1. `scp` CLI binary to `<host>:~/.local/bin/nocrumbs`
2. Detect remote shell, append `NOCRUMBS_HOST=localhost` + PATH
3. `ssh <host> 'nocrumbs install --remote'`
4. Add `RemoteForward 19876 localhost:19876` to local `~/.ssh/config`
5. `defaults write remoteTCPPort -int 19876` (enable TCP listener)
6. Verify tunnel via `nc -zw2 localhost 19876`
- All steps idempotent, safe to re-run
- Partial failure: reports what succeeded and what to fix manually

**`nocrumbs install-git-hooks`** writes `prepare-commit-msg` hook to `.git/hooks/`.

**`nocrumbs annotate-commit <msg-file> [source]`** — called by git `prepare-commit-msg` hook:
- Queries app via `query-prompts` socket message
- Reads content toggle flags: `show_prompt_list`, `show_file_count_per_prompt`, `show_session_id`, `deep_link_enabled`
- If response includes `"template"` key, renders it via CLI-side template renderer (respects toggles)
- Otherwise, uses built-in default format (summary line + prompt list, respects toggles)
- Respects `annotation_enabled` setting from app
- Skips merge/squash commits
- Won't double-annotate (checks for existing 🥐 marker)

**`nocrumbs describe`** — pipe per-file change descriptions to app:
- Reads stdin JSON: `{"session_id": "...", "descriptions": [{"file_path": "...", "description": "..."}]}`
- Sends `type: "file-descriptions"` to socket (fire-and-forget)
- App updates `fileChanges.description` column for matching session + path

**`nocrumbs template <action>`** — manage commit annotation templates:
- `add --name <name> --body <template>` — create or update a template
- `list` — show all templates (name, active status, body preview)
- `set --name <name>` — set active template
- `remove --name <name>` — delete a template
- `preview` — render active template with recent prompt data

Session ID links prompts to their file changes across hooks.

### Template Format

Simple `{{placeholder}}` syntax for commit annotation templates:

| Placeholder | Value |
|-------------|-------|
| `{{prompt_count}}` | Number of prompts |
| `{{total_files}}` | Total unique files changed |
| `{{session_id}}` | Session UUID (8-char prefix) |
| `{{summary_line}}` | Pre-built: `🥐 3 prompts · 12 files · abc12345` |
| `{{#prompts}}...{{/prompts}}` | Loop over prompts |
| `{{index}}` | 1-based prompt index (inside loop) |
| `{{text}}` | Prompt text, truncated to 72 chars (inside loop) |
| `{{file_count}}` | Files changed by this prompt (inside loop) |

Rendering is implemented in both `TemplateRenderer` (app-side) and as a lightweight copy in `AnnotateCommitCommand` (CLI can't link app code).

## Sidebar Architecture

The sidebar uses a **flat list** pattern — no `Section` or `DisclosureGroup` (both break `List(selection:)` tag propagation on macOS).

```swift
private struct SidebarItem: Identifiable {
    let id: UUID
    let kind: Kind         // .timePeriodHeader, .projectHeader, .session, .event
    let session: Session?
    let event: PromptEvent?
    let projectName: String?
}
```

**Time-grouped structure:** Sessions are grouped by time period (Today, Yesterday, This Week, etc.) with section headers and project sub-headers.

**Key design decisions:**
- `UUID` as selection type (not String, not custom enum — avoids compiler overload issues)
- Single `VStack` return type from `row(for:)` — `if/else` inside, not `switch` (avoids `_ConditionalContent` which breaks tag resolution)
- `.tag(item.id)` on the VStack directly
- `expandedSessions: Set<String>` drives conditional rendering of child events
- `NSEvent.addLocalMonitorForEvents` for Option+Arrow (SwiftUI `onKeyPress` is consumed by NSOutlineView)
- `SidebarState` is a class so the NSEvent closure captures a reference, not a stale struct copy
- Chevron disclosure indicator on LHS with `.onTapGesture` for click-to-expand
- Session rows show: project name + first prompt text + prompt count + relative timestamp

## VCS Abstraction

```swift
protocol VCSProvider: Sendable {
    var type: VCSType { get }
    func currentHead(at path: String) async throws -> String
    func currentBranch(at path: String) async throws -> String
    func isValidCommit(_ hash: String, at path: String) async throws -> Bool
    func diff(for hash: String, at path: String) async throws -> String
    func uncommittedDiff(at path: String) async throws -> String
    func diffForFiles(_ filePaths: [String], at path: String) async throws -> String
    func diffFromBase(_ baseHash: String, filePaths: [String], at path: String) async throws -> String
    func headBefore(_ date: Date, at path: String) async throws -> String?
    func untrackedFiles(_ filePaths: [String], at path: String) async throws -> Set<String>
}

func makeProvider(for vcs: VCSType) -> any VCSProvider
```

**Testability:** `DiffViewModel` accepts `(any VCSProvider)?` via init. When injected (tests), the provider is locked. Otherwise, `load()` selects the correct provider per event via `makeProvider(for: event.vcs)`.

**Implementations:**
- `GitProvider` — shells out to `/usr/bin/git` via `Process` with async wrapper
  - `currentHead` → `git rev-parse HEAD` (captured at prompt time for diff baseline)
  - `diffFromBase` → `git diff <baseHash> -- <files>` (primary diff strategy)
  - `diffForFiles` → `git diff HEAD -- <files>` (legacy fallback)
  - `headBefore` → `git log --before=<iso> -1 --format=%H` (for backfill)
  - `untrackedFiles` → `git ls-files --others --exclude-standard -- <files>`
  - `cleanFiles` → `git status --porcelain -- <files>` (identifies committed files)
- `MercurialProvider` — shells out to `hg` via resolved binary path + `ShellEnvironment`
  - Binary resolved via `VCSBinaryResolver` checking `/usr/local/bin/hg`, `/opt/homebrew/bin/hg`, `/opt/facebook/hg/bin/hg`
  - `currentHead` → `hg log -r . -T {node}`
  - `diffFromBase` → `hg diff --git -r <baseHash> <files>`
  - `headBefore` → `hg log -r "date('<iso>')" -l 1 -T {node}`
  - All commands produce `--git` format diffs for DiffParser compatibility
  - `process.environment = ShellEnvironment.variables` for EdenFS/FB env vars
- `SaplingProvider` — shells out to `sl` via resolved binary path + `ShellEnvironment`
  - Binary resolved via `VCSBinaryResolver` checking `/opt/facebook/hg/bin/sl`, `/opt/homebrew/bin/sl`, `/usr/local/bin/sl`
  - `currentHead` → `sl log -r . -T {node}`
  - `currentBranch` → `sl bookmark --active`
  - `diffFromBase` → `sl diff --git -r <baseHash> <files>`
  - `headBefore` → `sl log -r "date('<iso>')" -l 1 -T {node}`
  - `untrackedFiles` → `sl status -un`
  - `process.environment = ShellEnvironment.variables` for EdenFS/FB env vars

**Binary Resolution:** `VCSBinaryResolver.resolve(name, knownPaths)` checks known install paths in order, falls back to `/usr/local/bin/<name>`. GUI apps have no PATH, so `/usr/bin/env` won't work.

**Shell Environment:** `ShellEnvironment.variables` captures the user's login shell environment once at launch via `$SHELL -ilc env`. Falls back to `ProcessInfo.processInfo.environment` if capture fails. Required for `hg`/`sl` on machines with custom Python paths, `HGRCPATH`, or EdenFS configuration.

**Detection:** `VCSDetector.detect(at:)` walks up from a path checking for `.git`, `.sl`, or `.hg` directories. Input paths are normalized via `normalizePath()` (resolves symlinks, strips trailing slashes).
`VCSDetector.repoRoot(at:for:)` returns the root directory of the detected VCS repo.

**Remote URL Parsing:** `RemoteURLParser.commitURL(remoteURL:hash:)` converts git SSH/HTTPS remote URLs to web commit URLs. Used for clickable commit SHA links in the prompt timeline.

## Diff Viewer (M3)

Side-by-side diff viewer. Clicking a prompt event shows the diffs it produced, Phabricator-style.

### Architecture

```
Click PromptEvent in sidebar
    → DiffDetailView.reload()
    → DiffViewModel.load(event, fileChanges)
        → Convert absolute paths to relative (FileChange stores absolute)
        → git diff <baseCommitHash> -- <files>  (shows all changes since prompt, committed or not)
        → DiffParser.parse(rawDiff) → [FileDiff]
        → For untracked files: synthetic all-additions diff from file content
    → buildLinePairs() → [(left: DiffLine?, right: DiffLine?)]
    → DiffDetailView renders:
        ┌──────────────────────────────────────────────────┐
        │ Prompt: "fix sidebar selection bugs"              │
        │ 3:51 PM · 7 files                                 │
        ├──┬─────────┬──────────────┬───────────────────────┤
        │⊞ │ file1   │  Before      │  After                 │
        │  │ file2   │  (NSTextView)│  (NSTextView)          │
        │  │ file3   │  line nums   │  line nums             │
        │  │         │  red bg      │  green bg              │
        └──┴─────────┴──────────────┴───────────────────────┘
              ↑ collapsible (sidebar.left toggle button)
```

**Key design: `baseCommitHash`** — every prompt event stores VCS HEAD at the moment it arrives.
`vcs diff <baseHash>` always works regardless of whether changes are uncommitted, staged, or committed.
Legacy events are backfilled on startup via `headBefore(timestamp)`.

**VCS-aware provider selection:** `DiffViewModel.load()` selects the correct provider (Git/Mercurial/Sapling) based on `event.vcs`. When a test injects a mock provider, the injected provider is used instead.

**Fallback chain when baseHash is unavailable or dangling:**
1. If `baseCommitHash` is nil → attempt live `currentHead()` capture, update DB on success
2. If `isValidCommit()` returns false (commit rebased/stripped) → try `headBefore(eventTimestamp)` to find nearest valid ancestor, update DB on success
3. If all fallbacks fail → show error message

### Data Models

```swift
struct FileDiff: Identifiable, Equatable {
    let id: UUID
    let oldPath: String?    // nil = new file
    let newPath: String?    // nil = deleted file
    let hunks: [DiffHunk]
    var status: FileStatus  // .added, .deleted, .modified
    var displayPath: String { newPath ?? oldPath ?? "(unknown)" }
}

struct DiffHunk: Identifiable, Equatable {
    let id: UUID
    let oldStart: Int, oldCount: Int
    let newStart: Int, newCount: Int
    let lines: [DiffLine]
}

struct DiffLine: Identifiable, Equatable {
    let id: UUID
    let type: LineType      // .context, .addition, .deletion
    let text: String
    let oldLineNumber: Int? // nil for additions
    let newLineNumber: Int? // nil for deletions
}

struct DiffStat: Equatable, Sendable {
    let filePath: String
    let status: FileDiff.FileStatus
    let additions: Int
    let deletions: Int
}

struct PromptDiffStat: Equatable, Sendable {
    let eventID: UUID
    let fileStats: [DiffStat]
}

struct AggregatedFileStat: Identifiable, Equatable {
    let filePath: String
    let status: FileDiff.FileStatus
    let totalAdditions: Int
    let totalDeletions: Int
    let promptCount: Int
}
```

### Diff Parser

`DiffParser.parse(_ raw: String) -> [FileDiff]` — ~150 lines, parses unified `git diff` output:
- Guards against empty input (returns `[]`)
- Splits on `diff --git` boundaries
- Validates each chunk starts with `diff --git` header
- Parses `---`/`+++` for file paths (`/dev/null` → new/deleted)
- Parses `@@` hunk headers for line ranges
- Prefix-based line classification: ` ` context, `+` addition, `-` deletion
- Assigns line numbers (old/new independently)

### Line Pairing

`DiffViewModel.buildLinePairs()` creates side-by-side alignment:
- **Context lines**: appear on both sides `(left: line, right: line)`
- **Deletions followed by additions**: paired together (matched modification)
- **Lone deletions**: `(left: line, right: nil)` — empty placeholder on right
- **Lone additions**: `(left: nil, right: line)` — empty placeholder on left

### DiffTextView (NSViewRepresentable)

Wraps `NSTextView` (TextKit 1) via `NSViewRepresentable`:
- Read-only, monospaced font (SF Mono 12pt)
- Attributed string per-line: green bg for additions (0.12 alpha), red bg for deletions, clear for context
- Null lines (placeholder) get separator background
- Custom `DiffNSTextView` subclass draws line number gutter via `draw(_:)` override
- Line numbers: left pane shows `oldLineNumber`, right pane shows `newLineNumber`
- `lineFragmentPadding = 44` reserves gutter space

### Scroll Sync

`DiffScrollSync` synchronizes vertical scroll between left and right panes:
- `register(scrollView:side:)` — each DiffTextView registers its NSScrollView
- Auto-attaches when both sides are registered
- Observes `NSView.boundsDidChangeNotification` on each clip view
- Re-entrancy guard (`isSyncing` flag) prevents infinite loop
- `detach()` removes observers, called on reload

### View Layout

```
DiffDetailView
├── header (prompt text, timestamp, file count — expandable/collapsible with resize handle)
├── DiffSplitView (NSSplitView via NSViewRepresentable)
│   ├── fileList (List, sidebar style, searchable) — collapsible, native AppKit drag-to-resize
│   └── diffPanes
│       ├── column headers (sidebar.left toggle + "Before" | "After")
│       └── diffPanesContent (HStack, maxHeight: .infinity)
│           ├── leftPane (DiffTextView or "File did not exist")
│           ├── Divider
│           └── rightPane (DiffTextView or "File was deleted")
```

**DiffSplitView:** `NSSplitView` wrapper replacing manual SwiftUI `HStack` + frame sizing for the file list / diff panes split. Uses `NSHostingView` to embed SwiftUI views in each pane. Delegate constrains file list width to 120–400pt, file list pane is collapsible. Native AppKit drag handle eliminates SwiftUI relayout jank.

**Reactivity:** `onChange(of: event)` watches the full PromptEvent struct (not just `.id`) so backfill updates to `baseCommitHash` trigger a reload.

### Syntax Highlighting

`SyntaxHighlighter` — regex-based, per-line highlighting applied as `NSAttributedString` foreground colors on top of existing diff background colors.

- **20+ languages**: Swift, Python, JS/TS, Go, Rust, C/C++, Java, Ruby, JSON, YAML, Markdown, Shell, CSS, HTML, SQL, TOML
- **Rule priority**: First match wins per character position. Comments and strings match first so keywords inside them aren't colored.
- **Grammar structure**: Each language is a `Grammar` with ordered `[(NSRegularExpression, NSColor)]` rules
- **Integration**: Called by `DiffTextView` after building the base attributed string, before setting on NSTextView

### Theme System

JSON-based color themes loaded from `Resources/Themes/` at runtime.

**`DiffTheme`** (Codable struct): 17-key schema defining all colors for diff rendering and syntax highlighting:
- Diff colors: background, foreground, addedLine, removedLine, addedBackground, removedBackground, contextBackground, emptyLineBackground, lineNumber, hunkHeader
- Syntax colors: comment, string, keyword, type, number, preprocessor, property
- Hex strings → `NSColor` via computed properties

**`ThemeManager`** (@Observable singleton):
- Loads all bundled `.json` theme files, sorted alphabetically
- Persists selected theme name to `UserDefaults` (`selectedDiffTheme` key)
- Restores saved selection on launch (fallback to first theme)

**18 bundled themes** (12 dark, 6 light):
- Dark: Ayu Dark, Catppuccin Mocha, Dracula, Everforest Dark, Gruvbox Dark, Kanagawa, Monokai, Nightfox, Nord, One Dark Pro, Rosé Pine, Solarized Dark, Tokyo Night
- Light: Catppuccin Latte, GitHub Light, One Light, Rosé Pine Dawn, Solarized Light

**Settings picker**: `SettingsView` → "Diff Theme" section with `Picker` and inline `ThemeSwatch` (bg square + green/red dots).

## Test Infrastructure

140 tests across 13 files, all in `NoCrumbsTests/` (hosted test target).

```bash
xcodebuild test -project NoCrumbs.xcodeproj -scheme NoCrumbs -sdk macosx -derivedDataPath build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

| Suite | Tests | Type | Coverage |
|-------|-------|------|----------|
| `DatabaseTests` | 13 | Unit | CRUD operations, migrations, cascade delete, sequenceID |
| `DiffParserTests` | 14 | Pure unit | Parser edge cases: empty, add, delete, modify, multi-file, multi-hunk, line numbers, binary, no-newline-at-EOF, Mercurial format (git mode, new file, HG headers, no-prefix paths) |
| `DiffViewModelTests` | 11 | Unit (mock) | All load() paths: no VCS, no files, nil base hash (live capture success/fail), invalid commit, valid diff, git failure, untracked files, mercurial provider, VCS error message |
| `GitProviderTests` | 8 | Integration | Real temp git repos: currentHead, isValidCommit (valid/invalid/after-reset), diffFromBase, headBefore, untrackedFiles |
| `MercurialProviderTests` | 6 | Unit | Mercurial provider command construction and output parsing |
| `RemoteURLParserTests` | 12 | Pure unit | SSH/HTTPS URL parsing, edge cases, whitespace handling |
| `SaplingProviderTests` | 6 | Unit | Sapling provider command construction and output parsing |
| `SecretRedactorTests` | 20 | Pure unit | API key, token, JWT, credential redaction patterns |
| `TemplateTests` | 14 | Pure unit | TemplateRenderer and DB template CRUD, active switching |
| `SequenceBoundaryTests` | 5 | Unit | Prompt sequence grouping: new sequence after changes, continuation without |
| `SocketPipelineTests` | 4 | E2E | Socket → actor → DB pipeline: single prompt, event hook, concurrent clients, file change attachment |
| `SocketTransportTests` | 9 | Integration | TCP + Unix socket transport, connect/send/receive |
| `TransportEndpointTests` | 12 | Pure unit | Endpoint resolution from env vars, platform defaults |
| `VCSDetectorTests` | 10 | Filesystem | Temp dirs with .git/.hg/.sl markers: detect git/hg/sapling/none, nested repos, repoRoot |

**Key test utilities:**
- `MockVCSProvider` — configurable stub conforming to `VCSProvider` protocol
- `GitTestRepo` — creates temp git repo, provides `commit(file:content:)` and cleanup

## Menu Bar Behavior

- `LSUIElement`-style: starts as `.accessory` (no Dock icon), shows in Dock only when window is open
- `MenuBarExtra` with `doc.text.magnifyingglass` system image
- Global hotkey `Cmd+Shift+N` to show/create main window
- `Cmd+Q` closes window and hides to menu bar (not quit). Real quit via menu bar "Quit" button.
- Window visibility tracked via `NSWindow.didBecomeMainNotification` / `willCloseNotification`
- Launch at login via `SMAppService.mainApp.register()`

## Settings

Six sections in the Settings form:

**Hook Status:**
- CLI installed, Hooks configured, Socket active — green/red status indicators
- Socket check uses real POSIX `connect()` probe (detects ECONNREFUSED on dead listener, not just file existence)
- Read-only, refreshes on appear via `HookHealthChecker`

**General:**
- **Hide empty events** (`hideEmptyEvents`): Hide prompt events with no file changes from sidebar
- **Confirm before delete** (`confirmBeforeDelete`): Show confirmation dialog before deleting sessions
- **Retention** (`retentionDays`): Auto-cleanup sessions older than N days (default 7)
- **Annotation toggle** (`annotationEnabled`): Controls whether `nocrumbs annotate-commit` appends prompt context to commit messages
- **Content sub-toggles** (visible when annotation enabled):
  - **Include all details** — computed toggle: ON when all 4 sub-toggles are ON, sets all 4 at once
  - **Prompt list** (`showPromptList`) — show numbered prompt lines in multi-prompt annotations
  - **File count per prompt** (`showFileCountPerPrompt`) — show `(N files)` suffix on prompt lines
  - **Session ID** (`showSessionID`) — show 8-char session prefix in summary line
  - **Deep link** (`deepLinkInAnnotation`) — append `nocrumbs://` URL to annotations
- **Commit Templates**: Lists custom templates when annotation is enabled. Click to activate, right-click to delete. Shows hint to use `nocrumbs template add` when empty.
- All stored in `UserDefaults` via `@AppStorage`, defaults registered in `AppDelegate.applicationDidFinishLaunching` (all default to `true`)
- Read by `SocketServer.handleQueryPrompts` and included in response to CLI

**Remote:**
- **TCP port** (`remoteTCPPort`): Port for remote connections via SSH tunnel (0 = disabled, default 19876)
- When set, `SocketServer` starts a TCP listener on `127.0.0.1:<port>` alongside the Unix socket
- Used with `nocrumbs setup-remote` for one-command remote dev server setup

**Database** (push view via NavigationLink):
- Record counts: sessions, prompt events, file changes, hook events, templates (from in-memory cache, zero queries)
- Activity: oldest session date, newest activity (relative)
- Storage: schema version, DB file size (`ByteCountFormatter`), DB path with Copy + Reveal in Finder buttons
- Exposed via `Database.path`, `.fileSize`, `.schemaVersion` computed properties

**Diff Theme:**
- `Picker` listing all 18 available themes with inline color swatches
- Selection persisted via `ThemeManager.selectTheme(named:)` → `UserDefaults`
- Changes apply immediately to diff viewer (ThemeManager is @Observable, injected via environment)

Accessible via native Settings scene (`Cmd+,`) or menu bar "Settings..."

## SwiftUI + AppKit Hybrid

| Component | Framework | Why |
|-----------|-----------|-----|
| App lifecycle | `NSApplicationDelegateAdaptor` | Owns SocketServer + Database lifecycle, hotkey, activation policy |
| Sidebar + detail | SwiftUI `NavigationSplitView` | Native Mac sidebar/detail pattern |
| Session tree | SwiftUI `List(selection:)` | Flat list with manual expand/collapse |
| Key monitoring | `NSEvent.addLocalMonitorForEvents` | Intercepts Option+Arrow before NSOutlineView |
| Menu bar | `MenuBarExtra` | Native Mac menu bar pattern |
| Settings | SwiftUI `Settings` scene | Native Cmd+, integration |
| Zoom scaling | `AppScale` (@Observable) | Cmd+/- zoom (0.6–2.0×), persisted to UserDefaults |
| Auto-updates | Sparkle `SPUStandardUpdaterController` | Non-App Store update mechanism, EdDSA-signed appcast |
| Design tokens | `AppColors`, `AppFonts`, `LayoutGuide` | Semantic color/font/spacing constants, scale-aware |
| File list / diff split | `NSSplitView` (`NSViewRepresentable`) | Native AppKit drag-to-resize, no SwiftUI relayout jank |
| Diff panes | `NSTextView` (`NSViewRepresentable`) | TextKit 1 — battle-tested, no TextKit 2 scrolling bugs |
| Scroll sync | `DiffScrollSync` (NSView bounds observation) | Syncs left/right panes via boundsDidChangeNotification |
| Line numbers | Custom `DiffNSTextView.draw()` override | Draws gutter numbers in TextKit 1 coordinate space |
| Subprocesses | `Process` (Foundation) | Shell out to git/hg |

## App Lifecycle

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let socketServer = SocketServer()
    private var watchdogTask: Task<Void, Never>?
    lazy var updaterController = SPUStandardUpdaterController(...)

    func applicationDidFinishLaunching(_:) {
        updaterController.startUpdater()  // Sparkle auto-updates
        UserDefaults.standard.register(defaults: [
            "annotationEnabled": true, "deepLinkInAnnotation": true,
            "showPromptList": true, "showFileCountPerPrompt": true, "showSessionID": true,
        ])
        try Database.shared.open()     // SQLite + migrations (v1→v9) + cache load
        Task { await Database.shared.backfillBaseCommitHashes() }  // Async backfill for legacy events
        try await socketServer.start() // POSIX socket bind + listen (with 1s retry)
        startSocketWatchdog()          // 30s health check, auto-restart if dead
        try SMAppService.mainApp.register() // Launch at login
        NSApp.setActivationPolicy(.accessory) // Menu bar only until window opens
    }

    func applicationShouldTerminate(_:) -> TerminateReply {
        // Cmd+Q → close window + hide to menu bar (cancel terminate)
        // Real quit only from menu bar button
    }

    func applicationWillTerminate(_:) {
        watchdogTask?.cancel()
        await socketServer.stop()     // Close socket, unlink file
        Database.shared.close()       // Close SQLite
    }

    // Watchdog: 30s repeating check — if socketServer.isHealthy is false,
    // stop() + start() to recover from transient failures (fd exhaustion, etc.)
    // Legitimate hard timeout: socket server has no built-in health signal.
}
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Sparkle | 2.0+ | Auto-updates via EdDSA-signed appcast (non-App Store) |
| SQLite3 | System | Raw C API via `-lsqlite3` linker flag |

**CLI:** Zero dependencies (standalone SPM binary).

**Syntax highlighting:** Regex-based (no external dependency). Replaced planned TreeSitter/Neon approach with built-in `SyntaxHighlighter` — simpler, zero dependencies, covers 20+ languages adequately for diff viewing.

## Release Pipeline

**Script:** `scripts/release.sh [version] [--minor] [--major]`

Version is optional — defaults to patch bump. Reads current version from `VERSION` file.

```
Write VERSION file (single source of truth)
    → scripts/sync-version.sh (derives Info.plist, CLI Version.swift, cask template)
    → Clean Release build (Developer ID Application, hardened runtime, universal binary)
        → "Build & Embed CLI" build phase: swift build CLI → copy to .app/Contents/Resources/nocrumbs
    → Verify embedded CLI binary exists and reports correct version
    → Codesign embedded CLI binary (Developer ID + hardened runtime + timestamp)
    → Code signing verification (codesign --verify)
    → Zip (ditto) — CLI comes bundled inside app
    → Notarize (xcrun notarytool submit --wait)
    → Staple (xcrun stapler staple)
    → Re-zip (final distributable)
    → Sparkle EdDSA sign (sign_update)
    → Generate appcast.xml (generate_appcast)
    → Update Homebrew cask (geneyoo/homebrew-tap) with new version + SHA
```

**Version management:** Single `VERSION` file at repo root. `scripts/sync-version.sh` propagates to Info.plist, `CLI/Sources/nocrumbs/Version.swift`, and `homebrew-tap/Casks/nocrumbs.rb`. Xcode build phase runs sync automatically. No separate version constants to maintain.

**Distribution:** Single Homebrew cask installs app + symlinks CLI:
```bash
brew install --cask geneyoo/tap/nocrumbs
# Installs NoCrumbs.app to /Applications
# Symlinks NoCrumbs.app/Contents/Resources/nocrumbs to PATH
```

**Signing:** Developer ID Application certificate, hardened runtime enabled in both Debug and Release configs. Entitlements: Apple Events only (for `nocrumbs://` URL scheme).

**Sparkle integration:**
- `SPUStandardUpdaterController` initialized in `AppDelegate`, started on launch
- `CheckForUpdatesView` in app menu (after "About") — KVO bridge to `SPUUpdater.canCheckForUpdates`
- Feed URL: `https://nocrumbs.ai/appcast.xml` (Info.plist `SUFeedURL`)
- EdDSA public key in Info.plist (`SUPublicEDKey`), private key in macOS Keychain only

**Secrets management:**
- Team ID, keychain profile read from `scripts/.env.local` (gitignored)
- Private runbook at `scripts/RUNBOOK.local.md` (gitignored)
- Pre-commit hook (`scripts/pre-commit-secrets-check.sh`) blocks private key / credential patterns
- `.gitignore` blocks `*.env*`, `*.key`, `*.pem`, `*.p12`, `*.credential*`, `*.local`, `*.local.md`

## Docs Site

**Docusaurus v3** at `https://nocrumbs.ai`, auto-deployed via GitHub Actions on push to `main` (path-filtered to `docs-site/**`).

- Dark mode default, GitHub/Dracula syntax themes
- Content: Getting Started, How It Works, Installation, CLI Usage, App Usage, Remote Setup, FAQ, Contributing
- Static: CNAME, logo, hero SVG
- Deploy: `.github/workflows/deploy-docs.yml` → GitHub Pages (OIDC, no token secrets)

## Debugging

**Check Database:**
```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite ".schema"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT * FROM sessions;"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT * FROM promptEvents;"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT * FROM fileChanges;"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT * FROM hookEvents;"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT * FROM commitTemplates;"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "PRAGMA user_version;"
```

**Check Socket:**
```bash
ls -la ~/Library/Application\ Support/NoCrumbs/nocrumbs.sock
# Test prompt capture:
echo '{"session_id":"test","prompt":"hello","cwd":"/tmp"}' | nocrumbs capture-prompt
# Test change capture:
echo '{"session_id":"test","tool_name":"Write","tool_input":{"file_path":"test.swift"},"cwd":"/tmp"}' | nocrumbs capture-change
```

**Console Logs (OSLog categories):**
- `[NC:App]` — App lifecycle (Database open, SocketServer start, hotkey, activation policy)
- `[NC:Socket]` — IPC operations (message received, dispatch, query-prompts, template)
- `📦 [DB]` — Database operations (open, migration, close)
- `✅ [DB]` — Successful writes (upsert, insert, delete)
- `❌ [DB]` — Database errors
- `[NC:Git]` — Git subprocess operations
- `[NC:Hg]` — Mercurial subprocess operations
- `[DiffVM]` — Diff loading, parsing, baseCommitHash resolution

**Build:**
```bash
# Mac App (CLI is embedded automatically via "Build & Embed CLI" build phase)
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Debug \
  -sdk macosx -derivedDataPath build build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# Skip CLI embed for faster iterative builds
NOCRUMBS_SKIP_CLI=1 xcodebuild ...

# CLI only (standalone, for development)
swift build -c release --package-path CLI/

# Run app
open build/Build/Products/Debug/NoCrumbs.app
```

**Verify Pipeline:**
```bash
# Full E2E verification
/verify --all
```
