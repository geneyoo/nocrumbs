# NoCrumbs

> Git blame for the AI era.

A native Mac menu bar app that links every file change Claude Code makes back to the prompt that caused it. Seamless, lightweight, fully local.

## Quick Start

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
```

That's it. Use Claude Code normally — prompts and file changes appear in NoCrumbs automatically.

**Requirements:** macOS 14+, Xcode 15+ (to build), Claude Code CLI

---

## What It Does

| Feature | How |
|---------|-----|
| **Prompt → file change linkage** | Every file change tracked back to the prompt that caused it via session ID |
| **Side-by-side diff viewer** | Syntax-highlighted, Phabricator-style. Click a prompt, see what changed |
| **Commit message annotation** | Appends prompt history to commit messages automatically. Customizable templates |
| **Session export** | Copy session summary as markdown. Deep links back to NoCrumbs |
| **Git + Mercurial** | Detects VCS automatically |

### Commit Annotation

Single prompt:
```
refactor: convert auth to async/await
---
🍞 refactor auth to async/await · 4 files · abc12345
```

Multiple prompts:
```
refactor: convert auth to async/await
---
🍞 3 prompts · 8 files · abc12345

1. refactor auth to async/await (3 files)
2. add error handling to the new async methods (3 files)
3. update tests for new async patterns (2 files)
```

Granular content toggles in Settings: prompt list, file counts, session ID, deep links — all independently configurable. Customizable via `nocrumbs template add/set/remove/preview`.

---

## Design Principles

**Seamless.** Install once, never think about it again. The CLI hook exits in <50ms, always exit 0, silent fail if app isn't running. Zero friction.

**Lightweight.** Don't store diffs — git already has them. Store only prompt↔file change linkage. DB stays under 1MB for years of use. Raw SQLite, no ORM overhead. Sub-millisecond IPC via Unix domain socket.

**Local first.** No network calls, no API keys, no accounts, no telemetry. Ever.

**Capture intent, not noise.** Top-level user prompts only. Subagent activity, plan steps, todos — all discarded.

**Derive, don't duplicate.** Diffs computed on demand from git/hg. No diff blobs, no file snapshots.

---

## Architecture

```
Claude Code hooks
    ↓ stdin JSON → nocrumbs CLI (fire-and-forget)
    ↓ Unix domain socket
NoCrumbs.app SocketServer (POSIX, actor)
    ↓
SQLite (raw C API, WAL) + git/hg CLI (diffs on demand)
    ↓ @Observable in-memory cache
SwiftUI views (sidebar, diff viewer, session summary)
```

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
nocrumbs install-git-hooks    Install prepare-commit-msg hook
nocrumbs event                Pipe any hook event to app
nocrumbs annotate-commit      Annotate commit message (called by git hook)
nocrumbs describe             Pipe per-file change descriptions to app
nocrumbs template             Manage commit annotation templates (add/list/set/remove/preview)
```

---

## What NoCrumbs Is Not

- Not an inline editor diff (that's Cursor's job)
- Not a code review bot
- Not a cloud service
- Not an IDE plugin
