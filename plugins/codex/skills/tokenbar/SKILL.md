---
name: tokenbar
description: Show the user's AI usage limits (Codex, Claude Code, Copilot, Windsurf 5h/7d windows) with TokenBar, and check the budget before long or expensive work — multi-file refactors, large test runs, long agent loops — or when the user asks about usage, limits, quota or when a limit resets.
---

# TokenBar: usage limits

The `tokenbar` MCP server bundled with this plugin reports how much of each AI subscription window is used.

## Show usage (when the user asks, or invokes this skill directly)

1. Call the `get_usage` tool of the `tokenbar` MCP server (pass `provider` if the user named one).
   Without MCP, run `node server/tokenbar.mjs --json --no-color` from this plugin's folder.
2. Present one compact Markdown table, one row per AI: `AI | Window | Used now | Resets in`.
   Use `usedNow` (not `usedPercent`) and turn `resetsInSeconds` into text like `42m`, `3h 10m` or `2d 4h`.
3. Under the table, one line only: flag any window at 80% or more.

## Check the budget (before long work)

- Call `check_budget` with `provider: "codex"`.
- `ok: true`: proceed; for very long work, go in steps and check again between them.
- `ok: false`: tell the user in one line (window, % used, time to reset) and offer to keep the work small or wait until the reset. Don't refuse the task.
- No data: the TokenBar app is not running and no usage files were found. Mention it once and carry on.
