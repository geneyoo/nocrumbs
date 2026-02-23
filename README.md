# 🥐 NoCrumbs

> AI writes the code. You keep the receipts.

A local-first tool that links every file change your AI coding assistant makes back to the prompt that caused it. Native Mac app + fire-and-forget CLI. No cloud, no telemetry, no accounts.

## Quick Start

### Homebrew (recommended)

```bash
brew install geneyoo/tap/nocrumbs
```

### From source

```bash
# 1. Build & launch
git clone https://github.com/geneyoo/nocrumbs.git && cd nocrumbs
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Release \
  -sdk macosx -derivedDataPath build build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
open build/Build/Products/Release/NoCrumbs.app

# 2. Install CLI + hooks
swift build -c release --package-path CLI/
cp CLI/.build/release/nocrumbs /usr/local/bin/
nocrumbs install
nocrumbs install-git-hooks
```

That's it. Use your AI coding assistant normally — prompts and file changes appear in NoCrumbs automatically.

**Requirements:** macOS 14+, Xcode 15+ (to build from source)

---

## What It Does

| Feature | How |
|---------|-----|
| **Real-time tracking** | Captures every AI action as it happens — file writes, commands, commits — and links them back to the prompt that triggered them |
| **Side-by-side diff viewer** | Syntax-highlighted, Phabricator-style. Click a prompt, see what changed |
| **Commit message annotation** | Appends prompt history to commit messages automatically. Customizable templates |
| **Session export** | Copy session summary as markdown. Deep links back to NoCrumbs |
| **Git + Mercurial** | Detects VCS automatically |

### Commit Annotation

Single prompt:
```
refactor: convert auth to async/await
---
🥐 refactor auth to async/await · 4 files · abc12345
```

Multiple prompts:
```
refactor: convert auth to async/await
---
🥐 3 prompts · 8 files · abc12345

1. refactor auth to async/await (3 files)
2. add error handling to the new async methods (3 files)
3. update tests for new async patterns (2 files)
```

Granular content toggles in Settings: prompt list, file counts, session ID, deep links — all independently configurable. Customizable via `nocrumbs template add/set/remove/preview`.

---

## Design Principles

**Seamless.** Install once, never think about it again. The CLI hook exits in <50ms, always exit 0, silent fail if app isn't running. Zero friction.

**Lightweight.** Don't store diffs — git already has them. Store only prompt-to-commit linkage. DB stays under 1MB for years of use. Sub-millisecond IPC via Unix domain socket.

**Local-first, always.** No network calls, no API keys, no accounts, no telemetry. Everything stays on your machine via Unix domain socket.

**Capture intent, not noise.** Top-level user prompts only. Subagent activity, plan steps, todos — all discarded.

**Derive, don't duplicate.** Diffs computed on demand from git/hg. No diff blobs, no file snapshots.

---

## Architecture

```
AI Assistant ──PostToolUse hook──▶ nocrumbs CLI ──socket──▶ Mac App ──▶ SQLite
```

The CLI receives hook payloads as JSON, extracts metadata (session ID, prompt text, file paths), and forwards over a Unix domain socket. The Mac app stores prompt metadata locally and derives diffs from git on demand.

For full technical details: [`docs/architecture.md`](docs/architecture.md)

### Tech Stack

| Layer | Technology |
|-------|-----------|
| App | SwiftUI + AppKit hybrid, `@Observable` (Swift 5.9+) |
| Diff view | NSTextView (TextKit 1) via NSViewRepresentable |
| Syntax highlighting | Regex-based, 20+ languages, zero dependencies |
| Database | Raw SQLite3 C API, WAL mode |
| IPC | Unix domain socket (POSIX) |
| CLI | Swift Package Manager, zero dependencies |
| VCS | git/hg subprocess via Process |

### Storage

```
~/Library/Application Support/NoCrumbs/
├── nocrumbs.sqlite    ← sessions + prompt events + file changes
└── nocrumbs.sock      ← Unix domain socket (while app running)
```

No diff blobs, no file snapshots. Lean metadata sidecar only.

---

## CLI Commands

```
nocrumbs install              Configure Claude Code hooks (run once)
nocrumbs install-git-hooks    Install prepare-commit-msg hook (run per repo)
nocrumbs event                Pipe any hook event to app
nocrumbs annotate-commit      Annotate commit message (called by git hook)
nocrumbs describe             Pipe per-file change descriptions to app
nocrumbs rename-session       Rename a session
nocrumbs template             Manage commit annotation templates (add/list/set/remove/preview)
```

---

## Supported Tools

Currently supported:
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — via hook events

Coming soon:
- **[Codex CLI](https://github.com/openai/codex)** — via hook events

---

## What NoCrumbs Is Not

- Not an inline editor diff (that's Cursor's job)
- Not a code review bot
- Not a cloud service
- Not an IDE plugin
