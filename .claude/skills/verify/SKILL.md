---
name: verify
description: Run automated E2E verification of the NoCrumbs pipeline (hooks → CLI → socket → DB → UI). Use when the user says "verify", "check pipeline", "e2e check", or uses /verify.
version: 5.0.0
---

# Verify NoCrumbs Pipeline

> Last synced with codebase at commit: `d7b9ddf` (2026-02-22)

## Argument Handling

**`/verify --all`** — Run all checks without prompting.

**`/verify` (no args)** — Use `AskUserQuestion` to ask which checks to run:

```
question: "Which checks do you want to run?"
header: "Checks"
multiSelect: true
options:
  - label: "Build (app + CLI)"
    description: "Checks 1-2: xcodebuild + swift build"
  - label: "Pipeline (CLI, hooks, socket, DB)"
    description: "Checks 3-8: CLI binary, hooks, app running, socket, DB, live capture"
  - label: "Git hooks"
    description: "Check 9: prepare-commit-msg hook"
  - label: "UI interaction"
    description: "Check 10: AppleScript session selection, Option+Arrow expand/collapse"
```

Map selections to check numbers:
- "Build (app + CLI)" → checks 1, 2
- "Pipeline (CLI, hooks, socket, DB)" → checks 3, 4, 5, 6, 7, 8
- "Git hooks" → check 9
- "UI interaction" → check 10

Always run **check 11 (cleanup)** if check 8 was included.

**`/verify <specific args>`** — If the user passes other args (e.g., "build", "ui", "pipeline"), interpret them as check group names and skip the prompt.

## Execution

Run selected checks in order. **Continue past failures** — show full status for every check.

Output one line per check: `✅` or `❌` with details. At the end, print summary `N/N passed`.

**Prerequisite:** Accessibility permission must be granted for the terminal running Claude Code (System Settings → Privacy & Security → Accessibility). If AppleScript UI checks fail with "not allowed assistive access", tell the user to grant it and re-run.

## Checks

### 1. Build — Mac App

```bash
xcodebuild -project NoCrumbs.xcodeproj -scheme NoCrumbs -configuration Debug -sdk macosx -derivedDataPath build build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3
```

- ✅ `Build (app): succeeded`
- ❌ `Build (app): failed` — show the first 5 error lines from the build output

### 2. Build — CLI

```bash
swift build -c release --package-path CLI/ 2>&1 | tail -3
```

- ✅ `Build (CLI): succeeded`
- ❌ `Build (CLI): failed` — show the first 5 error lines

### 3. CLI binary

```bash
which nocrumbs && nocrumbs --version
```

- ✅ `CLI: nocrumbs 0.3.0`
- ❌ `CLI: not found in PATH` — tell user to run `swift build -c release --package-path CLI/ && cp CLI/.build/release/nocrumbs /usr/local/bin/`

### 4. Claude Code hooks installed

```bash
cat ~/.claude/settings.json
```

Parse JSON. Confirm both hooks exist:
- `hooks.UserPromptSubmit` contains `nocrumbs capture-prompt` or `nocrumbs event`
- `hooks.PostToolUse` contains matcher `Write|Edit` and `nocrumbs capture-change` or `nocrumbs event`

- ✅ `Hooks: UserPromptSubmit + PostToolUse (Write|Edit)`
- ❌ `Hooks: missing [which ones]` — tell user to run `nocrumbs install`

### 5. App running + window open

```bash
pgrep -x NoCrumbs
```

- If not running: quit any old instance, launch via `open build/Build/Products/Debug/NoCrumbs.app`, wait 2s, re-check
- Then ensure the main window is open and focused:

```bash
osascript -e '
tell application "NoCrumbs" to activate
delay 0.5
tell application "System Events" to tell process "NoCrumbs"
    if (count of windows) is 0 then
        keystroke "n" using {command down, shift down}
        delay 0.5
    end if
    set frontmost to true
end tell'
```

- ✅ `App: running (PID XXXXX), window open`
- ❌ `App: not running` or `App: window failed to open`

### 6. Socket alive

```bash
ls -la ~/Library/Application\ Support/NoCrumbs/nocrumbs.sock
```

- ✅ `Socket: nocrumbs.sock present`
- ❌ `Socket: nocrumbs.sock not found`

### 7. Database accessible

```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT COUNT(*) FROM sessions; SELECT COUNT(*) FROM promptEvents; SELECT COUNT(*) FROM commitTemplates;"
```

Also verify schema version:
```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "PRAGMA user_version;"
```

- ✅ `Database: N sessions, M events, K templates (schema v6)`
- ❌ `Database: not found or query failed`
- ⚠️ `Database: schema version < 6 — restart app to trigger migration`

### 8. Live capture test

Send a test prompt + a file change through the CLI:

```bash
echo '{"session_id":"verify-test","prompt":"NoCrumbs verification probe","cwd":"/tmp"}' | nocrumbs capture-prompt
```

Wait 1 second, then verify it landed in the DB:

```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT COUNT(*) FROM sessions WHERE id = 'verify-test';"
```

