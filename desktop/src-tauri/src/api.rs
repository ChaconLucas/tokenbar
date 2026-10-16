//! API local: HTTP só em 127.0.0.1 (porta 41777, ou a próxima livre até 41787), sem chave, só leitura.
//! Outros apps e scripts deste computador leem os limites (o mesmo contrato do app do Mac e da CLI/MCP).
//! Separada do servidor do Wi-Fi (net.rs), que escuta em 0.0.0.0 e exige a chave dos celulares.
//! `~/.tokenbar/api.json` diz a porta em uso; some ao sair. Desligada: arquivo `~/.tokenbar/api-off`.

use crate::collector::{now, tokenbar_dir, ProviderUsage, UsageSnapshot, UsageWindow};
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

pub const FIRST_PORT: u16 = 41777;
pub const LAST_PORT: u16 = 41787;

type Getter = Box<dyn Fn() -> UsageSnapshot + Send + Sync>;
static GETTER: OnceLock<Getter> = OnceLock::new();
static VERSION: OnceLock<String> = OnceLock::new();
static RUNNING: Mutex<Option<Running>> = Mutex::new(None);

struct Running { port: u16, stop: Arc<AtomicBool> }

pub fn platform() -> &'static str {
    if cfg!(target_os = "windows") { "windows" } else if cfg!(target_os = "macos") { "mac" } else { "linux" }
}

fn version() -> &'static str { VERSION.get().map(|s| s.as_str()).unwrap_or(env!("CARGO_PKG_VERSION")) }

fn off_flag() -> std::path::PathBuf { tokenbar_dir().join("api-off") }
fn info_file() -> std::path::PathBuf { tokenbar_dir().join("api.json") }

/// Ligada por padrão; desliga com o arquivo `api-off`.
pub fn enabled() -> bool { !off_flag().exists() }

/// Porta em uso (None = desligada ou nenhuma porta livre).
pub fn port() -> Option<u16> { RUNNING.lock().unwrap().as_ref().map(|r| r.port) }

/// Guarda a versão e de onde ler a última leitura; liga se não estiver desligada.
pub fn init(version: String, getter: impl Fn() -> UsageSnapshot + Send + Sync + 'static) {
    let _ = VERSION.set(version);
    let _ = GETTER.set(Box::new(getter));
    if enabled() { let _ = start(); }
}

pub fn set_enabled(on: bool) -> Result<Option<u16>, String> {
    std::fs::create_dir_all(tokenbar_dir()).map_err(|e| e.to_string())?;
    if on {
        let _ = std::fs::remove_file(off_flag());
        start().map(Some)
    } else {
        std::fs::write(off_flag(), b"").map_err(|e| e.to_string())?;
        stop();
        Ok(None)
    }
}

fn start() -> Result<u16, String> {
    let mut running = RUNNING.lock().unwrap();
    if let Some(r) = running.as_ref() { return Ok(r.port) }
    let listener = (FIRST_PORT..=LAST_PORT).find_map(|p| TcpListener::bind(("127.0.0.1", p)).ok())
        .ok_or_else(|| crate::i18n::t("Nenhuma porta livre para a API local.").to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    write_info(port);
    let stop = Arc::new(AtomicBool::new(false));
    let flag = stop.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            if flag.load(Ordering::SeqCst) { break }
            if let Ok(s) = stream { std::thread::spawn(move || handle(s, port)); }
        }
    });
    *running = Some(Running { port, stop });
    Ok(port)
}

fn stop() {
    let Some(r) = RUNNING.lock().unwrap().take() else { return };
    r.stop.store(true, Ordering::SeqCst);
    // Acorda o accept para o laço ver a bandeira e soltar a porta.
    let _ = TcpStream::connect_timeout(&([127, 0, 0, 1], r.port).into(), Duration::from_millis(500));
    remove_info();
}

/// Ao sair do app.
pub fn shutdown() { stop() }

fn write_info(port: u16) {
    let body = json!({ "port": port, "pid": std::process::id(), "app": "TokenBar", "version": version(), "platform": platform() });
    let _ = std::fs::create_dir_all(tokenbar_dir());
    let tmp = tokenbar_dir().join(format!("api.json.{}.tmp", std::process::id()));
    if std::fs::write(&tmp, body.to_string()).is_ok() { let _ = std::fs::rename(&tmp, info_file()); }
}

/// Só apaga se o arquivo for deste processo (o app do Mac pode ter escrito o dele por cima).
fn remove_info() {
    let mine = std::fs::read_to_string(info_file()).ok()
        .and_then(|s| serde_json::from_str::<Value>(&s).ok())
        .and_then(|v| v.get("pid").and_then(Value::as_u64))
        .map(|pid| pid == std::process::id() as u64).unwrap_or(false);
    if mine { let _ = std::fs::remove_file(info_file()); }
}

