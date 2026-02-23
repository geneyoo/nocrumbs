---
name: verify
description: Run automated E2E verification of the NoCrumbs pipeline (hooks → CLI → socket → DB → UI). Use when the user says "verify", "check pipeline", "e2e check", or uses /verify.
version: 6.0.0
---

# Verify NoCrumbs Pipeline

> Last synced with codebase at commit: `8856539` (2026-02-23)

## Argument Handling

**`/verify`** (no args) — **Runs ALL checks by default.** This is the agentic default — run everything, report results.

**`/verify --select`** — Interactive mode. Use `AskUserQuestion` to ask which check groups to run:

```
question: "Which checks do you want to run?"
header: "Checks"
multiSelect: true
options:
  - label: "Build + Tests"
    description: "Checks 1-3: xcodebuild, swift build, unit tests"
  - label: "Pipeline"
    description: "Checks 4-9: CLI binary, hooks, app running, socket, DB, live capture"
  - label: "Remote transport"
    description: "Check 10: transport endpoint config"
  - label: "UI interaction"
    description: "Checks 11-14: sidebar selection, expand/collapse, window title"
```

Map selections to check numbers:
- "Build + Tests" → checks 1, 2, 3
- "Pipeline" → checks 4, 5, 6, 7, 8, 9
- "Remote transport" → check 10
- "UI interaction" → checks 11, 12, 13, 14

Always run **check 15 (cleanup)** if check 9 was included.

**`/verify <specific args>`** — Interpret as group names: "build", "tests", "pipeline", "remote", "ui", "git". Skip the prompt.

**Inference:** When the user says "verify" in conversation (not as a slash command), infer `--all`. If context suggests only a subset is relevant (e.g., "verify the build" or "verify after my socket changes"), select only the relevant groups.

## Execution Strategy — Agentic Parallelism

**Maximize parallelism.** Independent check groups run concurrently via `Task` agents:

**Parallel group 1 (no dependencies):**
- Build checks (1, 2, 3) — can run simultaneously

**Sequential group (depends on builds passing):**
- Pipeline checks (4-9) — sequential, each depends on prior
- Remote transport (10) — independent but fast, run after builds
- UI checks (11-14) — sequential, depend on app running (check 6)

**Always last:**
- Cleanup (15)

Use `Task` subagents with `subagent_type: "Bash"` to run Build checks 1, 2, 3 in parallel. Then run pipeline + remote + UI sequentially.

**Continue past failures** — show full status for every check. Never bail early.

Output one line per check as you go: `✅` or `❌` with details. At the end, print summary `N/N passed`.

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

### 3. Unit Tests

```bash
xcodebuild test -project NoCrumbs.xcodeproj -scheme NoCrumbs -sdk macosx -derivedDataPath build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5
```

Parse the output for test results. Look for the line matching `Executed N tests, with M tests skipped and K failures`.

- ✅ `Tests: N passed, M skipped, 0 failures`
- ❌ `Tests: K failures out of N tests` — show failing test names from output (lines matching `Test Case.*FAILED`)
- ❌ `Tests: build failed` — show first 5 error lines

### 4. CLI binary

```bash
which nocrumbs && nocrumbs --version
```

- ✅ `CLI: nocrumbs X.Y.Z`
- ❌ `CLI: not found in PATH` — tell user to run `brew install --cask geneyoo/tap/nocrumbs` (or for dev builds: `swift build -c release --package-path CLI/ && ln -sf "$PWD/CLI/.build/release/nocrumbs" /opt/homebrew/bin/nocrumbs`)

### 5. Claude Code hooks installed

```bash
cat ~/.claude/settings.json
```

Parse JSON. Confirm hooks exist:
- `hooks.UserPromptSubmit` contains `nocrumbs event` or `nocrumbs capture-prompt`
- `hooks.PostToolUse` contains `nocrumbs event` or `nocrumbs capture-change`

- ✅ `Hooks: UserPromptSubmit + PostToolUse configured`
- ⚠️ `Hooks: using legacy commands (capture-prompt/capture-change) — run nocrumbs install to upgrade`
- ❌ `Hooks: missing [which ones]` — tell user to run `nocrumbs install`

### 6. App running + window open

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

