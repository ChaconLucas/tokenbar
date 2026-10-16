#!/bin/sh
# Installs the TokenBar CLI (`tokenbar`) and MCP server (`tokenbar-mcp`) on Mac/Linux:
#   curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.sh | sh
#
# Needs Node.js 18+. No npm packages, no sudo. Files go to ~/.tokenbar/cli/, commands to ~/.local/bin/.
# If the `claude` CLI exists, it also registers the MCP server in Claude Code (user scope).
#
# Environment overrides:
#   TB_CLI_PREFIX=<dir>   install into <dir>/cli and <dir>/bin instead, and skip `claude mcp add` (for tests)
#   TB_CLI_SOURCE=<repo>  copy cli/ from a local checkout instead of downloading
#   TB_CLI_REF=<branch>   download from this branch/tag (default: main)
#   TB_NO_MCP=1           don't touch the Claude Code config
set -eu

REPO="ChaconLucas/tokenbar"
REF="${TB_CLI_REF:-main}"
BASE="https://raw.githubusercontent.com/$REPO/$REF/cli"
FILES="tokenbar.mjs mcp.mjs lib/data.mjs package.json"

if [ -n "${TB_CLI_PREFIX:-}" ]; then
  DIR="$TB_CLI_PREFIX/cli"
  BIN="$TB_CLI_PREFIX/bin"
  TB_NO_MCP=1
else
  DIR="$HOME/.tokenbar/cli"
  BIN="$HOME/.local/bin"
fi

say() { printf '\033[1;35m▸\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

# 1. Node 18+
command -v node >/dev/null 2>&1 || fail "Node.js 18+ is required: https://nodejs.org (or: brew install node)"
major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
[ "$major" -ge 18 ] || fail "Node.js 18+ is required (found $(node --version))."

# 2. Files (into a temp dir first, so a failed download never leaves a half install)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/lib"
if [ -n "${TB_CLI_SOURCE:-}" ]; then
  say "Copying the CLI from $TB_CLI_SOURCE/cli…"
  for f in $FILES; do cp "$TB_CLI_SOURCE/cli/$f" "$tmp/$f" || fail "Missing $TB_CLI_SOURCE/cli/$f"; done
else
  say "Downloading the TokenBar CLI ($REF)…"
  for f in $FILES; do curl -fsSL "$BASE/$f" -o "$tmp/$f" || fail "Could not download $BASE/$f"; done
fi
node --check "$tmp/tokenbar.mjs" && node --check "$tmp/mcp.mjs" && node --check "$tmp/lib/data.mjs" \
  || fail "The downloaded files are broken; try again later."

mkdir -p "$DIR/lib" "$BIN"
for f in $FILES; do mv -f "$tmp/$f" "$DIR/$f"; done
chmod +x "$DIR/tokenbar.mjs" "$DIR/mcp.mjs"

# 3. Commands
cat > "$BIN/tokenbar" <<EOF
#!/bin/sh
exec node "$DIR/tokenbar.mjs" "\$@"
EOF
cat > "$BIN/tokenbar-mcp" <<EOF
#!/bin/sh
exec node "$DIR/mcp.mjs" "\$@"
EOF
chmod +x "$BIN/tokenbar" "$BIN/tokenbar-mcp"
say "Installed: $BIN/tokenbar  ($("$BIN/tokenbar" --version))"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *)
    warn "$BIN is not in your PATH. Add this line to your ~/.zshrc or ~/.bashrc:"
    printf '    export PATH="%s:$PATH"\n' "$BIN"
    ;;
esac

# 4. MCP server for Claude Code
MCP="$DIR/mcp.mjs"
if [ "${TB_NO_MCP:-}" = "1" ]; then
  say "Skipping Claude Code MCP setup."
elif command -v claude >/dev/null 2>&1; then
  if claude mcp get tokenbar >/dev/null 2>&1; then
    say "Claude Code already has the tokenbar MCP server."
  else
    answer=y
    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
      printf 'Add the tokenbar MCP server to Claude Code (lets it check its own limits)? [Y/n] ' > /dev/tty
      read -r answer < /dev/tty || answer=y
    fi
    case "$answer" in
      [nN]*) say "Skipped. Later: claude mcp add tokenbar --scope user -- node \"$MCP\"" ;;
      *) claude mcp add tokenbar --scope user -- node "$MCP" >/dev/null \
           && say "Added to Claude Code: tokenbar MCP server (user scope)." \
           || warn "Could not run: claude mcp add tokenbar --scope user -- node \"$MCP\"" ;;
    esac
  fi
fi

cat <<EOF

Try it:
    tokenbar              # bars per AI
    tokenbar --prompt     # CL 28% CX 0%  (for your shell prompt)
    tokenbar get claude 5h

MCP server for other agents (command: node, args: $MCP)
  Codex (~/.codex/config.toml):
    [mcp_servers.tokenbar]
    command = "node"
    args = ["$MCP"]
  Cursor (~/.cursor/mcp.json) / VS Code (.vscode/mcp.json uses "servers" instead of "mcpServers"):
    { "mcpServers": { "tokenbar": { "command": "node", "args": ["$MCP"] } } }

Docs: https://github.com/$REPO/blob/main/docs/api.md
EOF
