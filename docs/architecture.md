# NoCrumbs Architecture

> Detailed architecture reference. Auto-updated via `/sync-docs`.

## Data Flow

```
Claude Code hooks (dual-hook design)
    ↓ UserPromptSubmit         ↓ PostToolUse (Write|Edit)
nocrumbs capture-prompt    nocrumbs capture-change
    ↓ stdin JSON parsing       ↓ stdin JSON parsing
    ↓ session_id links prompts to file changes
    └──────────┬───────────────┘
               ↓ JSON via Unix domain socket
    NoCrumbs.app SocketServer (POSIX, actor)
               ↓
    Database.shared (raw SQLite3 C API, WAL mode)
               ↓ @Observable properties (in-memory cache)
    SwiftUI Views (sidebar session tree, diff detail view)
               ↓ on-demand
    git CLI via Process (derive diffs, never store them)
               ↓
    DiffParser → [FileDiff] → side-by-side line pairs
               ↓
    DiffTextView (NSTextView via NSViewRepresentable)

Commit annotation (M2):
    git prepare-commit-msg hook
        → nocrumbs annotate-commit $1
            → query-prompts via socket (request/response)
            → append prompt summary to commit message
            → respects annotation_enabled setting from app
```

## Directory Structure

```
NoCrumbs/
├── App/
│   ├── AppDelegate.swift       # NSApplicationDelegate — owns SocketServer + Database lifecycle
│   │                           #   Global hotkey (Cmd+Shift+N), launch at login, activation policy
│   ├── ContentView.swift       # NavigationSplitView — flat sidebar with session/event tree
│   │                           #   SidebarState (@Observable class), NSEvent key monitor for Option+Arrow
│   │                           #   SessionDetailView, EventDetailView (private structs)
│   └── NoCrumbsApp.swift       # @main entry, Window + Settings + MenuBarExtra scenes
│
├── Core/
│   ├── Database/
│   │   └── Database.swift      # @Observable @MainActor singleton, raw SQLite3, WAL, migrations, CRUD
│   │                           #   fileChangesCache: [UUID: [FileChange]] — in-memory join cache
│   ├── IPC/
│   │   ├── SocketClient.swift  # Connect + write JSON to Unix socket (app-side, also has makeUnixAddr helper)
│   │   └── SocketServer.swift  # POSIX socket actor: accept loop, parse JSON, dispatch to Database
│   │                           #   Handles: "prompt", "change", "query-prompts" (request/response)
│   ├── Models/
│   │   ├── FileDiff.swift      # FileDiff, DiffHunk, DiffLine — diff parsing output models
│   │   ├── FileChange.swift    # id, eventID, filePath, toolName, timestamp
│   │   ├── PromptEvent.swift   # id, sessionID, projectPath, promptText?, timestamp, vcs?, baseCommitHash?
│   │   ├── Session.swift       # id, projectPath, startedAt, lastActivityAt
│   │   └── VCSType.swift       # enum: .git, .mercurial
│   └── VCS/
│       ├── DiffParser.swift    # Parses unified git diff output → [FileDiff]
│       ├── GitProvider.swift   # VCSProvider impl — shells out to /usr/bin/git via Process
│       ├── VCSDetector.swift   # Static: walk up directory tree checking for .git/.hg
│       └── VCSProvider.swift   # Protocol: currentBranch, isValidCommit, diff, diffFromBase, currentHead, headBefore, untrackedFiles
│
├── Features/
│   ├── DiffViewer/
│   │   ├── DiffDetailView.swift     # Main diff layout: header + collapsible file list + side-by-side panes
│   │   ├── DiffViewModel.swift      # @Observable: loads diffs via injected VCSProvider, builds side-by-side line pairs
│   │   ├── DiffTextView.swift       # NSViewRepresentable wrapping NSTextView (TextKit 1)
│   │   ├── DiffScrollSync.swift     # Syncs scroll position between left + right panes
│   │   └── SyntaxHighlighter.swift  # Regex-based syntax highlighting for 20+ languages
│   └── Settings/
│       └── SettingsView.swift  # @AppStorage toggle for commit annotation (annotationEnabled)
│
├── Resources/
│   └── Themes/
│       └── gruvbox-dark.json   # Default color theme (bundled JSON)
│
├── UI/
│   └── Themes/
│       ├── DiffTheme.swift     # Codable color palette (diff + syntax colors, hex→NSColor)
│       └── ThemeManager.swift  # @Observable singleton — loads bundled JSON themes
│
NoCrumbsTests/                      # Test target (hosted by app)
├── DiffParserTests.swift           # 10 tests — pure unit, parses diff strings
├── DiffViewModelTests.swift        # 7 tests — MockVCSProvider injection
├── GitProviderTests.swift          # 8 tests — real temp git repos via GitTestRepo helper
└── VCSDetectorTests.swift          # 5 tests — filesystem with temp VCS markers

CLI/
├── Package.swift               # Swift 5.9, macOS 14+, zero dependencies
└── Sources/nocrumbs/
    ├── main.swift              # Subcommand dispatch: capture-prompt, capture-change, annotate-commit, install, install-git-hooks
    ├── CapturePromptCommand.swift  # Parse UserPromptSubmit stdin → JSON to socket
    ├── CaptureChangeCommand.swift  # Parse PostToolUse stdin → JSON to socket
    ├── AnnotateCommitCommand.swift # Query prompts via socket → append to commit message
    ├── InstallCommand.swift    # Write dual-hook config to ~/.claude/settings.json + install git hooks
    ├── Models.swift            # Minimal Codable structs (duplicated — CLI can't link app target)
    └── SocketClient.swift      # Connect + write/read to Unix socket (CLI-side, includes sendAndReceive)
```

