# Contributing to NoCrumbs

Thanks for your interest in contributing! This is a quick-start guide — see the [full contributing guide](https://geneyoo.github.io/nocrumbs/contributing) on the docs site for more detail.

## Prerequisites

- macOS 14+
- Xcode 15+ (Swift 5.9+)

## Setup

```bash
git clone https://github.com/geneyoo/nocrumbs.git
cd nocrumbs
git config core.hooksPath .githooks
```

## Build & Test

```bash
# Mac app
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Debug \
  -sdk macosx -derivedDataPath build build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# CLI
swift build -c release --package-path CLI/

# Tests
xcodebuild test -project NoCrumbs.xcodeproj -scheme NoCrumbs -sdk macosx \
  -derivedDataPath build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

## Before Submitting a PR

- All tests pass
- One concern per PR — keep changes focused
- Use conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`
- Use `@Observable` (Swift 5.9+), not `ObservableObject`

## Scope

NoCrumbs is intentionally **local-only**. PRs that add cloud sync, telemetry, or remote features will not be accepted. If you're unsure whether your idea fits, open an issue first.
