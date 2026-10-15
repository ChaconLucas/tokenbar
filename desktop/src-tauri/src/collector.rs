//! Lê os limites do disco: Claude Code (cópia da statusline), Codex (sessões) e qualquer outra IA
//! (~/.tokenbar/providers/*.json). Mesmo formato que o app do Mac manda para celular e servidor.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

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
    let account = if claude_login_on() { claude_account(false).ok() } else { None };
    // Statusline e login dizem a mesma coisa; vale o mais recente.
    let claude = match (read_claude(), account) {
        (Some(a), Some(b)) => Some(if b.observed_at > a.observed_at { b } else { a }),
        (a, b) => a.or(b),
    };
    let mut providers: Vec<ProviderUsage> = [claude, read_codex()].into_iter().flatten().collect();
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

// ---------- Claude pelo login (painel do VS Code não roda a statusline) ----------

const LOGIN_EXPIRED: &str = "Login do Claude expirado: abra o Claude Code uma vez.";
const LOGIN_MISSING: &str = "Não achei o login do Claude Code neste computador.";

struct Account { at: Option<Instant>, last: Option<ProviderUsage>, error: Option<String> }
static ACCOUNT: Mutex<Account> = Mutex::new(Account { at: None, last: None, error: None });

/// Ligado = existe ~/.tokenbar/claude-login (desligado por padrão).
fn claude_login_flag() -> PathBuf { tokenbar_dir().join("claude-login") }
pub fn claude_login_on() -> bool { claude_login_flag().exists() }

pub fn set_claude_login(on: bool) -> Result<(), String> {
    let flag = claude_login_flag();
    if on {
        fs::create_dir_all(tokenbar_dir()).map_err(|e| e.to_string())?;
        fs::write(&flag, b"").map_err(|e| e.to_string())?;
        claude_account(true).map(|_| ())
    } else {
        let _ = fs::remove_file(&flag);
        *ACCOUNT.lock().unwrap() = Account { at: None, last: None, error: None };
        Ok(())
    }
}

pub fn claude_login_error() -> Option<String> { ACCOUNT.lock().unwrap().error.clone() }

/// Uso do Claude pela API da conta, no máximo uma chamada a cada 5 min; entre elas (ou se falhar) fica o último bom.
pub fn claude_account(force: bool) -> Result<ProviderUsage, String> {
    {
        let mut acc = ACCOUNT.lock().unwrap();
        let fresh = acc.at.map(|t| t.elapsed() < Duration::from_secs(300)).unwrap_or(false);
        if fresh && !force { return acc.last.clone().ok_or_else(|| acc.error.clone().unwrap_or_else(|| LOGIN_MISSING.into())) }
        acc.at = Some(Instant::now());
    }
    let got = fetch_account();   // sem segurar a trava: a rede pode levar até 15 s
    let mut acc = ACCOUNT.lock().unwrap();
    match got {
        Ok(p) => { acc.last = Some(p.clone()); acc.error = None; Ok(p) }
        Err(e) => {
            acc.error = Some(e.clone());
            if force { return Err(e) }
            acc.last.clone().ok_or(e)
        }
    }
}

/// Só LÊ o arquivo do login; o token vai apenas no cabeçalho e nunca aparece em erro ou log.
fn fetch_account() -> Result<ProviderUsage, String> {
    let file = std::env::var_os("TOKENBAR_CLAUDE_CREDENTIALS").map(PathBuf::from)
        .or_else(|| std::env::var_os("CLAUDE_CONFIG_DIR").map(|d| PathBuf::from(d).join(".credentials.json")))
        .unwrap_or_else(|| home().join(".claude").join(".credentials.json"));
    let text = fs::read_to_string(&file).map_err(|_| LOGIN_MISSING.to_string())?;
    let creds: Value = serde_json::from_str(&text).map_err(|_| LOGIN_MISSING.to_string())?;
    let oauth = creds.get("claudeAiOauth").ok_or_else(|| LOGIN_MISSING.to_string())?;
    let token = oauth.get("accessToken").and_then(|v| v.as_str()).filter(|t| !t.is_empty())
        .ok_or_else(|| LOGIN_MISSING.to_string())?;
    if num(oauth.get("expiresAt")).map(|ms| ms / 1000.0 <= now()).unwrap_or(false) { return Err(LOGIN_EXPIRED.into()) }
    let resp = ureq::get("https://api.anthropic.com/api/oauth/usage")
        .set("Authorization", &format!("Bearer {token}"))
        .set("anthropic-beta", "oauth-2025-04-20")
        .timeout(Duration::from_secs(15))
        .call();
    let body: Value = match resp {
        Ok(r) => r.into_json().map_err(|_| "Resposta inválida da Anthropic.".to_string())?,
        Err(ureq::Error::Status(401, _)) => return Err(LOGIN_EXPIRED.into()),
        Err(ureq::Error::Status(code, _)) => return Err(format!("A Anthropic respondeu {code}.")),
        Err(_) => return Err("Sem conexão com a Anthropic.".into()),
    };
    parse_account(&body, now()).ok_or_else(|| "Resposta sem limites do Claude.".to_string())
}

