# NoCrumbs — Project Plan
> Git blame for the AI era. See every decision Claude Code made in your codebase and why.

---

## Vision

A native Mac menu bar app that gives engineers a beautiful, always-on view of everything Claude Code (or Codex CLI) does to their codebase — automatically, with zero changes to workflow. Built for IDE-less AI coding workflows where the terminal + Claude Code is the full stack.

**Core insight:** When AI writes code, the "author" is a prompt. Traditional diff tools show *what* changed. NoCrumbs shows *what* changed and *why* — linking every file change back to the prompt that caused it.

**Core experience:** A live companion window alongside your terminal. You type a prompt, Claude makes changes across 10+ files, and NoCrumbs instantly shows you what changed — organized by the prompt you just typed, not buried in a `git diff` wall. Like Kaleidoscope meets git blame, organized by AI prompts instead of commits.

---

## Problem Statement

Claude Code with subagents, plan mode, todos, and parallel agents generates massive activity logs. Engineers working IDE-less have no good way to:
- Review what the AI actually changed
- Understand the intent behind each change
- Navigate a session's history prompt by prompt
- Draft PR descriptions from session context

Cursor and VS Code have inline ephemeral diffs — gone when the session closes, IDE-bound, no persistent history. NoCrumbs is the real-time companion that's always there — updating live as Claude works, persistent across sessions, and organized by intent.

---

## What NoCrumbs Is Not

- Not an inline editor diff (that's Cursor's job — diffs injected into your source files)
- Not a code review bot
- Not another thing that needs an API key
- Not a cloud service
- Not an IDE plugin

---

## Core Features (v1)

### 1. Zero-friction capture
Claude Code triggers NoCrumbs via dual hooks (`UserPromptSubmit` + `PostToolUse`) — deterministic, not CLAUDE.md (which gets ignored). No commands, no extra steps. Install once, works forever.

### 2. Prompt → file change linkage
Every file change is linked to the prompt that caused it via session ID. Like git blame but for AI decisions. Subagent noise is filtered out — only top-level user prompts are captured.

### 3. Collapsible commit/prompt timeline
```
▼ Commit 2  — "refactor auth to async/await"        [3 files]
    ▼ Prompt 3 — "clean up error handling"           [auth.swift]
    ▼ Prompt 2 — "remove completion handlers"        [auth.swift, user.swift]
    ▶ Prompt 1 — "convert fetchUser to async"        [user.swift]

▶ Commit 1  — "add login flow"                       [5 files]
```
Chevron fold/expand per commit. Click a prompt → loads that diff in the right pane.

### 4. Two-pane diff viewer
Clean side-by-side diff with syntax highlighting. Before on left, after on right. Prompt header above showing intent.

### 5. Git + Mercurial support
Detects VCS automatically (`.git` vs `.hg`). Same unified diff format, just different commands. ~1 day of extra work.

### 6. Commit message annotation
Automatically appends prompt history to commit messages — below a `---` separator so it never interferes with existing templates (Phabricator, Conventional Commits, Jira prefixes, etc).

```
refactor: convert auth to async/await

Summary: Converted auth module from completion handlers to async/await.
Test Plan: Run AuthTests

---
🍞 2 prompts · 4 files · session abc123
› refactor auth to async/await
› add error handling to the new async methods
```

- Appends to the end, after whatever template the user/team already has
- `---` horizontal rule is a universal separator — Phabricator, GitHub, hg all ignore it
- `git log --oneline` / `hg log -T '{desc|firstline}'` never sees it
- First 3 prompts shown, rest collapsed (`+ 9 more`)
- Session ID is the lookup key back into NoCrumbs
- Can be disabled via settings

### 7. Fully local, no cloud
All data stays on device. No API keys, no accounts, no telemetry. NoCrumbs never makes network calls. Uses the user's own Claude Code subscription for any AI features.

---

## v2 Features (Backlog)

### PR Description Draft
At end of session, auto-draft PR description + test plan from prompt history. User edits, doesn't write. Stack-aware — each commit in a Mercurial stack or git stack gets its own description.

Instead of calling an API, NoCrumbs generates a structured prompt and invokes `claude` CLI as a subprocess using the user's own subscription. Zero API costs.

