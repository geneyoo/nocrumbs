# NoCrumbs - Claude Code Instructions

> Git blame for the AI era. Links every file change Claude Code makes back to the prompt that caused it.

## Product Context

Native Mac menu bar app for IDE-less AI coding workflows. Two components:
- **CLI** (`nocrumbs`) — fires via Claude Code `PostToolUse` hook, writes JSON to Unix domain socket, exits <50ms
- **Mac App** — menu bar resident, receives events, stores metadata in SQLite, derives diffs on demand from VCS

**Core principle:** Don't store diffs. Git already has them. Store only prompt-to-commit linkage.

## Code Organization

Feature-based folder structure with clear separation of concerns.

### Directory Structure

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

### File Placement Rules

| Type | Location |
|------|----------|
| Feature screen | `Features/[Feature]/[Feature]View.swift` |
| Data model | `Core/Models/[Entity].swift` |
| GRDB record | `Core/Database/Records/[Entity]Record.swift` |
| VCS operations | `Core/VCS/[VCS]Provider.swift` |
| Reusable component | `UI/Components/[Component].swift` |
| Design token | `UI/StyleGuide/[Token].swift` |

### Naming Conventions

- Views: `[Purpose]View.swift`
- ViewModels: `[Purpose]ViewModel.swift`
- Records: `[Entity]Record.swift`
- Providers: `[Domain]Provider.swift`
- Extensions: `[Type]+[Purpose].swift`

## Swift Observation (`@Observable`, not `ObservableObject`)

NoCrumbs uses the modern Observation framework (Swift 5.9 / macOS 14+). **Do NOT use the old Combine-based pattern.**

### The Rules

| Use | Don't Use |
|-----|-----------|
| `@Observable` | `ObservableObject` |
| `@State` (for owned objects) | `@StateObject` |
| `@Environment` | `@EnvironmentObject` |
| Direct property access | `@Published` |
| `@Bindable` (for bindings) | `@ObservedObject` |

### Database (Singleton)

```swift
// ✅ CORRECT: @Observable macro
@Observable
final class Database {
    static let shared = Database()

    // Just regular properties — no @Published needed
    var promptEvents: [PromptEvent] = []
    var sessions: [Session] = []

    // GRDB ValueObservation updates these properties directly
    // SwiftUI tracks reads automatically, re-renders only what changed
}
```

### Injection

```swift
// ✅ CORRECT: @State at root, @Environment down the tree
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
        // SwiftUI auto-tracks which properties you read
        ForEach(database.promptEvents) { event in ... }
    }
}

// ❌ WRONG: Old Combine pattern
@StateObject private var database = Database.shared   // NO
@EnvironmentObject var database: Database              // NO
@Published var events: [PromptEvent] = []              // NO
```

### ViewModels

```swift
// ✅ CORRECT: @Observable ViewModel
@Observable
final class TimelineViewModel {
    var selectedEvent: PromptEvent?
    var isLoading = false
    var expandedCommits: Set<String> = []
}

// Owned by the view via @State
struct TimelineView: View {
    @State private var viewModel = TimelineViewModel()
}

// For bindings to @Observable properties
struct DetailView: View {
    @Bindable var viewModel: TimelineViewModel
}
```


## Architecture

### Data Flow

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

### GRDB Database

Single source of truth with reactive memory cache. GRDB `ValueObservation` feeds into `@Observable` properties — SwiftUI re-renders automatically.

**Schema:**
```sql
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

CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    projectPath TEXT NOT NULL,
    startedAt REAL NOT NULL,
    lastActivityAt REAL NOT NULL
);
```

**Rules:**
```swift
// ✅ CORRECT: All writes through Database
try database.savePromptEvent(event)
// UI updates automatically via ValueObservation → @Observable

// ❌ WRONG: Bypass Database
UserDefaults.standard.set(data, forKey: "events")
```

**Storage:** `~/Library/Application Support/NoCrumbs/nocrumbs.sqlite`

### IPC: Unix Domain Socket

```
Socket path: ~/Library/Application Support/NoCrumbs/nocrumbs.sock
```

- CLI writes JSON, exits immediately
- App's SocketServer reads, parses, saves to DB
- Non-blocking: if app not running, CLI fails silently
- No retry, no queue — fire and forget

### VCS Abstraction

```swift
protocol VCSProvider {
    func detectVCS(at path: String) -> VCSType?
    func diff(commitHash: String, file: String?) async throws -> String
    func currentBranch(at path: String) async throws -> String
    func isValidCommit(_ hash: String, at path: String) async throws -> Bool
}
```

Two implementations: `GitProvider`, `MercurialProvider`. Both shell out to CLI.

### Diff Parsing

Parse unified diff format from VCS CLI output into:
```swift
struct DiffFile: Identifiable, Equatable { ... }
struct DiffHunk: Identifiable, Equatable { ... }
struct DiffLine: Identifiable, Equatable { ... }
```
All `Equatable` to skip unnecessary SwiftUI redraws. Stable IDs on everything.

## Mac App Specifics

### Menu Bar Behavior

- `LSUIElement = YES` — invisible to Cmd+Tab by default
- Dynamic activation policy: `.regular` when window open, `.accessory` when closed
- Global hotkey `Cmd+Shift+N` to show/hide
- Badge on menu bar icon when new activity while window hidden
- Launch at login via `SMAppService`

