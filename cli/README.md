# tokenbar CLI and MCP server

Your AI usage limits (Claude Code, Codex, GitHub Copilot, Windsurf, any AI added to
[TokenBar](https://github.com/ChaconLucas/tokenbar)) in the terminal, in your shell prompt and inside
AI agents. Node.js 18+, zero dependencies.

```sh
curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.sh | sh   # Mac/Linux
irm https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.ps1 | iex        # Windows
```

```
$ tokenbar
■ Claude Code   5h ●○○○○○○○○○  13%  ↻ 4h 36m    7d ●●●●○○○○○○  43%  ↻ 4d 12h
■ Codex         5h ○○○○○○○○○○   0%  reset       7d ●○○○○○○○○○   6%  ↻ 5d 14h
$ tokenbar --prompt
CL 13% CX 0%
$ tokenbar get claude 5h --field usedNow
13
```

Commands: `tokenbar`, `--json`, `--prompt [--color] [--window 7d]`,
`get <id> [5h|7d] [--field usedNow|usedPercent|resetsInSeconds|resetsAt|windowMinutes]`,
`watch [--interval 5]`, `--version`, `help`. Respects `NO_COLOR`. Exit code 2 = no data.

Data comes from the TokenBar app's local API (`http://localhost:41777`, real port in
`~/.tokenbar/api.json`), else `~/.tokenbar/snapshot.json`, else the Claude Code / Codex files directly,
so it also works without the app.

## MCP server

`mcp.mjs` (`tokenbar-mcp`) is an MCP server over stdio with the tools `get_usage`,
`time_until_reset` and `check_budget`, so an agent can check its limits before a long task:

```sh
claude mcp add tokenbar --scope user -- node ~/.tokenbar/cli/mcp.mjs
```

Codex, Cursor, VS Code setup, schemas and examples: [docs/api.md](../docs/api.md).

## Files

| File | What |
|---|---|
| `tokenbar.mjs` | CLI |
| `mcp.mjs` | MCP server (stdio, JSON-RPC 2.0, protocol 2025-06-18) |
| `lib/data.mjs` | shared data loader (local API → snapshot.json → direct files) |

License: MIT.
