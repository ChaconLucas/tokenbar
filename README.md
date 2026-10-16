<p align="center"><img src="docs/icon.png" width="128" alt="TokenBar icon"></p>

<h1 align="center">TokenBar</h1>

<p align="center">
How much of your <b>Claude Code</b>, <b>Codex</b> (or any AI) usage limits you have used, and when they reset,<br>
on an LED display on Mac, Windows, Linux, iPhone, Android, Apple Watch and Wear OS.
</p>

<p align="center"><img src="docs/iphone-5h.jpg" width="720" alt="TokenBar on a landscape iPhone"></p>

**English** · [Português](README.pt-BR.md)

> The app's interface is in Portuguese. Button and menu names below are quoted as they appear in the app, with a translation where it helps.

---

## Install

**Mac** (macOS 15+), one command in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-mac.sh | sh
```

<details>
<summary><b>Mac blocked it ("can't be opened", "unidentified developer", "is damaged")?</b></summary>

TokenBar isn't notarized by Apple yet (that needs a paid developer account), so macOS blocks the first launch when the app comes **from a browser**. Any of these fixes it:

1. **Install with the command above.** Downloaded from Terminal, the warning doesn't appear.
2. **Allow it once:** try to open TokenBar → **System Settings → Privacy & Security** → scroll down → **Open Anyway** → your Mac password.
3. **"Is damaged"?** In Terminal: `xattr -dr com.apple.quarantine /Applications/TokenBar.app` and open it again.

The prompt *"TokenBar wants to use confidential information stored in Claude Code-credentials"* isn't a block: it's the login reading (VS Code panel). Choose **Always Allow**.
</details>

**Or ask your AI.** Open Claude Code, Codex or any AI with a terminal and say:

> Read https://github.com/ChaconLucas/tokenbar/blob/main/INSTALL.md and install TokenBar for me.

[`INSTALL.md`](INSTALL.md) is written for the AI: it asks which devices you have, runs the commands, and only asks for your hands when needed (a permission, the phone, the watch).

| Device | How |
|---|---|
| **Mac** | the command above |
| **Windows** | `TokenBar-Windows-setup.exe` in [Releases](https://github.com/ChaconLucas/tokenbar/releases). If SmartScreen warns, **More info → Run anyway** |
| **Linux** | build from source for now (see `INSTALL.md`) |
| **Mac (Homebrew)** | `brew install --cask chaconlucas/tokenbar/tokenbar` |
| **Windows (winget)** | `winget install ChaconLucas.TokenBar` (pending Microsoft review) |
| **VS Code** | usage in VS Code's status bar: search **TokenBar** in Extensions ([Marketplace](https://marketplace.visualstudio.com/items?itemName=chaconlucas.tokenbar)) |
| **Raycast** | usage in the Mac menu bar and a Raycast command: with [Raycast](https://raycast.com) installed, run `cd raycast && npm install && npm run dev` (see [`raycast/README.md`](raycast/README.md)) |
| **Stream Deck** | AI usage and reset countdown keys (and Stream Deck + dials) in the LED look: download `TokenBar-StreamDeck.streamDeckPlugin` from [Releases](https://github.com/ChaconLucas/tokenbar/releases) and double-click it (works with the virtual Stream Deck, no hardware needed) |
| **Android** | `TokenBar-Android.apk` in [Releases](https://github.com/ChaconLucas/tokenbar/releases) |
| **Wear OS** | `TokenBar-WearOS.apk` in Releases, installed with `adb` |
| **iPhone** | on a Mac with Xcode (free) and the iPhone plugged in: `curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-ios.sh | sh`. Run it again to update and renew the free Apple account's 7 days |

**Updates:** from 0.3.0 on, Mac, Windows and Android show an **Atualizar** (update) button when a new version is out. One click. iPhone, Apple Watch and Wear OS update by installing again.

**The computer collects the numbers.** Phones and watches only show what it sends over Wi-Fi, so always start there.

---

## What it does

- **Mac:** an LED "device" on screen (you can make it bigger, smaller or full screen) and, in the menu bar, small colored LED dot bars, one per AI, with the %. Clicking them opens a summary with the device and glass buttons (*liquid glass* on macOS 26): Aparelho (device), Mini, Ajustes (settings), refresh and quit.
- **Mini (Mac):** the device in a small floating panel (NSPanel) that stays on top of everything, including full-screen apps, and on every Space. It can be resized while keeping its aspect ratio; position and size are remembered. Open it from the **Mini** button in the menu bar, the device's pop-out key (the small window icon on the right), or the Control Center control. To close it, use the **×** that appears on hover, or right-click → Fechar Mini.
- **Control Center (macOS 26 / iOS 18):** controls **TokenBar** (all AIs), **Claude**, **Codex**, **TokenBar flutuante** (floating) and **TokenBar aparelho** (device). The icon is a ring of 12 LED dots that lights up with your usage; when enlarged, the control shows two lines (the % on top, time to reset below). Apple only allows an icon plus 2 lines of text, and every new control starts small: enlarge it once to see the lines.
- **Windows and Linux:** the same LED device, the floating mini and a dot ring in the system tray (app in [`desktop/`](desktop), built with Tauri).
- **iPhone:** opens in landscape, full screen, with the screen always on, to use as a desk clock. Widgets on the Home Screen and Lock Screen.
- **Apple Watch:** an app and watch-face complications (circular, corner and inline). In the app, the **TODOS / CLAUDE / CODEX** key (or turning the Digital Crown) shows all AIs or just one (with its 5H and 7D), and **5H / 7D** switches the window. Colors follow the iPhone's. With the optional server, the watch fetches the numbers by itself, without the iPhone nearby.
- **Any AI:** Claude Code and Codex out of the box (terminal, VS Code or the Codex app); any other AI through a small JSON file ([docs/providers.md](docs/providers.md)). Choose which ones to show and swipe sideways to switch.
- **Windows:** 5 hours, 7 days, or both on the same screen.
- **Customization:** color for each AI, for the text and for the time, round or square dots, brightness, and red near the limit.
- **The background fills with usage:** 23% lights up 23% of the display.
- **Alerts:** a notification (on the iPhone, mirrored to the watch) when a window passes **80%** and **95%**, and when it **resets**. The iPhone refreshes in the background so it can alert you even with the app closed (iOS decides how often, usually every 15–60 min).
- **Widgets:** four presets in the gallery — **Todas · 5h e 7d** (all, 5h and 7d), **Todas · 5h** (all, 5h), **Claude · 5h e 7d**, **Codex · 5h e 7d** — plus **Personalizado** (custom; long-press → Edit): pick **Todas / Claude / Codex / Uma por vez** (all / Claude / Codex / one at a time) and **5h / 7d / As duas** (both). In "Uma por vez", tapping the widget switches AI without opening the app (iPhone and Mac). On the iPhone, stack widgets (drag one onto another) and swipe between them. Small, medium and large on Mac and iPhone; Lock Screen and watch face (rectangular, circular, corner and inline). On the watch, the combinations appear ready-made in the complication list.

<p align="center">
<img src="docs/iphone-5h-7d.jpg" width="49%" alt="5H and 7D together">
<img src="docs/mac.png" width="49%" alt="TokenBar on the Mac">
</p>
<p align="center"><img src="docs/widgets.png" width="640" alt="Widgets in every size"></p>
<p align="center"><img src="docs/watch.jpg" width="420" alt="TokenBar on Apple Watch: all AIs and a single AI"></p>

## Android and Wear OS

For people with a **Mac + Android phone + Wear OS watch** (Galaxy Watch, Pixel Watch and others). The app lives in [`android/`](android).

<p align="center">
<img src="docs/android.jpg" width="62%" alt="TokenBar on Android">
<img src="docs/wearos.jpg" width="30%" alt="TokenBar on Wear OS">
</p>

- **Phone:** opens in landscape, full screen, with the screen always on. CLAUDE/CODEX and 5H/7D/5H 7D keys; swipe to switch AI. Home-screen widget (wide = 5h and 7d for all AIs). Alerts at 80%, 95% and reset, with background refresh.
- **Watch:** works **with or without a phone**. With a phone, it gets the numbers from it; on its own, type on the watch the **6-digit code** the Mac shows under *Editar → Mais ajustes → RELÓGIO SEM CELULAR* (Edit → More settings → watch without phone; same Wi-Fi). The code works once and changes every 10 minutes. After that the watch fetches directly from the Mac (Wi-Fi) or from the server. TODOS/CLAUDE/CODEX and 5H/7D keys. Watch-face complications.
- **Pairing:** on the Mac, *Editar → Mais ajustes*; on Android, **ESCANEAR QR** (scan QR) or paste the link.
- Reads the Mac over Wi-Fi (the same Bonjour advertisement the iPhone uses) or through the optional server.

### Download

The [**Releases**](https://github.com/ChaconLucas/tokenbar/releases) page has `TokenBar-Android.apk` (phone) and `TokenBar-WearOS.apk` (watch). On the phone, open the `.apk` and allow "install unknown apps"; if Play Protect warns you, tap **Install anyway**. On the watch, install with `adb` (Settings → Developer options → Wireless debugging). Publishing on the Play Store would require a Google developer account (US$25, one-time).

**Huawei:** phones with EMUI / HarmonyOS 2–4 can install the `.apk`, but without Google services the "Escanear QR" button does not work — paste the link instead. Phones with **HarmonyOS NEXT** and Huawei watches (Watch GT, Watch 4/5, Watch Fit) are not supported yet: they would need a separate app built in DevEco Studio and a Huawei developer account.

### Build

Requirements: JDK 17 and the Android SDK (`brew install openjdk@17 android-commandlinetools`).

```sh
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :app:assembleDebug :wear:assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk          # phone
adb -s <watch> install wear/build/outputs/apk/debug/wear-debug.apk   # watch (wireless debugging on)
```

## How it works

```
                    Wi-Fi (Bonjour)                    WatchConnectivity
 Mac ─────────────────────────────────────► iPhone ─────────────────────► Apple Watch
  │ reads the limits from disk                │ widgets and Lock Screen      complications
  │ Claude Code: copy of the statusline       │
  │ Codex: ~/.codex/sessions                  │
  │                                           │
  └──── PUT ────► server (optional) ◄── GET ──┘   away from home
