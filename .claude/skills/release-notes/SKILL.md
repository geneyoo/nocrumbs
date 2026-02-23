---
name: release-notes
description: Generate human-readable release notes for the next version. Use when the user says "release notes", "summarize changes", "prep release", or uses /release-notes.
version: 1.0.0
---

# Release Notes Generator

Generate a human-readable summary of changes since the last tagged version and write to `RELEASE_NOTES.md`.

## Instructions

### 1. Find the previous version tag

```bash
# Get the latest version tag
git describe --tags --abbrev=0
```

### 2. Gather commits since that tag

```bash
git log <previous-tag>..HEAD --oneline
```

### 3. Read the actual code changes

Don't just reword commit messages. Read the diffs to understand what actually changed:

```bash
git diff <previous-tag>..HEAD --stat
```

Read key changed files if needed to understand the feature/fix.

### 4. Write RELEASE_NOTES.md

Group changes into these categories (skip empty categories):

```markdown
## What's New
- Feature descriptions in plain language (what the user gets, not what code changed)

## Fixes
- Bug fix descriptions (what was broken, now works)

## Improvements
- Performance, UX, or quality-of-life changes
```

**Rules:**
- Write for end users, not developers
- One bullet per logical change (merge related commits)
- No commit hashes, no file paths, no technical jargon
- Start each bullet with a verb (Add, Fix, Improve, etc.)
- Keep it concise — aim for 3-8 bullets total

### 5. Show the user the notes

Print the contents of RELEASE_NOTES.md so the user can review before running `release.sh`.

### 6. Remind the user

```
Release notes written to RELEASE_NOTES.md
Run `./scripts/release.sh` when ready to release.
```
