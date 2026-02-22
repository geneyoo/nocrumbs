---
sidebar_position: 5
---

# Contributing

Thanks for your interest in contributing to NoCrumbs!

## Development Setup

1. **Clone the repo:**
   ```bash
   git clone https://github.com/geneyoo/nocrumbs.git
   cd nocrumbs
   ```

2. **Requirements:**
   - macOS 14+
   - Xcode 15+ (Swift 5.9+)

3. **Build:**
   ```bash
   # Mac app
   xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Debug \
     -sdk macosx -derivedDataPath build build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

   # CLI
   swift build -c release --package-path CLI/
   ```

4. **Run tests:**
   ```bash
   xcodebuild test -project NoCrumbs.xcodeproj -scheme NoCrumbs -sdk macosx \
     -derivedDataPath build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
   ```

## Pull Request Requirements

- Run all tests before submitting
- Add tests for new functionality
- One concern per PR — keep changes focused

## Code Style

- Follow existing patterns in the codebase
- Use `@Observable` (Swift 5.9+), not `ObservableObject`
- Use conventional commit prefixes:

| Prefix | Usage |
|--------|-------|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `docs:` | Documentation only |
| `refactor:` | Code restructuring |
| `test:` | Adding or updating tests |

## Scope Statement

NoCrumbs is intentionally local-only. PRs that add cloud sync, telemetry, or remote features will not be accepted. If you're unsure whether your idea fits, open an issue to discuss first.
