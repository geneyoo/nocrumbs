## What's New
- Add prompt sequence grouping in the sidebar — related prompts are visually connected with a timeline until file changes create a new sequence
- Add debug mode for UI development — launch with `-debugMockData` to get realistic mock data across multiple repos and days without needing a live Claude Code session
- Add release notes generation to the release pipeline — human-readable summaries instead of auto-generated commit lists

## Fixes
- Fix prompts appearing to "replace" each other during active sessions — all prompts in the current sequence now show immediately, even before file changes arrive
- Fix the file list panel in the diff viewer sometimes starting collapsed when it should be expanded by default

## Improvements
- Filter out task-notification noise from the sidebar — only real user prompts are shown
- Improve session titles to use the first meaningful prompt instead of system messages