```

1. **The Mac collects.** Claude Code only hands its limits (`rate_limits.five_hour` and `seven_day`) to the *statusline*. The app installs a small script (`~/.tokenbar/claude-tee.sh`) that saves a copy of that JSON and passes it on to the statusline you already had, without changing anything you see in the terminal. Codex writes its limits into the session files in `~/.codex/sessions`.
2. **The Mac advertises on the local network** (`_tokenbar._tcp`) and only answers clients that have the pairing key.
3. **The iPhone finds the Mac on its own** on the same Wi-Fi, reads the numbers and passes them to the watch.
4. **Optional server:** if you set one up, the Mac also sends to it, and the iPhone uses the most recent number between Wi-Fi and server. That's how it works away from home.

## Requirements

- macOS 15+ with **Xcode 26+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- iPhone with iOS 17+ and, optionally, Apple Watch with watchOS 10+
- An Apple account (the free one is enough to run on your own devices; see **Distribution**)
- Claude Code and/or Codex installed on the Mac

## Install with Xcode (iPhone and Apple Watch)

You don't need this for the Mac alone: use the command at the top.

### 1. Clone and set up signing

```sh
git clone https://github.com/ChaconLucas/tokenbar.git
cd tokenbar
```

Create `Config/Signing.local.xcconfig` (git ignores this file) with two lines:

```
DEVELOPMENT_TEAM = ABCDE12345     // Xcode → Settings → Accounts → your team → Team ID
TB_BUNDLE_PREFIX = com.yourname   // any unique prefix of your own
```

Generate the project and open it:

```sh
xcodegen generate
open TokenBar.xcodeproj
```

### 2. Mac

1. In Xcode, pick the **TokenBarMac** scheme and run (⌘R). The device appears on screen and the % appears in the menu bar.
2. Click **EDITAR → Mais ajustes… → Conectar Claude Code** (Edit → More settings → Connect Claude Code). Before changing anything, a backup is saved to `~/.claude/settings.json.tokenbar-backup`.
3. Claude's numbers appear the next time a Claude Code session updates the statusline. Codex's appear right away if you used Codex recently.

> macOS may ask whether TokenBar can **accept incoming connections**. Answer **Allow**: that's how the iPhone reads the Mac over Wi-Fi.

To keep the app in Applications, use **Product → Archive → Distribute App → Copy App** in Xcode, or copy `TokenBar.app` from the build folder to `/Applications`.

### 3. iPhone

1. Connect the iPhone and turn on **Developer Mode** (Settings → Privacy & Security).
2. Pick the **TokenBar** scheme with your iPhone as the destination and run. The watch app comes along.
3. On first launch, **allow Local Network access**. Without it the iPhone can't find the Mac.
4. On the Mac, in **EDITAR → Mais ajustes…**, point the iPhone camera at the **QR code** and tap **Open in TokenBar**.
5. If iOS says the developer is not trusted: Settings → General → VPN & Device Management → trust.

### 4. Apple Watch

1. On the watch: **Settings → Privacy & Security → Developer Mode → on** (it restarts).
   If the option doesn't show up, open Xcode at **Window → Devices and Simulators** with the watch unlocked and near the iPhone.
2. On the iPhone: **Watch** app → **My Watch → TokenBar → Install**.
3. The watch receives the pairing and the numbers through the iPhone. Nothing to set up on it.

> **"Unable to install because its integrity could not be verified"** = Developer Mode is off on the watch, or the watch isn't registered to your team yet. Turn the mode on and run the **TokenBarWatch** scheme once with the watch as the destination.

### 5. Widgets

- **iPhone:** long-press the Home Screen or Lock Screen → **+** → TokenBar.
- **Watch:** long-press the watch face → Edit → complications → TokenBar.
- **Mac:** right-click the desktop → Edit Widgets → TokenBar.
- **Control Center (macOS 26 / iOS 18):** edit Control Center → add a control → TokenBar. Enlarge the control once to see both lines.

### Distribution

- **Free Apple account:** apps installed on the iPhone and watch expire after **7 days**. To renew, run them again from Xcode.
- **Paid account (US$99/year):** lets you distribute through TestFlight or the App Store.
- **Android:** the `.apk` files are on [Releases](https://github.com/ChaconLucas/tokenbar/releases) (see **Android and Wear OS → Download**).

## API & developers

TokenBar's numbers are yours to use in scripts and agents:

- **Local API** while the app runs: `curl http://localhost:41777/v1/usage` (localhost only; real port in `~/.tokenbar/api.json`).
- **CLI** `tokenbar` (Node 18+): bars in the terminal, `tokenbar --prompt` for your shell prompt or tmux, `tokenbar get claude 5h` for scripts. Works without the app too.
- **MCP server** `tokenbar-mcp`: Claude Code, Codex or Cursor can call `check_budget` before a long task.
- **Webhooks** at 80% / 95% / reset (Slack, Discord, Home Assistant…), and `~/.tokenbar/providers/*.json` to add any AI.