```bash
# NoCrumbs generates and runs:
claude "Generate a PR description from these commits and prompts: ..."
```

### Template System
Teams define PR format once. Auto-filled every time. Consistent across the org without anyone thinking about it.

### Theme Support
Drop-in VS Code / TextMate `.tmTheme` / `.json` theme files. Drag onto preferences window to install. Ships with Tokyo Night, Dracula, Catppuccin, Nord defaults. Future: themes gallery at nocrumbs.app/themes.

### Semantic Diff (Stretch)
Instead of line-level diff, understand code structure. "Function moved, unchanged" instead of 40 red/green lines. Uses `difftastic` under the hood.

---

## Architecture

> For full technical details (schema, code examples, data flow): see `docs/architecture.md`

```
Claude Code hooks (dual-hook design)
    ↓ UserPromptSubmit              ↓ PostToolUse (Write|Edit)
nocrumbs capture-prompt         nocrumbs capture-change
    ↓ stdin JSON → socket           ↓ stdin JSON → socket
    └──────────┬────────────────────┘
               ↓ Unix domain socket
    NoCrumbs.app SocketServer (POSIX, actor)
               ↓
    SQLite (raw C API, WAL mode)  +  git/hg CLI (diffs on demand)
               ↓
    Timeline UI → Diff Viewer → PR Draft
```

### Key architectural decisions

**Dual-hook design.** `UserPromptSubmit` captures the prompt text + session ID. `PostToolUse` (matcher: Write|Edit) captures file changes + session ID. Session ID links them together.

**CLI is fire-and-forget.** Reads stdin JSON, writes to socket, exits immediately. If app isn't running, drops payload silently. Always exits 0 — never blocks Claude Code.

**Don't store diffs.** Git already stores them permanently. NoCrumbs stores only the prompt↔file change mapping. Derive diffs on demand via `git diff`. Entire DB stays under 1MB for years of use.

**Separate fileChanges table.** A single prompt can touch 100+ files. Storing file paths in a normalized table (not a JSON array) enables indexed queries like "all prompts that touched this file."

**Raw SQLite over ORMs.** Bulk insert 100 file paths in a single transaction: ~1ms. No GRDB/SwiftData overhead. System library, zero dependencies.

**Capture at prompt boundary, not subagent boundary.** Subagent activity, plan mode steps, todo checkboxes — all discarded. Only top-level user prompts + resulting file changes are stored.

**No TTL needed.** Git has no TTL on local commits. Normal commits on a branch live forever locally. NoCrumbs just stores the metadata sidecar.

**Handle dangling commits gracefully.** If user rebases or force-pushes, commit hash changes. Check if hash resolves before rendering — show "commit no longer exists" if not.

---

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Mac App | SwiftUI + AppKit hybrid | SwiftUI for chrome, AppKit where SwiftUI can't do it |
| App Lifecycle | `NSApplicationDelegateAdaptor` | Owns SocketServer + Database lifecycle |
| Menu Bar | `MenuBarExtra` | Native Mac pattern |
| Diff View | `STTextView` (TextKit 2) | Performant, line numbers built in, SwiftUI wrapper (planned) |
| Syntax Highlighting | STTextView Neon plugin (TreeSitter) | Best-in-class, same as serious editors (planned) |
| Timeline | SwiftUI `List` + `DisclosureGroup` | Native, lazy, performant |
| Gutter/connector | SwiftUI `Canvas` | GPU-accelerated custom drawing |
| Scroll sync | `NSScrollView` delegate bridged to SwiftUI | Only AppKit can do this reliably |
| Local DB | Raw SQLite3 C API (WAL mode) | Bulk performance, zero dependencies, system library |
| IPC | Unix domain socket (POSIX) | Sub-millisecond, no overhead |
| CLI | Swift Package Manager standalone binary | Fast startup, zero dependencies |
| VCS | `git`/`hg` CLI subprocess via `Process` | Don't reinvent, just call them |
| Updates | Sparkle framework | Standard for non-App Store Mac apps |
| Observation | `@Observable` (Swift 5.9+) | Modern pattern, not ObservableObject |

