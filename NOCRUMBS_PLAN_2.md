# NoCrumbs — Project Plan
> Git blame for the AI era. See every decision Claude Code made in your codebase and why.

---

## Vision

A native Mac menu bar app that gives engineers a beautiful, always-on view of everything Claude Code (or Codex CLI) does to their codebase — automatically, with zero changes to workflow. Built for IDE-less AI coding workflows where the terminal + Claude Code is the full stack.

**Core insight:** When AI writes code, the "author" is a prompt. Traditional diff tools show *what* changed. NoCrumbs shows *what* changed and *why* — linking every file change back to the prompt that caused it.

---

## Problem Statement

Claude Code with subagents, plan mode, todos, and parallel agents generates massive activity logs. Engineers working IDE-less have no good way to:
- Review what the AI actually changed
- Understand the intent behind each change
- Navigate a session's history prompt by prompt
- Draft PR descriptions from session context

Cursor and VS Code have inline ephemeral diffs — gone when the session closes, IDE-bound, no persistent history. NoCrumbs is the persistent, IDE-independent audit trail.

---

## What NoCrumbs Is Not

- Not a real-time inline diff (that's Cursor's job)
- Not a code review bot
- Not another thing that needs an API key
- Not a cloud service
- Not an IDE plugin

---

## Core Features (v1)

### 1. Zero-friction capture
Claude Code triggers NoCrumbs via a `PostToolUse` hook — deterministic, not CLAUDE.md (which gets ignored). No commands, no extra steps. Install once, works forever.

### 2. Prompt → commit linkage
Every diff is linked to the top-level prompt that caused it. Like git blame but for AI decisions. Subagent noise is filtered out — only top-level user prompts are captured.

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

### 6. Fully local, no cloud
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

```
Claude Code
    ↓ PostToolUse hook (deterministic, not CLAUDE.md)
nocrumbs CLI          ← tiny binary, <50ms, fire-and-forget
    ↓ Unix domain socket (non-blocking write, silent fail if app not running)
NoCrumbs.app          ← menu bar app, always running
    ↓
SQLite (metadata)  +  git/hg CLI (diffs derived on demand, not stored)
    ↓
Timeline UI → Diff Viewer → PR Draft
```

### Key architectural decisions

**CLI is fire-and-forget.** Writes JSON to socket, exits immediately. If app isn't running, drops payload silently. Claude Code never waits for NoCrumbs.

**Don't store diffs.** Git already stores them permanently. NoCrumbs stores only the prompt↔commit mapping. Derive diffs on demand via `git show {hash}` or `hg diff -c {rev}`. Entire DB stays under 1MB for years of use.

**Capture at commit boundary, not subagent boundary.** Subagent activity, plan mode steps, todo checkboxes — all discarded at CLI level. Only top-level user prompts + resulting commits are stored.

**No TTL needed.** Git has no TTL on local commits. Normal commits on a branch live forever locally. NoCrumbs just stores the metadata sidecar.

**Handle dangling commits gracefully.** If user rebases or force-pushes, commit hash changes. Check if hash resolves before rendering — show "commit no longer exists" if not.

---

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Mac App | SwiftUI + AppKit hybrid | SwiftUI for chrome, AppKit where SwiftUI can't do it |
| Menu Bar | `NSStatusItem` + `MenuBarExtra` | Native Mac pattern |
| Diff View | `STTextView` (TextKit 2) | Performant, line numbers built in, SwiftUI wrapper |
| Syntax Highlighting | STTextView Neon plugin (TreeSitter) | Best-in-class, same as serious editors |
| Timeline | SwiftUI `List` + `DisclosureGroup` | Native, lazy, performant |
| Gutter/connector | SwiftUI `Canvas` | GPU-accelerated custom drawing |
| Scroll sync | `NSScrollView` delegate bridged to SwiftUI | Only AppKit can do this reliably |
| Local DB | SQLite via GRDB.swift | Fast, queryable, tiny footprint |
| IPC | Unix domain socket | Sub-millisecond, no overhead |
| CLI | Swift Package Manager standalone binary | Fast startup, no dependencies |
| VCS | `git`/`hg` CLI subprocess | Don't reinvent, just call them |
| Updates | Sparkle framework | Standard for non-App Store Mac apps |

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
// Only what git doesn't already store

struct PromptEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let commitHash: String?      // nil if uncommitted at capture time
    let projectPath: String
    let promptText: String       // what the engineer typed
    let summary: String?         // auto-generated one-liner (via claude CLI)
    let filesChanged: [String]
    let timestamp: Date
    let vcs: VCSType             // .git or .mercurial
}

enum VCSType: String, Codable {
    case git
    case mercurial
}