## Database Schema

**Storage:** `~/Library/Application Support/NoCrumbs/nocrumbs.sqlite`
**Engine:** Raw SQLite3 C API (no ORM) — WAL journal mode, foreign keys ON
**Schema version:** 2 (tracked via `PRAGMA user_version`)

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
    FOREIGN KEY(eventID) REFERENCES promptEvents(id) ON DELETE CASCADE
);

-- Indexes
CREATE INDEX idx_promptEvents_sessionID ON promptEvents(sessionID);
CREATE INDEX idx_promptEvents_timestamp ON promptEvents(timestamp);
CREATE INDEX idx_fileChanges_eventID ON fileChanges(eventID);
CREATE INDEX idx_fileChanges_filePath ON fileChanges(filePath);
```

**Design decision:** `fileChanges` is a separate table (not a JSON array) so a single prompt that touches 100+ files scales with indexed queries. Enables "show all prompts that touched file X" lookups.

Foreign key cascade: deleting a session cascades to its promptEvents, which cascades to their fileChanges.

## Database Singleton

```swift
@Observable
@MainActor
final class Database {
    static let shared = Database()

    private(set) var sessions: [Session] = []
    private(set) var recentEvents: [PromptEvent] = []       // Last 500, desc by timestamp
    private(set) var fileChangesCache: [UUID: [FileChange]]  // In-memory join cache

    // Raw SQLite3 via OpaquePointer
    // WAL journal mode, foreign keys enabled
    // CRUD: upsertSession, insertPromptEvent, insertFileChange(s), deleteSession
    // Queries: eventsForSession, recentEvents(forProject:since:), fileChangeCount, totalFileCount
    // Cache refreshed after each write
    // backfillBaseCommitHashes() — async, fills NULL baseCommitHash via git log --before
}
```

### Migrations

- **v1**: Initial schema (sessions, promptEvents, fileChanges with indexes)
- **v2**: `ALTER TABLE promptEvents ADD COLUMN baseCommitHash TEXT`

### Backfill

On startup, `Database.backfillBaseCommitHashes()` runs async:
- Finds events with NULL `baseCommitHash` and `vcs == .git`
- Uses `git log --before=<timestamp> -1 --format=%H` to find what HEAD was at prompt time
- Updates each event with the resolved hash
- Caches by `projectPath|timestamp` to avoid redundant git calls
```

### Injection Pattern

```swift
@main
struct NoCrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var database = Database.shared

    var body: some Scene {
        Window("NoCrumbs", id: "main") {
            ContentView()
                .environment(database)
        }

        Settings {
            SettingsView()
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
```

## IPC: Unix Domain Socket

```
Socket path: ~/Library/Application Support/NoCrumbs/nocrumbs.sock
```

**Server** (`SocketServer`): Swift actor, POSIX `socket()/bind()/listen()/accept()`.
- Accepts connections in a detached Task loop
- Reads full message, parses JSON, dispatches by `"type"` field
- `"prompt"` → captures `git rev-parse HEAD` as baseCommitHash, upserts session + inserts PromptEvent (fire-and-forget)
- `"change"` → finds most recent event for session, attaches FileChange (or creates orphan event with baseCommitHash)
- `"query-prompts"` → returns recent prompts + file counts + annotation_enabled flag (request/response)

**Client** (`SocketClient`):
- App-side: `send(_ data: Data)` — fire-and-forget
- CLI-side: `send(_ data: Data)` + `sendAndReceive(_ data: Data)` — the latter used for query-prompts
- Both use POSIX `socket()/connect()/write()/close()`

**Protocol:**
```json
// Prompt message (fire-and-forget)
{"type": "prompt", "session_id": "abc", "prompt": "...", "cwd": "/path"}

// Change message (fire-and-forget)
{"type": "change", "session_id": "abc", "file_path": "/path/file.swift", "tool_name": "Write", "cwd": "/path"}

// Query prompts (request/response)
{"type": "query-prompts", "cwd": "/path"}
// Response:
{"prompts": [{"text": "...", "file_count": 3}], "session_id": "abc", "total_files": 12, "annotation_enabled": true}
```

- Fire-and-forget: CLI exits 0 even on failure (never blocks Claude Code)
- No retry, no queue — if app not running, message is lost silently

