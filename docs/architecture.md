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
    SwiftUI Views (Timeline, DiffViewer) — not yet implemented
               ↓ on-demand
    git/hg CLI via Process (derive diffs, never store them)
```

## Directory Structure

```
NoCrumbs/
├── App/
│   ├── AppDelegate.swift       # NSApplicationDelegate — owns SocketServer + Database lifecycle
│   ├── ContentView.swift       # NavigationSplitView placeholder
│   └── NoCrumbsApp.swift       # @main entry, MenuBarExtra, injects Database via .environment()
│
├── Core/
│   ├── Database/
│   │   └── Database.swift      # @Observable @MainActor singleton, raw SQLite3, WAL, migrations, CRUD
│   ├── IPC/
│   │   ├── SocketClient.swift  # Connect + write JSON to Unix socket (app-side, also has makeUnixAddr helper)
│   │   └── SocketServer.swift  # POSIX socket actor: accept loop, parse JSON, dispatch to Database
│   ├── Models/
│   │   ├── FileChange.swift    # id, eventID, filePath, toolName, timestamp
│   │   ├── PromptEvent.swift   # id, sessionID, projectPath, promptText?, timestamp, vcs?
│   │   ├── Session.swift       # id, projectPath, startedAt, lastActivityAt
│   │   └── VCSType.swift       # enum: .git, .mercurial
│   ├── Utilities/              # (empty — Debouncer, async helpers planned)
│   └── VCS/
│       ├── GitProvider.swift   # VCSProvider impl — shells out to /usr/bin/git via Process
│       ├── VCSDetector.swift   # Static: walk up directory tree checking for .git/.hg
│       └── VCSProvider.swift   # Protocol: currentBranch, isValidCommit, diff, uncommittedDiff
│
├── Features/                   # (empty — Timeline, DiffViewer, MenuBar, PRDraft planned)
├── UI/                         # (empty — Components, StyleGuide planned)
└── Tests/                      # (empty — planned for M2)

CLI/
├── Package.swift               # Swift 5.9, macOS 14+, zero dependencies
└── Sources/nocrumbs/
    ├── main.swift              # Subcommand dispatch: capture-prompt, capture-change, install
    ├── CapturePromptCommand.swift  # Parse UserPromptSubmit stdin → JSON to socket
    ├── CaptureChangeCommand.swift  # Parse PostToolUse stdin → JSON to socket
    ├── InstallCommand.swift    # Write dual-hook config to ~/.claude/settings.json
    ├── Models.swift            # Minimal Codable structs (duplicated — CLI can't link app target)
    └── SocketClient.swift      # Connect + write to Unix socket (CLI-side duplicate)
```

## Database Schema

**Storage:** `~/Library/Application Support/NoCrumbs/nocrumbs.sqlite`
**Engine:** Raw SQLite3 C API (no ORM) — WAL journal mode, foreign keys ON
**Schema version:** 1 (tracked via `PRAGMA user_version`)

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,          -- Claude Code session_id
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
    private(set) var recentEvents: [PromptEvent] = []  // Last 500, desc by timestamp

    // Raw SQLite3 via OpaquePointer
    // WAL journal mode, foreign keys enabled
    // CRUD: upsertSession, insertPromptEvent, insertFileChange(s), deleteSession
    // Cache refreshed after each write
}
```

### Injection Pattern

```swift
// Root — AppDelegate opens DB, NoCrumbsApp injects it
@main
struct NoCrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var database = Database.shared

    var body: some Scene {
        Window("NoCrumbs", id: "main") {
            ContentView()
                .environment(database)
        }
    }
}

// Child views
struct TimelineView: View {
    @Environment(Database.self) private var database

    var body: some View {
        ForEach(database.recentEvents) { event in ... }
    }
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
- `"prompt"` → upserts session + inserts PromptEvent
- `"change"` → finds most recent event for session, attaches FileChange (or creates orphan event)

**Client** (`SocketClient`): Static `send(_ data: Data)` method.
- POSIX `socket()/connect()/write()/close()`
- Used by CLI to send JSON to the app

**Protocol:**
```json
// Prompt message
{"type": "prompt", "session_id": "abc", "prompt": "...", "cwd": "/path"}

// Change message
{"type": "change", "session_id": "abc", "file_path": "/path/file.swift", "tool_name": "Write", "cwd": "/path"}
```

- Fire-and-forget: CLI exits 0 even on failure (never blocks Claude Code)
- No retry, no queue — if app not running, message is lost silently

## CLI Hook Integration

The `nocrumbs` CLI is invoked by Claude Code hooks. Dual-hook design:

**`UserPromptSubmit` hook** → `nocrumbs capture-prompt`
- Reads stdin JSON: `{session_id, prompt, cwd}`
- Sends `type: "prompt"` to socket

**`PostToolUse` hook** (matcher: `Write|Edit`) → `nocrumbs capture-change`
- Reads stdin JSON: `{session_id, tool_name, tool_input: {file_path}, cwd}`
- Sends `type: "change"` to socket

**`nocrumbs install`** writes hook config to `~/.claude/settings.json`, merging with existing settings.

Session ID links prompts to their file changes across the two hooks.

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

## Diff Parsing

<!-- Not yet implemented -->

## Menu Bar Behavior

- `LSUIElement = YES` — invisible to Cmd+Tab by default
- `MenuBarExtra` with `doc.text.magnifyingglass` system image
- Global hotkey `Cmd+Shift+N` to show window (TODO: M2)
- Quit from menu bar available

## SwiftUI + AppKit Hybrid

| Component | Framework | Why |
|-----------|-----------|-----|
| App lifecycle | `NSApplicationDelegateAdaptor` | Owns SocketServer + Database lifecycle |
| Timeline, chrome | SwiftUI | Native, declarative |
| Main layout | `NavigationSplitView` | Native Mac sidebar/detail pattern |
| Diff panes | STTextView (`NSViewRepresentable`) | TextKit 2, line numbers, TreeSitter (planned) |
| Menu bar | `MenuBarExtra` | Native Mac menu bar pattern |
| Subprocesses | `Process` (Foundation) | Shell out to git/hg |

## App Lifecycle

```swift
// AppDelegate owns long-lived services
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let socketServer = SocketServer()

    func applicationDidFinishLaunching(_:) {
        try Database.shared.open()    // SQLite + migrations + cache load
        try await socketServer.start() // POSIX socket bind + listen
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
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT * FROM promptEvents;"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT * FROM fileChanges;"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "PRAGMA user_version;"
```

**Check Socket:**
```bash
ls -la ~/Library/Application\ Support/NoCrumbs/nocrumbs.sock
# Test manually:
echo '{"session_id":"test","prompt":"hello","cwd":"/tmp"}' | nocrumbs capture-prompt
echo '{"session_id":"test","tool_name":"Write","tool_input":{"file_path":"test.swift"},"cwd":"/tmp"}' | nocrumbs capture-change
```

**Console Logs (OSLog categories):**
- `[NC:App]` — App lifecycle (Database open, SocketServer start)
- `[NC:Socket]` — IPC operations (message received, dispatch)
- `[NC:DB]` — Database operations (📦 open, 🔄 migration, ✅ success, ❌ error)
- `[NC:Git]` — Git subprocess operations

**Build:**
```bash
# Mac App
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Debug \
  -sdk macosx -derivedDataPath build build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# CLI
swift build --package-path CLI/

# Run app
open build/Build/Products/Debug/NoCrumbs.app
```
