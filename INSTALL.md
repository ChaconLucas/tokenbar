# Installing TokenBar — guide for AI assistants

> **If you are an AI assistant** (Claude Code, Codex, Cursor, ChatGPT…) and a person asked you to
> install or explain TokenBar: follow this file. Talk to them **in their language**, one step at a
> time, and run the commands yourself when you have a terminal. Only ask them to click when a step
> really needs their hands (a permission dialog, the phone, the watch).
>
> **Se você é uma pessoa:** abra o seu Claude Code (ou outra IA com terminal) e diga:
> *"Leia https://github.com/ChaconLucas/tokenbar/blob/main/INSTALL.md e instale o TokenBar para mim."*

## What TokenBar is (explain this in one or two sentences)

An LED dot-matrix display that shows how much of each AI's usage limit is spent (5-hour and
7-day windows) and when it resets. **The computer collects the numbers**: it reads Claude Code's
statusline and Codex's session files. Phones and watches only show what the computer sends,
over the local Wi-Fi (or an optional server). So the computer is always step 1.

## Step 0 — ask the person (only what you can't detect)

1. Which computer: **Mac**, **Windows** or **Linux**? (Detect it yourself if you have a shell: `uname -s`.)
2. Which AIs they use: **Claude Code**, **Codex**, others? (Detect: `ls ~/.claude ~/.codex`.)
3. Do they want it on a **phone** or **watch** too? Which: iPhone, Android, Apple Watch, Wear OS?

Then tell them the plan before you start, using the table below.

| Device | How hard | What's needed |
|---|---|---|
| **Mac** (macOS 15+) | 1 command | nothing |
| **Windows** | download `TokenBar-Windows-setup.exe` | click through SmartScreen once |
| **Linux** | build from source (no package yet) | Rust + Node |
| **Android phone** | download `.apk` | allow "install unknown apps" |
| **Wear OS watch** | `.apk` via `adb` | developer options on the watch |
| **iPhone / Apple Watch** | build with Xcode | a Mac with Xcode, a free Apple ID; the app **expires every 7 days** (Apple rule for free accounts) |

Be upfront about the iPhone/Apple Watch limitation: Apple doesn't allow installing apps outside the
App Store/TestFlight without Xcode, and the project has no paid Apple account yet.

---

## Mac

```sh
curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-mac.sh | sh
```

What it does: downloads `TokenBar-macOS.zip` from the latest GitHub Release, quits a running
TokenBar, installs to `/Applications`, checks the code signature, opens it. Downloaded via
`curl`, the app isn't quarantined, so macOS won't show the "unidentified developer" warning.

### If macOS blocks it ("can't be opened", "unidentified developer", "is damaged")

TokenBar isn't notarized by Apple yet, so Gatekeeper blocks apps that arrive **quarantined**
(downloaded by a browser, AirDrop, chat apps). **Handle it yourself, don't just tell the person:**

1. Check: `xattr -p com.apple.quarantine /Applications/TokenBar.app 2>/dev/null && echo QUARANTINED`
2. If quarantined, or the person reports any of those messages:
   `xattr -dr com.apple.quarantine /Applications/TokenBar.app && open /Applications/TokenBar.app`
   (or simply re-run the `curl … | sh` installer above, which does the same).
3. Verify the signature is intact: `codesign --verify --deep --strict /Applications/TokenBar.app && echo OK`.
   If it fails, don't open it: reinstall with the `curl` command, and if it still fails, ask them to open an issue.
4. Without a terminal: System Settings → Privacy & Security → scroll down → **Open Anyway** (after one failed launch).

A prompt saying *"TokenBar wants to use your confidential information stored in 'Claude Code-credentials'"* is
**not** a block: it's the optional login reading (VS Code panel). Tell them to click **Always Allow**.

**Verify:** the LED device window appears and a small dot bar shows up in the menu bar.

### Connect Claude Code (Mac)

Claude Code only exposes its limits (`rate_limits`) to the **statusline** command. TokenBar
installs a tiny script that saves a copy of that JSON to `~/.tokenbar/claude.json` and then runs
the person's previous statusline, so what they see in the terminal doesn't change.

- **Preferred:** ask them to click **EDITAR → Mais ajustes… → Conectar Claude Code** in the app.
  It backs up `~/.claude/settings.json` to `~/.claude/settings.json.tokenbar-backup` first.
