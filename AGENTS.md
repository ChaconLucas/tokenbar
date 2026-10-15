# For AI agents

- **Installing TokenBar for someone?** Follow [INSTALL.md](INSTALL.md).
- Never commit `Config/Signing.local.xcconfig`, `server/wrangler.toml` or any signing key.
- Apple apps: `xcodegen generate` after editing `project.yml`. Android: `android/`. Windows/Linux: `desktop/` (Tauri).
- Other AIs plug in through `~/.tokenbar/providers/*.json`: see [docs/providers.md](docs/providers.md).
