## What's New
- Collapse no-change prompts in the sidebar — only prompts that caused file changes are shown by default, with noise between them collapsed into a toggleable "N prompts without changes" pill
- Add visual hierarchy to prompts — file-change prompts use bolder text, no-change prompts are dimmed and smaller, making commits easy to spot at a glance
- Add collapsible sequence headers in the session summary timeline with expand/collapse chevrons

## Improvements
- Make the prompt timeline in session summary scrollable with a fixed max height so it doesn't push the file list off-screen
- Add E2E socket pipeline tests to prevent actor deadlock regressions