### 7. Socket alive

```bash
ls -la ~/Library/Application\ Support/NoCrumbs/nocrumbs.sock
```

- ✅ `Socket: nocrumbs.sock present`
- ❌ `Socket: nocrumbs.sock not found`

### 8. Database accessible

```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT COUNT(*) FROM sessions; SELECT COUNT(*) FROM promptEvents; SELECT COUNT(*) FROM commitTemplates;"
```

Also verify schema version and sequenceID column:
```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "PRAGMA user_version;"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT COUNT(*) FROM promptEvents WHERE sequenceID IS NOT NULL;"
```

- ✅ `Database: N sessions, M events, K templates (schema vX), N events with sequenceID`
- ❌ `Database: not found or query failed`
- ⚠️ `Database: schema < v9 — sequenceID column missing`

### 9. Live capture test

Send two test events through the CLI to verify sequenceID grouping:

```bash
echo '{"session_id":"verify-test","prompt":"NoCrumbs verification probe 1","cwd":"/tmp"}' | nocrumbs capture-prompt
sleep 0.5
echo '{"session_id":"verify-test","prompt":"NoCrumbs verification probe 2","cwd":"/tmp"}' | nocrumbs capture-prompt
```

Wait 1 second, then verify both landed in the DB and share the same sequenceID:

```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT COUNT(*) FROM sessions WHERE id = 'verify-test';"
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "SELECT sequenceID, COUNT(*) FROM promptEvents WHERE sessionID = 'verify-test' GROUP BY sequenceID;"
```

- ✅ `Live capture: 2 test prompts stored, same sequenceID`
- ⚠️ `Live capture: prompts stored but sequenceID not grouped (NULL or different)`
- ❌ `Live capture: prompts sent but not found in DB`

### 10. Remote transport

Verify the transport endpoint resolution is correct and remote infrastructure exists:

**Step A: Check TransportEndpoint resolves to local Unix socket by default**

```bash
# Verify no stale env vars are set that would redirect transport
echo "NOCRUMBS_SOCK=${NOCRUMBS_SOCK:-unset} NOCRUMBS_HOST=${NOCRUMBS_HOST:-unset}"
```

- If either is set, report as ⚠️ warning (not failure — user may intend this)

**Step B: Check install-remote command exists**

```bash
nocrumbs install-remote --help 2>&1 || nocrumbs 2>&1 | grep -c "install.*remote"
```

- Verify `install-remote` or `install --remote` appears in CLI help

**Step C: Check remoteTCPPort setting**

```bash
defaults read com.geneyoo.nocrumbs remoteTCPPort 2>/dev/null || echo "not set"
```

