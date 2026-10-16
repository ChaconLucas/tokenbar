//! Lê os limites do disco: Claude Code (cópia da statusline), Codex (sessões) e qualquer outra IA
//! (~/.tokenbar/providers/*.json), Windsurf (banco de estado do editor) e, se ligado, GitHub Copilot
//! (API do GitHub com o login do gh). Mesmo formato que o app do Mac manda para celular e servidor.

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

pub fn num(v: Option<&Value>) -> Option<f64> {
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
    let copilot = if copilot_on() { copilot_usage(false).ok().flatten() } else { None };
    let mut providers: Vec<ProviderUsage> = [claude, read_codex(), copilot, read_windsurf()].into_iter().flatten().collect();
    providers.extend(read_extra());
    // Cursor, GLM, MiniMax, Kimi, OpenRouter, Droid: um arquivo em providers/ com o mesmo id repetiria.
    let net = crate::connectors::usages();
    providers.retain(|p| !crate::connectors::on(&p.id));
    providers.extend(net);
    UsageSnapshot { providers, updated_at: now() }
}

/// O JSON que o Claude Code entrega à statusline; o script do TokenBar guarda uma cópia.
fn read_claude() -> Option<ProviderUsage> {
    let file = tokenbar_dir().join("claude.json");
    let root: Value = serde_json::from_str(&fs::read_to_string(&file).ok()?).ok()?;
    let limits = root.get("rate_limits")?;
    // Janela que acabou de resetar some do JSON: entra zerada, para 5h e 7d nunca trocarem de lugar.
    let mut windows = vec![];
    let mut found = false;
    for (key, label, minutes) in [("five_hour", "5h", 300), ("seven_day", "7d", 10080)] {
        let w = limits.get(key);
        match w.and_then(|w| num(w.get("used_percentage"))) {
            Some(pct) => {
                found = true;
                windows.push(UsageWindow { id: key.into(), label: label.into(), used_percent: pct,
                                           resets_at: w.and_then(|w| num(w.get("resets_at"))), window_minutes: Some(minutes) });
            }
            None => windows.push(UsageWindow { id: key.into(), label: label.into(), used_percent: 0.0,
                                               resets_at: None, window_minutes: Some(minutes) }),
        }
    }
    if !found { return None }
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
    let mut found = false;
    for (key, label, minutes) in [("five_hour", "5h", 300), ("seven_day", "7d", 10080)] {
        let w = body.get(key);
        match w.and_then(|w| num(w.get("utilization"))) {
            Some(pct) => {
                found = true;
                let resets = w.and_then(|w| w.get("resets_at")).and_then(|v| v.as_str()).and_then(rfc3339);
                windows.push(UsageWindow { id: key.into(), label: label.into(), used_percent: pct,
                                           resets_at: resets, window_minutes: Some(minutes) });
            }
            None => windows.push(UsageWindow { id: key.into(), label: label.into(), used_percent: 0.0,
                                               resets_at: None, window_minutes: Some(minutes) }),
        }
    }
    if !found { windows.clear(); }
    if windows.is_empty() { return None }
    Some(ProviderUsage { id: "claude".into(), name: "Claude Code".into(), windows, observed_at, color: None })
}