### SwiftUI + AppKit Hybrid

| Component | Framework | Why |
|-----------|-----------|-----|
| Timeline, chrome | SwiftUI | Native, declarative |
| Main layout | `NavigationSplitView` | Native Mac sidebar/detail pattern |
| Diff panes | STTextView (`NSViewRepresentable`) | TextKit 2, line numbers, TreeSitter |
| Scroll sync | `NSScrollView` delegate bridged | SwiftUI can't sync two scroll views |
| Menu bar | `MenuBarExtra` / `NSStatusItem` | Native Mac menu bar pattern |
| Window chrome | `NSWindow` configuration | Title bar style, toolbar |
| Subprocesses | `Process` (Foundation) | Shell out to git/hg/claude |

### Performance Rules

- `LazyVStack` for timeline — never eager load all commits
- Parse diffs off main thread, publish via `@MainActor`
- Scope ViewModels tightly per feature
- Derive diffs on demand, cache in memory with LRU eviction
- Models are `Equatable` for diff skipping
- Use `Process` for git/hg calls — async wrapper, never block main thread

## Platform: macOS

**Target:** macOS 14+ (Sonoma). This is NOT an iOS app.

### macOS Reminders (NOT iOS)

- SDK: `macosx` — never `iphoneos` or `iphonesimulator`
- App lifecycle: `NSApplication`, not `UIApplication`
- Views: `NSViewRepresentable`, not `UIViewRepresentable`
- Window management: `NSWindow`, `NSPanel`, `MenuBarExtra`
- Navigation: `NavigationSplitView`, window-based — not `NavigationStack`
- No haptics — use visual feedback (animations, highlights)
- No touch targets — standard Mac hit targets
- No simulator — runs directly on Mac
- **Not sandboxed** — direct distribution, free subprocess/filesystem access

### macOS-Specific Patterns

**Window Management:**
```swift
// Main window with toolbar
Window("NoCrumbs", id: "main") {
    ContentView()
}
.defaultSize(width: 1000, height: 700)

// Menu bar presence
MenuBarExtra("NoCrumbs", systemImage: "doc.text.magnifyingglass") {
    MenuBarView()
}
.menuBarExtraStyle(.menu)
```

**Keyboard Shortcuts (Mac-first):**
```swift
.keyboardShortcut("n", modifiers: [.command, .shift])  // Global show/hide
.keyboardShortcut("[", modifiers: .command)              // Previous prompt
.keyboardShortcut("]", modifiers: .command)              // Next prompt
```

**No Haptics:** Mac has no haptic feedback API. Use visual feedback (animations, highlights) instead.

**NSViewRepresentable (not UIViewRepresentable):**
```swift
struct DiffTextView: NSViewRepresentable {
    func makeNSView(context: Context) -> STTextView { ... }
    func updateNSView(_ nsView: STTextView, context: Context) { ... }
}
```

**Process/Subprocess Access:** Not sandboxed — can freely shell out to `git`, `hg`, `claude` CLI. No entitlements needed for filesystem or subprocess access.

## Build

### Mac App
```bash
# Build without signing (syntax check)
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Debug -sdk macosx clean build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# Build with signing
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Debug -sdk macosx clean build CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=H32EKFDL92
```

### CLI
```bash
swift build -c release --package-path CLI/
# Binary at: CLI/.build/release/nocrumbs
```

### Run (macOS — no simulator needed)
```bash
# Run the built app directly
open ~/Library/Developer/Xcode/DerivedData/NoCrumbs-*/Build/Products/Debug/NoCrumbs.app
```

### Always verify builds before confirming fixes.

## Dependencies (SPM)

| Package | Purpose |
|---------|---------|
| GRDB.swift | SQLite with reactive queries |
| STTextView | TextKit 2 diff panes |
| Neon (STTextView plugin) | TreeSitter syntax highlighting |
| Sparkle | Auto-updates (non-App Store) |

## Key Design Decisions

1. **Don't store diffs** — derive from git/hg on demand. DB stays <1MB forever.
2. **Capture at commit boundary** — subagent noise discarded. Only top-level prompts + commits.
3. **CLI is fire-and-forget** — never blocks Claude Code. Silent fail if app not running.
4. **Handle dangling commits** — check if hash resolves before rendering. Show "commit no longer exists" if rebased/force-pushed.
5. **No network calls ever** — fully local. No API keys, accounts, or telemetry.
6. **PR drafting uses `claude` CLI** — invokes user's own subscription as subprocess. Zero API costs.

## Debugging

**Check Database:**
```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite ".schema"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT COUNT(*) FROM promptEvents;"
```

**Check Socket:**
```bash
# Verify socket exists
ls -la ~/Library/Application\ Support/NoCrumbs/nocrumbs.sock

# Test CLI → app pipeline
nocrumbs event --project "$(pwd)" --files "test.swift"
```

**Console Logs:**
- `[NC]` prefix for all NoCrumbs log output
- `[NC:Socket]` — IPC operations
- `[NC:DB]` — Database operations
- `[NC:VCS]` — Git/Hg operations
