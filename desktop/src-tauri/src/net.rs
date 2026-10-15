//! Pareamento, servidor no Wi-Fi (o mesmo protocolo do Mac: mDNS `_tokenbar._tcp` + HTTP) e envio ao servidor opcional.

use crate::collector::{tokenbar_dir, UsageSnapshot};
use base64::Engine;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Serialize, Deserialize, Clone, Default)]
pub struct Pairing {
    pub token: String,
    #[serde(default)]
    pub server: Option<String>,
}

impl Pairing {
    fn file() -> std::path::PathBuf { tokenbar_dir().join("desktop-pairing.json") }

    /// A chave é criada na primeira abertura: o Wi-Fi local funciona sem servidor.
    pub fn load_or_create() -> Pairing {
        if let Ok(s) = std::fs::read_to_string(Self::file()) {
            if let Ok(p) = serde_json::from_str::<Pairing>(&s) { if p.token.len() >= 32 { return p } }
        }
        let mut bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes);
        let p = Pairing { token: base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes), server: None };
        p.save();
        p
    }

    pub fn save(&self) {
        let _ = std::fs::create_dir_all(tokenbar_dir());
        let _ = std::fs::write(Self::file(), serde_json::to_string_pretty(self).unwrap());
    }

    pub fn lan_id(&self) -> String { self.token.chars().take(8).collect() }

    pub fn link(&self) -> String {
        let mut s = format!("tokenbar://pair?token={}", self.token);
        if let Some(srv) = &self.server { s.push_str("&server="); s.push_str(&urlencode(srv)); }
        s
    }
}

fn urlencode(s: &str) -> String {
    s.bytes().map(|b| match b {
        b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
        _ => format!("%{b:02X}"),
    }).collect()
}

/// Estado servido no Wi-Fi.
pub struct Lan {
    pub body: String,
    pub token: String,
    pub link: String,
    pub code: String,
    code_born: Instant,
    failures: u32,
    locked_until: Instant,
    /// Última leitura autorizada de um celular/relógio (o guia mostra "conectado").
    pub last_client: Option<Instant>,
}

impl Lan {
    pub fn new(p: &Pairing) -> Lan {
        Lan { body: "{}".into(), token: p.token.clone(), link: p.link(), code: new_code(),
              code_born: Instant::now(), failures: 0, locked_until: Instant::now(), last_client: None }
    }

    /// Código de 6 números para relógios sem celular; troca a cada 10 min.
    pub fn current_code(&mut self) -> String {
        if self.code_born.elapsed() > Duration::from_secs(600) { self.code = new_code(); self.code_born = Instant::now(); }
        self.code.clone()
    }
}

fn new_code() -> String { format!("{:06}", rand::random::<u32>() % 1_000_000) }

/// Liga o servidor HTTP e o anúncio mDNS. Responde só a quem manda a chave.
pub fn start(lan: Arc<Mutex<Lan>>, lan_id: String) {
    let listener = match TcpListener::bind("0.0.0.0:0") { Ok(l) => l, Err(_) => return };
    let port = listener.local_addr().map(|a| a.port()).unwrap_or(0);

    // Anúncio: o celular e o relógio procuram `_tokenbar._tcp` com o mesmo id.
    std::thread::spawn(move || {
        let Ok(mdns) = mdns_sd::ServiceDaemon::new() else { return };
        let host = hostname::get().ok().and_then(|h| h.into_string().ok()).unwrap_or_else(|| "tokenbar".into());
        let short = host.split('.').next().unwrap_or("tokenbar").to_string();
        let props = [("id", lan_id.as_str())];
        if let Ok(info) = mdns_sd::ServiceInfo::new("_tokenbar._tcp.local.", &short, &format!("{short}.local."), "", port, &props[..]) {
            let _ = mdns.register(info.enable_addr_auto());
        }
        loop { std::thread::sleep(Duration::from_secs(3600)) }
    });

    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let lan = lan.clone();
            std::thread::spawn(move || handle(stream, lan));
        }
    });
}

fn handle(mut s: TcpStream, lan: Arc<Mutex<Lan>>) {
    let _ = s.set_read_timeout(Some(Duration::from_secs(5)));
    let mut buf = [0u8; 16 * 1024];
    let n = s.read(&mut buf).unwrap_or(0);
    let req = String::from_utf8_lossy(&buf[..n]).to_string();
    let first = req.lines().next().unwrap_or("").to_string();
    let (code, body) = {
        let mut l = lan.lock().unwrap();
        if let Some(rest) = first.strip_prefix("GET /v1/pair?code=") {
            pair(&mut l, &rest.chars().take(6).collect::<String>())
        } else if !first.starts_with("GET /v1/usage") {
            (404, r#"{"error":"not_found"}"#.to_string())
        } else if !l.token.is_empty() && req.contains(&format!("Authorization: Bearer {}", l.token)) {
            l.last_client = Some(Instant::now());
            (200, l.body.clone())
        } else {
            (401, r#"{"error":"unauthorized"}"#.to_string())
        }
    };
    let reason = match code { 200 => "OK", 401 => "Unauthorized", 404 => "Not Found", 429 => "Too Many Requests", _ => "Error" };
    let resp = format!("HTTP/1.1 {code} {reason}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len());
    let _ = s.write_all(resp.as_bytes());
}

/// Errou 5 vezes, trava 1 minuto; acertou, o código muda (vale uma vez).
fn pair(l: &mut Lan, code: &str) -> (u16, String) {
    if Instant::now() < l.locked_until { return (429, r#"{"error":"wait"}"#.into()) }
    let current = l.current_code();
    if code != current {
        l.failures += 1;
        if l.failures >= 5 { l.locked_until = Instant::now() + Duration::from_secs(60); l.failures = 0; }
        return (401, r#"{"error":"wrong_code"}"#.into());
    }
    l.failures = 0;
    l.code = new_code();
    (200, serde_json::json!({ "link": l.link }).to_string())
}

/// Envia ao servidor opcional (PUT /v1/usage).
pub fn push(p: &Pairing, s: &UsageSnapshot) -> Result<(), String> {
    let Some(server) = &p.server else { return Ok(()) };
    let url = format!("{}/v1/usage", server.trim_end_matches('/'));
    ureq::put(&url)
        .set("Authorization", &format!("Bearer {}", p.token))
        .timeout(Duration::from_secs(10))
        .send_json(serde_json::to_value(s).unwrap())
        .map(|_| ()).map_err(|e| e.to_string())
}
