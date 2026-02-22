---
sidebar_position: 2
---

# Mac App Usage

NoCrumbs lives in your menu bar and captures AI coding sessions in real time.

## Menu Bar

The app runs as a menu bar daemon — no Dock icon by default. Click the magnifying glass icon to:

- **Show NoCrumbs** — open the main window
- **Settings** — configure annotation toggles, diff themes
- **Quit** — fully exit the app

**Tip:** `Cmd+Q` hides the window back to the menu bar. Use the menu bar "Quit" button to actually quit.

## Sidebar

Sessions are grouped by time period (Today, Yesterday, This Week, Older) and sub-grouped by project.

- **Click a session** to see its summary — all prompts, aggregated file stats, diffstat bars
- **Click a prompt event** to see the side-by-side diff it produced
- **Option+Right/Left** expands/collapses a session's events
- **Right-click a session** to rename it

Empty events (prompts with no file changes) are hidden by default. Toggle this in Settings.

## Session Summary

When you select a session, you see:

- **Header** — project path, duration, prompt count, file count, total additions/deletions
- **Prompt timeline** — each prompt with timestamp, commit SHA (clickable link to GitHub/GitLab/Bitbucket), and per-prompt file stats
- **All files** — every file changed across the session with status (Added/Modified/Deleted), line counts, and AI-generated descriptions
- **Copy as Markdown** — exports the full session summary to your clipboard

## Diff Viewer

When you select a prompt event, you see a Phabricator-style side-by-side diff:

- **File list** on the left (collapsible) — click a file to jump to its diff
- **Before/After panes** — syntax-highlighted with 20+ language support
- **Scroll sync** — left and right panes scroll together
- **Search** — filter the file list by filename

The diff is derived on demand from git using the `baseCommitHash` captured at prompt time — it always shows what changed relative to when the prompt was submitted, regardless of whether changes are committed or not.

## Settings

Open via `Cmd+,` or the menu bar.

### Annotation

Controls what appears in commit messages:

- **Annotation enabled** — master toggle for commit annotations
- **Prompt list** — include numbered prompt lines
- **File count per prompt** — show `(N files)` suffix
- **Session ID** — show 8-char session prefix
- **Deep link** — append `nocrumbs://` URL

### Commit Templates

Custom templates for commit annotations. Use `nocrumbs template add` from the CLI to create them, then activate from Settings.

### Diff Theme

18 bundled color themes (12 dark, 6 light) for the diff viewer. Changes apply immediately.

## Deep Links

NoCrumbs registers the `nocrumbs://` URL scheme:

```
nocrumbs://session/abc12345
nocrumbs://session/abc12345/event/uuid
```

Clicking a deep link (e.g., from an annotated commit message) opens NoCrumbs and navigates to that session or event.

## Data Storage

```
~/Library/Application Support/NoCrumbs/
├── nocrumbs.sqlite    ← sessions + prompt events + file changes
└── nocrumbs.sock      ← Unix domain socket (while app running)
```

All data is local. No network calls, no telemetry, no accounts.
