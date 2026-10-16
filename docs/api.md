# TokenBar API & developer guide

> **Resumo em português.** O TokenBar expõe o uso das IAs (Claude Code, Codex, Copilot, Windsurf
> e qualquer outra) para os seus scripts e agentes: uma **API local** só neste computador
> (`http://localhost:41777/v1/usage`, porta real em `~/.tokenbar/api.json`), a **CLI** `tokenbar`
> (barras no terminal, `--prompt` para o prompt do shell, `get` para scripts), um **servidor MCP**
> (`tokenbar-mcp`) para o Claude Code, Codex e Cursor consultarem o próprio limite
> (`check_budget` antes de uma tarefa longa), o arquivo `~/.tokenbar/snapshot.json`, a API do Wi-Fi
> usada pelos celulares e **webhooks** (aviso em 80%/95% e no reset, inclusive Slack e Discord).
> Para **escrever** dados de outra IA, grave `~/.tokenbar/providers/<id>.json`
> ([providers.md](providers.md)). Instalar a CLI:
> `curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.sh | sh`.
> Nada exige chave na API local, por isso ela **só escuta 127.0.0.1**: não a exponha na rede.

---

## Overview

```
 SOURCES (read by the app)                      TOKENBAR APP (Mac / Windows / Linux)
 Claude Code statusline → ~/.tokenbar/claude.json ─┐
 Codex session logs     → ~/.codex/sessions/*.jsonl├──▶  collector (every 30 s)
 Copilot, Windsurf      → built in                 │        │
 your script  (WRITE)   → ~/.tokenbar/providers/*.json      │
                                                            ├──▶ local API  http://localhost:41777  ◀── curl, scripts
                                                            │                                       ◀── `tokenbar` CLI
                                                            │                                       ◀── `tokenbar-mcp` ◀── AI agents
                                                            ├──▶ ~/.tokenbar/snapshot.json          ◀── VS Code ext., CLI fallback
                                                            ├──▶ webhooks (80% / 95% / reset)       ──▶ Slack, Discord, Home Assistant
                                                            └──▶ Wi-Fi API (Bearer token, Bonjour)  ──▶ iPhone, Android, watches
```