### SwiftUI performance rules
- Make `DiffLine` and `DiffHunk` models `Equatable` to skip unnecessary redraws
- Stable IDs on all `ForEach` / `List` items
- `LazyVStack` for timeline — never eager load all commits
- Scope ViewModels tightly, avoid large global environment objects
- Parse and prepare diff data off main thread, publish to UI via `@MainActor`

### STTextView for diff panes
```swift
import STTextViewSwiftUI

TextView(
    text: $diffContent,
    selection: $selection,
    options: [.wrapLines, .highlightSelectedLine],
    plugins: [NeonPlugin(theme: currentTheme)]
)
```
Layer diff line background colors (green/red) as paragraph-level `AttributedString` attributes on top. Syntax highlighting renders above. The two layers compose cleanly.

---

## Diffing Strategy

**v1:** Vanilla `git diff` / `hg diff`. Unified diff format. Simple, universal, works everywhere.

**v1.5:** Word-level diff (`git diff --word-diff`) for inline character highlighting within changed lines. Low effort, high polish.

**v2 backlog:** Semantic diff via `difftastic` for structure-aware comparison.

No need to implement diff algorithms in Swift — just parse the unified diff output from the VCS CLI. Swift's built-in `CollectionDifference` (Myers algorithm) is available if needed for UI-level diffing.

---

## Data Model

```swift
struct Session: Identifiable, Codable, Equatable, Sendable {
    let id: String              // Claude Code session_id
    let projectPath: String
    let startedAt: Date
    var lastActivityAt: Date
}

struct PromptEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: String
    let projectPath: String
    let promptText: String?     // nil for orphaned file changes
    let timestamp: Date
    let vcs: VCSType?
}

struct FileChange: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let eventID: UUID           // FK → PromptEvent
    let filePath: String
    let toolName: String        // "Write" or "Edit"
    let timestamp: Date
}

enum VCSType: String, Codable, Sendable {
    case git
    case mercurial
}

// Diffs NOT stored — derived on demand:
// git diff {hash}~1 {hash}
// hg diff -c {rev}
```

### Storage layout
```
~/Library/Application Support/NoCrumbs/
├── nocrumbs.sqlite    ← sessions + prompt events + file changes
└── nocrumbs.sock      ← Unix domain socket (while app running)
```

No diff blobs, no file snapshots. Lean sidecar only.

---

## Claude Code Hook Setup

Dual-hook design. Hooks receive data via **stdin as JSON** (not environment variables).

```json
// ~/.claude/settings.json (installed by `nocrumbs install`)
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [{
          "type": "command",
          "command": "nocrumbs capture-prompt"
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{
          "type": "command",
          "command": "nocrumbs capture-change"
        }]
      }
    ]
  }
}
```

**Stdin formats:**

```json
// UserPromptSubmit → nocrumbs capture-prompt
{"session_id": "abc123", "prompt": "refactor auth to async/await", "cwd": "/path/to/project"}

// PostToolUse → nocrumbs capture-change
{"session_id": "abc123", "tool_name": "Write", "tool_input": {"file_path": "/path/file.swift"}, "cwd": "/path/to/project"}
```

`nocrumbs install` command sets this up automatically, merging with existing settings. Engineer runs one command, never thinks about it again.

---

## Menu Bar App Behavior

```xml
<!-- Info.plist -->
<key>LSUIElement</key>
<true/>
```

Invisible to `⌘Tab` and Spotlight by default. When main window opens, dynamically switch to `.regular` activation policy so it appears in `⌘Tab`. Switch back to `.accessory` when window closes.

```swift
// Window opens
NSApp.setActivationPolicy(.regular)

// Window closes
NSApp.setActivationPolicy(.accessory)
```

Global hotkey (e.g. `⌘⇧N`) to show/hide from anywhere. Menu bar icon shows subtle badge when new activity captured while window is hidden.

---

## Distribution

**Not on Mac App Store.** App Store sandbox would block filesystem access, socket IPC, and subprocess execution. All critical for NoCrumbs.

**Requirements:**
- Apple Developer account ($99/yr) — for code signing + notarization
- Notarization via `notarytool` — prevents Gatekeeper warning
- Sparkle framework — in-app auto-updates

