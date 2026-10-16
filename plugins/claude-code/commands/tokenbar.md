---
description: Show AI usage limits (5h / 7d windows) from TokenBar
argument-hint: "[provider]"
---

Show the user's current AI usage limits from TokenBar.

1. Call the `get_usage` tool of the `tokenbar` MCP server. If `$ARGUMENTS` is not empty, pass it as `provider`.
   If the MCP tool is unavailable, run instead: `node "${CLAUDE_PLUGIN_ROOT}/server/tokenbar.mjs" --json --no-color`.
2. Present one compact Markdown table, one row per AI: `AI | Window | Used now | Resets in`.
   Use `usedNow` (not `usedPercent`) and turn `resetsInSeconds` into text like `42m`, `3h 10m` or `2d 4h`.
3. Under the table, one line only: flag any window at 80% or more ("Claude 5h at 86%: postpone long tasks until it resets"). Add nothing else.

If there is no data, say that the TokenBar app is not running and no Claude Code/Codex usage files were found, and point to https://github.com/ChaconLucas/tokenbar.
