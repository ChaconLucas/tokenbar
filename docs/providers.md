# Acrescentar outra IA ao TokenBar

## Já embutidas (built-in)

Estas o TokenBar lê sozinho, no Mac e no Windows/Linux. Nada sai do computador, exceto onde dito.

| IA | Como liga | De onde vem o número |
|---|---|---|
| **Claude Code** | Ajustes → IAs → Conectar | cópia do JSON da statusline em `~/.tokenbar/claude.json` (janelas 5h e 7d). Opcional: "Painel do VS Code" lê pela API da Anthropic com o login que o Claude Code guardou |
| **Codex** | automático | último `rate_limits` dos arquivos em `~/.codex/sessions/AAAA/MM/DD/*.jsonl` |
| **GitHub Copilot** | **opcional, desligado por padrão** (Ajustes → IAs → GitHub Copilot) | `GET https://api.github.com/copilot_internal/user` com o token de `gh auth token` (ou o `oauth_token` de `~/.config/github-copilot/apps.json`; no Windows `%LOCALAPPDATA%\github-copilot\apps.json`). Mostra a cota mensal de premium requests (no plano grátis, a de chat), `1M`, zerando em `quota_reset_date_utc`. No máximo 1 chamada a cada 5 min; o token só vai para o GitHub. Conta sem limite não aparece |
| **Windsurf** | automático, sem rede | chave `windsurf.settings.cachedPlanInfo` do banco `state.vscdb` do editor, aberto só para leitura: `~/Library/Application Support/Windsurf/User/globalStorage/` (Mac), `%APPDATA%\Windsurf\User\globalStorage\` (Windows), `~/.config/Windsurf/User/globalStorage/` (Linux). Janelas `1d` e `7d` (`quotaUsage`); planos antigos, mensagens do mês (`1M`) |
| **Cursor** | **opcional** (Ajustes → IAs → Cursor) | token `cursorAuth/accessToken` do `state.vscdb` do Cursor (mesmas pastas do Windsurf, trocando `Windsurf` por `Cursor`), só leitura. `GET https://cursor.com/api/usage-summary` com o cookie `WorkosCursorSessionToken=<id>%3A%3A<token>`. Mostra `totalPercentUsed` do plano, `1M`, zerando em `billingCycleEnd`. O token só vai para cursor.com |
| **GLM (Z.ai)** | chave de API nos Ajustes | `GET https://api.z.ai/api/monitor/usage/quota/limit` (chave da China: `open.bigmodel.cn`). Janelas de 5h e da semana do Coding Plan |
| **MiniMax** | chave do Coding Plan nos Ajustes | `GET https://api.minimax.io/v1/token_plan/remains` (China: `api.minimaxi.com`). Janela atual e semana |
| **Kimi Code** | chave de API nos Ajustes | `GET https://api.kimi.com/coding/v1/usages` (ou `api.kimi.ai`). Janelas de 5h e da semana |
| **OpenRouter** | chave de API nos Ajustes | `GET https://openrouter.ai/api/v1/key`: quanto do limite da chave já foi gasto; chave sem limite → `/api/v1/credits` (créditos usados, `$`) |
| **Factory Droid** | chave de API nos Ajustes (vazio = `FACTORY_API_KEY` de `~/.factory/.env`) | `GET https://api.factory.ai/api/billing/limits`. Janelas de 5h e da semana |

Leituras pela rede: no máximo 1 chamada a cada 5 min por IA, e a chave só vai para o site da própria IA. No Mac as chaves ficam no Keychain; no Windows/Linux, em `~/.tokenbar/connectors.json` (no Linux, só o seu usuário lê). Endereços e formatos conferidos no código aberto do [CodexBar](https://github.com/steipete/CodexBar).

Os ids `claude`, `codex`, `copilot` e `windsurf` são reservados: um arquivo em `providers/` com eles é ignorado. Um arquivo com o id de uma IA ligada acima (`cursor`, `zai`, `minimax`, `kimi`, `openrouter`, `factory`) fica de fora enquanto ela estiver ligada.

## Qualquer outra IA

O TokenBar mostra **qualquer IA** que tenha um arquivo JSON em `~/.tokenbar/providers/`
(no Windows: `%USERPROFILE%\.tokenbar\providers\`). Um arquivo por IA. Quem escreve o arquivo
pode ser um script seu, uma extensão, um cron — o TokenBar só lê.

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

| Campo | Obrigatório | O que é |
|---|---|---|
| `id` | sim | identificador curto, sem espaços (`claude`, `codex`, `copilot` e `windsurf` são reservados) |
| `name` | não | nome mostrado (as teclas usam as 2 primeiras letras quando há 3+ IAs) |
| `color` | não | cor `#RRGGBB`; sem ela, o app escolhe uma fixa pela `id` |
| `windows` | sim | até 2 janelas de limite (a primeira é a "curta", a segunda a "longa") |
| `windows[].usedPercent` | sim | 0–100 (pode passar de 100) |
| `windows[].label` | não | texto curto: `5h`, `1d`, `7d`, `30d`… |
| `windows[].resetsAt` | não | quando a janela zera, em segundos desde 1970 (Unix) |
| `observedAt` | não | quando o número foi lido; sem ele, vale a data do arquivo |

A IA nova aparece no Mac, no Windows/Linux, no iPhone, no Apple Watch, no Android e no Wear OS,
nos widgets e na Central de Controle, já ligada. Para esconder, toque na tecla dela no aparelho.

**Dica:** escreva o arquivo de forma atômica (grave num `.tmp` e renomeie), para o TokenBar
nunca ler um JSON pela metade.