- Numbers appear the next time a Claude Code session refreshes its statusline (send any message).
- **Verify:** `cat ~/.tokenbar/claude.json` contains `"rate_limits"`.

Do **not** edit `~/.claude/settings.json` by hand unless the button fails; if you must, keep their
existing `statusLine.command` by saving it to `~/.tokenbar/statusline-original` and pointing
`statusLine.command` to `~/.tokenbar/claude-tee.sh` (content: see `App/macOS/ClaudeHook.swift`).

### Claude Code in the VS Code panel (or the desktop app)

The statusline only runs in the **terminal**. If the person uses Claude Code in the VS Code
extension **panel**, no numbers arrive. Two options — explain both and let them choose:

1. Use `claude` in VS Code's integrated terminal (Ctrl+`) instead of the panel. Works now, nothing to turn on.
2. Turn on **"Ler pelo login do Claude Code"** (Mac: Ajustes → CLAUDE CODE; Windows/Linux: ⚙ → CLAUDE CODE;
   or the "painel do VS Code" link on the guide's Claude slide). TokenBar then reads the login Claude Code
   already saved (Mac: Keychain item `Claude Code-credentials` — answer **Always Allow** when macOS asks;
   Windows/Linux: `~/.claude/.credentials.json`) and asks `api.anthropic.com/api/oauth/usage` every 5 minutes.
   Read-only; the token never leaves the computer except to Anthropic. That endpoint is not officially
   documented and may change; the statusline keeps working as a fallback.

### Codex

Nothing to do. TokenBar reads the last `token_count` event in `~/.codex/sessions/**/*.jsonl`.
If Codex doesn't show up, they need to use Codex once (limits arrive with the first reply).

### Firewall prompt

If macOS asks whether TokenBar may **accept incoming network connections**, answer **Allow**:
that's how the phone and watch read the Mac over Wi-Fi.

---

### Mac with Homebrew (alternative)

`brew install --cask chaconlucas/tokenbar/tokenbar` — installs the same app and removes the quarantine flag.

## VS Code extension (optional, any OS)

Shows the % in VS Code's status bar. Download `TokenBar-VSCode.vsix` from the latest release and run
`code --install-extension TokenBar-VSCode.vsix` (or Extensions → ⋯ → Install from VSIX). It reads
`~/.tokenbar/snapshot.json` written by the TokenBar app, or the Claude/Codex files directly if the app isn't installed.

## Windows / Linux

Check the latest release for installers:
https://github.com/ChaconLucas/tokenbar/releases/latest
(or `gh release view --repo ChaconLucas/tokenbar --json assets -q '.assets[].name'`).

- **Windows:** `TokenBar-Windows-setup.exe` (or `TokenBar_*_x64-setup.exe` / `.msi` from CI builds). SmartScreen may warn
  ("Windows protected your PC") because the app isn't code-signed: **More info → Run anyway**.
- **Linux:** `TokenBar_*.AppImage` (`chmod +x` and run) or `.deb` (`sudo apt install ./TokenBar_*.deb`).

**If there are no Windows/Linux files in the release yet**, build from source (needs
[Rust](https://rustup.rs) and Node 18+):

```sh
git clone https://github.com/ChaconLucas/tokenbar.git
cd tokenbar/desktop
npm install
npx tauri build          # installers land in src-tauri/target/release/bundle/
```

Linux build deps (Debian/Ubuntu):
`sudo apt install libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev build-essential`.

The app lives in the system tray (a ring of 12 LED dots). Click it → the device window.
Settings (⚙) has **Connect Claude Code**, the QR code for the phone, and the 6-digit code for the watch.
On Windows the Claude hook is a PowerShell script; elsewhere it's `sh`.

---

## Android phone

1. On the phone, open https://github.com/ChaconLucas/tokenbar/releases/latest and download
   `TokenBar-Android.apk`.
2. Open it, allow "install unknown apps" for the browser. If Play Protect warns: **Install anyway**.
3. Pair: on the computer open **Mais ajustes** (Mac) or **⚙** (Windows/Linux) → in the app tap
   **ESCANEAR QR** and point at the QR code. Same Wi-Fi as the computer.

Huawei with HarmonyOS NEXT, and Huawei watches, are **not supported**.

## Wear OS watch (Galaxy Watch, Pixel Watch…)

Works with or without the phone.

1. On the watch: Settings → About → tap *Build number* 7× → Developer options → **ADB debugging**
   and **Wireless debugging** on. Note the IP:port it shows.
2. On the computer (needs `adb`: `brew install android-platform-tools` /
   `winget install Google.PlatformTools` / `sudo apt install adb`):
   ```sh
   adb pair <ip>:<pair-port>      # code shown on the watch under "Pair new device"
   adb connect <ip>:<port>
   adb install TokenBar-WearOS.apk
   ```
3. With a phone: it gets the numbers from the Android app automatically.
   Without a phone: type on the watch the **6-digit code** from the computer's settings
   (*RELÓGIO SEM CELULAR*). Valid once, changes every 10 minutes, same Wi-Fi.

---

## iPhone / Apple Watch (needs Xcode)

**Fast path (recommended):** with Xcode installed and opened once, the person signed into their Apple ID in
Xcode → Settings → Accounts, and the iPhone plugged in (unlocked, "Trust", Developer Mode on), run:

```sh
curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-ios.sh | sh
```

It clones the repo to `~/.tokenbar/src`, finds their Team ID from the Apple Development certificate, picks a unique
bundle prefix (saved in `~/.tokenbar/ios-prefix`), builds and installs on the connected iPhone. Running it again
updates the app and renews the 7-day free-account limit. The manual steps below are the fallback.

Only possible on a **Mac with Xcode 26+** (free from the App Store, ~15 GB). Tell the person this
takes ~20 minutes the first time and that **the app stops opening after 7 days** (free Apple
account); to renew, run it again from Xcode.

```sh
brew install xcodegen
git clone https://github.com/ChaconLucas/tokenbar.git
cd tokenbar
cat > Config/Signing.local.xcconfig <<'EOF'
DEVELOPMENT_TEAM = <TEAM_ID>
TB_BUNDLE_PREFIX = com.<something-unique>
EOF
xcodegen generate
open TokenBar.xcodeproj
```

- `<TEAM_ID>`: Xcode → Settings → Accounts → sign in with the Apple ID → the team → Team ID.
  (With a shell: `security find-identity -v -p codesigning` shows `Apple Development: … (XXXXXXXXXX)`;
  the Team ID is the `OU` of that certificate:
  `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`.)
- **Never commit** `Config/Signing.local.xcconfig`; it's git-ignored on purpose.
- iPhone: enable **Developer Mode** (Settings → Privacy & Security), connect it by cable, choose
  scheme **TokenBar** with the iPhone as destination, ⌘R. If iOS says the developer is untrusted:
  Settings → General → VPN & Device Management → trust.
- First launch: **allow Local Network** (otherwise it can't find the computer). Then scan the QR
  from the computer's settings with the iPhone camera → *Open in TokenBar*.
- Apple Watch: enable Developer Mode on the watch, then iPhone app **Watch → My Watch → TokenBar → Install**.
  Error "integrity could not be verified" = Developer Mode off on the watch.

---

## Other AIs (Gemini, Cursor, anything)

Any AI shows up if something writes a JSON file to `~/.tokenbar/providers/<id>.json`
(Windows: `%USERPROFILE%\.tokenbar\providers\`). Format and fields: [docs/providers.md](docs/providers.md).
If the person uses an AI whose limits you can read (an API, a CLI, a log), offer to write a small
script or scheduled job that keeps that file updated.

## Optional server (see numbers away from home)

Without it, phones update only on the same Wi-Fi as the computer. With a free Cloudflare
Worker they update anywhere: see "Optional server" in [README.md](README.md#optional-server-see-your-numbers-away-from-home).
Only suggest this if they ask to see it outside home.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Phone: "Mac not found on Wi-Fi" | Same Wi-Fi? iPhone: Settings → Privacy → Local Network → TokenBar on. Computer firewall allows TokenBar? |
| Phone: "key refused" | Scan the QR again. |
| Claude missing | Connect Claude Code, then send a message in a Claude Code session **in the terminal**. Uses the VS Code panel? See "Claude Code in the VS Code panel". Check `~/.tokenbar/claude.json`. |
| Codex missing | Use Codex once. |
| Mac: "can't be opened" / "unidentified developer" | Install with the `curl` command above, or Privacy & Security → Open Anyway. |
| Mac: blank Dock icon | `killall Dock`. |

## Privacy (tell them if they ask)

No code, prompt or conversation leaves the computer: only percentages and reset times. On Wi-Fi
the computer answers only devices holding the pairing key. **Whoever has the QR code sees the
numbers — don't post it.**