```sh
curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.sh | sh
```

Everything (schemas and examples in curl, JavaScript, Python, starship, tmux, zsh): [docs/api.md](docs/api.md).

## Optional server (see your numbers away from home)

Without a server, the iPhone only updates when it's on the same Wi-Fi as the Mac; elsewhere it shows the last number. To update from anywhere, deploy your own free server on Cloudflare (Worker + D1):

```sh
cd server
npm install
cp wrangler.example.toml wrangler.toml
npx wrangler login
npx wrangler d1 create tokenbar          # copy the database_id it prints into wrangler.toml
npx wrangler d1 execute tokenbar --remote --file=schema.sql
npx wrangler deploy                      # prints https://tokenbar.<your-account>.workers.dev
```

Then, on the Mac: **EDITAR → Mais ajustes… → Servidor**, paste the address, **SALVAR** (save) and scan the QR again on the iPhone.

Cloudflare's free plan allows 100,000 writes per day. The Mac only sends when the number changes, or every 10 minutes as a heartbeat.

## Privacy

- **No code, prompt or conversation leaves the Mac.** Only percentages, reset times and how long ago they were read.
- **On Wi-Fi:** the Mac only answers clients that send the pairing key. The network advertisement shows only its first 8 characters, so the iPhone knows which Mac is yours.
- **On the server:** it stores the `sha256` of the key, never the key itself, and the latest usage snapshot.
- **Anyone with the QR code can see your numbers.** Don't post it.