**Distribution stack:**
- GitHub releases for binary + DMG
- Landing page at nocrumbs.app
- Sparkle update feed hosted on nocrumbs.app

---

## Monetization

**Launch strategy: Free, closed source**

- Free to start — maximize distribution, build reputation, validate the tool
- Closed source — simpler, no forking risk
- No API costs (fully local architecture)
- Decide later: pivot to paid or open source based on traction

**If pivoting to paid:**
- $29 one-time via LemonSqueezy (handles global VAT as merchant of record)
- LemonSqueezy → Mercury bank account (business) or personal bank
- ~$24-25 net per sale after fees
- 1,000 sales = ~$24,000

**If pivoting to open source:**
- MIT license everything
- GitHub Sponsors + optional paid PR drafting tier
- Community contributions on themes, VCS support, integrations

**Warning:** Free → paid is hard (user backlash). Free → open source is easy. Decide before you have 10k users.

**Business setup (when ready):**
- Wyoming single-member LLC (~$100 to file, $60/yr)
- Northwest Registered Agent (~$39/yr)
- EIN from IRS.gov (free, instant)
- Mercury business bank account (free, no minimums)

---

## Competitive Landscape

| Feature | Cursor | VS Code + Claude Code ext | NoCrumbs |
|---|---|---|---|
| Real-time diff as AI works | ✅ (inline) | ✅ (inline) | ✅ (companion window) |
| Prompt-organized diffs | ❌ | ❌ | ✅ |
| Persistent diff history | ❌ (vanishes on accept) | ❌ | ✅ |
| IDE-less / terminal workflow | ❌ | ❌ | ✅ |
| Commit/stack timeline | ❌ | ❌ | ✅ |
| Mercurial support | ❌ | ❌ | ✅ |
| PR description from session | ❌ | ❌ | ✅ |
| Native Mac UX | ❌ | ❌ | ✅ |

Cursor shows you diffs inline and they vanish when you accept. NoCrumbs is the persistent, prompt-organized companion — live while you work, accumulated across sessions, IDE-independent.

---

## Milestones

### M0 — Project Setup ✅
- [x] Xcode project via XcodeGen: Mac App target + CLI target (separate SPM package)
- [x] Swift packages: Sparkle (GRDB removed — using raw SQLite)
- [x] GitHub repo
- [x] Code signing configured (H32EKFDL92)
- [x] Folder structure with App/, Core/, Features/, UI/, Tests/
- [x] Both targets build cleanly

---

### M1 — Data Pipeline ✅
- [x] `PromptEvent`, `Session`, `FileChange`, `VCSType` data models
- [x] SQLite schema via raw C API (WAL mode, foreign key cascade, indexed)
- [x] `Database` singleton: `@Observable @MainActor`, in-memory cache, CRUD
- [x] Unix domain socket server (POSIX actor) + client
- [x] CLI: stdin JSON parsing, `capture-prompt` + `capture-change` subcommands
- [x] VCS detection: `.git` vs `.hg` directory walk
- [x] `nocrumbs install` command auto-registers dual hooks
- [x] `AppDelegate` owns SocketServer + Database lifecycle
- [x] End-to-end verified: CLI → socket → DB (tested with manual JSON piping)

---

### M2 — Menu Bar Shell + Commit Annotation ✅
- [x] `LSUIElement = YES` already in Info.plist
- [x] `MenuBarExtra` with placeholder icon
- [x] Menu items: Show NoCrumbs / Quit
- [x] Launch at login via `SMAppService`
- [x] Socket server starts on launch, restarts on failure
- [x] Basic window: table of recent sessions (project + timestamp)
- [x] Dynamic activation policy (`⌘Tab` behavior)
- [x] Global hotkey (`⌘⇧N`) to show/hide
- [x] Commit annotation: `prepare-commit-msg` git hook / hg equivalent
- [x] Query DB for uncommitted prompt events in current session
- [x] Append `---` + prompt summary block to commit message
- [x] Cap at 3 prompts shown, collapse rest (`+ N more`)
- [x] Setting to disable annotation

**Exit criteria:** App lives in menu bar, starts at login, shows captured sessions. Commits automatically include prompt history.

---

### M3 — Diff Viewer
Core product. This is NoCrumbs.