fn handle(mut s: TcpStream, port: u16) {
    let _ = s.set_read_timeout(Some(Duration::from_secs(5)));
    let mut buf = Vec::with_capacity(2048);
    let mut chunk = [0u8; 4096];
    while buf.len() < 16 * 1024 && !buf.windows(4).any(|w| w == b"\r\n\r\n") {
        match s.read(&mut chunk) { Ok(0) | Err(_) => break, Ok(n) => buf.extend_from_slice(&chunk[..n]) }
    }
    let req = String::from_utf8_lossy(&buf).to_string();
    let mut first = req.lines().next().unwrap_or("").split_whitespace();
    let (method, target) = (first.next().unwrap_or(""), first.next().unwrap_or(""));
    let host = header(&req, "host");
    let snap = || GETTER.get().map(|g| g()).unwrap_or_default();
    let (code, body) = route(method, target, host.as_deref(), port, snap, now());
    let _ = s.write_all(response(code, &body).as_bytes());
}

fn header(req: &str, name: &str) -> Option<String> {
    req.lines().skip(1).take_while(|l| !l.is_empty()).find_map(|l| {
        let (k, v) = l.split_once(':')?;
        k.trim().eq_ignore_ascii_case(name).then(|| v.trim().to_string())
    })
}

/// Proteção contra DNS rebinding: só `127.0.0.1:<porta>` ou `localhost:<porta>`.
pub fn host_ok(host: Option<&str>, port: u16) -> bool {
    let Some(h) = host else { return false };
    let h = h.to_ascii_lowercase();
    h == format!("127.0.0.1:{port}") || h == format!("localhost:{port}")
}

