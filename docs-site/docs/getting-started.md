---
sidebar_position: 1
---

# Getting Started

NoCrumbs is a local-first tool that links every file change your AI coding assistant makes back to the prompt that caused it — git blame for the AI era.

## Installation

### Homebrew (recommended)

```bash
brew install nocrumbs
```

### From source

```bash
git clone https://github.com/pdswan/nocrumbs.git
cd nocrumbs
swift build -c release --package-path CLI/
cp .build/release/nocrumbs /usr/local/bin/
```

## Quick Start

1. **Initialize** NoCrumbs in your project:

```bash
nocrumbs init
```

This installs the necessary hooks into your Claude Code configuration.

2. **Work normally** — use Claude Code (or any supported AI assistant) as you always do. NoCrumbs captures prompt-to-commit linkage automatically in the background.

3. **Check status** to verify everything is connected:

```bash
nocrumbs status
```

4. **Open the Mac app** to browse your prompt timeline and see which prompts produced which commits.

## Next Steps

- [How It Works](/docs/how-it-works) — understand the architecture
- [CLI Usage](/docs/guides/cli-usage) — full CLI reference
- [Mac App Usage](/docs/guides/app-usage) — navigating the desktop app