- ✅ `Live capture: test prompt stored and verified`
- ❌ `Live capture: prompt sent but not found in DB`

### 9. Git hooks

```bash
cat .git/hooks/prepare-commit-msg
```

- ✅ `Git hooks: prepare-commit-msg installed` (if file exists and contains `nocrumbs`)
- ❌ `Git hooks: prepare-commit-msg not installed` — tell user to run `nocrumbs install-git-hooks`

### 10. UI interaction — session header selection

**This check uses AppleScript to physically click UI elements and verify behavior.**

The outline path for the sidebar list is:
```
outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
```

**Step A: Count rows before interaction**

```bash
osascript -e '
tell application "System Events" to tell process "NoCrumbs"
    set theOutline to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
    set rowCount to count of rows of theOutline
    return rowCount
end tell'
```

Record this as `rowsBefore`.

**Step B: Click the first row (session header)**

```bash
osascript -e '
tell application "System Events" to tell process "NoCrumbs"
    set theOutline to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
    tell theOutline
        select row 1
    end tell
    delay 0.3
    -- Check if row 1 is now selected
    set sel to value of attribute "AXSelected" of row 1 of theOutline
    return sel as text
end tell'
```

If `AXSelected` returns `missing value` or is not reliable, fall back to checking the detail pane. After clicking row 1, check if the detail pane shows session info:

```bash
osascript -e '
tell application "System Events" to tell process "NoCrumbs"
    -- Look for "Session" text in the detail pane (right side of splitter)
    set detailGroup to group 2 of splitter group 1 of group 1 of window 1
    set allText to entire contents of detailGroup
    return allText as text
end tell' 2>&1
```

If the output contains "Session" or "ID" (from SessionDetailView), selection worked. If it still shows "Select a prompt", selection failed.

- ✅ `UI click: session header selectable`
- ❌ `UI click: session header NOT selectable — clicking row 1 did not change detail pane`

**Step C: Option+Right to expand**

```bash
osascript -e '
tell application "System Events" to tell process "NoCrumbs"
    set theOutline to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
    -- Make sure outline has focus
    set focused of theOutline to true
    delay 0.1
    -- Send Option+Right arrow
    key code 124 using {option down}
    delay 0.5
    -- Count rows after expand
    set rowCount to count of rows of theOutline
    return rowCount
end tell'
```

Record this as `rowsAfterExpand`. If `rowsAfterExpand > rowsBefore`, expansion worked (child event rows appeared).

- ✅ `UI expand: Option+Right added N child rows (before: X, after: Y)`
- ❌ `UI expand: row count unchanged after Option+Right (still N)`

**Step D: Option+Left to collapse**

```bash
osascript -e '
tell application "System Events" to tell process "NoCrumbs"
    set theOutline to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
    set focused of theOutline to true
    delay 0.1
    -- Send Option+Left arrow
    key code 123 using {option down}
    delay 0.5
    set rowCount to count of rows of theOutline
    return rowCount
end tell'
```

Record this as `rowsAfterCollapse`. If `rowsAfterCollapse < rowsAfterExpand`, collapse worked.

- ✅ `UI collapse: Option+Left removed N child rows (before: X, after: Y)`
- ❌ `UI collapse: row count unchanged after Option+Left (still N)`

**Combined verdict for check 10:**
- ✅ `UI: session selectable, Option+Right expands (+N rows), Option+Left collapses (-N rows)`
- ❌ `UI: [specific sub-step that failed]`

**If AppleScript fails with accessibility error:**
- ❌ `UI: accessibility permission denied — grant Accessibility access to your terminal in System Settings → Privacy & Security → Accessibility`

### 11. Cleanup

```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "DELETE FROM sessions WHERE id = 'verify-test'; DELETE FROM promptEvents WHERE sessionID = 'verify-test';"
```

- 🧹 `Cleanup: test session removed`

## Final Output

```
✅ Build (app): succeeded
✅ Build (CLI): succeeded
✅ CLI: nocrumbs 0.3.0
✅ Hooks: UserPromptSubmit + PostToolUse (Write|Edit)
✅ App: running (PID 12345), window open
✅ Socket: nocrumbs.sock present
✅ Database: 3 sessions, 16 events, 0 templates (schema v6)
✅ Live capture: test prompt stored and verified
✅ Git hooks: prepare-commit-msg installed
✅ UI: session selectable, Option+Right expands (+3 rows), Option+Left collapses (-3 rows)
🧹 Cleanup: test session removed

10/10 passed
```

Count only the checks that were selected for the pass/fail summary (not cleanup). Show the full block at the end, not incrementally.

## Important Notes

- The outline path (`outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1`) may change if the view hierarchy changes. If AppleScript can't find the outline, dump the hierarchy with: `osascript -e 'tell application "System Events" to tell process "NoCrumbs" to entire contents of window 1'`
- Row counts from `count of rows` in SwiftUI outlines may only report top-level visible rows. Use individual `row N` access to probe deeper.
- Delays between actions are critical — SwiftUI needs time to update state and re-render.
