---
sidebar_position: 5
---

# Contributing

Thanks for your interest in contributing to NoCrumbs! Here's how to get started.

## Development Setup

1. **Clone the repo:**
   ```bash
   git clone https://github.com/pdswan/nocrumbs.git
   cd nocrumbs
   ```

2. **Requirements:**
   - Swift 5.9+
   - macOS 14+
   - Xcode 15+ (open `.xcworkspace`, not `.xcodeproj`)

3. **Build order:**
   - Build the CLI target first: `swift build --package-path CLI/`
   - Then build the Mac app via Xcode or `xcodebuild`

## Pull Request Requirements

- Run all tests before submitting
- Add tests for new functionality
- Update `CHANGELOG.md` with your changes
- One concern per PR — keep changes focused

## Code Style

- SwiftFormat is enforced via CI
- Follow existing patterns in the codebase
- Use conventional commit prefixes:

| Prefix | Usage |
|--------|-------|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `docs:` | Documentation only |
| `refactor:` | Code restructuring |
| `test:` | Adding or updating tests |

**Examples:**
```
feat: add mercurial provider support
fix: handle missing commit hash in timeline
docs: update CLI usage guide
```

## Scope Statement

NoCrumbs is intentionally local-only. PRs that add cloud sync, telemetry, or remote features will not be accepted. If you're unsure whether your idea fits, open an issue to discuss first.
