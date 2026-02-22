---
sidebar_position: 2
---

# How It Works

## The Problem

AI coding assistants are transforming how we write software, but they create a visibility gap: once code is committed, there's no easy way to trace *which prompt* produced *which change*. Traditional `git blame` tells you who and when, but not *why* — and with AI-assisted coding, the "why" is the prompt.

## The Solution

NoCrumbs bridges this gap by capturing the relationship between prompts and commits, entirely on your local machine.

### Architecture

```
Claude Code ──PostToolUse hook──▶ nocrumbs CLI ──socket──▶ Mac App ──▶ SQLite
```

1. **Hook integration** — NoCrumbs registers as a `PostToolUse` hook in Claude Code. Every time Claude executes a tool (file write, bash command, etc.), the hook fires.

2. **CLI capture** — The `nocrumbs` CLI receives the hook payload as JSON, extracts the relevant metadata (session ID, prompt text, tool name, file paths), and forwards it over a Unix domain socket.

3. **Mac App storage** — The native macOS app listens on the socket, processes incoming events, and stores prompt metadata in a local SQLite database via GRDB.

4. **Diff on demand** — NoCrumbs never stores diffs. When you want to see what changed, it derives diffs from git on the fly. This keeps the database tiny (under 1 MB) regardless of project size.

### What Gets Captured

- **Prompt text** — the instruction you gave the AI
- **Session ID** — groups related prompts together
- **Commit hashes** — linked after the commit happens
- **File paths** — which files were touched
- **Timestamps** — when each event occurred

### What Doesn't Get Captured

- File contents or diffs (derived from git on demand)
- API keys or credentials
- Network traffic of any kind

## Detection and Performance

NoCrumbs operates as a lightweight hook with minimal overhead:

- **Fire-and-forget** — the CLI never blocks Claude Code. If the Mac app isn't running, the CLI silently exits.
- **Under 50ms** — typical hook execution time
- **No network** — everything stays on your machine via Unix domain socket

## Supported Tools

Currently supported:
- **Claude Code** (Anthropic) — via PostToolUse hooks

Planned:
- Additional AI coding assistants as hook APIs become available