// Diff is NOT stored — derived on demand:
// git show {commitHash} -- {file}
// hg diff -c {rev} {file}
```

### Storage layout
```
~/Library/Application Support/NoCrumbs/
└── nocrumbs.sqlite    ← prompt events, ~1MB for years of use
```

No diff blobs, no file snapshots. Lean sidecar only.

---

## Claude Code Hook Setup

```json
// ~/.claude/settings.json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "nocrumbs event --project \"$CLAUDE_PROJECT_DIR\" --files \"$CLAUDE_TOOL_RESPONSE\""
          }
        ]
      }
    ]
  }
}
```

`nocrumbs install` command sets this up automatically. Engineer runs one command, never thinks about it again.

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
| Inline diff while coding | ✅ | ✅ | ❌ (not the goal) |
| Persistent diff history | ❌ | ❌ | ✅ |
| Prompt → diff linkage | ❌ | ❌ | ✅ |
| IDE-less / terminal workflow | ❌ | ❌ | ✅ |
| Commit/stack timeline | ❌ | ❌ | ✅ |
| Mercurial support | ❌ | ❌ | ✅ |
| PR description from session | ❌ | ❌ | ✅ |
| Native Mac UX | ❌ | ❌ | ✅ |
| Persistent across sessions | ❌ | ❌ | ✅ |

Cursor owns in-IDE ephemeral diffs. NoCrumbs owns the persistent, IDE-independent audit trail for engineers who've left the IDE entirely.

---

## Milestones

### M0 — Project Setup (Day 1)
- [ ] Xcode project: Mac App target + CLI target in same workspace
- [ ] Swift packages: GRDB.swift, Sparkle, STTextView
- [ ] GitHub repo, main/dev branches
- [ ] Code signing configured
- [ ] Folder structure:
  ```
  NoCrumbs/
  ├── App/        ← SwiftUI Mac app
  ├── CLI/        ← nocrumbs binary  
  ├── Core/       ← shared business logic
  │   ├── Models/
  │   ├── Database/
  │   ├── IPC/
  │   └── VCS/
  └── Tests/
  ```
- [ ] Both targets build cleanly

**Exit criteria:** App builds. CLI builds as standalone binary.

---

### M1 — Data Pipeline (Weekend 1)
The most important milestone. Prove data flows end to end before building any UI.

- [ ] `PromptEvent` and `Session` data models
- [ ] SQLite schema via GRDB
- [ ] Unix domain socket server (in app) + client (in CLI)
- [ ] CLI binary: receives args, writes JSON to socket, exits <50ms
- [ ] VCS detection: `.git` vs `.hg` directory check
- [ ] Claude Code `PostToolUse` hook wired up
- [ ] `nocrumbs install` command auto-registers hook
- [ ] Debug logging to verify pipeline end to end

**Exit criteria:** Make a file change in Claude Code → CLI fires → app receives event → stored in SQLite. Verified via debug log. No UI needed.

---

### M2 — Menu Bar Shell (Weekend 1–2)
- [ ] `LSUIElement = YES` in Info.plist
- [ ] `MenuBarExtra` with placeholder icon
- [ ] Menu items: Show NoCrumbs / Quit
- [ ] Launch at login via `SMAppService`
- [ ] Socket server starts on launch, restarts on failure
- [ ] Basic window: table of recent sessions (project + timestamp)
- [ ] Dynamic activation policy (`⌘Tab` behavior)
- [ ] Global hotkey (`⌘⇧N`) to show/hide

**Exit criteria:** App lives in menu bar, starts at login, shows captured sessions.

---

### M3 — Diff Viewer (Weekend 2–3)
Core product. This is NoCrumbs.

- [ ] Unified diff parser → `DiffFile` / `DiffHunk` / `DiffLine` structs
- [ ] `STTextView` integrated via `NSViewRepresentable`
- [ ] Neon TreeSitter syntax highlighting plugin wired up
- [ ] Line background colors: green additions, red removals
- [ ] Line number gutter
- [ ] Two-pane layout with `HSplitView`
- [ ] Synchronized scrolling via `NSScrollView` delegate
- [ ] Prompt header above panes (prompt text, summary, files, timestamp)
- [ ] File list sidebar
- [ ] Collapsible commit/prompt timeline with `DisclosureGroup`
- [ ] Click prompt event → load its diff in panes

**Exit criteria:** Open NoCrumbs, see timeline, click any prompt, see clean two-pane diff with prompt header.

---

### M4 — Polish (Weekend 3)
What separates a tool engineers love from one they tolerate.

- [ ] Smooth panel animation when new diff arrives
- [ ] Real-time update as Claude Code makes changes
- [ ] `⌘[` / `⌘]` keyboard navigation between prompt events
- [ ] Dark mode verified
- [ ] Empty state with setup instructions
- [ ] Onboarding flow on first launch
- [ ] Menu bar badge on new activity while window hidden
- [ ] Handle dangling commits gracefully

**Exit criteria:** Show to a friend. They say it feels polished.

---

### M5 — PR Description Draft (Weekend 4)
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

### M6 — Distribution Setup (Weekend 4–5)
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

**Fire and forget.** The hook must never slow Claude Code. CLI exits in <50ms. Silent failure if app isn't running.

**Local first, always.** No network calls, no accounts, no telemetry. Ever. This is a trust advantage.

**Capture intent, not noise.** Top-level prompts only. Subagents, plan steps, todos — all discarded. The commit message is the best condenser.

**Derive, don't duplicate.** Git already stores diffs. Store only what git doesn't have: the prompt↔commit link.

**Ship M4 before M5.** The diff viewer with prompt annotation is the product. PR drafting is a bonus. Don't let scope creep delay launch.

**Use real hooks from day one.** Wire up Claude Code hooks in your own workflow from M1. Don't mock data.

---

## One-liner
*"A native Mac diff viewer built for IDE-less AI coding. Claude Code logs every change it makes with the prompt that triggered it. Review decisions, not just diffs."*

## Elevator pitch
*"Git blame for the AI era. NoCrumbs links every file change Claude Code makes back to the prompt that caused it. Always running in your menu bar, zero changes to your workflow, fully local."*

---

## Domain + Branding
- **Name:** NoCrumbs
- **Domain:** nocrumbs.app ($12.98/yr on Namecheap/Porkbun)
- **CLI tool name:** `nocrumbs`
- **Logo direction:** clean surface, broom, or cookie with clean bite
- **Tone:** built by an engineer, for engineers. No fluff.
