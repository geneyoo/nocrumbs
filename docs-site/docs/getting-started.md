---
sidebar_position: 1
---

# Getting Started

NoCrumbs is a local-first Mac app + CLI that links every AI prompt to the file changes it produced. Install once, then use your AI coding assistant normally.

**Requirements:** macOS 14+, Xcode 15+ (to build from source)

## Install

### Homebrew (recommended)

```bash
brew install geneyoo/tap/nocrumbs
```

This installs both the Mac app and the `nocrumbs` CLI.

### From source

```bash
# 1. Clone & build the Mac app
git clone https://github.com/geneyoo/nocrumbs.git && cd nocrumbs
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Release \
  -sdk macosx -derivedDataPath build build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
open build/Build/Products/Release/NoCrumbs.app

# 2. Build & install the CLI
swift build -c release --package-path CLI/
cp CLI/.build/release/nocrumbs /usr/local/bin/
```

## Configure Hooks

Run these once after installing:

```bash
# Register Claude Code hooks (~/.claude/settings.json)
nocrumbs install

# Install git commit annotation hook (run in each repo)
nocrumbs install-git-hooks
```

`nocrumbs install` writes hook entries to your Claude Code config so prompts and file changes are captured automatically. `nocrumbs install-git-hooks` adds a `prepare-commit-msg` hook that annotates your commits with prompt context.

## Verify

1. The NoCrumbs icon appears in your menu bar
2. Open a Claude Code session and send a prompt
3. Open the NoCrumbs window — your prompt and file changes should appear in the sidebar

## Next Steps

- [How It Works](/docs/how-it-works) — architecture and data flow
- [CLI Usage](/docs/guides/cli-usage) — full command reference
- [Mac App Usage](/docs/guides/app-usage) — navigating the timeline and diff viewer
