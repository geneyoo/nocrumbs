---
sidebar_position: 2
---

# How It Works

## The Problem

AI coding assistants are transforming how we write software, but they create a visibility gap: once code is committed, there's no easy way to trace *which prompt* produced *which change*. Traditional `git blame` tells you who and when, but not *why* — and with AI-assisted coding, the "why" is the prompt.

## The Solution

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
- API keys or credentials
- Network traffic of any kind
- Subagent activity or internal planning steps

## Performance

NoCrumbs operates as a lightweight hook with minimal overhead:

- **Fire-and-forget** — the CLI never blocks Claude Code. If the Mac app isn't running, the CLI silently exits with code 0.
- **Under 50ms** — typical hook execution time
- **No network** — everything stays on your machine via Unix domain socket
- **Sub-1MB database** — only stores metadata, never diffs

## Supported Tools

Currently supported:
- **Claude Code** (Anthropic) — via hook events

Planned:
- Additional AI coding assistants as hook APIs become available
