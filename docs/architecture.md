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
    SwiftUI Views (sidebar session tree, event detail, file changes)
               ↓ on-demand
    git/hg CLI via Process (derive diffs, never store them)

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
│   │   ├── FileChange.swift    # id, eventID, filePath, toolName, timestamp
│   │   ├── PromptEvent.swift   # id, sessionID, projectPath, promptText?, timestamp, vcs?
│   │   ├── Session.swift       # id, projectPath, startedAt, lastActivityAt
│   │   └── VCSType.swift       # enum: .git, .mercurial
│   └── VCS/
│       ├── GitProvider.swift   # VCSProvider impl — shells out to /usr/bin/git via Process
│       ├── VCSDetector.swift   # Static: walk up directory tree checking for .git/.hg
│       └── VCSProvider.swift   # Protocol: currentBranch, isValidCommit, diff, uncommittedDiff
│
├── Features/
│   └── Settings/
│       └── SettingsView.swift  # @AppStorage toggle for commit annotation (annotationEnabled)
│
├── UI/                         # (empty — Components, StyleGuide planned)
└── Tests/                      # (empty — planned)

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
**Schema version:** 1 (tracked via `PRAGMA user_version`)

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
}
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
- `"prompt"` → upserts session + inserts PromptEvent (fire-and-forget)
- `"change"` → finds most recent event for session, attaches FileChange (or creates orphan event)
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
    func currentBranch(at path: String) async throws -> String
    func isValidCommit(_ hash: String, at path: String) async throws -> Bool
    func diff(for hash: String, at path: String) async throws -> String
    func uncommittedDiff(at path: String) async throws -> String
}
```

**Implementations:**
- `GitProvider` — shells out to `/usr/bin/git` via `Process` with async wrapper
- `MercurialProvider` — not yet implemented

**Detection:** `VCSDetector.detect(at:)` walks up from a path checking for `.git` or `.hg` directories.
`VCSDetector.repoRoot(at:for:)` returns the root directory of the detected VCS repo.

## Diff Parsing

<!-- Not yet implemented -->

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
| Diff panes | STTextView (`NSViewRepresentable`) | TextKit 2, line numbers, TreeSitter (planned) |
| Subprocesses | `Process` (Foundation) | Shell out to git/hg |

## App Lifecycle

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let socketServer = SocketServer()

    func applicationDidFinishLaunching(_:) {
        UserDefaults.standard.register(defaults: ["annotationEnabled": true])
        try Database.shared.open()     // SQLite + migrations + cache load
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

**Planned (not yet added):**
| Package | Purpose |
|---------|---------|
| STTextView | TextKit 2 diff panes |
| Neon | TreeSitter syntax highlighting |

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
