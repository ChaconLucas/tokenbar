//! Lê os limites do disco: Claude Code (cópia da statusline), Codex (sessões) e qualquer outra IA
//! (~/.tokenbar/providers/*.json). Mesmo formato que o app do Mac manda para celular e servidor.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Serialize, Deserialize, Clone, PartialEq, Debug)]
#[serde(rename_all = "camelCase")]
pub struct UsageWindow {
    pub id: String,
    pub label: String,
    pub used_percent: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resets_at: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub window_minutes: Option<i64>,
}

#[derive(Serialize, Deserialize, Clone, PartialEq, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ProviderUsage {
    pub id: String,
    pub name: String,
    pub windows: Vec<UsageWindow>,
    pub observed_at: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, PartialEq, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub struct UsageSnapshot {
    pub providers: Vec<ProviderUsage>,
    pub updated_at: f64,
}

pub fn now() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

pub fn home() -> PathBuf { dirs::home_dir().unwrap_or_else(|| PathBuf::from(".")) }
pub fn tokenbar_dir() -> PathBuf { home().join(".tokenbar") }

fn modified(p: &Path) -> f64 {
    fs::metadata(p).and_then(|m| m.modified()).ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map(|d| d.as_secs_f64()).unwrap_or_else(now)
}

fn num(v: Option<&Value>) -> Option<f64> {
    match v? {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

pub fn collect() -> UsageSnapshot {
    let mut providers: Vec<ProviderUsage> = [read_claude(), read_codex()].into_iter().flatten().collect();
    providers.extend(read_extra());
    UsageSnapshot { providers, updated_at: now() }
}

/// O JSON que o Claude Code entrega à statusline; o script do TokenBar guarda uma cópia.
fn read_claude() -> Option<ProviderUsage> {
    let file = tokenbar_dir().join("claude.json");
    let root: Value = serde_json::from_str(&fs::read_to_string(&file).ok()?).ok()?;
    let limits = root.get("rate_limits")?;
    let mut windows = vec![];
    for (key, label, minutes) in [("five_hour", "5h", 300), ("seven_day", "7d", 10080)] {
        let w = match limits.get(key) { Some(w) => w, None => continue };
        let pct = match num(w.get("used_percentage")) { Some(p) => p, None => continue };
        windows.push(UsageWindow { id: key.into(), label: label.into(), used_percent: pct,
                                   resets_at: num(w.get("resets_at")), window_minutes: Some(minutes) });
    }
    if windows.is_empty() { return None }
    Some(ProviderUsage { id: "claude".into(), name: "Claude Code".into(), windows, observed_at: modified(&file), color: None })
}

/// Sessões do Codex: o último evento `token_count` com `rate_limits`.
fn read_codex() -> Option<ProviderUsage> {
    let root = home().join(".codex").join("sessions");
    for file in recent_files(&root, "jsonl", 5) {
        let line = match last_line_with(&file, "\"rate_limits\"") { Some(l) => l, None => continue };
        let obj: Value = match serde_json::from_str(&line) { Ok(v) => v, Err(_) => continue };
        let limits = match obj.get("payload").and_then(|p| p.get("rate_limits")) { Some(l) => l, None => continue };
        let mut windows = vec![];
        for key in ["primary", "secondary"] {
            let w = match limits.get(key) { Some(w) if !w.is_null() => w, _ => continue };
            let pct = match num(w.get("used_percent")) { Some(p) => p, None => continue };
            let minutes = num(w.get("window_minutes")).map(|m| m as i64);
            let label = minutes.map(|m| if m % 1440 == 0 { format!("{}d", m / 1440) } else if m % 60 == 0 { format!("{}h", m / 60) } else { format!("{m}m") })
                .unwrap_or_else(|| key.into());
            let resets = num(w.get("resets_at"))
                .or_else(|| num(w.get("resets_in_seconds")).map(|s| modified(&file) + s));
            windows.push(UsageWindow { id: key.into(), label, used_percent: pct, resets_at: resets, window_minutes: minutes });
        }
        if windows.is_empty() { continue }
        return Some(ProviderUsage { id: "codex".into(), name: "Codex".into(), windows, observed_at: modified(&file), color: None });
    }
    None
}

/// Qualquer IA: um JSON por arquivo em ~/.tokenbar/providers/ (formato em docs/providers.md).
fn read_extra() -> Vec<ProviderUsage> {
    let dir = tokenbar_dir().join("providers");
    let mut files: Vec<PathBuf> = fs::read_dir(&dir).map(|r| r.flatten().map(|e| e.path())
        .filter(|p| p.extension().map(|e| e == "json").unwrap_or(false)).collect()).unwrap_or_default();
    files.sort();
    files.iter().filter_map(|f| {
        let o: Value = serde_json::from_str(&fs::read_to_string(f).ok()?).ok()?;
        let id = o.get("id")?.as_str()?.to_string();
        if id.is_empty() || id == "claude" || id == "codex" { return None }
        let windows: Vec<UsageWindow> = o.get("windows")?.as_array()?.iter().enumerate().filter_map(|(i, w)| {
            Some(UsageWindow {
                id: w.get("id").and_then(|v| v.as_str()).map(String::from).unwrap_or(format!("w{i}")),
                label: w.get("label").and_then(|v| v.as_str()).unwrap_or("").into(),
                used_percent: num(w.get("usedPercent"))?,
                resets_at: num(w.get("resetsAt")),
                window_minutes: num(w.get("windowMinutes")).map(|m| m as i64),
            })
        }).take(2).collect();
        if windows.is_empty() { return None }
        Some(ProviderUsage {
            name: o.get("name").and_then(|v| v.as_str()).unwrap_or(&id).into(),
            observed_at: num(o.get("observedAt")).unwrap_or_else(|| modified(f)),
            color: o.get("color").and_then(|v| v.as_str()).map(String::from),
            id, windows,
        })
    }).collect()
}

/// Desce pelas pastas de data mais novas primeiro (AAAA/MM/DD), sem varrer tudo.
fn recent_files(root: &Path, ext: &str, limit: usize) -> Vec<PathBuf> {
    fn children(d: &Path) -> Vec<PathBuf> {
        let mut v: Vec<PathBuf> = fs::read_dir(d).map(|r| r.flatten().map(|e| e.path()).collect()).unwrap_or_default();
        v.sort(); v.reverse(); v
    }
    let mut found = vec![];
    'outer: for y in children(root) { for m in children(&y) { for d in children(&m) {
        found.extend(children(&d).into_iter().filter(|p| p.extension().map(|e| e == ext).unwrap_or(false)));
        if found.len() >= limit * 3 { break 'outer }
    } } }
    found.sort_by(|a, b| modified(b).partial_cmp(&modified(a)).unwrap());
    found.truncate(limit);
    found
}

/// Lê só o fim do arquivo (sessões passam de dezenas de MB).
fn last_line_with(path: &Path, needle: &str) -> Option<String> {
    let mut f = fs::File::open(path).ok()?;
    let size = f.metadata().ok()?.len();
    let mut chunk: u64 = 256 * 1024;
    loop {
        let start = size.saturating_sub(chunk);
        f.seek(SeekFrom::Start(start)).ok()?;
        let mut buf = Vec::new();
        f.read_to_end(&mut buf).ok()?;
        let text = String::from_utf8_lossy(&buf);
        let mut lines: Vec<&str> = text.lines().collect();
        if start > 0 && !lines.is_empty() { lines.remove(0); }
        if let Some(l) = lines.iter().rev().find(|l| l.contains(needle)) { return Some(l.to_string()) }
        if start == 0 || chunk >= 8 * 1024 * 1024 { return None }
        chunk *= 4;
    }
}