fn parse_account(body: &Value, observed_at: f64) -> Option<ProviderUsage> {
    let mut windows = vec![];
    for (key, label, minutes) in [("five_hour", "5h", 300), ("seven_day", "7d", 10080)] {
        let w = match body.get(key) { Some(w) => w, None => continue };
        let pct = match num(w.get("utilization")) { Some(p) => p, None => continue };
        let resets = w.get("resets_at").and_then(|v| v.as_str()).and_then(rfc3339);
        windows.push(UsageWindow { id: key.into(), label: label.into(), used_percent: pct,
                                   resets_at: resets, window_minutes: Some(minutes) });
    }
    if windows.is_empty() { return None }
    Some(ProviderUsage { id: "claude".into(), name: "Claude Code".into(), windows, observed_at, color: None })
}

/// "2026-10-15T20:39:59.523289+00:00" (ou "Z") → segundos Unix.
fn rfc3339(s: &str) -> Option<f64> {
    let b = s.as_bytes();
    if b.len() < 20 || b[4] != b'-' || b[7] != b'-' || !matches!(b[10], b'T' | b't' | b' ') || b[13] != b':' || b[16] != b':' { return None }
    let n = |r: std::ops::Range<usize>| s.get(r)?.parse::<i64>().ok();
    let (y, mo, d, h, mi, se) = (n(0..4)?, n(5..7)?, n(8..10)?, n(11..13)?, n(14..16)?, n(17..19)?);
    let mut i = 19;
    let mut frac = 0.0;
    if b.get(i) == Some(&b'.') {
        let start = i;
        i += 1;
        while b.get(i).map(|c| c.is_ascii_digit()).unwrap_or(false) { i += 1 }
        frac = s.get(start..i)?.parse::<f64>().ok()?;
    }
    let offset = match s.get(i..)? {
        "Z" | "z" => 0,
        o if o.len() == 6 && (o.starts_with('+') || o.starts_with('-')) && o.as_bytes()[3] == b':' => {
            let v = n(i + 1..i + 3)? * 3600 + n(i + 4..i + 6)? * 60;
            if o.starts_with('-') { -v } else { v }
        }
        _ => return None,
    };
    // Dias desde 1970-01-01 (algoritmo de Howard Hinnant).
    let yy = if mo <= 2 { y - 1 } else { y };
    let era = yy.div_euclid(400);
    let yoe = yy - era * 400;
    let doy = (153 * ((mo + 9) % 12) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some((days * 86400 + h * 3600 + mi * 60 + se - offset) as f64 + frac)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn datas() {
        assert_eq!(rfc3339("1970-01-01T00:00:00Z"), Some(0.0));
        assert_eq!(rfc3339("2026-10-15T20:39:59+00:00"), Some(1792096799.0));
        assert_eq!(rfc3339("2026-10-15T17:39:59-03:00"), Some(1792096799.0));
        let t = rfc3339("2026-10-15T20:39:59.523289+00:00").unwrap();
        assert!((t - 1792096799.523289).abs() < 1e-5);
        assert_eq!(rfc3339("ontem"), None);
    }

    #[test]
    fn resposta_da_conta() {
        let body: Value = serde_json::from_str(r#"{"five_hour":{"utilization":20.0,"resets_at":"2026-10-15T20:39:59.523289+00:00"},
            "seven_day":{"utilization":25.0,"resets_at":"2026-10-21T04:59:59.523310+00:00"},"seven_day_opus":null}"#).unwrap();
        let p = parse_account(&body, 100.0).unwrap();
        assert_eq!(p.id, "claude");
        assert_eq!(p.observed_at, 100.0);
        assert_eq!(p.windows.len(), 2);
        assert_eq!((p.windows[0].id.as_str(), p.windows[0].label.as_str(), p.windows[0].used_percent, p.windows[0].window_minutes), ("five_hour", "5h", 20.0, Some(300)));
        assert_eq!((p.windows[1].id.as_str(), p.windows[1].label.as_str(), p.windows[1].used_percent, p.windows[1].window_minutes), ("seven_day", "7d", 25.0, Some(10080)));
        assert!((p.windows[1].resets_at.unwrap() - rfc3339("2026-10-21T04:59:59Z").unwrap() - 0.52331).abs() < 1e-4);
        assert!(parse_account(&serde_json::json!({"five_hour": null}), 0.0).is_none());
    }

    #[test]
    fn login_ausente_ou_vencido() {
        let dir = std::env::temp_dir().join(format!("tokenbar-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let f = dir.join("creds.json");
        std::env::set_var("TOKENBAR_CLAUDE_CREDENTIALS", &f);
        assert_eq!(fetch_account().unwrap_err(), LOGIN_MISSING);
        fs::write(&f, r#"{"claudeAiOauth":{"accessToken":"falso","expiresAt":1000}}"#).unwrap();
        assert_eq!(fetch_account().unwrap_err(), LOGIN_EXPIRED);
        if std::env::var_os("TOKENBAR_TEST_NET").is_some() {   // token falso: a API devolve 401
            fs::write(&f, r#"{"claudeAiOauth":{"accessToken":"falso","expiresAt":99999999999999}}"#).unwrap();
            assert_eq!(fetch_account().unwrap_err(), LOGIN_EXPIRED);
        }
        let _ = fs::remove_dir_all(&dir);
    }
}
