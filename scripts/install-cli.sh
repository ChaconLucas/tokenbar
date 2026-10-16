#!/bin/sh
# Installs the TokenBar CLI (`tokenbar`) and MCP server (`tokenbar-mcp`) on Mac/Linux:
#   curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.sh | sh
#
# Also add the MCP server to other AI tools (comma-separated, or `all` for every one installed):
#   curl -fsSL …/install-cli.sh | sh -s -- --add-to cursor,vscode,codex
# Tools: cursor windsurf vscode cline opencode continue goose zed gemini antigravity codex claude
#        claude-desktop kiro amp. Each file is backed up first (<file>.tokenbar-backup-<time>), only the
#        "tokenbar" entry is added (other servers untouched, comments kept), and never twice.
#
# Needs Node.js 18+. No npm packages, no sudo. Files go to ~/.tokenbar/cli/, commands to ~/.local/bin/.
# If the `claude` CLI exists, it also registers the MCP server in Claude Code (user scope).
#
# Environment overrides:
#   TB_CLI_PREFIX=<dir>   install into <dir>/cli and <dir>/bin instead, and skip `claude mcp add` (for tests)
#   TB_CLI_SOURCE=<repo>  copy cli/ from a local checkout instead of downloading
#   TB_CLI_REF=<branch>   download from this branch/tag (default: main)
#   TB_NO_MCP=1           don't touch the Claude Code config
#   TB_ADD_TO=<tools>     same as --add-to
set -eu

ADD_TO="${TB_ADD_TO:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --add-to) [ $# -ge 2 ] || { echo "--add-to needs a tool name (e.g. --add-to cursor)" >&2; exit 2; }
              ADD_TO="${ADD_TO:+$ADD_TO,}$2"; shift ;;
    --add-to=*) ADD_TO="${ADD_TO:+$ADD_TO,}${1#--add-to=}" ;;
    -h|--help) sed -n '2,24p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "Unknown option: $1 (try --add-to <tool>)" >&2; exit 2 ;;
  esac
  shift
done

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

# 4. MCP server for Claude Code (with --add-to, only the tools listed there)
MCP="$DIR/mcp.mjs"
if [ -n "$ADD_TO" ]; then
  :
elif [ "${TB_NO_MCP:-}" = "1" ]; then
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

# 5. --add-to: write the MCP server into other AI tools' configs
if [ -n "$ADD_TO" ]; then
  TB_NODE=$(command -v node) node - "$ADD_TO" "$MCP" <<'JS' || warn "Some tools were not set up (see above); the rest is fine."
// tokenbar --add-to: writes the MCP server into other AI tools' config files.
// Rules: back up before writing, only add the "tokenbar" entry (never touch other servers),
// never add it twice, keep comments/formatting (text insertion), skip tools that aren't installed.
const fs = require('fs'), path = require('path'), os = require('os'), cp = require('child_process');
const [want = '', MCP] = process.argv.slice(2);
const HOME = os.homedir(), WIN = process.platform === 'win32', MAC = process.platform === 'darwin';
// Absolute node (GUI apps often don't see the shell PATH); the PATH one, e.g. /opt/homebrew/bin/node,
// survives upgrades better than process.execPath (a versioned Cellar path).
const NODE = process.env.TB_NODE || process.execPath;
const XDG = process.env.XDG_CONFIG_HOME || path.join(HOME, '.config');
const APPDATA = process.env.APPDATA || path.join(HOME, 'AppData', 'Roaming');
const appDir = (name) => WIN ? path.join(APPDATA, name) : MAC ? path.join(HOME, 'Library', 'Application Support', name) : path.join(XDG, name);
const has = (p) => { try { fs.statSync(p); return true; } catch { return false; } };
const std = { command: NODE, args: [MCP] };
let failed = 0;
const ok = (t, m) => console.log(`  ✓ ${t}: ${m}`);
const skip = (t, m) => console.log(`  - ${t}: ${m}`);
const bad = (t, m) => { failed++; console.log(`  ! ${t}: ${m}`); };

