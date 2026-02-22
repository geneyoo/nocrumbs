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
               ↓ JSON via Unix domain socket
    NoCrumbs.app SocketServer (POSIX, actor)
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
            → if active template: render with TemplateRenderer
            → else: use built-in default format
            → append to commit message
            → respects annotation_enabled setting from app

Template management:
    nocrumbs template add/list/set/remove/preview
        → socket request/response to app
        → app stores templates in commitTemplates table
        → Settings UI shows templates, click to activate, right-click to delete
```

## Directory Structure

```
NoCrumbs/
├── App/
│   ├── AppDelegate.swift       # NSApplicationDelegate — owns SocketServer + Database lifecycle
│   │                           #   Global hotkey (Cmd+Shift+N), launch at login, activation policy
│   ├── ContentView.swift       # NavigationSplitView — time-grouped sidebar with session/event tree
│   │                           #   SidebarItem (.timePeriodHeader, .projectHeader, .session, .event)
│   │                           #   NSEvent key monitor for Option+Arrow
│   └── NoCrumbsApp.swift       # @main entry, Window + Settings + MenuBarExtra scenes
│                               #   Injects Database, ThemeManager, AppScale, HookHealthChecker
│                               #   Cmd+/- zoom commands
│
├── Core/
│   ├── Database/
│   │   └── Database.swift      # @Observable @MainActor singleton, raw SQLite3, WAL, migrations v1-v6
│   │                           #   In-memory caches: sessions, recentEvents, fileChangesCache,
│   │                           #   recentHookEvents, commitTemplates
│   ├── IPC/
│   │   ├── SocketClient.swift  # Connect + write JSON to Unix socket (app-side, also has makeUnixAddr helper)
│   │   └── SocketServer.swift  # POSIX socket actor: accept loop, parse JSON, dispatch to Database
│   │                           #   Handles: "event", "prompt", "change", "query-prompts", "template"
│   ├── Models/
│   │   ├── CommitTemplate.swift   # name (PK), body, isActive, createdAt
│   │   ├── DiffStat.swift         # Per-file, per-prompt, and aggregated diff statistics
│   │   ├── FileChange.swift       # id, eventID, filePath, toolName, timestamp
│   │   ├── FileDiff.swift         # FileDiff, DiffHunk, DiffLine — diff parsing output models
│   │   ├── HookEvent.swift        # id, sessionID, hookEventName, projectPath, timestamp, payload (JSON)
│   │   ├── PromptEvent.swift      # id, sessionID, projectPath, promptText?, timestamp, vcs?, baseCommitHash?
│   │   ├── Session.swift          # id, projectPath, startedAt, lastActivityAt
│   │   ├── TemplateRenderer.swift # Renders {{placeholder}} templates with TemplateContext data
│   │   └── VCSType.swift          # enum: .git, .mercurial
│   ├── Utilities/
│   │   └── HookHealthChecker.swift # @Observable: checks CLI installed, hooks configured, socket active
│   └── VCS/
│       ├── DiffParser.swift       # Parses unified git/hg diff output → [FileDiff]
│       ├── GitProvider.swift      # VCSProvider impl — shells out to /usr/bin/git via Process
│       ├── MercurialProvider.swift # VCSProvider impl — shells out to hg via /usr/bin/env
│       ├── RemoteURLParser.swift  # Parses git remote URLs (SSH/HTTPS) → web commit URLs
│       ├── VCSDetector.swift      # Static: walk up directory tree checking for .git/.hg
│       └── VCSProvider.swift      # Protocol + makeProvider(for:) factory
│
├── Features/
│   ├── DiffViewer/
│   │   ├── DiffDetailView.swift     # Main diff layout: header + collapsible file list + side-by-side panes
│   │   ├── DiffViewModel.swift      # @Observable: loads diffs via injected VCSProvider, builds side-by-side line pairs
│   │   ├── DiffTextView.swift       # NSViewRepresentable wrapping NSTextView (TextKit 1)
│   │   ├── DiffScrollSync.swift     # Syncs scroll position between left + right panes
│   │   └── SyntaxHighlighter.swift  # Regex-based syntax highlighting for 20+ languages
│   ├── SessionSummary/
│   │   ├── SessionSummaryView.swift       # Rich summary: prompt timeline with clickable commit SHAs, diffstat bars
│   │   └── SessionSummaryViewModel.swift  # Aggregates session data, resolves commit SHAs via git log
│   ├── Settings/
│   │   └── SettingsView.swift  # Hook status, annotation toggle + template list, diff theme picker
│   └── Setup/
│       └── SetupView.swift     # First-run guide: install CLI, configure hooks, verify socket
│
├── Resources/
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
│   │   └── SessionStateIndicator.swift  # Live/paused/stale session status indicator
│   ├── StyleGuide/
│   │   ├── AppColors.swift     # Semantic color tokens (addition, deletion, modified, muted variants)
│   │   ├── AppFonts.swift      # Semantic font tokens (filePath, numeric, sectionHeader, diffEditor)
│   │   └── AppScale.swift      # @Observable singleton — Cmd+/- zoom (0.6–2.0×), persisted to UserDefaults
│   └── Themes/
│       ├── DiffTheme.swift     # Codable color palette (diff + syntax colors, hex→NSColor)
│       └── ThemeManager.swift  # @Observable singleton — loads bundled JSON themes, persists selection
│
NoCrumbsTests/                      # Test target (hosted by app)
├── DatabaseTests.swift            # DB CRUD, migrations, cascade delete
├── DiffParserTests.swift          # 10 tests — pure unit, parses diff strings
├── DiffViewModelTests.swift       # 7 tests — MockVCSProvider injection
├── GitProviderTests.swift         # 8 tests — real temp git repos via GitTestRepo helper
├── MercurialProviderTests.swift   # hg provider unit tests with mock process
├── RemoteURLParserTests.swift     # SSH/HTTPS remote URL → commit URL parsing
└── VCSDetectorTests.swift         # 5 tests — filesystem with temp VCS markers