/// Responde (código, corpo). A leitura só é feita quando a rota precisa dela.
pub fn route(method: &str, target: &str, host: Option<&str>, port: u16, snap: impl FnOnce() -> UsageSnapshot, t: f64) -> (u16, String) {
    if !host_ok(host, port) { return (403, r#"{"error":"forbidden"}"#.into()) }
    if method != "GET" { return (405, r#"{"error":"method_not_allowed"}"#.into()) }
    let path = target.split(['?', '#']).next().unwrap_or("");
    let path = if path.len() > 1 { path.trim_end_matches('/') } else { path };
    match path {
        "/v1/health" => (200, json!({ "ok": true, "app": "TokenBar", "version": version(), "platform": platform() }).to_string()),
        "/v1/usage" => (200, usage_json(&snap(), t).to_string()),
        _ => match path.strip_prefix("/v1/usage/") {
            Some(id) if !id.is_empty() && !id.contains('/') => {
                let id = percent_decode(id);
                match snap().providers.iter().find(|p| p.id == id) {
                    Some(p) => (200, provider_json(p, t).to_string()),
                    None => (404, r#"{"error":"not_found"}"#.into()),
                }
            }
            _ => (404, r#"{"error":"not_found"}"#.into()),
        },
    }
}

fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Some(v) = std::str::from_utf8(&b[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok()) { out.push(v); i += 3; continue }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn response(code: u16, body: &str) -> String {
    let reason = match code { 200 => "OK", 403 => "Forbidden", 404 => "Not Found", 405 => "Method Not Allowed", _ => "Error" };
    let allow = if code == 405 { "Allow: GET\r\n" } else { "" };
    format!("HTTP/1.1 {code} {reason}\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n{allow}Connection: close\r\nContent-Length: {}\r\n\r\n{body}", body.len())
}

/// Passou do reset: o número guardado é do ciclo velho, o uso de agora é 0.
pub fn used_now(w: &UsageWindow, t: f64) -> f64 {
    if w.resets_at.map(|r| r <= t).unwrap_or(false) { 0.0 } else { w.used_percent }
}

pub fn window_json(w: &UsageWindow, t: f64) -> Value {
    json!({
        "id": w.id,
        "label": w.label,
        "usedPercent": w.used_percent,
        "usedNow": used_now(w, t),
        "resetsAt": w.resets_at,
        "resetsInSeconds": w.resets_at.map(|r| (r - t).ceil().max(0.0) as i64),
        "windowMinutes": w.window_minutes,
    })
}

pub fn provider_json(p: &ProviderUsage, t: f64) -> Value {
    json!({
        "id": p.id,
        "name": p.name,
        "color": p.color,
        "observedAt": p.observed_at,
        "windows": p.windows.iter().map(|w| window_json(w, t)).collect::<Vec<_>>(),
    })
}

pub fn usage_json(s: &UsageSnapshot, t: f64) -> Value {
    json!({ "updatedAt": s.updated_at, "providers": s.providers.iter().map(|p| provider_json(p, t)).collect::<Vec<_>>() })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snap() -> UsageSnapshot {
        UsageSnapshot {
            updated_at: 1000.0,
            providers: vec![ProviderUsage {
                id: "claude".into(), name: "Claude Code".into(), observed_at: 990.0, color: None,
                windows: vec![
                    UsageWindow { id: "5h".into(), label: "5h".into(), used_percent: 42.0, resets_at: Some(1100.4), window_minutes: Some(300) },
                    UsageWindow { id: "7d".into(), label: "7d".into(), used_percent: 70.0, resets_at: Some(900.0), window_minutes: None },
                    UsageWindow { id: "m".into(), label: "mês".into(), used_percent: 5.0, resets_at: None, window_minutes: None },
                ],
            }],
        }
    }

    #[test]
    fn json_shape() {
        let v = usage_json(&snap(), 1000.0);
        let keys = |v: &Value| v.as_object().unwrap().keys().cloned().collect::<Vec<_>>();
        assert_eq!(keys(&v), ["updatedAt", "providers"]);
        let p = &v["providers"][0];
        assert_eq!(keys(p), ["id", "name", "color", "observedAt", "windows"]);
        assert!(p["color"].is_null());
        let w = &p["windows"][0];
        assert_eq!(keys(w), ["id", "label", "usedPercent", "usedNow", "resetsAt", "resetsInSeconds", "windowMinutes"]);
        assert_eq!(w["usedNow"], 42.0);
        assert_eq!(w["resetsInSeconds"], 101);
        assert_eq!(w["windowMinutes"], 300);
        // Passou do reset: usedNow 0, faltam 0 s.
        let w = &p["windows"][1];
        assert_eq!(w["usedPercent"], 70.0);
        assert_eq!(w["usedNow"], 0.0);
        assert_eq!(w["resetsInSeconds"], 0);
        assert!(w["windowMinutes"].is_null());
        let w = &p["windows"][2];
        assert!(w["resetsAt"].is_null() && w["resetsInSeconds"].is_null());
        assert_eq!(w["usedNow"], 5.0);
    }

    #[test]
    fn host_check() {
        assert!(host_ok(Some("127.0.0.1:4777"), 4777));
        assert!(host_ok(Some("localhost:4778"), 4778));
        assert!(host_ok(Some("LocalHost:4777"), 4777));
        assert!(!host_ok(Some("localhost"), 4777));
        assert!(!host_ok(Some("127.0.0.1:4778"), 4777));
        assert!(!host_ok(Some("evil.com:4777"), 4777));
        assert!(!host_ok(Some("localhost.evil.com:4777"), 4777));
        assert!(!host_ok(None, 4777));
        assert_eq!(route("GET", "/v1/health", Some("evil.com:4777"), 4777, snap, 1000.0).0, 403);
        assert_eq!(route("GET", "/v1/usage", None, 4777, snap, 1000.0).0, 403);
    }

    #[test]
    fn routes() {
        let h = Some("localhost:4777");
        let (c, b) = route("GET", "/v1/health", h, 4777, snap, 1000.0);
        assert_eq!(c, 200);
        let v: Value = serde_json::from_str(&b).unwrap();
        assert_eq!(v["ok"], true);
        assert_eq!(v["app"], "TokenBar");
        assert_eq!(v["platform"], platform());
        assert_eq!(route("GET", "/v1/usage?x=1", h, 4777, snap, 1000.0).0, 200);
        let (c, b) = route("GET", "/v1/usage/claude", h, 4777, snap, 1000.0);
        assert_eq!(c, 200);
        assert_eq!(serde_json::from_str::<Value>(&b).unwrap()["id"], "claude");
        assert_eq!(route("GET", "/v1/usage/nope", h, 4777, snap, 1000.0), (404, r#"{"error":"not_found"}"#.into()));
        assert_eq!(route("GET", "/v1/other", h, 4777, snap, 1000.0).0, 404);
        assert_eq!(route("GET", "/", h, 4777, snap, 1000.0).0, 404);
        assert_eq!(route("POST", "/v1/usage", h, 4777, snap, 1000.0).0, 405);
        assert_eq!(route("HEAD", "/v1/health", h, 4777, snap, 1000.0).0, 405);
    }

    #[test]
    fn headers() {
        let r = response(200, "{}");
        assert!(r.contains("Content-Type: application/json; charset=utf-8\r\n"));
        assert!(r.contains("Cache-Control: no-store\r\n"));
        assert!(r.contains("Connection: close\r\n"));
        assert!(!r.to_ascii_lowercase().contains("access-control"));
        assert_eq!(header("GET / HTTP/1.1\r\nhOsT:  localhost:4777 \r\n\r\n", "host").as_deref(), Some("localhost:4777"));
        assert_eq!(percent_decode("a%20b"), "a b");
        assert_eq!(percent_decode("a%2"), "a%2");
    }
}
