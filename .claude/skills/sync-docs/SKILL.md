---
name: sync-docs
description: Scans the codebase and updates docs/architecture.md to match the current state. Run after completing a milestone.
version: 1.0.0
---

# Sync Architecture Docs

Update `docs/architecture.md` to reflect the current codebase state.

## Instructions

When the user invokes `/sync-docs`:

### 1. Scan Current State

Gather the following from the actual codebase (not from memory):

- **Directory structure**: Glob for all `.swift` files, reconstruct the tree
- **Database schema**: Read `Core/Database/Database.swift` (or wherever migrations live) for current table definitions
- **Models**: Read all files in `Core/Models/` for current data structures
- **VCS providers**: Read `Core/VCS/` for current protocol and implementations
- **IPC**: Read `Core/IPC/` for socket server/client details
- **Features**: List all feature modules in `Features/`
- **Dependencies**: Read `Package.swift` or `.xcodeproj` SPM references
- **ViewModels**: Scan `Features/` for any `*ViewModel.swift` files

### 2. Update docs/architecture.md

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

### 3. Report Changes

After updating, summarize what changed:
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
