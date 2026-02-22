---
sidebar_position: 3
---

# Installation

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (only needed to build from source)

## Homebrew (recommended)

```bash
brew install geneyoo/tap/nocrumbs
```

Installs both the Mac app and the `nocrumbs` CLI.

## From Source

```bash
git clone https://github.com/geneyoo/nocrumbs.git
cd nocrumbs

# Build the Mac app
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Release \
  -sdk macosx -derivedDataPath build build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# Launch it
open build/Build/Products/Release/NoCrumbs.app

# Build and install the CLI
swift build -c release --package-path CLI/
cp CLI/.build/release/nocrumbs /usr/local/bin/
```

## Post-Install Setup

```bash
# Register Claude Code hooks (run once)
nocrumbs install

# Install git commit annotation hook (run in each repo you want annotations)
nocrumbs install-git-hooks
```

## Updating

The Mac app checks for updates automatically via Sparkle. You'll be prompted when a new version is available.

To update the CLI via Homebrew:

```bash
brew upgrade nocrumbs
```

## Uninstall

```bash
brew uninstall nocrumbs
# Or if built from source: rm /usr/local/bin/nocrumbs
```

The app stores data in `~/Library/Application Support/NoCrumbs/`. Remove that directory to delete all local data.
