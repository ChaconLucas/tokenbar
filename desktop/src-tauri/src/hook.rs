//! Liga o Claude Code ao TokenBar: a statusline passa a ser um script que guarda uma cópia do JSON
//! (com `rate_limits`) e repassa para a statusline que a pessoa já tinha. Windows usa PowerShell.

use crate::collector::{home, tokenbar_dir};
use serde_json::Value;
use std::fs;

fn settings() -> std::path::PathBuf { home().join(".claude").join("settings.json") }

#[cfg(windows)]
fn script() -> (std::path::PathBuf, String, String) {
    let path = tokenbar_dir().join("claude-tee.ps1");
    let body = r#"# TokenBar: guarda o JSON da statusline do Claude Code e repassa para a statusline original.
$d = Join-Path $HOME ".tokenbar"
$data = [Console]::In.ReadToEnd()
if ($data -match '"rate_limits"') {
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  [IO.File]::WriteAllText((Join-Path $d "claude.json.tmp"), $data)
  Move-Item -Force (Join-Path $d "claude.json.tmp") (Join-Path $d "claude.json")
}
$orig = Join-Path $d "statusline-original"
if (Test-Path $orig) {
  $cmd = (Get-Content $orig -Raw).Trim()
  if ($cmd) { $data | cmd /c $cmd }
}
"#.to_string();
    let command = format!("powershell -NoProfile -ExecutionPolicy Bypass -File \"{}\"", path.display());
    (path, body, command)
}

#[cfg(not(windows))]
fn script() -> (std::path::PathBuf, String, String) {
    let path = tokenbar_dir().join("claude-tee.sh");
    let body = r#"#!/bin/sh
# TokenBar: guarda o JSON da statusline do Claude Code e repassa para a statusline original.
d="$HOME/.tokenbar"
input=$(cat)
case "$input" in
  *'"rate_limits"'*) mkdir -p "$d" && printf '%s' "$input" > "$d/claude.json.tmp" && mv "$d/claude.json.tmp" "$d/claude.json" ;;
esac
orig=$(cat "$d/statusline-original" 2>/dev/null)
if [ -n "$orig" ]; then printf '%s' "$input" | sh -c "$orig"; fi
"#.to_string();
    let command = path.display().to_string();
    (path, body, command)
}

fn current_command() -> Option<String> {
    let v: Value = serde_json::from_str(&fs::read_to_string(settings()).ok()?).ok()?;
    v.get("statusLine")?.get("command")?.as_str().map(String::from)
}

pub fn is_installed() -> bool {
    current_command().map(|c| c.contains("claude-tee")).unwrap_or(false)
}

pub fn install() -> Result<(), String> {
    let (path, body, command) = script();
    fs::create_dir_all(tokenbar_dir()).map_err(|e| e.to_string())?;
    fs::write(&path, body).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o755));
    }
    if is_installed() { return Ok(()) }

    let original = current_command().unwrap_or_default();
    fs::write(tokenbar_dir().join("statusline-original"), &original).map_err(|e| e.to_string())?;

    // Muda só a statusline; o resto do settings.json fica como estava (com backup).
    let file = settings();
    let mut v: Value = fs::read_to_string(&file).ok().and_then(|s| {
        let _ = fs::write(file.with_extension("json.tokenbar-backup"), &s);
        serde_json::from_str(&s).ok()
    }).unwrap_or_else(|| serde_json::json!({}));
    v["statusLine"] = serde_json::json!({ "type": "command", "command": command });
    if let Some(dir) = file.parent() { let _ = fs::create_dir_all(dir); }
    fs::write(&file, serde_json::to_string_pretty(&v).unwrap()).map_err(|e| e.to_string())
}
