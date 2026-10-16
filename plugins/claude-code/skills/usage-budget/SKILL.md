---
name: usage-budget
description: Check the user's AI usage limits (Claude Code 5h/7d windows, Codex, Copilot, Windsurf) with TokenBar before long or expensive work — multi-file refactors, large test runs, long agent loops — or when the user asks about usage, limits, quota or when a limit resets.
---

# TokenBar: usage budget

TokenBar's MCP server (`tokenbar`, bundled with this plugin) reports how much of each AI subscription window is used.

When to check:
- Before a task that will take many turns or tool calls: call `check_budget` with `provider: "claude"`.
- When the user asks about usage, limits, quota or "how long until it resets": call `get_usage` or `time_until_reset`.

How to act on the answer:
- `ok: true`: proceed. For very long work, go in steps and check again between them.
- `ok: false`: tell the user in one line (window, % used, time to reset) and offer to keep the work small or wait until the reset. Don't refuse the task.
- No data: the TokenBar app is not running and no usage files were found. Mention it once and carry on.

Without MCP, the same data is available from `node "${CLAUDE_PLUGIN_ROOT}/server/tokenbar.mjs" --json`.
