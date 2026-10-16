//! IAs lidas pela rede: o Cursor pelo login que o próprio editor guardou; GLM (Z.ai), MiniMax, Kimi Code,
//! OpenRouter e Factory Droid por uma chave de API colada nos Ajustes. Mesma lógica do app do Mac
//! (App/macOS/Connectors.swift). A chave só vai para o site da própria IA, nunca para erro ou log.
//! Estado em ~/.tokenbar/connectors.json: { "cursor": true, "keys": { "zai": "…" } } (só o dono lê, no Linux).

use crate::collector::{home, now, num, sqlite_value, tokenbar_dir, ProviderUsage, UsageWindow};
use serde::Serialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs;
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub struct Def { pub id: &'static str, name: &'static str, title: &'static str, color: &'static str, needs_key: bool, info: &'static str }

pub const ALL: [Def; 6] = [
    Def { id: "cursor", name: "Cursor", title: "CURSOR", color: "#e5e5e5", needs_key: false,
          info: "Lê o uso do mês do plano usando o login que o Cursor já guardou neste computador. O token só vai para cursor.com." },
    Def { id: "zai", name: "GLM", title: "Z.AI GLM", color: "#3b82f6", needs_key: true,
          info: "Coding Plan do GLM: limites de 5 horas e da semana. Crie uma chave de API em z.ai (ou open.bigmodel.cn) e cole aqui. A chave só vai para a Z.ai." },
    Def { id: "minimax", name: "MiniMax", title: "MINIMAX", color: "#f43f5e", needs_key: true,
          info: "Coding Plan da MiniMax: janela atual e semana. Cole a chave do Coding Plan (sk-cp-…). A chave só vai para a MiniMax." },
    Def { id: "kimi", name: "Kimi", title: "KIMI CODE", color: "#8b5cf6", needs_key: true,
          info: "Kimi Code: limites de 5 horas e da semana. Crie uma chave no console do Kimi Code e cole aqui. A chave só vai para a Kimi." },
    Def { id: "openrouter", name: "OpenRouter", title: "OPENROUTER", color: "#6366f1", needs_key: true,
          info: "Quanto do limite da chave (ou dos créditos) já foi gasto. Cole uma chave de openrouter.ai/keys. A chave só vai para o OpenRouter." },
    Def { id: "factory", name: "Droid", title: "FACTORY DROID", color: "#f97316", needs_key: true,
          info: "Limites de 5 horas e da semana do Droid. Cole a chave de app.factory.ai/settings/api-keys (ou deixe em ~/.factory/.env). A chave só vai para a Factory." },
];

fn def(id: &str) -> Option<&'static Def> { ALL.iter().find(|d| d.id == id) }

// ---------- estado ----------

#[derive(Clone, Debug, PartialEq)]
enum Fail { NoLogin, Expired, NoKey, BadKey, Http(u16), Format, Offline }

impl Fail {
    fn text(&self, name: &str) -> String {
        let en = crate::i18n::lang() == "en";
        match (self, en) {
            (Fail::NoLogin, false) => "Não achei o login do Cursor neste computador: abra o Cursor e entre na conta.".into(),
            (Fail::NoLogin, true) => "Couldn't find a Cursor login on this computer: open Cursor and sign in.".into(),
            (Fail::Expired, false) => "Login do Cursor expirado: abra o Cursor uma vez.".into(),
            (Fail::Expired, true) => "Cursor login expired: open Cursor once.".into(),
            (Fail::NoKey, false) => "Falta a chave de API.".into(),
            (Fail::NoKey, true) => "The API key is missing.".into(),
            (Fail::BadKey, false) => format!("{name} recusou a chave."),
            (Fail::BadKey, true) => format!("{name} rejected the key."),
            (Fail::Http(c), false) => format!("{name} respondeu {c}."),
            (Fail::Http(c), true) => format!("{name} responded {c}."),
            (Fail::Format, false) => format!("Resposta inesperada de {name}."),
            (Fail::Format, true) => format!("Unexpected response from {name}."),
            (Fail::Offline, false) => format!("Sem conexão com {name}."),
            (Fail::Offline, true) => format!("Can't reach {name}."),
        }
    }
}

#[derive(Default)]
struct Entry { at: Option<Instant>, last: Option<ProviderUsage>, error: Option<Fail>, busy: bool }
static STATE: Mutex<Option<HashMap<&'static str, Entry>>> = Mutex::new(None);

fn with<R>(id: &'static str, f: impl FnOnce(&mut Entry) -> R) -> R {
    let mut g = STATE.lock().unwrap();
    f(g.get_or_insert_with(HashMap::new).entry(id).or_default())
}

fn file() -> std::path::PathBuf { tokenbar_dir().join("connectors.json") }
fn load() -> Value { fs::read_to_string(file()).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_else(|| json!({})) }

fn save(v: &Value) -> Result<(), String> {
    fs::create_dir_all(tokenbar_dir()).map_err(|e| e.to_string())?;
    let tmp = file().with_extension("tmp");
    fs::write(&tmp, serde_json::to_vec_pretty(v).unwrap_or_default()).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    { use std::os::unix::fs::PermissionsExt; let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600)); }
    fs::rename(&tmp, file()).map_err(|e| e.to_string())
}