CLI/
├── Package.swift               # Swift 5.9, macOS 14+, zero dependencies
└── Sources/nocrumbs/
    ├── main.swift              # Subcommand dispatch: event, capture-*, annotate-commit, install*, template
    ├── CaptureEventCommand.swift  # Unified hook event → JSON to socket (v3+)
    ├── CapturePromptCommand.swift # (legacy) Parse UserPromptSubmit stdin → JSON to socket
    ├── CaptureChangeCommand.swift # (legacy) Parse PostToolUse stdin → JSON to socket
    ├── AnnotateCommitCommand.swift # Query prompts via socket → render template → append to commit message
    ├── TemplateCommand.swift      # nocrumbs template add/list/set/remove/preview
    ├── InstallCommand.swift       # Write hook config to ~/.claude/settings.json + install git hooks
    ├── Models.swift               # Minimal Codable structs (duplicated — CLI can't link app target)
    └── SocketClient.swift         # Connect + write/read to Unix socket (CLI-side, includes sendAndReceive)
```

## Database Schema

**Storage:** `~/Library/Application Support/NoCrumbs/nocrumbs.sqlite`
**Engine:** Raw SQLite3 C API (no ORM) — WAL journal mode, foreign keys ON
**Schema version:** 6 (tracked via `PRAGMA user_version`)

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,          -- Claude Code session_id (UUID string)
    projectPath TEXT NOT NULL,
    startedAt REAL NOT NULL,
    lastActivityAt REAL NOT NULL
);

CREATE TABLE promptEvents (
    id TEXT PRIMARY KEY,          -- UUID
    sessionID TEXT NOT NULL,
    projectPath TEXT NOT NULL,
    promptText TEXT,              -- NULL for orphaned file changes
    timestamp REAL NOT NULL,
    vcs TEXT,                     -- "git" or "mercurial", NULL if not in repo
    baseCommitHash TEXT,          -- git HEAD at prompt time (diff baseline) [v2]
    FOREIGN KEY(sessionID) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE TABLE fileChanges (
    id TEXT PRIMARY KEY,          -- UUID
    eventID TEXT NOT NULL,
    filePath TEXT NOT NULL,
    toolName TEXT NOT NULL,       -- "Write" or "Edit"
    timestamp REAL NOT NULL,
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
    private(set) var commitTemplates: [CommitTemplate] = []  // All templates, ordered by createdAt

    var activeTemplate: CommitTemplate? {                    // Computed from cache
        commitTemplates.first(where: \.isActive)
    }

    // Raw SQLite3 via OpaquePointer
    // WAL journal mode, foreign keys enabled
    // CRUD: upsertSession, insertPromptEvent, insertFileChange(s), deleteSession
    //       insertHookEvent, saveCommitTemplate, deleteCommitTemplate, setActiveTemplate
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

### Backfill

On startup, `Database.backfillBaseCommitHashes()` runs async:
- Finds events with NULL `baseCommitHash` and `vcs == .git`
- Uses `git log --before=<timestamp> -1 --format=%H` to find what HEAD was at prompt time
- Updates each event with the resolved hash
- Caches by `projectPath|timestamp` to avoid redundant git calls

### Injection Pattern

```swift
@main
struct NoCrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var database = Database.shared
    @State private var themeManager = ThemeManager.shared
    @State private var appScale = AppScale.shared

    var body: some Scene {
        Window("NoCrumbs", id: "main") {
            ContentView()
                .environment(database)
                .environment(themeManager)
                .environment(appScale)
                .onAppear { themeManager.loadBundledThemes() }
        }
        .commands {
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
```

## IPC: Unix Domain Socket

```
Socket path: ~/Library/Application Support/NoCrumbs/nocrumbs.sock
```

**Server** (`SocketServer`): Swift actor, POSIX `socket()/bind()/listen()/accept()`.
- Accepts connections in a detached Task loop
- Reads full message, parses JSON, dispatches by `"type"` field
- `"event"` → unified hook event handler; stores HookEvent, bridges to legacy prompt/change tables (fire-and-forget)
- `"prompt"` → (legacy) captures `git rev-parse HEAD` as baseCommitHash, upserts session + inserts PromptEvent
- `"change"` → (legacy) finds most recent event for session, attaches FileChange (or creates orphan event)
- `"query-prompts"` → returns recent prompts + file counts + annotation_enabled flag + active template body (request/response)
- `"template"` → CRUD for commit annotation templates: add, list, set, remove, preview (request/response)

**Client** (`SocketClient`):
- App-side: `send(_ data: Data)` — fire-and-forget
- CLI-side: `send(_ data: Data)` + `sendAndReceive(_ data: Data)` — the latter used for query-prompts + template
- Both use POSIX `socket()/connect()/write()/close()`

**Protocol:**
```json
// Unified event (fire-and-forget) — v3+
{"type": "event", "session_id": "abc", "hook_event_name": "UserPromptSubmit", "cwd": "/path",
 "prompt": "...", "tool_name": "Write", "tool_input": {...}}

// Legacy prompt (fire-and-forget)
{"type": "prompt", "session_id": "abc", "prompt": "...", "cwd": "/path"}

// Legacy change (fire-and-forget)
{"type": "change", "session_id": "abc", "file_path": "/path/file.swift", "tool_name": "Write", "cwd": "/path"}

// Query prompts (request/response)
{"type": "query-prompts", "cwd": "/path"}
// Response:
{"prompts": [{"text": "...", "file_count": 3}], "session_id": "abc", "total_files": 12,
 "annotation_enabled": true, "template": "---\n{{summary_line}}"}

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

The `nocrumbs` CLI (v0.3.0) is invoked by Claude Code hooks.

**`nocrumbs event`** (preferred, v3+) — unified hook event handler:
- Reads stdin JSON from any Claude Code hook
- Sends `type: "event"` with full payload to socket
- App-side bridges to legacy prompt/change tables automatically

**Legacy commands** (still supported):
- `nocrumbs capture-prompt` — `UserPromptSubmit` hook
- `nocrumbs capture-change` — `PostToolUse` hook (matcher: Write|Edit)

**`nocrumbs install`** writes hook config to `~/.claude/settings.json`, merging with existing settings.

**`nocrumbs install-git-hooks`** writes `prepare-commit-msg` hook to `.git/hooks/`.

**`nocrumbs annotate-commit <msg-file> [source]`** — called by git `prepare-commit-msg` hook:
- Queries app via `query-prompts` socket message
- If response includes `"template"` key, renders it via CLI-side template renderer
- Otherwise, uses built-in default format (summary line + top 3 prompts)
- Respects `annotation_enabled` setting from app
- Skips merge/squash commits
- Won't double-annotate (checks for existing 🍞 marker)

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
| `{{summary_line}}` | Pre-built: `🍞 3 prompts · 12 files · abc12345` |
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

**Testability:** `DiffViewModel` accepts `any VCSProvider` via init (defaults to `GitProvider()`), enabling `MockVCSProvider` injection in tests.

**Implementations:**
- `GitProvider` — shells out to `/usr/bin/git` via `Process` with async wrapper
  - `currentHead` → `git rev-parse HEAD` (captured at prompt time for diff baseline)
  - `diffFromBase` → `git diff <baseHash> -- <files>` (primary diff strategy)
  - `diffForFiles` → `git diff HEAD -- <files>` (legacy fallback)
  - `headBefore` → `git log --before=<iso> -1 --format=%H` (for backfill)
  - `untrackedFiles` → `git ls-files --others --exclude-standard -- <files>`
  - `cleanFiles` → `git status --porcelain -- <files>` (identifies committed files)
- `MercurialProvider` — shells out to `hg` via `/usr/bin/env` with async wrapper
  - `currentHead` → `hg log -r . -T {node}`
  - `diffFromBase` → `hg diff --git -r <baseHash> <files>`
  - `headBefore` → `hg log -r "date('<iso>')" -l 1 -T {node}`
  - All commands produce `--git` format diffs for DiffParser compatibility

**Detection:** `VCSDetector.detect(at:)` walks up from a path checking for `.git` or `.hg` directories.
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

**Key design: `baseCommitHash`** — every prompt event stores git HEAD at the moment it arrives.
`git diff <baseHash>` always works regardless of whether changes are uncommitted, staged, or committed.
No fallback strategies needed. Legacy events are backfilled on startup via `git log --before`.

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
├── header (prompt text, timestamp, file count)
├── HStack
│   ├── fileList (List, 180pt, sidebar style) — collapsible via sidebar.left toggle
│   ├── Divider
│   └── diffPanes
│       ├── column headers (toggle button + "Before" | "After")
│       └── diffPanesContent (HStack, maxHeight: .infinity)
│           ├── leftPane (DiffTextView or "File did not exist")
│           ├── Divider
│           └── rightPane (DiffTextView or "File was deleted")
```

**Key layout fix:** `maxHeight: .infinity` on `diffPanesContent` and each pane — required because `NSScrollView` has no intrinsic content size in SwiftUI, so without this the HStack collapses to zero height.

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

53 tests across 7 files, all in `NoCrumbsTests/` (hosted test target).

```bash
xcodebuild test -project NoCrumbs.xcodeproj -scheme NoCrumbs -sdk macosx -derivedDataPath build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

| Suite | Tests | Type | Coverage |
|-------|-------|------|----------|
| `DatabaseTests` | — | Unit | CRUD operations, migrations, cascade delete |
| `DiffParserTests` | 10 | Pure unit | Parser edge cases: empty, add, delete, modify, multi-file, multi-hunk, line numbers, binary, no-newline-at-EOF |
| `DiffViewModelTests` | 7 | Unit (mock) | All load() paths: no VCS, no files, nil base hash, invalid commit, valid diff, git failure, untracked files |
| `GitProviderTests` | 8 | Integration | Real temp git repos: currentHead, isValidCommit (valid/invalid/after-reset), diffFromBase, headBefore, untrackedFiles |
| `MercurialProviderTests` | — | Unit | Mercurial provider command construction and output parsing |
| `RemoteURLParserTests` | 12 | Pure unit | SSH/HTTPS URL parsing, edge cases, whitespace handling |
| `VCSDetectorTests` | 5 | Filesystem | Temp dirs with .git/.hg markers: detect git/hg/none, nested repos, repoRoot |

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

Three sections in the Settings form:

**Hook Status:**
- CLI installed, Hooks configured, Socket active — green/red status indicators
- Read-only, refreshes on appear via `HookHealthChecker`

**General:**
- **Annotation toggle** (`annotationEnabled`): Controls whether `nocrumbs annotate-commit` appends prompt context to commit messages
- **Commit Templates**: Lists custom templates when annotation is enabled. Click to activate, right-click to delete. Shows hint to use `nocrumbs template add` when empty.
- Stored in `UserDefaults` via `@AppStorage`
- Registered with default `true` in `AppDelegate.applicationDidFinishLaunching`
- Read by `SocketServer.handleQueryPrompts` and included in response to CLI

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
| Design tokens | `AppColors`, `AppFonts` | Semantic color/font constants, scale-aware |
| Diff panes | `NSTextView` (`NSViewRepresentable`) | TextKit 1 — battle-tested, no TextKit 2 scrolling bugs |
| Scroll sync | `DiffScrollSync` (NSView bounds observation) | Syncs left/right panes via boundsDidChangeNotification |
| Line numbers | Custom `DiffNSTextView.draw()` override | Draws gutter numbers in TextKit 1 coordinate space |
| Subprocesses | `Process` (Foundation) | Shell out to git/hg |

## App Lifecycle

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let socketServer = SocketServer()

    func applicationDidFinishLaunching(_:) {
        UserDefaults.standard.register(defaults: ["annotationEnabled": true])
        try Database.shared.open()     // SQLite + migrations (v1→v6) + cache load
        Task { await Database.shared.backfillBaseCommitHashes() }  // Async backfill for legacy events
        try await socketServer.start() // POSIX socket bind + listen (with 1s retry)
        try SMAppService.mainApp.register() // Launch at login
        NSApp.setActivationPolicy(.accessory) // Menu bar only until window opens
    }

    func applicationShouldTerminate(_:) -> TerminateReply {
        // Cmd+Q → close window + hide to menu bar (cancel terminate)
        // Real quit only from menu bar button
    }

    func applicationWillTerminate(_:) {
        await socketServer.stop()     // Close socket, unlink file
        Database.shared.close()       // Close SQLite
    }
}
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Sparkle | 2.0+ | Auto-updates (non-App Store) |
| SQLite3 | System | Raw C API via `-lsqlite3` linker flag |

**CLI:** Zero dependencies (standalone SPM binary).

**Syntax highlighting:** Regex-based (no external dependency). Replaced planned TreeSitter/Neon approach with built-in `SyntaxHighlighter` — simpler, zero dependencies, covers 20+ languages adequately for diff viewing.

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
# Mac App
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Debug \
  -sdk macosx -derivedDataPath build build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# CLI
swift build -c release --package-path CLI/

# Install CLI
cp CLI/.build/release/nocrumbs /usr/local/bin/

# Run app
open build/Build/Products/Debug/NoCrumbs.app
```

**Verify Pipeline:**
```bash
# Full E2E verification
/verify --all
```
