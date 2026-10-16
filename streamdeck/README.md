# TokenBar for Elgato Stream Deck

AI usage limits (Claude Code, Codex, Copilot, Windsurf and any AI TokenBar knows) on Stream Deck
keys, in the TokenBar LED look. Mac 12+ and Windows 10+, Stream Deck 6.5+.

| Action | Shows | Press |
|---|---|---|
| **AI usage** | `CL 5H`, the % used (red from 85%), a 12-dot bar and the time to reset | switches 5h / 7d |
| **Reset countdown** | time to reset inside a ring of dots that drains with the window | switches 5h / 7d |

On a **Stream Deck +**, put **AI usage** on a dial: rotate to switch AI, push or tap to switch 5h / 7d.
Pick the AI and the window in the action's settings (the list shows the AIs TokenBar sees now).

Data: the TokenBar app's local API (`127.0.0.1`, port in `~/.tokenbar/api.json`), else
`~/.tokenbar/snapshot.json`, else the same files the CLI reads. Refreshed every 30 s; the countdown
ticks every minute. Nothing is sent anywhere.

## Build and install

```sh
cd streamdeck
npm install
npm run build      # com.chaconlucas.tokenbar.sdPlugin/bin/plugin.js
npm run validate
npm run pack       # dist/com.chaconlucas.tokenbar.streamDeckPlugin: double-click to install
```

Development: `npx streamdeck link com.chaconlucas.tokenbar.sdPlugin` and `npm run watch`.
`npm run images` regenerates the PNG icons; `npm run preview -- <dir>` renders sample keys (SVG, and
PNG if Google Chrome is installed).

The loader in `src/data.ts` is a port of [`cli/lib/data.mjs`](../cli/lib/data.mjs): keep them in sync.