fn key(id: &str) -> Option<String> {
    load().get("keys").and_then(|k| k.get(id)).and_then(|v| v.as_str()).filter(|s| !s.is_empty()).map(String::from)
}

pub fn on(id: &str) -> bool {
    match def(id) {
        Some(d) if d.needs_key => key(id).is_some(),
        Some(_) => load().get(id).and_then(|v| v.as_bool()).unwrap_or(false),
        None => false,
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status { id: &'static str, title: &'static str, info: String, needs_key: bool, on: bool, error: Option<String> }

pub fn statuses() -> Vec<Status> {
    ALL.iter().map(|d| {
        let on = on(d.id);
        let error = if on { with(d.id, |e| e.error.clone()).map(|f| f.text(d.name)) } else { None };
        Status { id: d.id, title: d.title, info: d.info.into(), needs_key: d.needs_key, on, error }
    }).collect()
}

/// Liga/desliga o Cursor, ou guarda/apaga a chave (None ou vazio apaga). Ao ligar, já tenta uma leitura.
pub fn set(id: &str, on_: bool, new_key: Option<String>) -> Result<(), String> {
    let d = def(id).ok_or("?")?;
    let mut v = load();
    if !v.is_object() { v = json!({}) }
    if d.needs_key {
        let mut k = new_key.map(|k| k.trim().to_string()).filter(|k| !k.is_empty());
        if on_ && k.is_none() && d.id == "factory" { k = factory_env_key() }
        if on_ && k.is_none() { return Err(Fail::NoKey.text(d.name)) }
        if !v.get("keys").map(|k| k.is_object()).unwrap_or(false) { v["keys"] = json!({}) }
        match k.filter(|_| on_) { Some(k) => { v["keys"][d.id] = json!(k) }, None => { v["keys"].as_object_mut().unwrap().remove(d.id); } }
    } else {
        v[d.id] = json!(on_);
    }
    save(&v)?;
    with(d.id, |e| *e = Entry::default());
    if !on_ { return Ok(()) }
    refresh(d);
    match with(d.id, |e| e.error.clone()) { Some(f) => Err(f.text(d.name)), None => Ok(()) }
}

/// Os números das IAs ligadas. Leitura velha (5 min) é renovada numa thread; até lá fica o último bom.
pub fn usages() -> Vec<ProviderUsage> {
    ALL.iter().filter(|d| on(d.id)).filter_map(|d| {
        let stale = with(d.id, |e| {
            let s = !e.busy && e.at.map(|t| t.elapsed() > Duration::from_secs(300)).unwrap_or(true);
            if s { e.busy = true }
            s
        });
        if stale { std::thread::spawn(move || refresh(d)); }
        with(d.id, |e| e.last.clone())
    }).collect()
}

fn refresh(d: &'static Def) {
    with(d.id, |e| { e.busy = true; e.at = Some(Instant::now()) });
    let got = fetch(d);
    with(d.id, |e| {
        e.busy = false;
        match got { Ok(p) => { e.last = p; e.error = None } Err(f) => e.error = Some(f) }
    });
}

// ---------- rede ----------

/// Tenta os endereços em ordem (internacional, depois China): vale o primeiro 200.
/// 401/403/404 passam para o próximo; se todos recusam, a chave é que está errada.
fn first_ok(d: &Def, urls: &[String], headers: &[(&str, String)]) -> Result<Value, Fail> {
    let (mut refused, mut last) = (false, 0);
    for u in urls {
        let mut req = ureq::get(u).timeout(Duration::from_secs(15)).set("User-Agent", "TokenBar");
        for (k, v) in headers { req = req.set(k, v) }
        match req.call() {
            Ok(r) => return r.into_json().map_err(|_| Fail::Format),
            Err(ureq::Error::Status(401 | 403, _)) => refused = true,
            Err(ureq::Error::Status(404, _)) => last = 404,
            Err(ureq::Error::Status(c, _)) => return Err(Fail::Http(c)),
            Err(_) => return Err(Fail::Offline),
        }
    }
    if refused { return Err(if d.needs_key { Fail::BadKey } else { Fail::Expired }) }
    Err(Fail::Http(last))
}

fn fetch(d: &Def) -> Result<Option<ProviderUsage>, Fail> {
    let k = if d.needs_key { key(d.id).ok_or(Fail::NoKey)? } else { String::new() };
    let bearer = vec![("Authorization", format!("Bearer {k}")), ("Accept", "application/json".into())];
    let urls = |hosts: &[&str], paths: &[&str]| -> Vec<String> {
        hosts.iter().flat_map(|h| paths.iter().map(move |p| format!("{h}{p}"))).collect()
    };
    let t = now();
    match d.id {
        "cursor" => fetch_cursor(d),
        "zai" => Ok(parse_zai(&first_ok(d, &urls(&["https://api.z.ai", "https://open.bigmodel.cn"], &["/api/monitor/usage/quota/limit"]), &bearer)?, t)),
        "minimax" => {
            let root = first_ok(d, &urls(&["https://api.minimax.io", "https://api.minimaxi.com"],
                                        &["/v1/token_plan/remains", "/v1/api/openplatform/coding_plan/remains"]), &bearer)?;
            let base = root.get("base_resp").or_else(|| root.get("data").and_then(|x| x.get("base_resp")));
            if let Some(code) = base.and_then(|b| num(b.get("status_code"))) {
                if code == 1004.0 { return Err(Fail::BadKey) }
                if code != 0.0 { return Err(Fail::Format) }
            }
            Ok(parse_minimax(&root, t))
        }
        "kimi" => Ok(parse_kimi(&first_ok(d, &urls(&["https://api.kimi.com", "https://api.kimi.ai"], &["/coding/v1/usages"]), &bearer)?, t)),
        "openrouter" => {
            let info = first_ok(d, &["https://openrouter.ai/api/v1/key".into()], &bearer)?;
            if let Some(p) = parse_openrouter_key(&info, t) { return Ok(Some(p)) }
            Ok(parse_openrouter_credits(&first_ok(d, &["https://openrouter.ai/api/v1/credits".into()], &bearer)?, t))
        }
        "factory" => {
            let mut h = bearer.clone();
            h.push(("Origin", "https://app.factory.ai".into()));
            h.push(("x-factory-client", "web-app".into()));
            let root = first_ok(d, &["https://api.factory.ai/api/billing/limits".into()], &h)?;
            if let Some(p) = parse_factory(&root, t) { return Ok(Some(p)) }
            Ok(parse_factory_legacy(&first_ok(d, &["https://api.factory.ai/api/organization/subscription/usage?useCache=true".into()], &h)?, t))
        }
        _ => Ok(None),
    }
}

// ---------- Cursor ----------

fn cursor_db() -> Option<std::path::PathBuf> {
    let base = if cfg!(target_os = "macos") { home().join("Library").join("Application Support") }
               else if cfg!(windows) { dirs::config_dir()? }   // %APPDATA%
               else { home().join(".config") };
    Some(base.join("Cursor").join("User").join("globalStorage").join("state.vscdb"))
}

pub fn jwt_claims(jwt: &str) -> Option<Value> {
    use base64::Engine;
    let part = jwt.split('.').nth(1)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(part.trim_end_matches('=')).ok()?;
    serde_json::from_slice(&bytes).ok()
}

/// O token do editor (um JWT) vira o cookie de sessão do site: `<id do usuário>::<token>`.
fn fetch_cursor(d: &Def) -> Result<Option<ProviderUsage>, Fail> {
    let db = cursor_db().filter(|p| p.is_file()).ok_or(Fail::NoLogin)?;
    let token = sqlite_value(&db, "cursorAuth/accessToken", true).map(|t| t.trim_matches(|c| c == '"' || c == ' ' || c == '\n').to_string())
        .filter(|t| !t.is_empty()).ok_or(Fail::NoLogin)?;
    let claims = jwt_claims(&token).ok_or(Fail::NoLogin)?;
    let user = claims.get("sub").and_then(|s| s.as_str()).and_then(|s| s.split('|').last()).ok_or(Fail::NoLogin)?.to_string();
    if num(claims.get("exp")).map(|e| e < now() + 60.0).unwrap_or(false) { return Err(Fail::Expired) }
    let root = first_ok(d, &["https://cursor.com/api/usage-summary".into()],
                        &[("Accept", "application/json".into()), ("Cookie", format!("WorkosCursorSessionToken={user}%3A%3A{token}"))])?;
    Ok(parse_cursor(&root, now()))
}

// ---------- leitura das respostas ----------

fn label(minutes: Option<i64>) -> String {
    match minutes {
        Some(m) if m > 0 && m % 1440 == 0 => format!("{}d", m / 1440),
        Some(m) if m > 0 && m % 60 == 0 => format!("{}h", m / 60),
        Some(m) if m > 0 => format!("{m}m"),
        _ => String::new(),
    }
}

/// Segundos ou milissegundos desde 1970.
fn epoch(v: f64) -> f64 { if v > 1e11 { v / 1000.0 } else { v } }

fn iso(v: Option<&Value>) -> Option<f64> { v?.as_str().and_then(crate::collector::rfc3339) }

fn win(id: &str, label: String, pct: f64, resets_at: Option<f64>, window_minutes: Option<i64>) -> UsageWindow {
    UsageWindow { id: id.into(), label, used_percent: pct.max(0.0), resets_at, window_minutes }
}

/// Até 2 janelas, a mais curta primeiro.
fn provider(id: &str, mut windows: Vec<UsageWindow>, observed_at: f64) -> Option<ProviderUsage> {
    if windows.is_empty() { return None }
    windows.truncate(2);
    let d = def(id)?;
    Some(ProviderUsage { id: d.id.into(), name: d.name.into(), windows, observed_at, color: Some(d.color.into()) })
}

/// `totalPercentUsed` já vem em % (0,36 = 0,36%); sem ele, a média de auto e API, depois os valores em centavos.
fn parse_cursor(root: &Value, t: f64) -> Option<ProviderUsage> {
    let ind = root.get("individualUsage");
    let plan = ind.and_then(|i| i.get("plan"));
    let g = |k: &str| num(plan.and_then(|p| p.get(k)));
    let pct = g("totalPercentUsed")
        .or_else(|| Some((g("autoPercentUsed")? + g("apiPercentUsed")?) / 2.0))
        .or_else(|| g("apiPercentUsed").or_else(|| g("autoPercentUsed")))
        .or_else(|| [plan, ind.and_then(|i| i.get("overall")), root.get("teamUsage").and_then(|x| x.get("pooled"))].into_iter()
            .find_map(|p| { let (u, l) = (num(p?.get("used"))?, num(p?.get("limit"))?); if l > 0.0 { Some(u / l * 100.0) } else { None } }))?;
    provider("cursor", vec![win("month", "1M".into(), pct, iso(root.get("billingCycleEnd")), None)], t)
}

/// `data.limits[]`: TOKENS_LIMIT/CREDIT_LIMIT (TIME_LIMIT é a cota de MCP, fica de fora).
/// unit 3 = hora, 1 = dia, 6 = semana, 5 = minuto; `nextResetTime` em ms.
fn parse_zai(root: &Value, t: f64) -> Option<ProviderUsage> {
    let mut windows = vec![];
    for l in root.get("data")?.get("limits")?.as_array()? {
        let ty = l.get("type").and_then(|v| v.as_str()).unwrap_or("");
        if ty != "TOKENS_LIMIT" && ty != "CREDIT_LIMIT" { continue }
        let Some(mut pct) = num(l.get("percentage")) else { continue };
        if let Some(total) = num(l.get("usage")).filter(|u| *u > 0.0) {
            if let Some(left) = num(l.get("remaining")) { pct = (total - left).clamp(0.0, total) / total * 100.0 }
            else if let Some(cur) = num(l.get("currentValue")) { pct = cur.clamp(0.0, total) / total * 100.0 }
        }
        let mult = match num(l.get("unit")).map(|u| u as i64) { Some(1) => Some(1440), Some(3) => Some(60), Some(5) => Some(1), Some(6) => Some(10080), _ => None };
        let minutes = mult.and_then(|m| num(l.get("number")).map(|n| n as i64 * m));
        let mut reset = num(l.get("nextResetTime")).map(epoch);
        // Reset de 5h a mais de 5h daqui é fuso trocado: melhor sem hora do que hora errada.
        if minutes == Some(300) && reset.map(|r| r > t + 5.0 * 3600.0 + 60.0).unwrap_or(false) { reset = None }
        windows.push(win(&format!("w{}", minutes.unwrap_or(windows.len() as i64)), label(minutes), pct.min(100.0), reset, minutes));
    }
    provider("zai", windows, t)
}

/// `model_remains[]` (na raiz ou em `data`). Atenção: `current_interval_usage_count` é o que RESTA, não o usado.
fn parse_minimax(root: &Value, t: f64) -> Option<ProviderUsage> {
    let list = root.get("model_remains").or_else(|| root.get("data")?.get("model_remains"))?.as_array()?;
    let is_text = |m: &&Value| {
        let s = m.get("model_name").and_then(|v| v.as_str()).unwrap_or("").to_lowercase();
        s == "general" || s.contains("minimax-m") || s.starts_with("m2.")
    };
    let item = list.iter().find(is_text).or(list.first())?;
    let w = |id: &str, total: &str, left: &str, left_pct: &str, start: &str, end: &str| -> Option<UsageWindow> {
        let pct = num(item.get(left_pct)).map(|rp| 100.0 - rp).or_else(|| {
            let tt = num(item.get(total)).filter(|t| *t > 0.0)?;
            Some((tt - num(item.get(left))?).max(0.0) / tt * 100.0)
        })?;
        let (s, e) = (num(item.get(start)).map(epoch), num(item.get(end)).map(epoch));
        let minutes = s.zip(e).map(|(s, e)| ((e - s) / 60.0).round() as i64).filter(|m| *m > 0);
        let lbl = if minutes.is_none() && id == "weekly" { "7d".into() } else { label(minutes) };
        Some(win(id, lbl, pct.min(100.0), e, minutes))
    };
    let windows = [
        w("interval", "current_interval_total_count", "current_interval_usage_count", "current_interval_remaining_percent", "start_time", "end_time"),
        w("weekly", "current_weekly_total_count", "current_weekly_usage_count", "current_weekly_remaining_percent", "weekly_start_time", "weekly_end_time"),
    ].into_iter().flatten().collect();
    provider("minimax", windows, t)
}

/// Formato novo: `usages.limit_5h / limit_7d / limit_month_total` com `used_ratio` (0–1).
/// Antigo: `limits[]` (janela de 5h) e `usage` (semana), com números em texto.
fn parse_kimi(root: &Value, t: f64) -> Option<ProviderUsage> {
    let mut by: std::collections::BTreeMap<i64, UsageWindow> = Default::default();
    if let Some(pools) = root.get("usages") {
        for (key, minutes) in [("limit_5h", 300), ("limit_7d", 10080), ("limit_month_total", 43200)] {
            let Some(p) = pools.get(key) else { continue };
            let Some(r) = num(p.get("used_ratio")).filter(|r| *r >= 0.0) else { continue };
            let month = minutes == 43200;
            by.insert(minutes, win(key, if month { "1M".into() } else { label(Some(minutes)) }, r.min(1.0) * 100.0,
                                   iso(p.get("reset_time")), if month { None } else { Some(minutes) }));
        }
    }
    let mut legacy = |d: Option<&Value>, id: String, minutes: i64| {
        if by.contains_key(&minutes) { return }
        let Some(d) = d else { return };
        let Some(limit) = num(d.get("limit")).filter(|l| *l > 0.0) else { return };
        let Some(used) = num(d.get("used")).or_else(|| num(d.get("remaining")).map(|r| limit - r)) else { return };
        let reset = ["resetTime", "reset_time", "resetAt", "reset_at"].iter().find_map(|k| iso(d.get(*k)));
        by.insert(minutes, win(&id, label(Some(minutes)), used.max(0.0) / limit * 100.0, reset, Some(minutes)));
    };
    for l in root.get("limits").and_then(|v| v.as_array()).into_iter().flatten() {
        let Some(w) = l.get("window") else { continue };
        let Some(dur) = num(w.get("duration")) else { continue };
        let m = match w.get("timeUnit").and_then(|v| v.as_str()) { Some("TIME_UNIT_HOUR") => 60, Some("TIME_UNIT_DAY") => 1440, _ => 1 };
        let minutes = dur as i64 * m;
        legacy(l.get("detail"), format!("limit_{minutes}m"), minutes);
    }
    legacy(root.get("usage"), "limit_7d".into(), 10080);
    provider("kimi", by.into_values().collect(), t)
}

/// Limite da chave (`data.limit` em US$); chave sem limite = None, aí vale o saldo de créditos.
fn parse_openrouter_key(root: &Value, t: f64) -> Option<ProviderUsage> {
    let d = root.get("data")?;
    let limit = num(d.get("limit")).filter(|l| *l > 0.0)?;
    let left = num(d.get("limit_remaining")).unwrap_or_else(|| (limit - num(d.get("usage")).unwrap_or(0.0)).max(0.0));
    let lbl = match d.get("limit_reset").and_then(|v| v.as_str()) { Some("daily") => "1d", Some("weekly") => "7d", Some("monthly") => "1M", _ => "$" };
    provider("openrouter", vec![win("key", lbl.into(), (limit - left).max(0.0) / limit * 100.0, None, None)], t)
}

fn parse_openrouter_credits(root: &Value, t: f64) -> Option<ProviderUsage> {
    let d = root.get("data")?;
    let total = num(d.get("total_credits")).filter(|v| *v > 0.0)?;
    provider("openrouter", vec![win("credits", "$".into(), num(d.get("total_usage")).unwrap_or(0.0) / total * 100.0, None, None)], t)
}

/// `limits.standard.{fiveHour,weekly}` com `usedPercent` (0–100), `secondsRemaining` e `windowEnd`.
fn parse_factory(root: &Value, t: f64) -> Option<ProviderUsage> {
    if root.get("usesTokenRateLimitsBilling").and_then(|v| v.as_bool()) != Some(true) { return None }
    let std = root.get("limits")?.get("standard")?;
    let mut windows = vec![];
    for (key, lbl, minutes) in [("fiveHour", "5h", 300), ("weekly", "7d", 10080)] {
        let Some(w) = std.get(key) else { continue };
        let Some(mut pct) = num(w.get("usedPercent")) else { continue };
        let mut reset = None;
        if let Some(s) = num(w.get("secondsRemaining")).filter(|s| *s > 0.0) { reset = Some(t + s) }
        else if let Some(end) = num(w.get("windowEnd")).map(epoch).or_else(|| iso(w.get("windowEnd"))) {
            if end > t { reset = Some(end) } else if w.get("secondsRemaining").is_none() { pct = 0.0 }   // janela já virou
        }
        windows.push(win(key, lbl.into(), pct.min(100.0), reset, Some(minutes)));
    }
    provider("factory", windows, t)
}

/// Contas antigas: tokens do mês (`usage.standard`), fim do período em ms.
fn parse_factory_legacy(root: &Value, t: f64) -> Option<ProviderUsage> {
    let u = root.get("usage")?;
    let s = u.get("standard")?;
    let pct = num(s.get("usedRatio")).map(|r| r * 100.0).or_else(|| {
        let (used, total) = (num(s.get("userTokens"))?, num(s.get("totalAllowance"))?);
        if total > 0.0 && total < 1e12 { Some(used / total * 100.0) } else { None }
    })?;
    provider("factory", vec![win("month", "1M".into(), pct, num(u.get("endDate")).map(epoch), None)], t)
}

/// `FACTORY_API_KEY=…` (ou `export FACTORY_API_KEY=…`) em ~/.factory/.env.
fn factory_env_key() -> Option<String> {
    let text = fs::read_to_string(home().join(".factory").join(".env")).ok()?;
    text.lines().find_map(|l| {
        let l = l.trim();
        let l = l.strip_prefix("export ").map(str::trim).unwrap_or(l);
        let v = l.strip_prefix("FACTORY_API_KEY=")?.trim_matches(|c| c == '"' || c == '\'' || c == ' ');
        (!v.is_empty()).then(|| v.to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ws(p: Option<ProviderUsage>) -> Vec<(String, f64, Option<f64>)> {
        p.map(|p| p.windows.into_iter().map(|w| (w.label, (w.used_percent * 10.0).round() / 10.0, w.resets_at)).collect()).unwrap_or_default()
    }

    #[test]
    fn cursor() {
        let a = json!({"billingCycleEnd": "2026-11-01T00:00:00.000Z", "individualUsage": {"plan": {"used": 1200, "limit": 2000, "totalPercentUsed": 37.5}}});
        assert_eq!(ws(parse_cursor(&a, 0.0)), vec![("1M".into(), 37.5, Some(1793491200.0))]);
        let b = json!({"individualUsage": {"plan": {"used": 500, "limit": 2000}}});
        assert_eq!(ws(parse_cursor(&b, 0.0)), vec![("1M".into(), 25.0, None)]);
        assert!(parse_cursor(&json!({}), 0.0).is_none());
        let jwt = format!("x.{}.y", base64::Engine::encode(&base64::engine::general_purpose::URL_SAFE_NO_PAD, br#"{"sub":"auth0|user_abc","exp":1999999999}"#));
        assert_eq!(jwt_claims(&jwt).unwrap()["sub"], "auth0|user_abc");
    }

    #[test]
    fn zai() {
        let t = 1_792_000_000.0;
        let r5 = (t + 3600.0) * 1000.0;
        let v = json!({"success": true, "code": 200, "data": {"limits": [
            {"type": "TIME_LIMIT", "unit": 5, "number": 1, "percentage": 3},
            {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 42, "nextResetTime": r5},
            {"type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 10, "usage": 1000, "remaining": 800, "nextResetTime": 1793000000000u64}]}});
        assert_eq!(ws(parse_zai(&v, t)), vec![("5h".into(), 42.0, Some(t + 3600.0)), ("7d".into(), 20.0, Some(1793000000.0))]);
        // 5h com reset 10h à frente: sem hora
        let bad = json!({"data": {"limits": [{"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 1, "nextResetTime": (t + 36000.0) * 1000.0}]}});
        assert_eq!(ws(parse_zai(&bad, t)), vec![("5h".into(), 1.0, None)]);
    }

    #[test]
    fn minimax() {
        let v = json!({"base_resp": {"status_code": 0}, "model_remains": [
            {"model_name": "speech", "current_interval_total_count": 10, "current_interval_usage_count": 10},
            {"model_name": "MiniMax-M2", "start_time": 1792980000000u64, "end_time": 1792998000000u64,
             "current_interval_total_count": 1500, "current_interval_usage_count": 1200,
             "current_weekly_total_count": 15000, "current_weekly_usage_count": 9000,
             "weekly_start_time": 1792500000000u64, "weekly_end_time": 1793104800000u64}]});
        assert_eq!(ws(parse_minimax(&v, 0.0)), vec![("5h".into(), 20.0, Some(1792998000.0)), ("7d".into(), 40.0, Some(1793104800.0))]);
        let nested = json!({"data": {"model_remains": [{"model_name": "general", "current_interval_remaining_percent": 70}]}});
        assert_eq!(ws(parse_minimax(&nested, 0.0)), vec![("".into(), 30.0, None)]);
    }

    #[test]
    fn kimi() {
        let v = json!({"limits": [{"window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"}, "detail": {"limit": "100", "used": "25", "remaining": "75"}}],
                       "usages": {"limit_7d": {"used_ratio": 0.125, "reset_time": "2026-09-20T00:00:00Z"}, "limit_month_total": {"used_ratio": 0.0056}}});
        assert_eq!(ws(parse_kimi(&v, 0.0)), vec![("5h".into(), 25.0, None), ("7d".into(), 12.5, Some(1789862400.0))]);
        let old = json!({"usage": {"limit": "100", "used": "25", "remaining": "75", "resetTime": "2026-09-20T00:00:00Z"}, "limits": []});
        assert_eq!(ws(parse_kimi(&old, 0.0)), vec![("7d".into(), 25.0, Some(1789862400.0))]);
    }

    #[test]
    fn openrouter() {
        assert_eq!(ws(parse_openrouter_key(&json!({"data": {"limit": 20, "limit_remaining": 15, "limit_reset": "monthly"}}), 0.0)), vec![("1M".into(), 25.0, None)]);
        assert!(parse_openrouter_key(&json!({"data": {"limit": null, "usage": 5}}), 0.0).is_none());
        assert_eq!(ws(parse_openrouter_credits(&json!({"data": {"total_credits": 50, "total_usage": 12.5}}), 0.0)), vec![("$".into(), 25.0, None)]);
    }

    #[test]
    fn factory() {
        let v = json!({"usesTokenRateLimitsBilling": true, "limits": {"standard": {
            "fiveHour": {"usedPercent": 33, "secondsRemaining": 3600}, "weekly": {"usedPercent": 70, "windowEnd": 1000}, "monthly": {"usedPercent": 5}}}});
        assert_eq!(ws(parse_factory(&v, 100.0)), vec![("5h".into(), 33.0, Some(3700.0)), ("7d".into(), 70.0, Some(1000.0))]);
        assert_eq!(ws(parse_factory(&v, 5000.0))[1], ("7d".into(), 0.0, None));
        assert!(parse_factory(&json!({"usesTokenRateLimitsBilling": false}), 0.0).is_none());
        let old = json!({"usage": {"endDate": 1793000000000u64, "standard": {"userTokens": 5, "totalAllowance": 10}}});
        assert_eq!(ws(parse_factory_legacy(&old, 0.0)), vec![("1M".into(), 50.0, Some(1793000000.0))]);
    }
}
