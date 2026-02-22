---
sidebar_position: 1
---

# CLI Usage

The `nocrumbs` CLI is the bridge between Claude Code and the NoCrumbs Mac app. It runs as a hook — you don't invoke most commands directly.

## Setup Commands

### `nocrumbs install`

Writes hook entries to `~/.claude/settings.json`. Run once after installing:

```bash
nocrumbs install
```

This registers NoCrumbs to receive `UserPromptSubmit` and `PostToolUse` events from Claude Code.

### `nocrumbs install-git-hooks`

Installs a `prepare-commit-msg` git hook in the current repository:

```bash
cd your-project
nocrumbs install-git-hooks
```

This enables automatic commit message annotation with prompt context. Run in each repo where you want annotations.

## Hook Commands (automatic)

These are called by hooks — you don't run them manually:

| Command | Trigger | Purpose |
|---------|---------|---------|
| `nocrumbs event` | Any Claude Code hook | Unified event capture (prompts + file changes) |
| `nocrumbs annotate-commit` | `git commit` | Appends prompt context to commit messages |

## Utility Commands

### `nocrumbs describe`

Pipe per-file change descriptions to the app:

```bash
echo '{"session_id":"<id>","descriptions":[{"file_path":"/path/to/file","description":"what changed"}]}' | nocrumbs describe
```

### `nocrumbs rename-session`

Rename a session:

```bash
echo '{"session_id":"<id>","name":"my session name"}' | nocrumbs rename-session
```

### `nocrumbs template`

Manage commit annotation templates:

```bash
nocrumbs template add --name minimal --body '---\n{{summary_line}}'
nocrumbs template list
nocrumbs template set --name minimal
nocrumbs template remove --name minimal
nocrumbs template preview
```

#### Template Placeholders

| Placeholder | Value |
|-------------|-------|
| `{{prompt_count}}` | Number of prompts |
| `{{total_files}}` | Total unique files changed |
| `{{session_id}}` | Session UUID (8-char prefix) |
| `{{summary_line}}` | `🥐 3 prompts · 12 files · abc12345` |
| `{{#prompts}}...{{/prompts}}` | Loop over prompts |
| `{{index}}` | 1-based prompt index (inside loop) |
| `{{text}}` | Prompt text, truncated to 72 chars (inside loop) |
| `{{file_count}}` | Files changed by this prompt (inside loop) |

### `nocrumbs --version`

```bash
nocrumbs --version
```
