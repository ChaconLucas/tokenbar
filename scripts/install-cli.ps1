# Installs the TokenBar CLI (`tokenbar`) and MCP server (`tokenbar-mcp`) on Windows:
#   irm https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-cli.ps1 | iex
#
# Needs Node.js 18+. No npm packages, no admin. Files go to %USERPROFILE%\.tokenbar\cli\,
# commands (tokenbar.cmd, tokenbar-mcp.cmd) to %USERPROFILE%\.tokenbar\bin\.
#
# Environment overrides: TB_CLI_PREFIX (install into <dir>\cli and <dir>\bin, skip Claude setup),
# TB_CLI_SOURCE (copy from a local checkout), TB_CLI_REF (branch/tag), TB_NO_MCP=1.
$ErrorActionPreference = 'Stop'

$Repo = 'ChaconLucas/tokenbar'
$Ref = if ($env:TB_CLI_REF) { $env:TB_CLI_REF } else { 'main' }
$Base = "https://raw.githubusercontent.com/$Repo/$Ref/cli"
$Files = @('tokenbar.mjs', 'mcp.mjs', 'lib/data.mjs', 'package.json')
$NoMcp = $env:TB_NO_MCP -eq '1'

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

# 4. MCP server for Claude Code
if ($NoMcp) {
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

$McpJson = $Mcp.Replace('\', '\\')
Write-Host @"

Try it:
    tokenbar              # bars per AI
    tokenbar --prompt     # CL 28% CX 0%
    tokenbar get claude 5h

MCP server for other agents (command: node, args: $Mcp)
  Codex (%USERPROFILE%\.codex\config.toml):
    [mcp_servers.tokenbar]
    command = "node"
    args = ['$Mcp']
  Cursor (%USERPROFILE%\.cursor\mcp.json) / VS Code (.vscode\mcp.json uses "servers" instead of "mcpServers"):
    { "mcpServers": { "tokenbar": { "command": "node", "args": ["$McpJson"] } } }

Docs: https://github.com/$Repo/blob/main/docs/api.md
"@