| Want to… | Use |
|---|---|
| Read usage from a script on the same computer | [Local API](#local-api) or [`tokenbar get`](#cli) |
| Show usage in the shell prompt / tmux | [`tokenbar --prompt`](#shell-prompts) |
| Let an AI agent check its own budget | [MCP server](#mcp-server) |
| Read without the app running | [CLI](#cli) (falls back to the files) or [`snapshot.json`](#snapshotjson) |
| Be notified at 80% / 95% / reset | [Webhooks](#webhooks) |
| Add another AI to TokenBar | [Write a provider file](#writing-add-any-ai) |
| See usage in Raycast / VS Code / Stream Deck | [Integrations](#integrations) |

---

## Local API

Served by the TokenBar desktop app (Mac, Windows, Linux) while it runs.

- **Base URL:** `http://127.0.0.1:<port>` — normally `http://localhost:41777`. The app tries port
  **41777** first, then the next free one up to 41787. The real port is in `~/.tokenbar/api.json` (Windows: `%USERPROFILE%\.tokenbar\api.json`):

  ```json
  {"port": 41777, "pid": 12345, "app": "TokenBar", "version": "0.5.0", "platform": "mac"}
  ```

  `platform` is `mac`, `windows` or `linux`. **No file = the app is not running** (it is deleted on quit).
  If the app crashed, the file can be left behind: when its `pid` is not alive, treat the app as not
  running and fall back to [`snapshot.json`](#snapshotjson).
- **Client recipe:** read the port from `api.json` (default 41777) → skip if the `pid` is dead →
  `GET /v1/health` and check `"app": "TokenBar"` before trusting the port (another program may own it)
  → `GET /v1/usage`. Use a short timeout (~1.5 s).
- **Localhost only**, `GET` only, no auth, no CORS headers. The `Host` header must be
  `127.0.0.1:<port>` or `localhost:<port>` (anything else gets `403`), which blocks DNS-rebinding
  attacks from web pages.
- Errors are JSON: `{"error": "not_found"}` (404), `forbidden` (403), `method_not_allowed` (405), `bad_request` (400).

### `GET /v1/health`

```json
{"ok": true, "app": "TokenBar", "version": "0.5.0", "platform": "mac"}
```

### `GET /v1/usage`

```json
{
  "updatedAt": 1792167244,
  "providers": [
    {
      "id": "claude",
      "name": "Claude Code",
      "color": "#9e5cff",
      "observedAt": 1792167193,
      "windows": [
        {"id": "five_hour", "label": "5h", "usedPercent": 13, "usedNow": 13,
         "resetsAt": 1792183800, "resetsInSeconds": 16556, "windowMinutes": 300},
        {"id": "seven_day", "label": "7d", "usedPercent": 43, "usedNow": 43,
         "resetsAt": 1792558800, "resetsInSeconds": 391556, "windowMinutes": 10080}
      ]
    },
    {
      "id": "codex",
      "name": "Codex",
      "color": "#ee29c2",
      "observedAt": 1792079865,
      "windows": [
        {"id": "primary", "label": "5h", "usedPercent": 30, "usedNow": 0,
         "resetsAt": 1792084449, "resetsInSeconds": 0, "windowMinutes": 300},
        {"id": "secondary", "label": "7d", "usedPercent": 6, "usedNow": 6,
         "resetsAt": 1792651192, "resetsInSeconds": 483982, "windowMinutes": 10080}
      ]
    }
  ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `updatedAt` | number | when the app last read the sources (Unix seconds) |
| `providers[].id` | string | `claude`, `codex`, `copilot`, `windsurf`, or the id of a [provider file](#writing-add-any-ai) |
| `providers[].name` | string | display name |
| `providers[].color` | string \| null | `#RRGGBB` |
| `providers[].observedAt` | number \| null | when this AI's number was last observed (Unix s). Claude only updates while a Claude Code session runs, so this can be old |
| `windows[].id` | string | window id (`five_hour`, `seven_day`, `primary`, `secondary`, or the provider file's) |
| `windows[].label` | string | short label: `5h`, `7d`, `1d`, `30d`, `1M`… The first window is the short one, the second the long one |
| `windows[].usedPercent` | number | last observed % (can exceed 100) |
| `windows[].usedNow` | number | **use this one**: `usedPercent`, or `0` once `resetsAt` has passed |
| `windows[].resetsAt` | number \| null | when the window resets (Unix s) |
| `windows[].resetsInSeconds` | number \| null | seconds until `resetsAt` (`0` if it passed) |
| `windows[].windowMinutes` | number \| null | window length (300 = 5 h, 10080 = 7 d) |

### `GET /v1/usage/{id}`

One provider object (same shape as an item of `providers`), or `404 {"error":"not_found"}`.

---

## CLI

`tokenbar` works with or without the app: it reads the **local API** (port from `api.json`,
default 41777, 1.5 s timeout), then **`~/.tokenbar/snapshot.json`** (if younger than 10 min), then the
**sources directly** (`~/.tokenbar/claude.json`, the newest Codex session log,
`~/.tokenbar/providers/*.json`). Node.js 18+, zero dependencies.

```sh
# Mac / Linux
curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.sh | sh
# Windows (PowerShell)
irm https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.ps1 | iex
```

The installer puts the files in `~/.tokenbar/cli/`, the commands `tokenbar` and `tokenbar-mcp` in
`~/.local/bin/` (Windows: `tokenbar.cmd` in `%USERPROFILE%\.tokenbar\bin\`), and offers to register
the MCP server in Claude Code. From a checkout you can also run `node cli/tokenbar.mjs`.

| Command | Output |
|---|---|
| `tokenbar` | one line per AI: colored 10-dot bars for 5h and 7d, %, time to reset |
| `tokenbar --json` | the `/v1/usage` shape, plus `"source"`: `api`, `snapshot`, `direct`, `stale-snapshot` or `none` |
| `tokenbar --prompt` | `CL 13% CX 0%` (first window; `--window 7d` for the long one; colors only with `--color`) |
| `tokenbar get <id> [5h\|7d] [--field F]` | one number. `F`: `usedNow` (default), `usedPercent`, `resetsInSeconds`, `resetsAt`, `windowMinutes` |
| `tokenbar watch [--interval 5]` | full-screen view refreshed every 5 s |
| `tokenbar --version`, `tokenbar help` | |

```
$ tokenbar
■ Claude Code   5h ●○○○○○○○○○  13%  ↻ 4h 36m    7d ●●●●○○○○○○  43%  ↻ 4d 12h
■ Codex         5h ○○○○○○○○○○   0%  reset       7d ●○○○○○○○○○   6%  ↻ 5d 14h
from TokenBar app · updated 22s ago

$ tokenbar get claude 5h
13
$ tokenbar get codex 7d --field resetsInSeconds
483982
```

`<id>` also accepts the 2-letter code (`CL`, `CX`) or the name. `5h`/`7d` mean "first/second
window", so they work for AIs whose windows are `1d`/`30d` too. Colors follow
[NO_COLOR](https://no-color.org) and are off when the output is not a terminal (`--color` forces them).
Exit codes: `0` ok, `1` usage error or empty field (e.g. no reset time), `2` no data / unknown AI or window.

---

## MCP server

`tokenbar-mcp` (`cli/mcp.mjs`) is a [Model Context Protocol](https://modelcontextprotocol.io) server
over **stdio** (protocol `2025-06-18`), so AI agents can check their own limits. Same data loader as the CLI.

| Tool | Arguments | Returns |
|---|---|---|
| `get_usage` | `provider?` | text summary + `structuredContent` in the `/v1/usage` shape (or one provider) |
| `time_until_reset` | `provider`, `window?` (`5h`\|`7d`, default the first) | `{provider, window, seconds, resetsAt, human, usedNow}` |
| `check_budget` | `provider`, `max_percent?` (default 80), `window?` | `{ok, usedNow, resetsInSeconds, resetsAt, advice, window, windows[]…}`. Without `window` it checks the most used one |

### Claude Desktop (one click)

Download `TokenBar.mcpb` from [Releases](https://github.com/ChaconLucas/tokenbar/releases) and double-click it
(or drag it into Claude Desktop → Settings → Extensions). It bundles the server, so the CLI install is not needed;
Claude Desktop runs it with its own Node.

### Claude Code

```sh
claude mcp add tokenbar --scope user -- node ~/.tokenbar/cli/mcp.mjs
```

(the installer does this for you; check with `claude mcp get tokenbar`).

### Codex (`~/.codex/config.toml`)

```toml
[mcp_servers.tokenbar]
command = "node"
args = ["/Users/you/.tokenbar/cli/mcp.mjs"]
```

### Cursor (`~/.cursor/mcp.json`) and VS Code (`.vscode/mcp.json`)

```json
{ "mcpServers": { "tokenbar": { "command": "node", "args": ["/Users/you/.tokenbar/cli/mcp.mjs"] } } }
```

VS Code uses `"servers"` instead of `"mcpServers"`. Use the absolute path (no `~`). Windows:
`"C:\\Users\\you\\.tokenbar\\cli\\mcp.mjs"`. Installed from npm instead? Use `"command": "tokenbar-mcp"`, no args.

### Example agent prompt

Put this in `CLAUDE.md`, `AGENTS.md` or your agent's system prompt:

```text
Before starting a long task (big refactor, many files, long test loops), call the tokenbar
check_budget tool with provider "claude" (use "codex" if you are Codex). If ok is false,
stop and tell me the usage and when it resets (resetsInSeconds), and propose either waiting
or a smaller first step. If ok is true but usedNow is above 60, prefer the cheaper plan.
```

A session looks like:

```text
→ check_budget {"provider":"claude"}
← OK: Claude Code 7d window is at 43% (budget 80%, 37 points left). Fine to proceed; …
```

---

## Shell prompts

`tokenbar --prompt` reads the local API (≈ 70 ms). Without the app it reads files, still fast.

**zsh** (`~/.zshrc`):

```zsh
setopt PROMPT_SUBST
RPROMPT='$(tokenbar --prompt 2>/dev/null)'
```

**bash** (`~/.bashrc`): `PS1='$(tokenbar --prompt 2>/dev/null) \w \$ '`

**starship** (`~/.config/starship.toml`):

```toml
[custom.tokenbar]
command = "tokenbar --prompt"
when = "true"
shell = ["sh"]
format = "[$output]($style) "
style = "purple"
```

**tmux** (`~/.tmux.conf`):

```tmux
set -g status-interval 30
set -g status-right '#(tokenbar --prompt) %H:%M'
```

**Script**, e.g. wait until Claude is under 50% before a batch job:

```sh
while [ "$(tokenbar get claude 5h)" -ge 50 ]; do sleep 300; done
```

---

## Code examples

### curl

```sh
curl -s http://localhost:41777/v1/usage          # default port
# robust: real port from api.json, and make sure it's TokenBar answering
PORT=$(node -p 'require(require("os").homedir()+"/.tokenbar/api.json").port' 2>/dev/null || echo 41777)
curl -s -m 2 http://127.0.0.1:$PORT/v1/health | grep -q '"app":"TokenBar"' \
  && curl -s -m 2 http://127.0.0.1:$PORT/v1/usage/claude
```

### JavaScript (Node 18+, fetch)

```js
import { readFileSync } from "node:fs";
import { homedir } from "node:os";

let port = 41777;
try {
  const info = JSON.parse(readFileSync(`${homedir()}/.tokenbar/api.json`, "utf8"));
  process.kill(info.pid, 0); // throws if the app is gone (stale file) → read snapshot.json instead
  port = info.port;
} catch {}
const get = (path) => fetch(`http://127.0.0.1:${port}${path}`, { signal: AbortSignal.timeout(1500) }).then((r) => r.json());
if ((await get("/v1/health")).app !== "TokenBar") throw new Error("not TokenBar on this port");
const { providers } = await get("/v1/usage");
for (const p of providers) console.log(p.name, p.windows.map((w) => `${w.label} ${w.usedNow}%`).join(" "));
```

### Python (standard library)

```python
import json, pathlib, urllib.request

try:
    port = json.loads((pathlib.Path.home() / ".tokenbar" / "api.json").read_text())["port"]
except (OSError, ValueError, KeyError):
    port = 41777

def get(path):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=1.5) as r:
        return json.load(r)

assert get("/v1/health").get("app") == "TokenBar", "not TokenBar on this port"
usage = get("/v1/usage")
claude = next((p for p in usage["providers"] if p["id"] == "claude"), None)
if claude:
    w = claude["windows"][0]
    print(f'{claude["name"]} {w["label"]}: {w["usedNow"]}%, resets in {w["resetsInSeconds"]} s')
```

---

## snapshot.json

`~/.tokenbar/snapshot.json` (Windows: `%USERPROFILE%\.tokenbar\snapshot.json`) is written by the
desktop apps every 30 s, atomically. Same providers as `/v1/usage`, but windows have only
`id`, `label`, `usedPercent`, `resetsAt`, `windowMinutes`, so compute the rest yourself:

```
usedNow         = (resetsAt != null && resetsAt <= now) ? 0 : usedPercent
resetsInSeconds = resetsAt == null ? null : max(0, resetsAt - now)
```

Treat it as stale when `updatedAt` is more than ~10 minutes old (the app is closed). The VS Code
extension and the CLI read this file.

---

## Phone Wi-Fi API

The desktop apps also serve the phones (iPhone, Android, watches through them) on the local
network: advertised over Bonjour/mDNS as `_tokenbar._tcp` (random port), `GET /v1/usage` with
`Authorization: Bearer <token>`. The token is the one in the pairing link/QR code
(`tokenbar://pair?token=…`); anyone with it can read your numbers. It's meant for the TokenBar
phone apps; on the same computer, use the local API instead.

---

## Webhooks

Settings → **WEBHOOK**: paste a URL, choose the events (80%, 95%, reset) and press **TESTAR** (test).
The app `POST`s JSON (`Content-Type: application/json`, `User-Agent: TokenBar/<version>`):

```json
{
  "event": "threshold",
  "threshold": 80,
  "provider": {"id": "claude", "name": "Claude Code"},
  "window": {"id": "five_hour", "label": "5h", "usedPercent": 82, "usedNow": 82,
             "resetsAt": 1792183800, "resetsInSeconds": 4210, "windowMinutes": 300},
  "at": 1792179590,
  "text": "Claude Code 5h passou de 80% (82%). Reseta em 1:10."
}
```

| Field | Values |
|---|---|
| `event` | `threshold` (crossed 80% or 95%; once per reset cycle, only the highest), `reset` (a window that was ≥ 50% went back to 0), `test` |
| `threshold` | `80`, `95` or `null` |
| `provider` | `{id, name}` (can be `null` on `test` when there is no data) |
| `window` | the window, in the `/v1/usage` shape |
| `at` | when it was sent (Unix s) |
| `text` | a ready-made sentence in the app's language |

**Slack** (`hooks.slack.com` incoming webhook) receives `{"text": "…"}` and **Discord**
(`discord.com/api/webhooks/…`) receives `{"content": "…"}`, so you can paste those URLs as-is.

**Home Assistant** — create an automation with a webhook trigger and paste
`http://homeassistant.local:8123/api/webhook/tokenbar-usage` into TokenBar:

```yaml
alias: TokenBar usage alert
trigger:
  - platform: webhook
    webhook_id: tokenbar-usage
    allowed_methods: [POST]
    local_only: true
condition:
  - condition: template
    value_template: "{{ trigger.json.event == 'threshold' and trigger.json.threshold == 95 }}"
action:
  - service: notify.notify
    data:
      title: "{{ trigger.json.provider.name }} at {{ trigger.json.window.usedNow }}%"
      message: "{{ trigger.json.text }}"
  - service: light.turn_on
    target: { entity_id: light.desk }
    data: { color_name: red }
```

**Your own endpoint** (Node, no dependencies):

```js
import http from "node:http";
http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c)).on("end", () => {
    const e = JSON.parse(body);
    console.log(e.event, e.provider?.id, e.window?.label, e.window?.usedNow, e.text);
    res.end("ok");
  });
}).listen(8099);
```

---

## Writing: add any AI

TokenBar shows any AI that has a JSON file in `~/.tokenbar/providers/<id>.json` (Windows:
`%USERPROFILE%\.tokenbar\providers\`). Your script, cron job or extension writes it; every app and
device picks it up (and so do the local API, CLI, MCP server and webhooks).

```json
{
  "id": "gemini",
  "name": "Gemini CLI",
  "color": "#4285F4",
  "windows": [
    { "id": "day",   "label": "1d",  "usedPercent": 42, "resetsAt": 1792000000 },
    { "id": "month", "label": "30d", "usedPercent": 11, "resetsAt": 1794000000 }
  ]
}
```

Required: `id` (not `claude`, `codex`, `copilot`, `windsurf`) and `windows[].usedPercent`; at most 2
windows (short first). Optional: `name`, `color`, `windows[].label`, `windows[].resetsAt` (Unix s),
`observedAt`. Write atomically (to a `.tmp`, then rename). Full reference: [providers.md](providers.md).

```sh
# e.g. from a cron job
printf '{"id":"myai","name":"My AI","windows":[{"label":"1d","usedPercent":%s}]}' "$PCT" \
  > ~/.tokenbar/providers/myai.json.tmp && mv ~/.tokenbar/providers/myai.json.tmp ~/.tokenbar/providers/myai.json
```

---

## Integrations

Ready-made clients of the local API (they fall back to `snapshot.json` and the files, like the CLI):

- **VS Code**: status bar extension, source in [`vscode/`](../vscode), on the [Marketplace](https://marketplace.visualstudio.com/items?itemName=chaconlucas.tokenbar).
- **Raycast**: menu bar command (`CL 28% · CX 0%`, refreshed every minute) and a list with details and copy actions. Source in [`raycast/`](../raycast). To install it, put Raycast on the Mac, then run `cd raycast && npm install && npm run dev`.
- **Elgato Stream Deck** (Mac and Windows): "AI usage" key (% of the 5h/7d limit, dot bar, countdown; press toggles 5h/7d; on a Stream Deck + dial, rotate switches AI) and "Reset countdown" key with a draining ring. Source in [`streamdeck/`](../streamdeck); `npm install && npm run pack` builds `com.chaconlucas.tokenbar.streamDeckPlugin` (double-click installs it).

---

## Security

- The local API listens on **127.0.0.1 only**, has **no auth** and sends **no CORS** headers, so web
  pages in your browser can't read it, and the `Host` check blocks DNS rebinding. Anything running
  as your user can read it, the same as reading `~/.tokenbar/` directly.
- **Don't expose it**: no port forwarding, `ngrok`, reverse proxy or `0.0.0.0` relay. To see your
  numbers away from home, use the [optional server](../README.md#optional-server-see-your-numbers-away-from-home).
- The data is only percentages, reset times and AI names: no prompts, code or tokens.
- The phone Wi-Fi API requires the pairing token; whoever has the QR code can read your numbers.
- Webhooks send the same data to the URL you set. Prefer `https://`, and treat Slack/Discord webhook
  URLs as secrets.
- The CLI and MCP server only read local files and `127.0.0.1`; they never send anything over the network.
