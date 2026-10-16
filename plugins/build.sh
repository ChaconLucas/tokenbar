#!/bin/sh
# Copies the MCP server and CLI (cli/mcp.mjs, cli/tokenbar.mjs, cli/lib/) into each plugin's server/:
#   sh plugins/build.sh [release folder]
# The copies ARE committed: Claude Code, Codex and Gemini CLI install plugins straight from the git
# repo, with no build step, so plugins/*/server/ must match cli/ in every pushed commit.
# scripts/release.sh runs this after the version bump; run it by hand whenever cli/ changes.
#
# With a folder, it also packs the Gemini CLI extension as release assets. `gemini extensions install
# https://github.com/ChaconLucas/tokenbar` takes the latest GitHub release asset named after the
# platform (darwin.*, linux.*, win32.*) and can't install from a subfolder of the repo, so the same
# platform-independent archive goes up three times, with plugins/gemini/ at its root.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for p in claude-code codex gemini; do
  dst="$ROOT/plugins/$p/server"
  rm -rf "$dst"
  mkdir -p "$dst"
  cp "$ROOT/cli/mcp.mjs" "$ROOT/cli/tokenbar.mjs" "$dst/"
  cp -R "$ROOT/cli/lib" "$dst/lib"
done
# Versions follow cli/package.json.
V=$(sed -n 's/^  "version": "\([^"]*\)".*/\1/p' "$ROOT/cli/package.json" | head -1)
for f in claude-code/.claude-plugin/plugin.json codex/.codex-plugin/plugin.json gemini/gemini-extension.json; do
  [ -f "$ROOT/plugins/$f" ] && sed -i.bak "s/^  \"version\": \"[^\"]*\"/  \"version\": \"$V\"/" "$ROOT/plugins/$f" && rm -f "$ROOT/plugins/$f.bak"
done
echo "plugins/*/server ← cli/ ($V)"

if [ $# -gt 0 ]; then
  mkdir -p "$1"
  OUT=$(cd "$1" && pwd)
  ( cd "$ROOT/plugins/gemini" && COPYFILE_DISABLE=1 tar -czf "$OUT/tokenbar-gemini.tar.gz" gemini-extension.json GEMINI.md commands server )
  for os in darwin linux win32; do cp "$OUT/tokenbar-gemini.tar.gz" "$OUT/$os.tokenbar-gemini.tar.gz"; done
  rm "$OUT/tokenbar-gemini.tar.gz"
  echo "$OUT/{darwin,linux,win32}.tokenbar-gemini.tar.gz"
fi