// ---- JSON with comments: a tiny scanner (strings, // and /* */ comments, depth) ----
function skipWs(s, i) {
  for (;;) {
    while (i < s.length && /\s/.test(s[i])) i++;
    if (s.startsWith('//', i)) { while (i < s.length && s[i] !== '\n') i++; continue; }
    if (s.startsWith('/*', i)) { const e = s.indexOf('*/', i + 2); i = e < 0 ? s.length : e + 2; continue; }
    return i;
  }
}
function readStr(s, i) { // s[i] === '"' → [value, index after]
  let j = i + 1;
  while (j < s.length && s[j] !== '"') j += s[j] === '\\' ? 2 : 1;
  return [JSON.parse(s.slice(i, j + 1)), j + 1];
}
function parseJsonc(s) { // strip comments and trailing commas, then JSON.parse
  let out = '', i = 0;
  while (i < s.length) {
    if (s[i] === '"') { const [, j] = readStr(s, i); out += s.slice(i, j); i = j; continue; }
    if (s.startsWith('//', i) || s.startsWith('/*', i)) { i = skipWs(s, i); out += ' '; continue; }
    if (s[i] === ',') { const j = skipWs(s, i + 1); if (s[j] === '}' || s[j] === ']') { i++; continue; } }
    out += s[i++];
  }
  return JSON.parse(out.trim() || '{}');
}
// Index just after the "{" of property `key` inside the object that opens at `open` (or -1).
function findProp(s, open, key) {
  let depth = 0, i = open;
  while (i < s.length) {
    i = skipWs(s, i);
    const c = s[i];
    if (c === '"') {
      const [v, j] = readStr(s, i); i = j;
      if (depth === 1 && v === key) { const k = skipWs(s, i); if (s[k] === ':') { const m = skipWs(s, k + 1); return s[m] === '{' ? m + 1 : -2; } }
      continue;
    }
    if (c === '{' || c === '[') depth++;
    else if (c === '}' || c === ']') { if (--depth === 0) return -1; }
    i++;
  }
  return -1;
}
function insertAt(s, at, text) { // put `text` (one property) right after a "{", with a comma if needed
  const next = s[skipWs(s, at)];
  return s.slice(0, at) + text + (next === '}' ? '\n' : ',') + s.slice(at);
}
function backup(file) {
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
  const b = `${file}.tokenbar-backup-${stamp}`;
  fs.copyFileSync(file, b);
  return b;
}
function write(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const b = has(file) ? backup(file) : null;
  const tmp = `${file}.tokenbar-tmp`;
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, file);
  return b ? ` (backup: ${b})` : ' (new file)';
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function mergeJson(tool, file, key, entry) {
  const text = has(file) ? fs.readFileSync(file, 'utf8') : '';
  let obj;
  try { obj = parseJsonc(text); } catch (e) { return bad(tool, `${file} is not valid JSON, left untouched (${e.message})`); }
  if (typeof obj !== 'object' || Array.isArray(obj) || obj === null) return bad(tool, `${file} is not a JSON object, left untouched`);
  const cur = obj[key] && obj[key].tokenbar;
  if (cur && same(cur, entry)) return skip(tool, `already in ${file}`);
  let out;
  if (cur) { // ours, but with an old path: replace only when the file is plain JSON (no comments to lose)
    let strict; try { strict = JSON.parse(text); } catch { }
    if (!strict) return bad(tool, `${file} has an older "tokenbar" entry; edit it by hand to: ${JSON.stringify(entry)}`);
    strict[key].tokenbar = entry;
    out = JSON.stringify(strict, null, 2) + '\n';
  } else if (!text.trim()) {
    out = JSON.stringify({ [key]: { tokenbar: entry } }, null, 2) + '\n';
  } else {
    const root = skipWs(text, 0);
    if (text[root] !== '{') return bad(tool, `${file} does not start with "{", left untouched`);
    const at = findProp(text, root, key);
    if (at === -2) return bad(tool, `"${key}" in ${file} is not an object, left untouched`);
    const line = `"tokenbar": ${JSON.stringify(entry)}`;
    out = at > 0 ? insertAt(text, at, `\n    ${line}`) : insertAt(text, root + 1, `\n  "${key}": {\n    ${line}\n  }`);
  }
  let check; try { check = parseJsonc(out); } catch { }
  if (!check || !same(check[key] && check[key].tokenbar, entry)) return bad(tool, `could not merge ${file} safely, left untouched`);
  ok(tool, `${cur ? 'updated in' : 'added to'} ${file}${write(file, out)}`);
}

function mergeToml(tool, file) { // Codex
  const text = has(file) ? fs.readFileSync(file, 'utf8') : '';
  if (/^\s*\[\s*mcp_servers\s*\.\s*"?tokenbar"?\s*\]/m.test(text) || /^\s*mcp_servers\s*\.\s*"?tokenbar"?\s*[.=]/m.test(text))
    return skip(tool, `already in ${file}`);
  const block = `[mcp_servers.tokenbar]\ncommand = ${JSON.stringify(NODE)}\nargs = [${JSON.stringify(MCP)}]\n`;
  const out = text + (text && !text.endsWith('\n') ? '\n' : '') + (text ? '\n' : '') + block;
  ok(tool, `added to ${file}${write(file, out)}`);
}

