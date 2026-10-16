# Installs the TokenBar CLI (`tokenbar`) and MCP server (`tokenbar-mcp`) on Windows:
#   irm https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.ps1 | iex
#
# Also add the MCP server to other AI tools (comma-separated, or `all` for every one installed):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.ps1))) -AddTo cursor,vscode
#   (or: $env:TB_ADD_TO = 'cursor,vscode'; irm … | iex)
# Tools: cursor windsurf vscode cline opencode continue goose zed gemini antigravity codex claude
#        claude-desktop kiro amp. Each file is backed up first (<file>.tokenbar-backup-<time>), only the
#        "tokenbar" entry is added (other servers untouched, comments kept), and never twice.
#
# Needs Node.js 18+. No npm packages, no admin. Files go to %USERPROFILE%\.tokenbar\cli\,
# commands (tokenbar.cmd, tokenbar-mcp.cmd) to %USERPROFILE%\.tokenbar\bin\.
#
# Environment overrides: TB_CLI_PREFIX (install into <dir>\cli and <dir>\bin, skip Claude setup),
# TB_CLI_SOURCE (copy from a local checkout), TB_CLI_REF (branch/tag), TB_NO_MCP=1, TB_ADD_TO (= -AddTo).
param([string[]]$AddTo = @())
$ErrorActionPreference = 'Stop'

$Repo = 'ChaconLucas/tokenbar'
$Ref = if ($env:TB_CLI_REF) { $env:TB_CLI_REF } else { 'main' }
$Base = "https://raw.githubusercontent.com/$Repo/$Ref/cli"
$Files = @('tokenbar.mjs', 'mcp.mjs', 'lib/data.mjs', 'package.json')
$NoMcp = $env:TB_NO_MCP -eq '1'
$AddToList = (@($AddTo) + @($env:TB_ADD_TO) | Where-Object { $_ }) -join ','

if ($env:TB_CLI_PREFIX) {
  $Dir = Join-Path $env:TB_CLI_PREFIX 'cli'
  $Bin = Join-Path $env:TB_CLI_PREFIX 'bin'
  $NoMcp = $true
} else {
  $Dir = Join-Path $env:USERPROFILE '.tokenbar\cli'
  $Bin = Join-Path $env:USERPROFILE '.tokenbar\bin'
}

function Say($m) { Write-Host "> $m" -ForegroundColor Magenta }
function Warn($m) { Write-Host "! $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "x $m" -ForegroundColor Red; exit 1 }

# 1. Node 18+
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Fail 'Node.js 18+ is required: https://nodejs.org (or: winget install OpenJS.NodeJS.LTS)' }
$major = [int](node -p "process.versions.node.split('.')[0]")
if ($major -lt 18) { Fail "Node.js 18+ is required (found $(node --version))." }

# 2. Files (temp dir first, so a failed download never leaves a half install)
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tokenbar-cli-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'lib') | Out-Null
try {
  foreach ($f in $Files) {
    $out = Join-Path $tmp $f
    if ($env:TB_CLI_SOURCE) { Copy-Item (Join-Path $env:TB_CLI_SOURCE "cli/$f") $out }
    else { Invoke-WebRequest -UseBasicParsing -Uri "$Base/$f" -OutFile $out }
  }
  foreach ($f in @('tokenbar.mjs', 'mcp.mjs', 'lib/data.mjs')) {
    node --check (Join-Path $tmp $f)
    if ($LASTEXITCODE -ne 0) { Fail 'The downloaded files are broken; try again later.' }
  }
  New-Item -ItemType Directory -Force -Path (Join-Path $Dir 'lib'), $Bin | Out-Null
  foreach ($f in $Files) { Move-Item -Force (Join-Path $tmp $f) (Join-Path $Dir $f) }
} catch {
  Fail "Install failed: $($_.Exception.Message)"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# 3. Commands
$Cli = Join-Path $Dir 'tokenbar.mjs'
$Mcp = Join-Path $Dir 'mcp.mjs'
Set-Content -Encoding ASCII -Path (Join-Path $Bin 'tokenbar.cmd') -Value "@echo off`r`nnode `"$Cli`" %*"
Set-Content -Encoding ASCII -Path (Join-Path $Bin 'tokenbar-mcp.cmd') -Value "@echo off`r`nnode `"$Mcp`" %*"
Say "Installed: $(Join-Path $Bin 'tokenbar.cmd')  ($(node $Cli --version))"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (($userPath -split ';') -contains $Bin)) {
  Warn "$Bin is not in your PATH. To add it (then open a new terminal):"
  Write-Host "    [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';$Bin', 'User')"
}

# 4. MCP server for Claude Code (with -AddTo, only the tools listed there)
if ($AddToList) {
  # handled in step 5
} elseif ($NoMcp) {
  Say 'Skipping Claude Code MCP setup.'
} elseif (Get-Command claude -ErrorAction SilentlyContinue) {
  claude mcp get tokenbar *> $null
  if ($LASTEXITCODE -eq 0) {
    Say 'Claude Code already has the tokenbar MCP server.'
  } else {
    $answer = Read-Host 'Add the tokenbar MCP server to Claude Code (lets it check its own limits)? [Y/n]'
    if ($answer -match '^[nN]') {
      Say "Skipped. Later: claude mcp add tokenbar --scope user -- node `"$Mcp`""
    } else {
      claude mcp add tokenbar --scope user -- node $Mcp | Out-Null
      if ($LASTEXITCODE -eq 0) { Say 'Added to Claude Code: tokenbar MCP server (user scope).' }
      else { Warn "Could not run: claude mcp add tokenbar --scope user -- node `"$Mcp`"" }
    }
  }
}

# 5. -AddTo: write the MCP server into other AI tools' configs (same writer as install-cli.sh)
if ($AddToList) {
  $AddToJs = @'
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
'@
  $jsFile = Join-Path ([IO.Path]::GetTempPath()) ("tokenbar-addto-" + [guid]::NewGuid() + '.cjs')
  Set-Content -Encoding UTF8 -Path $jsFile -Value $AddToJs
  $env:TB_NODE = (Get-Command node).Source
  try { node $jsFile $AddToList $Mcp } finally { Remove-Item -Force $jsFile -ErrorAction SilentlyContinue; Remove-Item Env:TB_NODE -ErrorAction SilentlyContinue }
  if ($LASTEXITCODE -ne 0) { Warn 'Some tools were not set up (see above); the rest is fine.' }
}

$McpJson = $Mcp.Replace('\', '\\')
Write-Host @"

Try it:
    tokenbar              # bars per AI
    tokenbar --prompt     # CL 28% CX 0%
    tokenbar get claude 5h

MCP server for other agents (command: node, args: $Mcp)
  One step for Cursor, VS Code, Windsurf, Zed, Codex, Gemini, Goose...: re-run with -AddTo <tool>
  Codex (%USERPROFILE%\.codex\config.toml):
    [mcp_servers.tokenbar]
    command = "node"
    args = ['$Mcp']
  Cursor (%USERPROFILE%\.cursor\mcp.json) / VS Code (.vscode\mcp.json uses "servers" instead of "mcpServers"):
    { "mcpServers": { "tokenbar": { "command": "node", "args": ["$McpJson"] } } }

Install in your AI: https://github.com/$Repo/blob/main/docs/api.md#install-in-your-ai
"@