/// "2026-10-15T20:39:59.523289+00:00" (ou "Z") → segundos Unix.
pub fn rfc3339(s: &str) -> Option<f64> {
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

// ---------- GitHub Copilot (opcional: usa o token do gh) ----------

const GH_MISSING: &str = "Não achei o login do GitHub (gh auth login) nem do Copilot neste computador.";
const GH_EXPIRED: &str = "Login do GitHub expirado: rode gh auth login.";
const GH_FORMAT: &str = "Resposta inesperada do GitHub.";
const GH_OFFLINE: &str = "Sem conexão com o GitHub.";

struct Copilot { at: Option<Instant>, last: Option<ProviderUsage>, error: Option<String> }
static COPILOT: Mutex<Copilot> = Mutex::new(Copilot { at: None, last: None, error: None });

/// Ligado = existe ~/.tokenbar/copilot-on (desligado por padrão).
fn copilot_flag() -> PathBuf { tokenbar_dir().join("copilot-on") }
pub fn copilot_on() -> bool { copilot_flag().exists() }

pub fn set_copilot(on: bool) -> Result<(), String> {
    let flag = copilot_flag();
    if on {
        fs::create_dir_all(tokenbar_dir()).map_err(|e| e.to_string())?;
        fs::write(&flag, b"").map_err(|e| e.to_string())?;
        copilot_usage(true).map(|_| ()).map_err(|e| copilot_tr(&e))
    } else {
        let _ = fs::remove_file(&flag);
        *COPILOT.lock().unwrap() = Copilot { at: None, last: None, error: None };
        Ok(())
    }
}

/// Erro da última leitura, já no idioma do app.
pub fn copilot_error() -> Option<String> { COPILOT.lock().unwrap().error.as_deref().map(copilot_tr) }

fn copilot_tr(msg: &str) -> String {
    if crate::i18n::lang() != "en" { return msg.to_string() }
    if let Some(code) = msg.strip_prefix("O GitHub respondeu ").and_then(|r| r.strip_suffix('.')) { return format!("GitHub responded {code}.") }
    match msg {
        GH_MISSING => "Couldn't find a GitHub (gh auth login) or Copilot login on this computer.",
        GH_EXPIRED => "GitHub login expired: run gh auth login.",
        GH_FORMAT => "Unexpected response from GitHub.",
        GH_OFFLINE => "Can't reach GitHub.",
        _ => msg,
    }.to_string()
}

/// No máximo uma chamada a cada 5 min; entre elas (ou se falhar) fica o último bom. Ok(None) = conta sem limite.
pub fn copilot_usage(force: bool) -> Result<Option<ProviderUsage>, String> {
    {
        let mut c = COPILOT.lock().unwrap();
        let fresh = c.at.map(|t| t.elapsed() < Duration::from_secs(300)).unwrap_or(false);
        if fresh && !force {
            return match (&c.last, &c.error) { (Some(p), _) => Ok(Some(p.clone())), (None, Some(e)) => Err(e.clone()), _ => Ok(None) };
        }
        c.at = Some(Instant::now());
    }
    let got = fetch_copilot();   // sem segurar a trava: a rede pode levar até 15 s
    let mut c = COPILOT.lock().unwrap();
    match got {
        Ok(p) => { c.last = p.clone(); c.error = None; Ok(p) }
        Err(e) => {
            c.error = Some(e.clone());
            if force { return Err(e) }
            c.last.clone().map(Some).ok_or(e)
        }
    }
}

/// Sem janela de console no Windows.
fn quiet(cmd: &mut std::process::Command) -> &mut std::process::Command {
    #[cfg(windows)]
    { use std::os::windows::process::CommandExt; cmd.creation_flags(0x0800_0000); }
    cmd
}

/// `gh auth token`; sem ele, o `oauth_token` que o plugin do Copilot guardou. O token nunca vai para erro ou log.
fn copilot_token() -> Option<String> {
    let mut ghs: Vec<PathBuf> = vec![];
    if cfg!(windows) {
        ghs.push("gh.exe".into());
        if let Some(pf) = std::env::var_os("ProgramFiles") { ghs.push(PathBuf::from(pf).join("GitHub CLI").join("gh.exe")) }
    } else {
        ghs.extend(["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh", "gh"].map(PathBuf::from));
    }
    for gh in ghs {
        let out = quiet(std::process::Command::new(&gh).args(["auth", "token", "--hostname", "github.com"])
            .stdin(std::process::Stdio::null()).stderr(std::process::Stdio::null())).output();
        if let Ok(o) = out {
            let tok = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if o.status.success() && !tok.is_empty() && !tok.contains(char::is_whitespace) { return Some(tok) }
        }
    }
    let dir = if cfg!(windows) { dirs::data_local_dir().map(|d| d.join("github-copilot")) }
              else { Some(home().join(".config").join("github-copilot")) };
    for name in ["apps.json", "hosts.json"] {
        let v: Value = match dir.as_ref().and_then(|d| fs::read_to_string(d.join(name)).ok()).and_then(|t| serde_json::from_str(&t).ok()) {
            Some(v) => v, None => continue };
        let obj = match v.as_object() { Some(o) => o, None => continue };
        let mut keys: Vec<&String> = obj.keys().collect();
        keys.sort_by_key(|k| (!k.starts_with("github.com"), k.as_str()));
        if let Some(t) = keys.iter().filter_map(|k| obj[k.as_str()].get("oauth_token")?.as_str()).find(|t| !t.is_empty()) {
            return Some(t.to_string())
        }
    }
    None
}

fn fetch_copilot() -> Result<Option<ProviderUsage>, String> {
    let token = copilot_token().ok_or_else(|| GH_MISSING.to_string())?;
    let resp = ureq::get("https://api.github.com/copilot_internal/user")
        .set("Authorization", &format!("token {token}"))
        .set("Accept", "application/json")
        .set("X-Github-Api-Version", "2025-04-01")
        .set("User-Agent", "TokenBar")
        .timeout(Duration::from_secs(15))
        .call();
    let body: Value = match resp {
        Ok(r) => r.into_json().map_err(|_| GH_FORMAT.to_string())?,
        Err(ureq::Error::Status(401, _)) => return Err(GH_EXPIRED.into()),
        Err(ureq::Error::Status(code, _)) => return Err(format!("O GitHub respondeu {code}.")),
        Err(_) => return Err(GH_OFFLINE.into()),
    };
    if !body.get("quota_snapshots").map(|q| q.is_object()).unwrap_or(false) { return Err(GH_FORMAT.into()) }
    Ok(parse_copilot(&body, now()))
}

/// Premium requests quando o plano tem; senão o chat (plano grátis). Ilimitado = None.
fn parse_copilot(body: &Value, observed_at: f64) -> Option<ProviderUsage> {
    let snaps = body.get("quota_snapshots")?;
    for key in ["premium_interactions", "chat"] {
        let q = match snaps.get(key) { Some(q) if q.is_object() => q, _ => continue };
        if q.get("unlimited").and_then(|v| v.as_bool()) == Some(true) { continue }
        if num(q.get("entitlement")).map(|e| e <= 0.0).unwrap_or(true) { continue }
        let left = match num(q.get("percent_remaining")) { Some(l) => l, None => continue };
        let resets = body.get("quota_reset_date_utc").and_then(|v| v.as_str()).and_then(rfc3339);
        return Some(ProviderUsage {
            id: "copilot".into(), name: "Copilot".into(), observed_at, color: Some("#3fb950".into()),
            windows: vec![UsageWindow { id: key.into(), label: "1M".into(), used_percent: (100.0 - left).max(0.0),
                                        resets_at: resets, window_minutes: None }],
        });
    }
    None
}

// ---------- Windsurf (banco de estado do editor, só leitura, sem rede) ----------

fn windsurf_db() -> Option<PathBuf> {
    let base = if cfg!(target_os = "macos") { home().join("Library").join("Application Support") }
               else if cfg!(windows) { dirs::config_dir()? }   // %APPDATA%
               else { home().join(".config") };
    Some(base.join("Windsurf").join("User").join("globalStorage").join("state.vscdb"))
}

fn read_windsurf() -> Option<ProviderUsage> {
    let file = windsurf_db()?;
    if !file.is_file() { return None }
    let json = sqlite_value(&file, "windsurf.settings.cachedPlanInfo", false)?;
    let root: Value = serde_json::from_str(&json).ok()?;
    let wal = file.with_file_name("state.vscdb-wal");
    let observed = if wal.is_file() { modified(&file).max(modified(&wal)) } else { modified(&file) };
    parse_windsurf(&root, observed)
}

/// "file:///C:/a%20b/state.vscdb?mode=ro&immutable=1": imutável = sem trava e sem gravar nada no arquivo do editor.
fn sqlite_uri(path: &Path, live: bool) -> String {
    let p = path.to_string_lossy().replace('\\', "/");
    let mut out = String::from("file://");
    if !p.starts_with('/') { out.push('/') }
    for b in p.bytes() {
        if b.is_ascii_alphanumeric() || b"/:-._~".contains(&b) { out.push(b as char) } else { out.push_str(&format!("%{b:02X}")) }
    }
    out + if live { "?mode=ro" } else { "?mode=ro&immutable=1" }
}

/// `live`: só leitura, mas enxergando o WAL (valor que o editor acabou de trocar, como um token renovado).
pub fn sqlite_value(path: &Path, key: &str, live: bool) -> Option<String> {
    if live { if let Some(v) = sqlite_read(path, key, true) { return Some(v) } }
    sqlite_read(path, key, false)
}

fn sqlite_read(path: &Path, key: &str, live: bool) -> Option<String> {
    use rusqlite::{types::ValueRef, Connection, OpenFlags};
    let db = Connection::open_with_flags(sqlite_uri(path, live),
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_URI | OpenFlags::SQLITE_OPEN_NO_MUTEX).ok()?;
    db.query_row("SELECT value FROM ItemTable WHERE key = ?1", [key], |r| {
        Ok(match r.get_ref(0)? {
            // Alguns editores gravam em UTF-16LE (um zero a cada dois bytes).
            ValueRef::Blob(t) if t.len() >= 2 && t.len() % 2 == 0 && t[1] == 0 =>
                Some(String::from_utf16_lossy(&t.chunks(2).map(|c| u16::from_le_bytes([c[0], c[1]])).collect::<Vec<_>>())),
            ValueRef::Text(t) | ValueRef::Blob(t) => Some(String::from_utf8_lossy(t).into_owned()),
            _ => None,
        })
    }).ok().flatten()
}

/// Segundos ou milissegundos desde 1970.
fn epoch(v: f64) -> f64 { if v > 1e11 { v / 1000.0 } else { v } }

/// Formato novo: `quotaUsage` com % restante do dia e da semana. Antigo: `usage` com mensagens do mês.
fn parse_windsurf(root: &Value, observed_at: f64) -> Option<ProviderUsage> {
    let mut windows = vec![];
    if let Some(q) = root.get("quotaUsage") {
        for (key, label, minutes) in [("daily", "1d", 1440), ("weekly", "7d", 10080)] {
            let left = match num(q.get(format!("{key}RemainingPercent").as_str())) { Some(l) => l, None => continue };
            windows.push(UsageWindow { id: key.into(), label: label.into(), used_percent: (100.0 - left).max(0.0),
                                       resets_at: num(q.get(format!("{key}ResetAtUnix").as_str())).map(epoch),
                                       window_minutes: Some(minutes) });
        }
    }
    if windows.is_empty() {
        if let Some(u) = root.get("usage") {
            if let (Some(total), Some(used)) = (num(u.get("messages")), num(u.get("usedMessages"))) {
                if total > 0.0 {
                    let end = num(u.get("endTimestamp")).or_else(|| num(root.get("endTimestamp"))).map(epoch);
                    windows.push(UsageWindow { id: "month".into(), label: "1M".into(), used_percent: used / total * 100.0,
                                               resets_at: end, window_minutes: None });
                }
            }
        }
    }
    if windows.is_empty() { return None }
    Some(ProviderUsage { id: "windsurf".into(), name: "Windsurf".into(), windows, observed_at, color: Some("#14b8a6".into()) })
}

/// Ids que o próprio TokenBar lê; um arquivo com eles seria repetido.
const BUILT_IN: [&str; 4] = ["claude", "codex", "copilot", "windsurf"];

/// Qualquer IA: um JSON por arquivo em ~/.tokenbar/providers/ (formato em docs/providers.md).
fn read_extra() -> Vec<ProviderUsage> {
    let dir = tokenbar_dir().join("providers");
    let mut files: Vec<PathBuf> = fs::read_dir(&dir).map(|r| r.flatten().map(|e| e.path())
        .filter(|p| p.extension().map(|e| e == "json").unwrap_or(false)).collect()).unwrap_or_default();
    files.sort();
    files.iter().filter_map(|f| {
        let o: Value = serde_json::from_str(&fs::read_to_string(f).ok()?).ok()?;
        let id = o.get("id")?.as_str()?.to_string();
        if id.is_empty() || BUILT_IN.contains(&id.as_str()) { return None }
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

    #[test]
    fn copilot_cota() {
        let body: Value = serde_json::from_str(r#"{"quota_reset_date_utc":"2026-11-01T00:00:00.000Z","quota_snapshots":{
            "premium_interactions":{"entitlement":300,"percent_remaining":62.5,"unlimited":false},"chat":{"unlimited":true}}}"#).unwrap();
        let p = parse_copilot(&body, 1.0).unwrap();
        assert_eq!((p.id.as_str(), p.windows[0].id.as_str(), p.windows[0].label.as_str(), p.windows[0].used_percent), ("copilot", "premium_interactions", "1M", 37.5));
        assert_eq!(p.windows[0].resets_at, rfc3339("2026-11-01T00:00:00Z"));
        // plano grátis: premium zerado, vale o chat
        let free = serde_json::json!({"quota_snapshots":{"premium_interactions":{"entitlement":0,"percent_remaining":0.0,"unlimited":false},
            "chat":{"entitlement":200,"percent_remaining":80.0,"unlimited":false}}});
        assert_eq!(parse_copilot(&free, 0.0).unwrap().windows[0].used_percent, 20.0);
        let unlimited = serde_json::json!({"quota_snapshots":{"premium_interactions":{"unlimited":true},"chat":{"unlimited":true}}});
        assert!(parse_copilot(&unlimited, 0.0).is_none());
    }

    #[test]
    fn copilot_ao_vivo() {   // TOKENBAR_TEST_NET=1: chama a API com o login do gh; imprime só os números
        if std::env::var_os("TOKENBAR_TEST_NET").is_none() { return }
        match fetch_copilot() {
            Ok(Some(p)) => for w in &p.windows { println!("copilot {} {} {:.1}% reset {:?}", w.id, w.label, w.used_percent, w.resets_at) },
            Ok(None) => println!("copilot ilimitado"),
            Err(e) => println!("copilot erro: {e}"),
        }
    }

    #[test]
    fn windsurf_formatos() {
        let novo = serde_json::json!({"quotaUsage":{"dailyRemainingPercent":73,"weeklyRemainingPercent":41.5,"dailyResetAtUnix":1792108800,"weeklyResetAtUnix":1792540800}});
        let p = parse_windsurf(&novo, 5.0).unwrap();
        assert_eq!(p.windows.len(), 2);
        assert_eq!((p.windows[0].label.as_str(), p.windows[0].used_percent, p.windows[0].resets_at, p.windows[0].window_minutes), ("1d", 27.0, Some(1792108800.0), Some(1440)));
        assert_eq!((p.windows[1].label.as_str(), p.windows[1].used_percent, p.windows[1].window_minutes), ("7d", 58.5, Some(10080)));
        let antigo = serde_json::json!({"usage":{"messages":500,"usedMessages":125},"endTimestamp":1793491200000u64});
        let p = parse_windsurf(&antigo, 5.0).unwrap();
        assert_eq!((p.windows[0].label.as_str(), p.windows[0].used_percent, p.windows[0].resets_at), ("1M", 25.0, Some(1793491200.0)));
        assert!(parse_windsurf(&serde_json::json!({"planName":"Free"}), 0.0).is_none());
    }

    #[test]
    fn windsurf_sqlite() {
        let dir = std::env::temp_dir().join(format!("tokenbar ws {}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let f = dir.join("state.vscdb");
        let _ = fs::remove_file(&f);
        let db = rusqlite::Connection::open(&f).unwrap();
        db.execute_batch(r#"CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
            INSERT INTO ItemTable VALUES ('windsurf.settings.cachedPlanInfo', '{"quotaUsage":{"dailyRemainingPercent":90,"weeklyRemainingPercent":60}}');"#).unwrap();
        drop(db);
        let json = sqlite_value(&f, "windsurf.settings.cachedPlanInfo", false).unwrap();
        let p = parse_windsurf(&serde_json::from_str(&json).unwrap(), 0.0).unwrap();
        assert_eq!((p.windows[0].used_percent, p.windows[1].used_percent), (10.0, 40.0));
        assert!(sqlite_value(&f, "nada", false).is_none());
        assert!(sqlite_uri(Path::new(r"C:\Users\a b\x.db"), false).starts_with("file:///C:/Users/a%20b/x.db?"));
        let _ = fs::remove_dir_all(&dir);
    }
}
