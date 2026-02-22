# NoCrumbs - Claude Code Instructions

> Git blame for the AI era. Links every file change Claude Code makes back to the prompt that caused it.

## Product Context

Native Mac menu bar app + CLI for IDE-less AI coding workflows.
- **CLI** (`nocrumbs`) — PostToolUse hook, JSON to Unix domain socket, <50ms
- **Mac App** — menu bar resident, SQLite metadata, diffs derived from VCS on demand
- **Core principle:** Don't store diffs. Git already has them. Store only prompt-to-commit linkage.

For detailed architecture, schema, and data flow: see `docs/architecture.md`

## Swift Observation (`@Observable`, not `ObservableObject`)

Modern Observation framework (Swift 5.9 / macOS 14+). **Never use the old Combine-based pattern.**

| Use | Don't Use |
|-----|-----------|
| `@Observable` | `ObservableObject` |
| `@State` (for owned objects) | `@StateObject` |
| `@Environment` | `@EnvironmentObject` |
| Direct property access | `@Published` |
| `@Bindable` (for bindings) | `@ObservedObject` |

## File Placement Rules

| Type | Location |
|------|----------|
| Feature screen | `Features/[Feature]/[Feature]View.swift` |
| ViewModel | `Features/[Feature]/[Feature]ViewModel.swift` |
| Data model | `Core/Models/[Entity].swift` |
| GRDB record | `Core/Database/Records/[Entity]Record.swift` |
| VCS operations | `Core/VCS/[VCS]Provider.swift` |
| Reusable component | `UI/Components/[Component].swift` |
| Design token | `UI/StyleGuide/[Token].swift` |
| Extension | `Core/Extensions/[Type]+[Purpose].swift` |

## Database Rules

- Single source of truth: all writes through `Database` methods
- All reads from `@Observable` memory cache (instant, no DB query)
- GRDB `ValueObservation` → `@Observable` properties → SwiftUI auto-update
- Foreign key cascade deletion — single delete, SQL handles the rest
- Never bypass Database with UserDefaults or direct file writes

## Platform: macOS 14+ (NOT iOS)

- SDK: `macosx` — never `iphoneos`
- `NSApplication`, not `UIApplication`
- `NSViewRepresentable`, not `UIViewRepresentable`
- `NavigationSplitView`, not `NavigationStack`
- No haptics — visual feedback only
- No simulator — runs directly on Mac
- **Not sandboxed** — direct distribution, free subprocess/filesystem access

## Performance Rules

- `LazyVStack` for timeline — never eager load all commits
- Parse diffs off main thread, publish via `@MainActor`
- Scope ViewModels tightly per feature
- Derive diffs on demand, cache in memory with LRU eviction
- Models are `Equatable` for diff skipping
- `Process` for git/hg calls — async wrapper, never block main thread

## Anti-Patterns

```swift
// ❌ Old observation pattern
@StateObject private var db = Database.shared
@EnvironmentObject var db: Database
@Published var events: [PromptEvent] = []

// ❌ Bypass database
UserDefaults.standard.set(data, forKey: "events")

// ❌ Store diffs
database.saveDiff(diffContent)  // Derive from git on demand

// ❌ iOS patterns on macOS
UIViewRepresentable  // Use NSViewRepresentable
UIApplication.shared // Use NSApplication.shared
NavigationStack      // Use NavigationSplitView
```

## Build

```bash
# Mac App — build (output to local build/ directory)
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Debug -sdk macosx -derivedDataPath build build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# Mac App — run
open build/Build/Products/Debug/NoCrumbs.app

# CLI
swift build -c release --package-path CLI/
```

Use `/run` skill to build + launch in one step. Always verify builds before confirming fixes.

## Tests

```bash
# Run all tests
xcodebuild test -project NoCrumbs.xcodeproj -scheme NoCrumbs -sdk macosx -derivedDataPath build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

- **Test target:** `NoCrumbsTests` (hosted by app, `TEST_HOST` set)
- **Test files live in:** `NoCrumbsTests/`
- **Run tests after any change** to VCS, DiffParser, DiffViewModel, or VCSDetector code
- `DiffViewModel` accepts `any VCSProvider` via init — use `MockVCSProvider` in tests
- `GitProviderTests` use real temp git repos via `GitTestRepo` helper
- When adding new test files, register them in `project.pbxproj` (PBXFileReference + PBXBuildFile in test target's Sources build phase `39DB1C349AA47E01F3AE7896`)

## Key Design Decisions

1. **Don't store diffs** — derive from git/hg on demand. DB stays <1MB forever.
2. **Capture at commit boundary** — subagent noise discarded. Only top-level prompts + commits.
3. **CLI is fire-and-forget** — never blocks Claude Code. Silent fail if app not running.
4. **Handle dangling commits** — check if hash resolves before rendering.
5. **No network calls ever** — fully local. No API keys, accounts, or telemetry.

## Workflow

After completing a milestone, run `/sync-docs` to update `docs/architecture.md` with current codebase state.

### File Descriptions
After completing file changes, describe what changed in each file:
```bash
echo '{"session_id":"$SESSION_ID","descriptions":[{"file_path":"/abs/path/to/File.swift","description":"what changed"}]}' | nocrumbs describe
```
