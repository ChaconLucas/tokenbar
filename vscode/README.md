# TokenBar — AI usage limits

See how much of your **Claude Code**, **Codex** and any other AI limit you have used, right in the VS Code status bar.

Status bar: **`CL 52% · CX 0%`** (Claude 5h · Codex 5h), next to a pulse icon.

- **Status bar** — the short window (5h) by default. Click to cycle **5h → 7d → both**. Turns to the warning color when any limit reaches 85%.
- **Tooltip** — every AI, both windows, the %, when each one resets ("resets in 1h 23m") and how old the reading is.
- **TokenBar: Show details** — a dot-matrix LED display, the same look as the TokenBar apps.
- **Local only** — the extension reads files on your disk. It makes no network calls.

## Where the numbers come from

1. `~/.tokenbar/snapshot.json`, written every 30 s by the [TokenBar](https://github.com/ChaconLucas/tokenbar) desktop app (Mac, Windows, Linux).
2. Without the app, it reads the sources directly:
   - **Claude Code** — `~/.tokenbar/claude.json`, the copy of the status line JSON kept by TokenBar's `claude-tee.sh`.
   - **Codex** — the newest session logs in `~/.codex/sessions/`.
   - **Any other AI** — one JSON file per AI in `~/.tokenbar/providers/` ([format](https://github.com/ChaconLucas/tokenbar/blob/main/docs/providers.md)).

On Windows, `~` is `%USERPROFILE%`.

## Settings

| Setting | Default | |
|---|---|---|
| `tokenbar.window` | `5h` | `5h`, `7d` or `both` |
| `tokenbar.providers` | `[]` | ids to show, e.g. `["claude", "codex"]`; empty shows all |

## Português

O TokenBar mostra na barra de status do VS Code quanto você já gastou dos limites do **Claude Code**, do **Codex** e de qualquer outra IA (janelas de 5h e 7d), com o tempo até zerar. Clique para alternar entre 5h, 7d e ambas; use **TokenBar: Show details** para ver o display de LED. A extensão só lê arquivos locais — nenhuma chamada de rede — e fica em português quando o VS Code está em português.

## License

MIT
