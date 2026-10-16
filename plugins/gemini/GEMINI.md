# TokenBar

The `tokenbar` MCP server reports the user's AI subscription usage limits (Claude Code, Codex, GitHub Copilot, Windsurf and any AI the user added to TokenBar): for each AI, windows (usually 5h and 7d) with `usedNow` (% used now) and `resetsInSeconds`.

- When the user asks about usage, limits, quota or when a limit resets: call `get_usage` or `time_until_reset`.
- Before a long or expensive task for the user (multi-file refactors, large test runs, long agent loops) that will also run on another AI they track, such as Claude Code or Codex: call `check_budget` with that provider. If `ok` is false, say so in one line (window, % used, time to reset) and offer to keep the work small or wait. Don't refuse the task.
- If there is no data, the TokenBar app is not running and no Claude Code/Codex usage files were found; mention it once and carry on.
