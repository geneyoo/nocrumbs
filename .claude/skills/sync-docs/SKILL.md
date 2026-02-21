---
name: sync-docs
description: Scans the codebase and updates docs/architecture.md to match the current state. Run after completing a milestone.
version: 2.0.0
---

# Sync Architecture Docs

Update `docs/architecture.md` to reflect the current codebase state.

## Instructions

When the user invokes `/sync-docs`:

### 1. Determine Sync Strategy

**Delta sync (default):** Find the last commit that touched `docs/architecture.md`:

```bash
git log -1 --format=%H -- docs/architecture.md
```

Then get the diff stat since that commit:

```bash
git diff <last-sync-commit>..HEAD --stat
```

If no files changed since the last sync, report "architecture.md is up to date" and stop.

**Full sync:** Use `--full` flag OR if `docs/architecture.md` doesn't exist yet OR if the delta approach returns errors. Falls back to scanning everything.

### 2. Delta Sync (Default Path)

From the `git diff --stat` output, identify which categories of files changed:

| Changed files matching | Read & update section |
|---|---|
| `Core/Database/*` | Database Schema, Database Singleton |
| `Core/Models/*` | Data models referenced in schema/flow |
| `Core/VCS/*` | VCS Abstraction, Diff Parsing |
| `Core/IPC/*` | IPC details |
| `Features/**/*` | Feature modules, ViewModels |
| `App/*` | Menu Bar Behavior, App lifecycle |
| `UI/*` | SwiftUI + AppKit Hybrid |
| `Package.swift`, `*.xcodeproj` | Dependencies |
| `CLI/*` | CLI section |

Only read files in the changed categories. Read the current `docs/architecture.md` and do **targeted section updates** — don't rewrite unchanged sections.

Also check for:
- **New `.swift` files** → update Directory Structure section
- **Deleted files** → remove from Directory Structure
- **New directories** → update tree

### 3. Full Sync (Fallback)

Gather the following from the actual codebase (not from memory):

- **Directory structure**: Glob for all `.swift` files, reconstruct the tree
- **Database schema**: Read `Core/Database/Database.swift` for current table definitions
- **Models**: Read all files in `Core/Models/` for current data structures
- **VCS providers**: Read `Core/VCS/` for current protocol and implementations
- **IPC**: Read `Core/IPC/` for socket server/client details
- **Features**: List all feature modules in `Features/`
- **Dependencies**: Read `Package.swift` or `.xcodeproj` SPM references
- **ViewModels**: Scan `Features/` for any `*ViewModel.swift` files

Rewrite `docs/architecture.md` with the scanned data. Preserve the document structure:

1. Data Flow diagram
2. Directory Structure (from actual files)
3. Database Schema (from actual code)
4. Database Singleton (from actual code)
5. IPC details
6. VCS Abstraction
7. Diff Parsing models
8. Menu Bar Behavior
9. SwiftUI + AppKit Hybrid table
10. Dependencies
11. Debugging commands

### 4. Report Changes

After updating, summarize what changed:
- Which sections were updated and why
- New files/features added
- Schema changes
- New dependencies
- Anything removed

### Rules

- **Read the actual code** — never write docs from memory or assumptions
- **Keep code examples real** — copy from actual source files, not templates
- **Don't modify CLAUDE.md** — that file contains rules, not architecture details
- **Don't modify source code** — this skill is read-only except for docs/architecture.md
- **If a section has no corresponding code yet**, mark it as `<!-- Not yet implemented -->` rather than removing it
- **Non-code changes matter too** — if scripts, configs, or skill definitions changed, check if they affect documented architecture (e.g., new IPC patterns, build steps, debugging commands)