## Known limitations

- **Claude Code:** the numbers only update while some Claude Code session is open, because that's what feeds the statusline. The display shows how long ago the number was read.
- **Widgets:** iOS and watchOS limit widget refreshes to roughly every 15 minutes. Without a server, the iPhone widget shows what the app read the last time it was open.
- **After a reset:** the bar goes back to 0% on its own, even before a new number arrives.
- **App Store:** the Mac app isn't sandboxed (it needs to read `~/.codex` and `~/.claude`), so it can't be distributed through the Mac App Store.

## Troubleshooting

| Symptom | What to do |
|---|---|
| iPhone says "Mac não encontrado no Wi-Fi" (Mac not found on Wi-Fi) | Same Wi-Fi? **Local Network** permission on (Settings → Privacy → Local Network → TokenBar)? Mac firewall allowing TokenBar? |
| iPhone says "O Mac recusou a chave" (the Mac rejected the key) | Scan the QR again. |
| Claude doesn't show up | Click **Conectar Claude Code** and send a message in Claude Code **in the terminal**. Using the **VS Code panel**? The statusline doesn't run there: use `claude` in VS Code's terminal, or turn on **Ler pelo login do Claude Code** in settings (macOS asks once: Always Allow). |
| Codex doesn't show up | Use Codex once. The limits appear in the session files after the first response. |
| Watch: "integrity could not be verified" | See **Install → Apple Watch**. |
| Blank icon in the Dock | `killall Dock`. If it persists, restart the Mac (macOS icon cache). |

## Structure

```
App/macOS     collector (Claude/Codex), Wi-Fi server (Bonjour), window, menu bar, settings
App/iOS       full-screen app, Wi-Fi + server fetch, relays to the watch
App/watchOS   watch app (receives from the iPhone)
Shared/       model, dot-matrix display, theme, Wi-Fi client, server API
Widget/       widgets and complications (one codebase for Mac, iPhone and Watch)
server/       Cloudflare Worker + D1 (optional)
Config/       signing (Signing.xcconfig + your Signing.local.xcconfig)
scripts/      icon generator
```

## License

MIT. See [LICENSE](LICENSE).

TokenBar is an independent project and is not affiliated with Anthropic or OpenAI. "Claude", "Claude Code" and "Codex" are trademarks of their respective owners.
