# NoCrumbs Architecture

> Detailed architecture reference. Auto-updated via `/sync-docs`.

## Data Flow

```
Claude Code PostToolUse hook
    ↓
nocrumbs CLI (fire-and-forget, <50ms)
    ↓ JSON via Unix domain socket
NoCrumbs.app SocketServer
    ↓
Database.shared (GRDB + reactive cache)
    ↓ ValueObservation → @Observable properties
SwiftUI Views (Timeline, DiffViewer)
    ↓ on-demand
git/hg CLI (derive diffs, never store them)
```

## Directory Structure

```
NoCrumbs/
├── App/                    # SwiftUI Mac app entry point
│   └── NoCrumbsApp.swift
│
├── CLI/                    # nocrumbs binary (SPM standalone)
│   └── Sources/
│       └── nocrumbs/
│
├── Core/                   # Shared business logic
│   ├── Models/            # Pure data structures (PromptEvent, Session, VCSType)
│   ├── Database/          # GRDB singleton, records, reactive cache
│   ├── IPC/               # Unix domain socket server + client
│   ├── VCS/               # Git/Hg CLI wrappers, diff parsing
│   └── Utilities/         # Debouncer, async helpers
│
├── Features/              # Feature modules
│   ├── Timeline/          # Collapsible commit/prompt timeline
│   ├── DiffViewer/        # Two-pane side-by-side diff (STTextView)
│   ├── MenuBar/           # NSStatusItem, MenuBarExtra, badge
│   └── PRDraft/           # v2: PR description generation
│
├── UI/                    # Reusable components and design system
│   ├── Components/
│   └── StyleGuide/        # Colors, Typography, Spacing
│
└── Tests/
```

## Database Schema

**Storage:** `~/Library/Application Support/NoCrumbs/nocrumbs.sqlite`

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    projectPath TEXT NOT NULL,
    startedAt REAL NOT NULL,
    lastActivityAt REAL NOT NULL
);

CREATE TABLE promptEvents (
    id TEXT PRIMARY KEY,
    sessionID TEXT NOT NULL,
    commitHash TEXT,           -- nil if uncommitted at capture time
    projectPath TEXT NOT NULL,
    promptText TEXT NOT NULL,
    summary TEXT,
    filesChanged TEXT NOT NULL, -- JSON array
    timestamp REAL NOT NULL,
    vcs TEXT NOT NULL,          -- "git" or "mercurial"
    FOREIGN KEY(sessionID) REFERENCES sessions(id) ON DELETE CASCADE
);
```

Foreign key cascade: deleting a session automatically deletes its promptEvents.

## Database Singleton

```swift
@Observable
final class Database {
    static let shared = Database()

    var promptEvents: [PromptEvent] = []
    var sessions: [Session] = []

    // GRDB ValueObservation updates these properties directly
    // SwiftUI tracks reads automatically, re-renders only what changed
}
```

### Injection Pattern

```swift
// Root
@main
struct NoCrumbsApp: App {
    @State private var database = Database.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(database)
        }
    }
}

// Child views
struct TimelineView: View {
    @Environment(Database.self) private var database

    var body: some View {
        ForEach(database.promptEvents) { event in ... }
    }
}
```

### Write Pattern

```swift
// All writes through Database methods
try database.savePromptEvent(event)
// ValueObservation → @Observable property update → SwiftUI re-render
```

## IPC: Unix Domain Socket

```
Socket path: ~/Library/Application Support/NoCrumbs/nocrumbs.sock
```

- CLI writes JSON, exits immediately
- App's SocketServer reads, parses, saves to DB
- Non-blocking: if app not running, CLI fails silently
- No retry, no queue — fire and forget

## VCS Abstraction

```swift
protocol VCSProvider {
    func detectVCS(at path: String) -> VCSType?
    func diff(commitHash: String, file: String?) async throws -> String
    func currentBranch(at path: String) async throws -> String
    func isValidCommit(_ hash: String, at path: String) async throws -> Bool
}
```

Two implementations: `GitProvider`, `MercurialProvider`. Both shell out to CLI via `Process`.

## Diff Parsing

Parse unified diff format into view-ready structs:

```swift
struct DiffFile: Identifiable, Equatable {
    let id: String          // file path
    let oldPath: String
    let newPath: String
    let hunks: [DiffHunk]
}

struct DiffHunk: Identifiable, Equatable {
    let id: String
    let header: String      // @@ -x,y +a,b @@
    let lines: [DiffLine]
}

struct DiffLine: Identifiable, Equatable {
    let id: String
    let type: LineType      // .addition, .deletion, .context
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}
```

All `Equatable` for SwiftUI diff skipping. Stable IDs on everything.

## Menu Bar Behavior

- `LSUIElement = YES` — invisible to Cmd+Tab by default
- Dynamic activation policy: `.regular` when window open, `.accessory` when closed
- Global hotkey `Cmd+Shift+N` to show/hide
- Badge on menu bar icon when new activity while window hidden
- Launch at login via `SMAppService`

## SwiftUI + AppKit Hybrid

| Component | Framework | Why |
|-----------|-----------|-----|
| Timeline, chrome | SwiftUI | Native, declarative |
| Main layout | `NavigationSplitView` | Native Mac sidebar/detail pattern |
| Diff panes | STTextView (`NSViewRepresentable`) | TextKit 2, line numbers, TreeSitter |
| Scroll sync | `NSScrollView` delegate bridged | SwiftUI can't sync two scroll views |
| Menu bar | `MenuBarExtra` / `NSStatusItem` | Native Mac menu bar pattern |
| Window chrome | `NSWindow` configuration | Title bar style, toolbar |
| Subprocesses | `Process` (Foundation) | Shell out to git/hg/claude |

## macOS Window Management

```swift
Window("NoCrumbs", id: "main") {
    ContentView()
}
.defaultSize(width: 1000, height: 700)

MenuBarExtra("NoCrumbs", systemImage: "doc.text.magnifyingglass") {
    MenuBarView()
}
.menuBarExtraStyle(.menu)
```

## Keyboard Shortcuts

```swift
.keyboardShortcut("n", modifiers: [.command, .shift])  // Global show/hide
.keyboardShortcut("[", modifiers: .command)              // Previous prompt
.keyboardShortcut("]", modifiers: .command)              // Next prompt
```

## Dependencies (SPM)

| Package | Purpose |
|---------|---------|
| GRDB.swift | SQLite with reactive queries |
| STTextView | TextKit 2 diff panes |
| Neon (STTextView plugin) | TreeSitter syntax highlighting |
| Sparkle | Auto-updates (non-App Store) |

## Debugging

**Check Database:**
```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite ".schema"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT COUNT(*) FROM promptEvents;"
```

**Check Socket:**
```bash
ls -la ~/Library/Application\ Support/NoCrumbs/nocrumbs.sock
nocrumbs event --project "$(pwd)" --files "test.swift"
```

**Console Logs:**
- `[NC]` prefix for all NoCrumbs log output
- `[NC:Socket]` — IPC operations
- `[NC:DB]` — Database operations
- `[NC:VCS]` — Git/Hg operations
