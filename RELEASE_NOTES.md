## Fixes

- Fix socket server dying permanently after a single transient error (e.g., file descriptor exhaustion) — the accept loop now recovers automatically
- Fix Settings showing the socket as "active" when it was actually dead — the health check now probes the socket with a real connection instead of just checking the file exists

## Improvements

- Add a 30-second watchdog that automatically restarts the socket server if it goes down, eliminating the need to manually relaunch the app