## CLI Hook Integration

The `nocrumbs` CLI (v0.2.0) is invoked by Claude Code hooks. Dual-hook design:

**`UserPromptSubmit` hook** → `nocrumbs capture-prompt`
- Reads stdin JSON: `{session_id, prompt, cwd}`
- Sends `type: "prompt"` to socket

**`PostToolUse` hook** (matcher: `Write|Edit`) → `nocrumbs capture-change`
- Reads stdin JSON: `{session_id, tool_name, tool_input: {file_path}, cwd}`
- Sends `type: "change"` to socket

**`nocrumbs install`** writes hook config to `~/.claude/settings.json`, merging with existing settings.

**`nocrumbs install-git-hooks`** writes `prepare-commit-msg` hook to `.git/hooks/`.

**`nocrumbs annotate-commit <msg-file> [source]`** — called by git `prepare-commit-msg` hook:
- Queries app via `query-prompts` socket message
- Respects `annotation_enabled` setting from app
- Skips merge/squash commits
- Appends prompt summary block (up to 3 prompts, truncated to 72 chars)
- Won't double-annotate (checks for existing marker)

Session ID links prompts to their file changes across the two hooks.

## Sidebar Architecture

The sidebar uses a **flat list** pattern — no `Section` or `DisclosureGroup` (both break `List(selection:)` tag propagation on macOS).

```swift
@MainActor @Observable
private final class SidebarState {
    var selection: UUID?
    var expandedSessions: Set<String> = []
    var keyMonitor: Any?  // NSEvent local monitor
}

private struct SidebarItem: Identifiable {
    let id: UUID           // Same type as List selection binding
    let kind: Kind         // .session or .event
    let session: Session?
    let event: PromptEvent?
}
```

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
- `MercurialProvider` — not yet implemented

**Detection:** `VCSDetector.detect(at:)` walks up from a path checking for `.git` or `.hg` directories.
`VCSDetector.repoRoot(at:for:)` returns the root directory of the detected VCS repo.

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

**`DiffTheme`** (Codable struct): Defines all colors for diff rendering and syntax highlighting:
- Diff colors: background, foreground, addedBackground, removedBackground, contextBackground, lineNumber
- Syntax colors: comment, string, keyword, type, number, preprocessor, property
- Hex strings → `NSColor` via computed properties

**`ThemeManager`** (@Observable singleton): Loads bundled `.json` theme files, exposes `currentTheme` and `availableThemes`.

**Default theme**: Gruvbox Dark — warm, low-contrast palette optimized for code reading.

## Test Infrastructure (M3.5)

30 tests across 4 files, all in `NoCrumbsTests/` (hosted test target).

```bash
xcodebuild test -project NoCrumbs.xcodeproj -scheme NoCrumbs -sdk macosx -derivedDataPath build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

| Suite | Tests | Type | Coverage |
|-------|-------|------|----------|
| `DiffParserTests` | 10 | Pure unit | Parser edge cases: empty, add, delete, modify, multi-file, multi-hunk, line numbers, binary, no-newline-at-EOF |
| `DiffViewModelTests` | 7 | Unit (mock) | All load() paths: no VCS, no files, nil base hash, invalid commit, valid diff, git failure, untracked files |
| `GitProviderTests` | 8 | Integration | Real temp git repos: currentHead, isValidCommit (valid/invalid/after-reset), diffFromBase, headBefore, untrackedFiles |
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

- **Annotation toggle** (`annotationEnabled`): Controls whether `nocrumbs annotate-commit` appends prompt context to commit messages
- Stored in `UserDefaults` via `@AppStorage`
- Registered with default `true` in `AppDelegate.applicationDidFinishLaunching`
- Read by `SocketServer.handleQueryPrompts` and included in response to CLI
- Accessible via native Settings scene (`Cmd+,`) or menu bar "Settings..."

## SwiftUI + AppKit Hybrid

| Component | Framework | Why |
|-----------|-----------|-----|
| App lifecycle | `NSApplicationDelegateAdaptor` | Owns SocketServer + Database lifecycle, hotkey, activation policy |
| Sidebar + detail | SwiftUI `NavigationSplitView` | Native Mac sidebar/detail pattern |
| Session tree | SwiftUI `List(selection:)` | Flat list with manual expand/collapse |
| Key monitoring | `NSEvent.addLocalMonitorForEvents` | Intercepts Option+Arrow before NSOutlineView |
| Menu bar | `MenuBarExtra` | Native Mac menu bar pattern |
| Settings | SwiftUI `Settings` scene | Native Cmd+, integration |
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
        try Database.shared.open()     // SQLite + migrations (v1→v2) + cache load
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
- `[NC:Socket]` — IPC operations (message received, dispatch, query-prompts)
- `📦 [DB]` — Database operations (open, migration, close)
- `✅ [DB]` — Successful writes (upsert, insert, delete)
- `❌ [DB]` — Database errors
- `[NC:Git]` — Git subprocess operations
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
