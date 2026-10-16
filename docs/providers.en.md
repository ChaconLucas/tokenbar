Versão em português: [providers.md](providers.md)

# Add another AI to TokenBar

## Already built in

TokenBar reads these on its own, on Mac and on Windows/Linux. Nothing leaves the computer, except where noted.

| AI | How to turn it on | Where the number comes from |
|---|---|---|
| **Claude Code** | Settings → AIs → Connect | copy of the statusline JSON in `~/.tokenbar/claude.json` (5h and 7d windows). Optional: "VS Code panel" reads it from the Anthropic API with the login Claude Code saved |
| **Codex** | automatic | latest `rate_limits` from the files in `~/.codex/sessions/YYYY/MM/DD/*.jsonl` |
| **GitHub Copilot** | **optional, off by default** (Settings → AIs → GitHub Copilot) | `GET https://api.github.com/copilot_internal/user` with the token from `gh auth token` (or the `oauth_token` from `~/.config/github-copilot/apps.json`; on Windows `%LOCALAPPDATA%\github-copilot\apps.json`). Shows the monthly premium requests quota (on the free plan, the chat one), `1M`, resetting at `quota_reset_date_utc`. At most 1 call every 5 min; the token only goes to GitHub. Accounts without a limit don't show up |
| **Windsurf** | automatic, no network | `windsurf.settings.cachedPlanInfo` key from the editor's `state.vscdb` database, opened read-only: `~/Library/Application Support/Windsurf/User/globalStorage/` (Mac), `%APPDATA%\Windsurf\User\globalStorage\` (Windows), `~/.config/Windsurf/User/globalStorage/` (Linux). `1d` and `7d` windows (`quotaUsage`); on older plans, messages for the month (`1M`) |
| **Cursor** | **optional** (Settings → AIs → Cursor) | token `cursorAuth/accessToken` from Cursor's `state.vscdb` (same folders as Windsurf, with `Cursor` instead of `Windsurf`), read-only. `GET https://cursor.com/api/usage-summary` with the cookie `WorkosCursorSessionToken=<id>%3A%3A<token>`. Shows the plan's `totalPercentUsed`, `1M`, resetting at `billingCycleEnd`. The token only goes to cursor.com |
| **Gemini CLI** | **optional** (Settings → AIs → Gemini CLI) | Gemini CLI login in `~/.gemini/oauth_creds.json` (TokenBar doesn't refresh the token: it uses it while the CLI keeps it valid). `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` and `:retrieveUserQuota`. Daily quota of the Pro (`PRO`) and Flash (`FL`) models. **Workspace and Code Assist accounts only**: since 2026-06-18 Google doesn't expose it to personal accounts |
| **Kiro** | **optional** (Settings → AIs → Kiro) | `kiro-cli` token and profile (`data.sqlite3`, tables `auth_kv` and `state`, read-only) in `~/Library/Application Support/kiro-cli/` (Mac), `~/.local/share/kiro-cli/` (Linux). AWS `GetUsageLimits` in the profile's region. The plan's monthly credits (without overage), `1M` |
| **Amp** | key in Settings (empty = Amp CLI login in `~/.local/share/amp/secrets.json`) | `POST https://ampcode.com/api/internal?userDisplayBalanceInfo` (the same text as `amp usage`). Paid plan (`1M`) and Amp Free (`1d`, resets at 8 PM New York time) |
| **GLM (Z.ai)** | API key in Settings | `GET https://api.z.ai/api/monitor/usage/quota/limit` (China keys: `open.bigmodel.cn`). Coding Plan 5-hour and weekly windows |
| **MiniMax** | Coding Plan key in Settings | `GET https://api.minimax.io/v1/token_plan/remains` (China: `api.minimaxi.com`). Current window and week |
| **Kimi Code** | API key in Settings | `GET https://api.kimi.com/coding/v1/usages` (or `api.kimi.ai`). 5-hour and weekly windows |
| **OpenRouter** | API key in Settings | `GET https://openrouter.ai/api/v1/key`: how much of the key's limit is spent; key without a limit → `/api/v1/credits` (credits used, `$`) |
| **Factory Droid** | API key in Settings (empty = `FACTORY_API_KEY` from `~/.factory/.env`) | `GET https://api.factory.ai/api/billing/limits`. 5-hour and weekly windows |

Network reads: at most 1 call every 5 min per AI, and the key only goes to that AI's own site. On Mac the keys live in the Keychain; on Windows/Linux in `~/.tokenbar/connectors.json` (on Linux, readable only by your user). Endpoints and formats checked against the open-source [CodexBar](https://github.com/steipete/CodexBar).

The ids `claude`, `codex`, `copilot` and `windsurf` are reserved: a file in `providers/` using them is ignored. A file with the id of a connected AI above (`cursor`, `gemini`, `kiro`, `zai`, `minimax`, `kimi`, `openrouter`, `factory`, `amp`) is ignored while that AI is turned on.

## Any other AI

TokenBar shows **any AI** that has a JSON file in `~/.tokenbar/providers/`
(on Windows: `%USERPROFILE%\.tokenbar\providers\`). One file per AI. Whatever writes the file
can be your own script, an extension, a cron job — TokenBar only reads it.

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

| Field | Required | What it is |
|---|---|---|
| `id` | yes | short identifier, no spaces (`claude`, `codex`, `copilot` and `windsurf` are reserved) |
| `name` | no | display name (keys use the first 2 letters when there are 3+ AIs) |
| `color` | no | `#RRGGBB` color; without it, the app picks a fixed one from the `id` |
| `windows` | yes | up to 2 limit windows (the first is the "short" one, the second the "long" one) |
| `windows[].usedPercent` | yes | 0–100 (can go over 100) |
| `windows[].label` | no | short text: `5h`, `1d`, `7d`, `30d`… |
| `windows[].resetsAt` | no | when the window resets, in seconds since 1970 (Unix) |
| `observedAt` | no | when the number was read; without it, the file's date is used |

The new AI shows up on the Mac, on Windows/Linux, on iPhone, Apple Watch, Android and Wear OS,
in the widgets and in Control Center, already turned on. To hide it, tap its key on the device.

**Tip:** write the file atomically (write to a `.tmp` and rename it), so TokenBar
never reads a half-written JSON.
