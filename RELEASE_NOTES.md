## Fixes
- Fix socket server crashes when multiple Claude Code instances run concurrently (local + devserver + OD)
- Fix SIGPIPE crash when CLI client disconnects mid-response
- Fix hung connections from dropped SSH tunnels or killed CLI processes (5s read timeout)
- Fix partial writes on large payloads (e.g., big Edit tool_input)

## Improvements
- Increase listen backlog from 5 to 128 for burst traffic from concurrent agents
- Add exponential backoff on accept failures to prevent CPU spin
