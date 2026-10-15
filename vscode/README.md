# TokenBar — AI usage limits

See how much of your **Claude Code**, **Codex** and any other AI limit you have used, right in the VS Code status bar.

Status bar: one item per AI, each in its own color — **`CL ●●●○○○○○○○ 28% · 4:12`** (Claude: 28% of the 5h limit used, resets in 4h 12m), then **`CX ○○○○○○○○○○ 0% · 2:05`** for Codex, and so on.

- **Status bar** — a 10-dot meter per AI (lit dots = used), the % and the time left until it resets. The short window (5h) by default; click to cycle **5h → 7d → both** (both shows two 5-dot meters: `CL ●○○○○ 28 · ●●○○○ 39`). An item turns to the warning color at 85% and to the error color at 95%. Prefer the old one-line text? Set `tokenbar.statusStyle` to `compact` (`CL 28% · CX 0%`).
- **Tooltip** — every AI, both windows, the %, when each one resets ("resets in 1h 23m") and how old the reading is.
- **TokenBar in the Activity Bar** — a ring-of-dots icon opens the **Usage** view: the dot-matrix LED device of the TokenBar apps, always on. For each AI a black panel fills up with the % in the AI's color (red from 85%), with the time left to reset on the right; the countdown keeps ticking. The keys on top show / hide each AI and switch 5H / 7D / both (shared with the status bar). It fits a narrow sidebar and a wide bottom panel — drag the view wherever you like. **TokenBar: Show details** opens it.
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
| `tokenbar.statusStyle` | `dots` | `dots` (one colored item per AI, with meter and countdown) or `compact` (`CL 28% · CX 0%`) |
| `tokenbar.providers` | `[]` | ids to show, e.g. `["claude", "codex"]`; empty shows all |

## Português

O TokenBar mostra na barra de status do VS Code quanto você já gastou dos limites do **Claude Code**, do **Codex** e de qualquer outra IA (janelas de 5h e 7d), com o tempo até zerar. Cada IA tem o seu item, na cor dela, com um medidor de 10 pontos, a % e o tempo até zerar (`CL ●●●○○○○○○○ 28% · 4:12`); clique para alternar entre 5h, 7d e ambas (`tokenbar.statusStyle: compact` volta ao texto antigo). O ícone do TokenBar na Activity Bar abre a view **Uso**: o display de LED do aparelho, sempre aceso, com as teclas para mostrar/esconder cada IA e trocar 5H/7D — cabe na barra lateral estreita e no painel de baixo. A extensão só lê arquivos locais — nenhuma chamada de rede — e fica em português quando o VS Code está em português.

## License

MIT
