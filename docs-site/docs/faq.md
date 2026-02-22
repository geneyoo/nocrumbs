---
sidebar_position: 6
---

# FAQ

### Does NoCrumbs send any data off my machine?

No. NoCrumbs is entirely local. There are no network calls, no telemetry, no cloud sync, and no third-party servers. All data stays on your filesystem and communicates via Unix domain socket between the CLI and Mac app.

### Does NoCrumbs support Mercurial or SVN?

NoCrumbs supports **git** and **Mercurial**. SVN is not on the roadmap.

### Will NoCrumbs slow down my commits?

No. The CLI hook executes in under 50ms and is fire-and-forget — it never blocks your AI assistant or git operations. If the Mac app isn't running, the CLI silently exits with no delay.