- [ ] Unified diff parser → `DiffFile` / `DiffHunk` / `DiffLine` structs
- [ ] `STTextView` integrated via `NSViewRepresentable`
- [ ] Neon TreeSitter syntax highlighting plugin wired up
- [ ] Line background colors: green additions, red removals
- [ ] Line number gutter
- [ ] Two-pane layout with `HSplitView`
- [ ] Synchronized scrolling via `NSScrollView` delegate
- [ ] Prompt header above panes (prompt text, files, timestamp)
- [ ] File list sidebar
- [ ] Collapsible commit/prompt timeline with `DisclosureGroup`
- [ ] Click prompt event → load its diff in panes
- [ ] Live update: new prompt events appear instantly as Claude works (via @Observable)

**Exit criteria:** Have NoCrumbs open alongside terminal. Type a prompt in Claude Code. See the diff appear in NoCrumbs within seconds, organized under that prompt.

---

### M4 — Polish
What separates a tool engineers love from one they tolerate.

- [ ] Smooth animation when new prompt/diff arrives
- [ ] `⌘[` / `⌘]` keyboard navigation between prompt events
- [ ] Dark mode verified
- [ ] Empty state with setup instructions
- [ ] Onboarding flow on first launch
- [ ] Menu bar badge on new activity while window hidden
- [ ] Handle dangling commits gracefully

**Exit criteria:** Show to a friend. They say it feels polished.

---

### M5 — PR Description Draft
v2 workflow layer.

- [ ] "Draft PR" button in session view
- [ ] Collects all `PromptEvent`s for current branch
- [ ] Generates structured prompt from session data
- [ ] Invokes `claude` CLI as subprocess with user's own subscription
- [ ] Editable text field for engineer to tweak
- [ ] Stack-aware: per-commit descriptions for stacked diffs
- [ ] Copy to clipboard / open in browser
- [ ] Basic template system

**Exit criteria:** Finish a coding session, click Draft PR, get 90% complete description in 10 seconds.

---

### M6 — Distribution Setup
- [ ] Code sign + notarize
- [ ] Build `.dmg` installer
- [ ] Sparkle update feed at nocrumbs.app
- [ ] Landing page: one headline, one screenshot, one download button
- [ ] GitHub releases for binary

---

### M7 — Launch
- [ ] Screen recording showing full workflow
- [ ] Post on X with demo
- [ ] Show HN: "NoCrumbs – Git blame for the AI era"
- [ ] Post in Claude Code communities (Reddit, Discord)
- [ ] DM 10 engineer friends for honest feedback
- [ ] First install 🎉

---

## Design Principles

**Fire and forget.** The hook must never slow Claude Code. CLI exits in <50ms. Silent failure if app isn't running. Always exit 0.

**Local first, always.** No network calls, no accounts, no telemetry. Ever. This is a trust advantage.

**Capture intent, not noise.** Top-level prompts only. Subagents, plan steps, todos — all discarded. The commit message is the best condenser.

**Derive, don't duplicate.** Git already stores diffs. Store only what git doesn't have: the prompt↔file change link.

**Scale for real workloads.** A single prompt can generate 100+ file changes. Normalized tables with indexes, not JSON arrays.

**Ship M4 before M5.** The diff viewer with prompt annotation is the product. PR drafting is a bonus. Don't let scope creep delay launch.

**Use real hooks from day one.** Wire up Claude Code hooks in your own workflow from M1. Don't mock data.

---

## One-liner
*"A live companion for IDE-less AI coding. See every change Claude Code makes, organized by the prompt that caused it — as it happens."*

## Elevator pitch
*"Git blame for the AI era. NoCrumbs sits alongside your terminal and shows you what Claude Code changed and why — in real time, organized by prompt, persistent across sessions. Kaleidoscope meets git blame, built for engineers who've left the IDE."*

---

## Domain + Branding
- **Name:** NoCrumbs
- **Domain:** nocrumbs.app ($12.98/yr on Namecheap/Porkbun)
- **CLI tool name:** `nocrumbs`
- **Logo direction:** clean surface, broom, or cookie with clean bite
- **Tone:** built by an engineer, for engineers. No fluff.
