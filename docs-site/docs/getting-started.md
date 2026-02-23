---
sidebar_position: 1
---

# Getting Started

Install NoCrumbs and start tracking AI-generated changes in under a minute.

## 1. Install

```bash
brew install --cask geneyoo/tap/nocrumbs
```

This installs both the Mac app and the `nocrumbs` CLI. Requires macOS 14+.

<details>
<summary>Building from source</summary>

Requires Xcode 15+.

```bash
git clone https://github.com/geneyoo/nocrumbs.git && cd nocrumbs

# Build app (CLI is embedded automatically)
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Release \
  -sdk macosx -derivedDataPath build build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
open build/Build/Products/Release/NoCrumbs.app

# Symlink the embedded CLI to your PATH
ln -sf "$PWD/build/Build/Products/Release/NoCrumbs.app/Contents/Resources/nocrumbs" /usr/local/bin/nocrumbs
```

</details>

## 2. Configure

```bash
nocrumbs install
```

That's it. This registers Claude Code hooks so prompts and file changes are captured automatically.

Optionally, add commit annotations to a repo:

```bash
nocrumbs install-git-hooks    # run in each repo you want annotations
```

## 3. Verify

1. The NoCrumbs icon appears in your menu bar
2. Open a Claude Code session and send a prompt
3. Open the NoCrumbs window — your prompt and file changes appear in the sidebar

## Updating

The Mac app checks for updates automatically via Sparkle. To update everything via Homebrew:

```bash
brew upgrade --cask nocrumbs
```

## Uninstall

```bash
brew uninstall --cask nocrumbs
```

Data lives in `~/Library/Application Support/NoCrumbs/`. Remove that directory to delete all local data.

## Next Steps

- [How It Works](/docs/how-it-works) — architecture and data flow
- [CLI Usage](/docs/guides/cli-usage) — full command reference
- [Mac App Usage](/docs/guides/app-usage) — navigating the timeline and diff viewer
