# TokenBar

See how much of your AI usage limits you have left without leaving Raycast. It covers Claude Code, Codex, Copilot, Windsurf and any other AI that [TokenBar](https://github.com/ChaconLucas/tokenbar) knows about.

## Commands

- **AI Usage in Menu Bar**: puts a short title like `CL 28% · CX 0%` in the menu bar. The ring icon fills with the highest usage and turns orange at 80% and red at 95%. The menu lists the 5h and 7d windows of each AI and the time left until each reset. It also has **Open TokenBar** and **Refresh**. It refreshes every minute.
- **Show AI Usage**: lists one row per AI, for example `Claude Code — 5h 28% · 7d 39%`, with colored tags and a reset countdown. Press `⌘D` for the detail panel, which shows each window as a bar (`●●●○○○○○○○`), the reset time and when the data was last read. Actions: Copy Summary, Copy as JSON, Open TokenBar, Open API Docs.

## Preferences

| Preference | What it does |
|---|---|
| Menu Bar Window | Which window appears in the menu bar title: `5h`, `7d` or both (`CL 28/39%`). |
| AIs | Comma-separated ids of the AIs to show, for example `claude, codex`. Leave it empty to show all of them. |

## Requirements

Install and run the [TokenBar app](https://github.com/ChaconLucas/tokenbar#install) for macOS. The extension reads only local data and sends nothing over the network:

1. First, the app's local API at `http://127.0.0.1:<port>/v1/usage`. The port comes from `~/.tokenbar/api.json`, and the extension trusts that port only when `/v1/health` answers `"app":"TokenBar"`.
2. If the API doesn't answer, `~/.tokenbar/snapshot.json`, which the app writes every 30 seconds.
3. If the app isn't running, it reads the same files the app reads (`~/.tokenbar/claude.json`, the Codex session logs and `~/.tokenbar/providers/*.json`).

To add any other AI, see [providers.md](https://github.com/ChaconLucas/tokenbar/blob/main/docs/providers.md). The data format is documented in [api.md](https://github.com/ChaconLucas/tokenbar/blob/main/docs/api.md).