// YAML: insert one item right under a top-level `key:` (block style only); never parse the rest.
function mergeYaml(tool, file, key, isDup, render, create) {
  const text = has(file) ? fs.readFileSync(file, 'utf8') : null;
  if (text === null && !create) return bad(tool, `${file} not found; open the app once so it creates it`);
  const lines = (text || '').split('\n');
  const k = lines.findIndex((l) => new RegExp(`^${key}:`).test(l));
  let out;
  if (k < 0) {
    const t = text || '';
    out = t + (t && !t.endsWith('\n') ? '\n' : '') + `${key}:\n` + render('  ') + '\n';
  } else {
    if (!new RegExp(`^${key}:\\s*(#.*)?$`).test(lines[k])) return bad(tool, `"${key}:" in ${file} is written inline; add TokenBar by hand`);
    let end = k + 1;
    while (end < lines.length && (/^(\s|- |-$)/.test(lines[end]) || /^\s*(#.*)?$/.test(lines[end]))) end++;
    const block = lines.slice(k + 1, end);
    if (isDup(block.join('\n'))) return skip(tool, `already in ${file}`);
    const first = block.find((l) => l.trim() && !l.trim().startsWith('#'));
    const indent = first ? first.match(/^\s*/)[0] : '  ';
    lines.splice(k + 1, 0, render(indent));
    out = lines.join('\n');
  }
  ok(tool, `added to ${file}${write(file, out)}`);
}
const q = JSON.stringify; // YAML double-quoted strings accept JSON escapes

const tools = {
  cursor: () => has(path.join(HOME, '.cursor'))
    ? mergeJson('cursor', path.join(HOME, '.cursor', 'mcp.json'), 'mcpServers', { type: 'stdio', ...std })
    : skip('cursor', 'not installed (~/.cursor not found)'),
  windsurf: () => { // Windsurf is now Devin Desktop; write wherever it lives
    const legacy = path.join(HOME, '.codeium', 'windsurf'), devin = WIN ? path.join(APPDATA, 'devin') : path.join(XDG, 'devin');
    const dirs = [legacy, devin].filter(has);
    if (!dirs.length) return skip('windsurf', 'not installed (~/.codeium/windsurf and devin config dir not found)');
    dirs.forEach((d) => mergeJson('windsurf', path.join(d, 'mcp_config.json'), 'mcpServers', std));
  },
  vscode: () => {
    const users = ['Code', 'Code - Insiders'].map((n) => path.join(appDir(n), 'User')).filter(has);
    if (!users.length) return skip('vscode', 'not installed (Code/User folder not found)');
    users.forEach((u) => mergeJson('vscode', path.join(u, 'mcp.json'), 'servers', { type: 'stdio', ...std }));
  },
  cline: () => {
    const dirs = ['Code', 'Code - Insiders', 'Cursor', 'Windsurf'].map((n) => path.join(appDir(n), 'User', 'globalStorage', 'saoudrizwan.claude-dev'))
      .concat(path.join(HOME, '.cline', 'data')).filter(has);
    if (!dirs.length) return skip('cline', 'not installed (extension storage and ~/.cline not found)');
    dirs.forEach((d) => mergeJson('cline', path.join(d, 'settings', 'cline_mcp_settings.json'), 'mcpServers', { ...std, disabled: false, autoApprove: [] }));
  },
  opencode: () => {
    const dir = path.join(HOME, '.config', 'opencode');
    if (!has(dir)) return skip('opencode', 'not installed (~/.config/opencode not found)');
    const jsonc = path.join(dir, 'opencode.jsonc'), json = path.join(dir, 'opencode.json');
    mergeJson('opencode', has(jsonc) && !has(json) ? jsonc : json, 'mcp', { type: 'local', command: [NODE, MCP], enabled: true });
  },
  continue: () => has(path.join(HOME, '.continue'))
    ? mergeYaml('continue', path.join(HOME, '.continue', 'config.yaml'), 'mcpServers',
        (b) => /^\s*-?\s*name:\s*["']?tokenbar["']?\s*$/m.test(b),
        (i) => `${i}- name: tokenbar\n${i}  type: stdio\n${i}  command: ${q(NODE)}\n${i}  args:\n${i}    - ${q(MCP)}`, false)
    : skip('continue', 'not installed (~/.continue not found)'),
  goose: () => {
    const dir = WIN ? path.join(APPDATA, 'Block', 'goose', 'config') : path.join(XDG, 'goose');
    if (!has(dir)) return skip('goose', `not installed (${dir} not found)`);
    mergeYaml('goose', path.join(dir, 'config.yaml'), 'extensions',
      (b) => /^\s+["']?tokenbar["']?:\s*$/m.test(b),
      (i) => [`tokenbar:`, `  name: TokenBar`, `  type: stdio`, `  cmd: ${q(NODE)}`, `  args:`, `  - ${q(MCP)}`,
        `  enabled: true`, `  envs: {}`, `  timeout: 300`, `  description: AI usage limits (check_budget before long tasks)`].map((l) => i + l).join('\n'), true);
  },
  zed: () => {
    const dir = WIN ? path.join(APPDATA, 'Zed') : path.join(XDG, 'zed');
    if (!has(dir)) return skip('zed', `not installed (${dir} not found)`);
    mergeJson('zed', path.join(dir, 'settings.json'), 'context_servers', { ...std, env: {} });
  },
  gemini: () => has(path.join(HOME, '.gemini'))
    ? mergeJson('gemini', path.join(HOME, '.gemini', 'settings.json'), 'mcpServers', std)
    : skip('gemini', 'not installed (~/.gemini not found)'),
  antigravity: () => has(path.join(HOME, '.gemini'))
    ? mergeJson('antigravity', path.join(HOME, '.gemini', 'config', 'mcp_config.json'), 'mcpServers', std)
    : skip('antigravity', 'not installed (~/.gemini not found)'),
  kiro: () => has(path.join(HOME, '.kiro'))
    ? mergeJson('kiro', path.join(HOME, '.kiro', 'settings', 'mcp.json'), 'mcpServers', { ...std, disabled: false })
    : skip('kiro', 'not installed (~/.kiro not found)'),
  amp: () => has(path.join(HOME, '.config', 'amp'))
    ? mergeJson('amp', path.join(HOME, '.config', 'amp', 'settings.json'), 'amp.mcpServers', std)
    : skip('amp', 'not installed (~/.config/amp not found)'),
  codex: () => {
    const dir = process.env.CODEX_HOME || path.join(HOME, '.codex');
    if (!has(dir)) return skip('codex', `not installed (${dir} not found)`);
    mergeToml('codex', path.join(dir, 'config.toml'));
  },
  claude: () => { // Claude Code keeps its config in a big live file: go through its own CLI
    const run = (args) => cp.spawnSync('claude', args, { stdio: 'ignore', shell: WIN });
    const probe = run(['mcp', 'get', 'tokenbar']);
    if (probe.error) return skip('claude', 'not installed (`claude` command not found)');
    if (probe.status === 0) return skip('claude', 'already in Claude Code');
    run(['mcp', 'add', 'tokenbar', '--scope', 'user', '--', 'node', WIN ? `"${MCP}"` : MCP]).status === 0
      ? ok('claude', 'added to Claude Code (claude mcp add, user scope)')
      : bad('claude', `could not run: claude mcp add tokenbar --scope user -- node "${MCP}"`);
  },
  'claude-desktop': () => has(appDir('Claude'))
    ? mergeJson('claude-desktop', path.join(appDir('Claude'), 'claude_desktop_config.json'), 'mcpServers', std)
    : skip('claude-desktop', 'not installed (Claude config folder not found); or use TokenBar.mcpb'),
};
const alias = { code: 'vscode', devin: 'windsurf', 'claude-code': 'claude', claudedesktop: 'claude-desktop', 'gemini-cli': 'gemini' };

if (!MCP) { console.error('usage: --add-to <tool[,tool…]|all>'); process.exit(2); }
let list = want.toLowerCase().split(/[,\s]+/).filter(Boolean).map((t) => alias[t] || t);
if (list.includes('all')) list = Object.keys(tools);
const unknown = list.filter((t) => !tools[t]);
if (unknown.length) { console.error(`Unknown tool: ${unknown.join(', ')}. Known: ${Object.keys(tools).join(', ')}, all`); process.exit(2); }
console.log(`Adding the tokenbar MCP server (${NODE} ${MCP}):`);
for (const t of [...new Set(list)]) { try { tools[t](); } catch (e) { bad(t, e.message); } }
console.log('Restart the app (or reload its MCP servers) to pick it up.');
process.exit(failed ? 1 : 0);
JS
fi

cat <<EOF

Try it:
    tokenbar              # bars per AI
    tokenbar --prompt     # CL 28% CX 0%  (for your shell prompt)
    tokenbar get claude 5h

MCP server for other agents (command: node, args: $MCP)
  One step for Cursor, VS Code, Windsurf, Zed, Codex, Gemini, Goose…: re-run with --add-to <tool>
  Codex (~/.codex/config.toml):
    [mcp_servers.tokenbar]
    command = "node"
    args = ["$MCP"]
  Cursor (~/.cursor/mcp.json) / VS Code (.vscode/mcp.json uses "servers" instead of "mcpServers"):
    { "mcpServers": { "tokenbar": { "command": "node", "args": ["$MCP"] } } }

Install in your AI: https://github.com/$REPO/blob/main/docs/api.md#install-in-your-ai
EOF
