English version: [api.md](api.md)

# Guia da API e do desenvolvedor do TokenBar

## Visão geral

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

| Quero… | Use |
|---|---|
| Ler o uso a partir de um script no mesmo computador | [API local](#api-local) ou [`tokenbar get`](#cli) |
| Mostrar o uso no prompt do shell / tmux | [`tokenbar --prompt`](#prompts-do-shell) |
| Deixar um agente de IA consultar o próprio limite | [Servidor MCP](#servidor-mcp) |
| Ler sem o app aberto | [CLI](#cli) (recorre aos arquivos) ou [`snapshot.json`](#snapshotjson) |
| Ser avisado em 80% / 95% / reset | [Webhooks](#webhooks) |
| Acrescentar outra IA ao TokenBar | [Escrever um arquivo de provedor](#escrita-acrescente-qualquer-ia) |
| Ver o uso no Raycast / VS Code / Stream Deck | [Integrações](#integraes) |

---

## API local

Servida pelo app de desktop do TokenBar (Mac, Windows, Linux) enquanto ele está aberto.

- **URL base:** `http://127.0.0.1:<port>` — normalmente `http://localhost:41777`. O app tenta primeiro a porta
  **41777** e depois a próxima livre, até a 41787. A porta real fica em `~/.tokenbar/api.json` (Windows: `%USERPROFILE%\.tokenbar\api.json`):

  ```json
  {"port": 41777, "pid": 12345, "app": "TokenBar", "version": "0.5.0", "platform": "mac"}
  ```

  `platform` é `mac`, `windows` ou `linux`. **Sem arquivo = o app não está aberto** (ele é apagado ao sair).
  Se o app travou, o arquivo pode ficar para trás: quando o `pid` dele não estiver vivo, considere o app
  fechado e recorra ao [`snapshot.json`](#snapshotjson).
- **Receita do cliente:** leia a porta do `api.json` (padrão 41777) → pule se o `pid` estiver morto →
  `GET /v1/health` e confira `"app": "TokenBar"` antes de confiar na porta (outro programa pode estar nela)
  → `GET /v1/usage`. Use um timeout curto (~1,5 s).
- **Só localhost**, só `GET`, sem autenticação, sem cabeçalhos CORS. O cabeçalho `Host` precisa ser
  `127.0.0.1:<port>` ou `localhost:<port>` (qualquer outro recebe `403`), o que bloqueia ataques de
  DNS rebinding vindos de páginas web.
- Os erros são JSON: `{"error": "not_found"}` (404), `forbidden` (403), `method_not_allowed` (405), `bad_request` (400).

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

| Campo | Tipo | Significado |
|---|---|---|
| `updatedAt` | number | quando o app leu as fontes pela última vez (segundos Unix) |
| `providers[].id` | string | `claude`, `codex`, `copilot`, `windsurf` ou o id de um [arquivo de provedor](#escrita-acrescente-qualquer-ia) |
| `providers[].name` | string | nome exibido |
| `providers[].color` | string \| null | `#RRGGBB` |
| `providers[].observedAt` | number \| null | quando o número desta IA foi observado pela última vez (Unix s). O Claude só atualiza enquanto há uma sessão do Claude Code rodando, então esse valor pode estar antigo |
| `windows[].id` | string | id da janela (`five_hour`, `seven_day`, `primary`, `secondary` ou o do arquivo de provedor) |
| `windows[].label` | string | rótulo curto: `5h`, `7d`, `1d`, `30d`, `1M`… A primeira janela é a curta, a segunda é a longa |
| `windows[].usedPercent` | number | último % observado (pode passar de 100) |
| `windows[].usedNow` | number | **use este**: `usedPercent`, ou `0` depois que `resetsAt` passou |
| `windows[].resetsAt` | number \| null | quando a janela zera (Unix s) |
| `windows[].resetsInSeconds` | number \| null | segundos até `resetsAt` (`0` se já passou) |
| `windows[].windowMinutes` | number \| null | duração da janela (300 = 5 h, 10080 = 7 d) |

### `GET /v1/usage/{id}`

Um objeto de provedor (no mesmo formato de um item de `providers`), ou `404 {"error":"not_found"}`.

---

## CLI

O `tokenbar` funciona com ou sem o app: ele lê a **API local** (porta do `api.json`,
padrão 41777, timeout de 1,5 s), depois o **`~/.tokenbar/snapshot.json`** (se tiver menos de 10 min) e, por fim, as
**fontes diretamente** (`~/.tokenbar/claude.json`, o log de sessão mais recente do Codex,
`~/.tokenbar/providers/*.json`). Node.js 18+, zero dependências.

```sh
# Mac / Linux
curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.sh | sh
# Windows (PowerShell)
irm https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.ps1 | iex
```

O instalador coloca os arquivos em `~/.tokenbar/cli/`, os comandos `tokenbar` e `tokenbar-mcp` em
`~/.local/bin/` (Windows: `tokenbar.cmd` em `%USERPROFILE%\.tokenbar\bin\`) e oferece registrar
o servidor MCP no Claude Code. A partir de um clone do repositório, você também pode rodar `node cli/tokenbar.mjs`.

| Comando | Saída |
|---|---|
| `tokenbar` | uma linha por IA: barras coloridas de 10 pontos para 5h e 7d, %, tempo até o reset |
| `tokenbar --json` | o formato do `/v1/usage`, mais `"source"`: `api`, `snapshot`, `direct`, `stale-snapshot` ou `none` |
| `tokenbar --prompt` | `CL 13% CX 0%` (primeira janela; `--window 7d` para a longa; cores só com `--color`) |
| `tokenbar get <id> [5h\|7d] [--field F]` | um número. `F`: `usedNow` (padrão), `usedPercent`, `resetsInSeconds`, `resetsAt`, `windowMinutes` |
| `tokenbar watch [--interval 5]` | tela cheia atualizada a cada 5 s |
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

`<id>` também aceita o código de 2 letras (`CL`, `CX`) ou o nome. `5h`/`7d` significam "primeira/segunda
janela", então funcionam também para IAs cujas janelas são `1d`/`30d`. As cores seguem o
[NO_COLOR](https://no-color.org) e ficam desligadas quando a saída não é um terminal (`--color` força as cores).
Códigos de saída: `0` ok, `1` erro de uso ou campo vazio (por exemplo, sem horário de reset), `2` sem dados / IA ou janela desconhecida.

---

## Servidor MCP

O `tokenbar-mcp` (`cli/mcp.mjs`) é um servidor [Model Context Protocol](https://modelcontextprotocol.io)
via **stdio** (protocolo `2025-06-18`), para que agentes de IA consultem os próprios limites. Usa o mesmo carregador de dados da CLI.

| Ferramenta | Argumentos | Retorna |
|---|---|---|
| `get_usage` | `provider?` | resumo em texto + `structuredContent` no formato do `/v1/usage` (ou de um provedor) |
| `time_until_reset` | `provider`, `window?` (`5h`\|`7d`, padrão a primeira) | `{provider, window, seconds, resetsAt, human, usedNow}` |
| `check_budget` | `provider`, `max_percent?` (padrão 80), `window?` | `{ok, usedNow, resetsInSeconds, resetsAt, advice, window, windows[]…}`. Sem `window`, verifica a mais usada |

### Claude Code

```sh
claude mcp add tokenbar --scope user -- node ~/.tokenbar/cli/mcp.mjs
```

(o instalador faz isso por você; confira com `claude mcp get tokenbar`).

### Codex (`~/.codex/config.toml`)

```toml
[mcp_servers.tokenbar]
command = "node"
args = ["/Users/you/.tokenbar/cli/mcp.mjs"]
```

### Cursor (`~/.cursor/mcp.json`) e VS Code (`.vscode/mcp.json`)

```json
{ "mcpServers": { "tokenbar": { "command": "node", "args": ["/Users/you/.tokenbar/cli/mcp.mjs"] } } }
```

O VS Code usa `"servers"` no lugar de `"mcpServers"`. Use o caminho absoluto (sem `~`). Windows:
`"C:\\Users\\you\\.tokenbar\\cli\\mcp.mjs"`. Instalou pelo npm? Use `"command": "tokenbar-mcp"`, sem args.

### Exemplo de prompt para o agente

Coloque isto no `CLAUDE.md`, no `AGENTS.md` ou no system prompt do seu agente:

```text
Before starting a long task (big refactor, many files, long test loops), call the tokenbar
check_budget tool with provider "claude" (use "codex" if you are Codex). If ok is false,
stop and tell me the usage and when it resets (resetsInSeconds), and propose either waiting
or a smaller first step. If ok is true but usedNow is above 60, prefer the cheaper plan.
```

Uma sessão fica assim:

```text
→ check_budget {"provider":"claude"}
← OK: Claude Code 7d window is at 43% (budget 80%, 37 points left). Fine to proceed; …
```

---

## Prompts do shell

O `tokenbar --prompt` lê a API local (≈ 70 ms). Sem o app, ele lê os arquivos, e continua rápido.

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

**Script**, por exemplo para esperar o Claude ficar abaixo de 50% antes de um job em lote:

```sh
while [ "$(tokenbar get claude 5h)" -ge 50 ]; do sleep 300; done
```

---

## Exemplos de código

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

### Python (biblioteca padrão)

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

O `~/.tokenbar/snapshot.json` (Windows: `%USERPROFILE%\.tokenbar\snapshot.json`) é gravado pelos
apps de desktop a cada 30 s, de forma atômica. Traz os mesmos provedores do `/v1/usage`, mas as janelas têm só
`id`, `label`, `usedPercent`, `resetsAt`, `windowMinutes`, então calcule o resto você mesmo:

```
usedNow         = (resetsAt != null && resetsAt <= now) ? 0 : usedPercent
resetsInSeconds = resetsAt == null ? null : max(0, resetsAt - now)
```

Considere-o desatualizado quando o `updatedAt` tiver mais de ~10 minutos (o app está fechado). A extensão
do VS Code e a CLI leem este arquivo.

---

## API do Wi-Fi para os celulares

Os apps de desktop também servem os celulares (iPhone, Android e, por meio deles, os relógios) na rede
local: anunciados por Bonjour/mDNS como `_tokenbar._tcp` (porta aleatória), `GET /v1/usage` com
`Authorization: Bearer <token>`. O token é o do link/QR code de pareamento
(`tokenbar://pair?token=…`); quem tiver esse token consegue ler os seus números. Ela foi feita para os apps de
celular do TokenBar; no mesmo computador, use a API local.

---

## Webhooks

Ajustes → **WEBHOOK**: cole uma URL, escolha os eventos (80%, 95%, reset) e toque em **TESTAR**.
O app faz `POST` de um JSON (`Content-Type: application/json`, `User-Agent: TokenBar/<version>`):

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

| Campo | Valores |
|---|---|
| `event` | `threshold` (passou de 80% ou 95%; uma vez por ciclo de reset, só o mais alto), `reset` (uma janela que estava em ≥ 50% voltou a 0), `test` |
| `threshold` | `80`, `95` ou `null` |
| `provider` | `{id, name}` (pode ser `null` no `test` quando não há dados) |
| `window` | a janela, no formato do `/v1/usage` |
| `at` | quando foi enviado (Unix s) |
| `text` | uma frase pronta no idioma do app |

**Slack** (incoming webhook do `hooks.slack.com`) recebe `{"text": "…"}` e o **Discord**
(`discord.com/api/webhooks/…`) recebe `{"content": "…"}`, então você pode colar essas URLs do jeito que estão.

**Home Assistant** — crie uma automação com um gatilho de webhook e cole
`http://homeassistant.local:8123/api/webhook/tokenbar-usage` no TokenBar:

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

**Seu próprio endpoint** (Node, sem dependências):

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

## Escrita: acrescente qualquer IA

O TokenBar mostra qualquer IA que tenha um arquivo JSON em `~/.tokenbar/providers/<id>.json` (Windows:
`%USERPROFILE%\.tokenbar\providers\`). Quem grava é o seu script, cron ou extensão; todos os apps e
aparelhos pegam o arquivo (e também a API local, a CLI, o servidor MCP e os webhooks).

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

Obrigatórios: `id` (não pode ser `claude`, `codex`, `copilot`, `windsurf`) e `windows[].usedPercent`; no máximo 2
janelas (a curta primeiro). Opcionais: `name`, `color`, `windows[].label`, `windows[].resetsAt` (Unix s),
`observedAt`. Grave de forma atômica (num `.tmp` e depois renomeie). Referência completa: [providers.md](providers.md).

```sh
# e.g. from a cron job
printf '{"id":"myai","name":"My AI","windows":[{"label":"1d","usedPercent":%s}]}' "$PCT" \
  > ~/.tokenbar/providers/myai.json.tmp && mv ~/.tokenbar/providers/myai.json.tmp ~/.tokenbar/providers/myai.json
```

---

## Integrações

Clientes prontos da API local (eles recorrem ao `snapshot.json` e aos arquivos, como a CLI):

- **VS Code**: extensão da barra de status, código em [`vscode/`](../vscode), no [Marketplace](https://marketplace.visualstudio.com/items?itemName=chaconlucas.tokenbar).
- **Raycast**: comando na barra de menus (`CL 28% · CX 0%`, atualizado a cada minuto) e uma lista com detalhes e ações de copiar. Código em [`raycast/`](../raycast). Para instalar, tenha o Raycast no Mac e rode `cd raycast && npm install && npm run dev`.
- **Elgato Stream Deck** (Mac e Windows): tecla "AI usage" (% do limite de 5h/7d, barra de pontos, contagem regressiva; apertar alterna 5h/7d; no dial do Stream Deck +, girar troca de IA) e tecla "Reset countdown" com um anel que vai esvaziando. Código em [`streamdeck/`](../streamdeck); `npm install && npm run pack` gera o `com.chaconlucas.tokenbar.streamDeckPlugin` (dois cliques instalam).

---

## Segurança

- A API local escuta **só em 127.0.0.1**, **não tem autenticação** e **não envia** cabeçalhos **CORS**, então
  páginas web no seu navegador não conseguem lê-la, e a checagem do `Host` bloqueia DNS rebinding. Qualquer coisa rodando
  com o seu usuário consegue lê-la, assim como consegue ler `~/.tokenbar/` diretamente.
- **Não a exponha**: nada de redirecionamento de porta, `ngrok`, proxy reverso ou relay em `0.0.0.0`. Para ver os seus
  números longe de casa, use o [servidor opcional](../README.md#optional-server-see-your-numbers-away-from-home).
- Os dados são só porcentagens, horários de reset e nomes de IAs: nada de prompts, código ou tokens.
- A API do Wi-Fi dos celulares exige o token de pareamento; quem tiver o QR code consegue ler os seus números.
- Os webhooks enviam os mesmos dados para a URL que você definir. Prefira `https://` e trate as URLs de webhook
  do Slack/Discord como segredos.
- A CLI e o servidor MCP só leem arquivos locais e `127.0.0.1`; nunca enviam nada pela rede.
