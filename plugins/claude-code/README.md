# TokenBar for Claude Code

See how much of your AI usage limits you have used — and when they reset — without leaving Claude Code. TokenBar reads the 5-hour and 7-day windows of Claude Code, Codex, GitHub Copilot, Windsurf or any AI you add, and lets Claude check its own budget before starting a long task.

## What you get

- **MCP tools** (`get_usage`, `time_until_reset`, `check_budget`): Claude can answer "how much of my limit have I used?" and decide to postpone a big task until the reset.
- **`/tokenbar:tokenbar [provider]`**: a quick table of every AI's usage and reset times.
- **A budget warning**: when a Claude window passes 80%, a one-line note is added to your next prompt ("Claude 5h at 86%, resets in 42m — consider postponing long tasks"). At most once every 30 minutes; silent below 80%. Change the threshold with `TOKENBAR_HOOK_PERCENT`.
- **A skill** that tells Claude when it is worth checking the budget.

## Install

```
/plugin marketplace add ChaconLucas/tokenbar
/plugin install tokenbar@tokenbar
```

Requires Node.js 18 or newer. Works best with the TokenBar app (Mac, Windows, Linux) running, but also works without it.

## What it reads, writes and sends

Everything stays on your computer. The plugin makes **no internet requests**.

- **Reads (local only):**
  - `http://127.0.0.1:<port>/v1/usage` — the TokenBar app's localhost API, if running (port from `~/.tokenbar/api.json`).
  - `~/.tokenbar/snapshot.json`, `~/.tokenbar/claude.json`, `~/.tokenbar/providers/*.json` — files written by the TokenBar app.
  - `~/.codex/sessions/**/*.jsonl` — only the newest files, only the `rate_limits` numbers.
- **Writes:** `~/.tokenbar/plugin-hook.json` — the time of the last warning, so it isn't repeated within 30 minutes.
- **Sends:** nothing. No telemetry, no network calls. Your prompts and code are never read.

The source is plain, readable JavaScript in `server/` and `hooks/` (no minified code, no dependencies).

## Links

- Website and API docs: https://chaconlucas.github.io/tokenbar/
- Source: https://github.com/ChaconLucas/tokenbar
- License: MIT