Report current state — no failure if not set (it's opt-in).

- ✅ `Remote: transport defaults to Unix socket, install-remote available, TCP port [not set | NNNNN]`
- ⚠️ `Remote: NOCRUMBS_HOST is set to X — transport will use TCP`
- ❌ `Remote: install-remote command not found in CLI`

### 11. Git hooks

```bash
cat .git/hooks/prepare-commit-msg 2>/dev/null
```

- ✅ `Git hooks: prepare-commit-msg installed` (if file exists and contains `nocrumbs`)
- ❌ `Git hooks: prepare-commit-msg not installed` — tell user to run `nocrumbs install-git-hooks`

### 12. UI interaction — session header selection

**This check uses AppleScript to physically click UI elements and verify behavior.**

**Prerequisite:** Accessibility permission must be granted for the terminal running Claude Code (System Settings → Privacy & Security → Accessibility). If AppleScript UI checks fail with "not allowed assistive access", tell the user to grant it and re-run.

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
    set sel to value of attribute "AXSelected" of row 1 of theOutline
    return sel as text
end tell'
```

If `AXSelected` returns `missing value` or is not reliable, fall back to checking the detail pane:

```bash
osascript -e '
tell application "System Events" to tell process "NoCrumbs"
    set detailGroup to group 2 of splitter group 1 of group 1 of window 1
    set allText to entire contents of detailGroup
    return allText as text
end tell' 2>&1
```

If output contains "Session" or "ID", selection worked. If "Select a prompt", failed.

- ✅ `UI click: session header selectable`
- ❌ `UI click: session header NOT selectable`

**Step C: Option+Right to expand**

```bash
osascript -e '
tell application "System Events" to tell process "NoCrumbs"
    set theOutline to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
    set focused of theOutline to true
    delay 0.1
    key code 124 using {option down}
    delay 0.5
    set rowCount to count of rows of theOutline
    return rowCount
end tell'
```

Record as `rowsAfterExpand`. If `rowsAfterExpand > rowsBefore`, expansion worked.

**Step D: Option+Left to collapse**

```bash
osascript -e '
tell application "System Events" to tell process "NoCrumbs"
    set theOutline to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1
    set focused of theOutline to true
    delay 0.1
    key code 123 using {option down}
    delay 0.5
    set rowCount to count of rows of theOutline
    return rowCount
end tell'
```

Record as `rowsAfterCollapse`. If `rowsAfterCollapse < rowsAfterExpand`, collapse worked.

**Combined verdict:**
- ✅ `UI: session selectable, expand (+N rows), collapse (-N rows)`
- ❌ `UI: [specific sub-step that failed]`
- ❌ `UI: accessibility permission denied — grant access in System Settings`

### 13. Window title consistency — 3 scenarios

**Requires:** At least one session with 2+ events. If not, skip with ⚠️.

macOS joins `.navigationTitle` + `.navigationSubtitle` into `AXTitle` as `"{title} – {subtitle}"`.

**Step A: Select session row → read AXTitle**
**Step B: Expand, select first child event → read AXTitle**
**Step C: Select different child event → read AXTitle**
**Step D: Collapse back**

(Use same AppleScript patterns as check 12, reading `title of window 1` after each selection.)

**Validation:**
1. All three titles identical
2. Contains " – " separator
3. Non-empty project name and subtitle

- ✅ `Window title: consistent across 3 scenarios`
- ❌ `Window title: MISMATCH` — show each value
- ⚠️ `Window title: skipped — need session with 2+ events`

### 14. Window title format validation

Validates title content against the database.

```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "
    SELECT s.projectPath, pe.promptText
    FROM sessions s
    JOIN promptEvents pe ON pe.sessionID = s.id
    ORDER BY s.lastActivityAt DESC, pe.timestamp ASC
    LIMIT 1;
"
```

Compare against AXTitle from check 13.

- ✅ `Window title content: matches DB`
- ❌ `Window title content: mismatch` — show expected vs actual

### 15. Cleanup

```bash
sqlite3 ~/Library/Application\ Support/NoCrumbs/nocrumbs.sqlite "DELETE FROM sessions WHERE id = 'verify-test'; DELETE FROM promptEvents WHERE sessionID = 'verify-test';"
```

- 🧹 `Cleanup: test session removed`

## Final Output

```
✅ Build (app): succeeded
✅ Build (CLI): succeeded
✅ Tests: 131 passed, 12 skipped, 0 failures
✅ CLI: nocrumbs 0.4.7
✅ Hooks: UserPromptSubmit + PostToolUse configured
✅ App: running (PID 12345), window open
✅ Socket: nocrumbs.sock present
✅ Database: 3 sessions, 16 events, 0 templates (schema v6)
✅ Live capture: test prompt stored and verified
✅ Remote: transport defaults to Unix socket, install-remote available, TCP port not set
✅ Git hooks: prepare-commit-msg installed
✅ UI: session selectable, expand (+3 rows), collapse (-3 rows)
✅ Window title: consistent across 3 scenarios
✅ Window title content: matches DB
🧹 Cleanup: test session removed

14/14 passed
```

Count only checks that were selected for the pass/fail summary (not cleanup). Show the full block at the end, not incrementally.

Checks 13-14 depend on check 12 completing first (they reuse the sidebar state).

## Important Notes

- The outline path (`outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1`) may change if the view hierarchy changes. If AppleScript can't find the outline, dump the hierarchy with: `osascript -e 'tell application "System Events" to tell process "NoCrumbs" to entire contents of window 1'`
- Row counts from `count of rows` in SwiftUI outlines may only report top-level visible rows. Use individual `row N` access to probe deeper.
- Delays between actions are critical — SwiftUI needs time to update state and re-render.
