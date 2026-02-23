---
sidebar_position: 2
---

# How It Works

## The Problem

- **IDEs are pre-agentic.** They were built for humans writing code line-by-line — file trees, syntax highlighting, inline diffs. That workflow is fading.
- **CLI agents are replacing them** — Claude Code, Codex CLI, aider. No file trees, no inline diffs. Just a prompt and a commit. Faster, less overhead, no UI tax.
- **But you lose all traceability.** The agent touches a dozen files across 3 commits, and `git log` gives you a hash and a message. Which prompt caused which change? Gone.
- **`git log` tells you what and when — not why.** With agents writing the code, the "why" is the prompt. And nothing catches those crumbs today.

## The Solution

![NoCrumbs session summary — prompt timeline and file changes](/img/screenshot-summary.png)

NoCrumbs bridges this gap by capturing the relationship between prompts and file changes, entirely on your local machine.

### Architecture

```
Claude Code ──hook event──▶ nocrumbs CLI ──Unix socket──▶ Mac App ──▶ SQLite
```

1. **Hook integration** — NoCrumbs registers as a Claude Code hook. Every time you submit a prompt or Claude executes a tool (file write, edit, etc.), the hook fires.

2. **CLI capture** — The `nocrumbs` CLI receives the hook payload as JSON, extracts metadata (session ID, prompt text, tool name, file paths), and forwards it over a Unix domain socket in under 50ms.

3. **Mac App storage** — The native macOS app listens on the socket, processes incoming events, and stores prompt metadata in a local SQLite database (raw C API, WAL mode).

4. **Diff on demand** — NoCrumbs never stores diffs. When you want to see what changed, it derives diffs from git/hg on the fly. This keeps the database under 1 MB regardless of project size.

### What Gets Captured

- **Prompt text** — the instruction you gave the AI
- **Session ID** — groups related prompts together
- **File paths** — which files were touched, by which tool (Write/Edit)
- **Base commit hash** — git HEAD at prompt time, used as diff baseline
- **Timestamps** — when each event occurred

### What Doesn't Get Captured

- File contents or diffs (derived from git on demand)
- API keys or credentials (automatically redacted — see below)
- Network traffic of any kind
- Subagent activity or internal planning steps

## Security

### Secret Redaction

When NoCrumbs annotates commit messages, it automatically scrubs secrets from prompt text before writing to git history. Covered patterns:

- OpenAI / Anthropic API keys (`sk-...`)
- AWS access key IDs (`AKIA...`)
- GitHub / GitLab personal access tokens
- Slack bot and user tokens
- JWTs
- Generic `password=`, `token=`, `api_key=` assignments

Redaction runs in both the Mac app and CLI — secrets never reach your commit history.

### Contributor Secret Scanning

The repo includes a [gitleaks](https://github.com/gitleaks/gitleaks) pre-commit hook and CI workflow:

```bash
# One-time setup for contributors
git config core.hooksPath .githooks
```

The hook scans staged changes before every commit. The same scan runs on all PRs via GitHub Actions.

## Performance

NoCrumbs operates as a lightweight hook with minimal overhead:

- **Fire-and-forget** — the CLI never blocks Claude Code. If the Mac app isn't running, the CLI silently exits with code 0.
- **Under 50ms** — typical hook execution time
- **No network** — everything stays on your machine via Unix domain socket
- **Sub-1MB database** — only stores metadata, never diffs

## Supported Tools

Currently supported:
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — via hook events

Coming soon:
- **[Codex CLI](https://github.com/openai/codex)** — via hook events
