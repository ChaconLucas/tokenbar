//! Webhooks: avisa um endereço quando uma janela passa de 80% / 95% e quando volta do reset.
//! Ajustes em `~/.tokenbar/webhook.json`; o que já foi avisado em `~/.tokenbar/webhook-sent.json`
//! (provedor + janela + resetsAt + limite), para não repetir depois de reabrir o app.
//! Slack e Discord recebem só o texto, no formato de cada um; o resto recebe o JSON inteiro.

use crate::api::{used_now, window_json};
use crate::collector::{tokenbar_dir, UsageSnapshot, UsageWindow};
use crate::i18n;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

fn yes() -> bool { true }

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Config {
    #[serde(default)]
    pub url: String,
    #[serde(default = "yes")]
    pub t80: bool,
    #[serde(default = "yes")]
    pub t95: bool,
    #[serde(default = "yes")]
    pub reset: bool,
}

impl Default for Config {
    fn default() -> Self { Config { url: String::new(), t80: true, t95: true, reset: true } }
}

fn config_file() -> std::path::PathBuf { tokenbar_dir().join("webhook.json") }
fn sent_file() -> std::path::PathBuf { tokenbar_dir().join("webhook-sent.json") }

pub fn load() -> Config {
    std::fs::read_to_string(config_file()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
}

pub fn save(c: &Config) -> Result<(), String> {
    let url = c.url.trim();
    if !url.is_empty() && !(url.starts_with("http://") || url.starts_with("https://")) {
        return Err(i18n::t("Endereço inválido").into());
    }
    let c = Config { url: url.to_string(), ..c.clone() };
    write_atomic(&config_file(), &serde_json::to_string_pretty(&c).unwrap())
}

fn write_atomic(path: &std::path::Path, body: &str) -> Result<(), String> {
    std::fs::create_dir_all(tokenbar_dir()).map_err(|e| e.to_string())?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, body).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, path).map_err(|e| e.to_string())
}

/// Último envio (aparece embaixo do campo).
#[derive(Serialize, Clone, Debug)]
pub struct Last { pub ok: bool, pub error: Option<String>, pub event: String, pub at: i64 }

static LAST: Mutex<Option<Last>> = Mutex::new(None);
pub fn last() -> Option<Last> { LAST.lock().unwrap().clone() }

// ---------- quando avisar ----------

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Sent {
    pub provider: String,
    pub window: String,
    pub resets_at: Option<f64>,
    /// "80" | "95" | "reset"
    pub threshold: String,
    pub at: f64,
}

#[derive(Serialize, Deserialize, Default)]
struct SentFile { #[serde(default)] sent: Vec<Sent> }

#[derive(Clone, Debug, PartialEq)]
pub struct Event {
    pub kind: &'static str,
    pub threshold: Option<u8>,
    pub provider_id: String,
    pub provider_name: String,
    pub window: UsageWindow,
}

/// O que já foi avisado e a última leitura de cada janela (para ver o reset acontecer).
#[derive(Default)]
pub struct Tracker {
    pub sent: Vec<Sent>,
    last: HashMap<String, (Option<f64>, f64)>,
}

/// O resetsAt pode variar uns segundos entre leituras: dentro de 5 min é o mesmo ciclo.
const SAME_CYCLE: f64 = 300.0;
/// Reset que passou há mais que isso (app fechado) não vira aviso.
const RESET_FRESH: f64 = 3600.0;
/// Registros mais velhos que isso saem do arquivo (a maior janela é a mensal).
const KEEP: f64 = 40.0 * 86400.0;

impl Tracker {
    fn is_sent(&self, p: &str, w: &str, r: Option<f64>, th: &str) -> bool {
        self.sent.iter().any(|s| s.provider == p && s.window == w && s.threshold == th && match (s.resets_at, r) {
            (Some(a), Some(b)) => (a - b).abs() <= SAME_CYCLE,
            (None, None) => true,
            _ => false,
        })
    }

    fn mark(&mut self, p: &str, w: &str, r: Option<f64>, th: &str, t: f64) {
        if !self.is_sent(p, w, r, th) {
            self.sent.push(Sent { provider: p.into(), window: w.into(), resets_at: r, threshold: th.into(), at: t });
        }
    }

    /// Avisos novos desta leitura (já ficam marcados como enviados).
    pub fn events(&mut self, cfg: &Config, snap: &UsageSnapshot, t: f64) -> Vec<Event> {
        let mut out = Vec::new();
        for p in &snap.providers {
            for w in &p.windows {
                let ev = |kind, threshold| Event { kind, threshold, provider_id: p.id.clone(), provider_name: p.name.clone(), window: w.clone() };
                let key = format!("{}\u{1f}{}", p.id, w.id);
                let prev = self.last.insert(key, (w.resets_at, w.used_percent));
                if cfg.reset {
                    // O horário passou com uso guardado, ou a leitura nova já é de um ciclo seguinte.
                    let passed = w.resets_at.filter(|&r| r <= t && t - r < RESET_FRESH && w.used_percent > 0.0);
                    let rolled = match (prev, w.resets_at) {
                        (Some((Some(old), used)), Some(new)) if new > old + SAME_CYCLE && used > 0.0 && t - old < RESET_FRESH => Some(old),
                        _ => None,
                    };
                    if let Some(r) = passed.or(rolled) {
                        if !self.is_sent(&p.id, &w.id, Some(r), "reset") {
                            self.mark(&p.id, &w.id, Some(r), "reset", t);
                            out.push(ev("reset", None));
                        }
                    }
                }
                let used = used_now(w, t);
                let r = w.resets_at;
                let mut fired = false;
                if cfg.t95 && used >= 95.0 && !self.is_sent(&p.id, &w.id, r, "95") {
                    self.mark(&p.id, &w.id, r, "95", t);
                    self.mark(&p.id, &w.id, r, "80", t); // pulou direto: um aviso só
                    out.push(ev("threshold", Some(95)));
                    fired = true;
                }
                if !fired && cfg.t80 && used >= 80.0 && !self.is_sent(&p.id, &w.id, r, "80") {
                    self.mark(&p.id, &w.id, r, "80", t);
                    out.push(ev("threshold", Some(80)));
                }
            }
        }
        self.sent.retain(|s| t - s.at < KEEP);
        out
    }
}

static TRACKER: Mutex<Option<Tracker>> = Mutex::new(None);

/// Chamado a cada leitura (30 s). Os envios correm em outra thread.
pub fn check(snap: &UsageSnapshot) {
    let cfg = load();
    let t = crate::collector::now();
    let events = {
        let mut g = TRACKER.lock().unwrap();
        let tr = g.get_or_insert_with(|| {
            let f: SentFile = std::fs::read_to_string(sent_file()).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
            Tracker { sent: f.sent, last: HashMap::new() }
        });
        // Sem endereço: só acompanha as janelas, sem marcar nada.
        let active = if cfg.url.trim().is_empty() { Config { url: String::new(), t80: false, t95: false, reset: false } } else { cfg.clone() };
        let before = tr.sent.clone();
        let ev = tr.events(&active, snap, t);
        if tr.sent != before {
            let body = serde_json::to_string_pretty(&json!({ "sent": tr.sent })).unwrap_or_default();
            let _ = write_atomic(&sent_file(), &body);
        }
        ev
    };
    if events.is_empty() { return }
    let lang = i18n::lang();
    std::thread::spawn(move || {
        for e in events {
            let body = event_json(&e, lang, t);
            record(e.kind, send(&cfg.url, &body));
        }
    });
}

/// Botão TESTAR: manda já, com a primeira janela que houver.
pub fn test(snap: &UsageSnapshot) -> Result<(), String> {
    let cfg = load();
    if cfg.url.trim().is_empty() { return Err(i18n::t("Informe o endereço do webhook.").into()) }
    let t = crate::collector::now();
    let lang = i18n::lang();
    let text = test_text(lang);
    let body = match snap.providers.iter().find_map(|p| p.windows.first().map(|w| (p, w))) {
        Some((p, w)) => json!({ "event": "test", "threshold": null, "provider": { "id": p.id, "name": p.name },
                                "window": window_json(w, t), "at": t as i64, "text": text }),
        None => json!({ "event": "test", "threshold": null, "provider": { "id": "tokenbar", "name": "TokenBar" },
                        "window": null, "at": t as i64, "text": text }),
    };
    let r = send(&cfg.url, &body);
    record("test", r.clone());
    r
}

fn record(event: &str, r: Result<(), String>) {
    *LAST.lock().unwrap() = Some(Last { ok: r.is_ok(), error: r.err(), event: event.into(), at: crate::collector::now() as i64 });
}

fn send(url: &str, body: &Value) -> Result<(), String> {
    let text = body["text"].as_str().unwrap_or_default();
    ureq::post(url.trim())
        .timeout(Duration::from_secs(10))
        .send_json(payload(url, body.clone(), text))
        .map(|_| ())
        .map_err(|e| match e {
            ureq::Error::Status(code, _) => format!("HTTP {code}"),
            ureq::Error::Transport(t) => t.to_string(),
        })
}

// ---------- formato ----------

#[derive(Debug, PartialEq)]
pub enum Target { Slack, Discord, Generic }

fn host_of(url: &str) -> String {
    let rest = url.trim().split_once("://").map(|(_, r)| r).unwrap_or(url);
    let auth = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host = auth.rsplit('@').next().unwrap_or("");
    host.split(':').next().unwrap_or("").to_ascii_lowercase()
}

pub fn target(url: &str) -> Target {
    let h = host_of(url);
    let is = |d: &str| h == d || h.ends_with(&format!(".{d}"));
    if h == "hooks.slack.com" { Target::Slack }
    else if (is("discord.com") || is("discordapp.com")) && url.contains("/api/webhooks/") { Target::Discord }
    else { Target::Generic }
}

pub fn payload(url: &str, full: Value, text: &str) -> Value {
    match target(url) {
        Target::Slack => json!({ "text": text }),
        Target::Discord => json!({ "content": text }),
        Target::Generic => full,
    }
}

pub fn event_json(e: &Event, lang: &str, t: f64) -> Value {
    json!({
        "event": e.kind,
        "threshold": e.threshold,
        "provider": { "id": e.provider_id, "name": e.provider_name },
        "window": window_json(&e.window, t),
        "at": t as i64,
        "text": event_text(e, lang, t),
    })
}

/// 1:12 (até um dia) ou 3d 4h.
pub fn duration(secs: i64) -> String {
    let s = secs.max(0);
    let m = (s + 59) / 60;
    if m < 24 * 60 { format!("{}:{:02}", m / 60, m % 60) } else { format!("{}d {}h", m / 1440, (m % 1440) / 60) }
}

pub fn event_text(e: &Event, lang: &str, t: f64) -> String {
    let w = &e.window;
    let used = used_now(w, t).round() as i64;
    let en = lang == "en";
    let name = format!("{} {}", e.provider_name, w.label);
    match (e.kind, e.threshold) {
        ("threshold", Some(th)) => {
            let mut s = if en { format!("{name} passed {th}% ({used}%).") } else { format!("{name} passou de {th}% ({used}%).") };
            if let Some(r) = w.resets_at.filter(|&r| r > t) {
                let d = duration((r - t).ceil() as i64);
                s.push_str(&if en { format!(" Resets in {d}.") } else { format!(" Reseta em {d}.") });
            }
            s
        }
        _ => if en { format!("{name} reset. Usage now {used}%.") } else { format!("{name} resetou. Uso agora em {used}%.") },
    }
}

fn test_text(lang: &str) -> String {
    if lang == "en" { "TokenBar test: the webhook is working.".into() } else { "Teste do TokenBar: o webhook está funcionando.".into() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::collector::ProviderUsage;

    fn snap(used: f64, resets_at: Option<f64>) -> UsageSnapshot {
        UsageSnapshot { updated_at: 0.0, providers: vec![ProviderUsage {
            id: "claude".into(), name: "Claude Code".into(), observed_at: 0.0, color: None,
            windows: vec![UsageWindow { id: "5h".into(), label: "5h".into(), used_percent: used, resets_at, window_minutes: Some(300) }],
        }] }
    }
    fn on() -> Config { Config { url: "https://x".into(), ..Default::default() } }
    fn kinds(v: &[Event]) -> Vec<(&'static str, Option<u8>)> { v.iter().map(|e| (e.kind, e.threshold)).collect() }

    #[test]
    fn slack_discord_or_full() {
        let full = json!({ "event": "test", "text": "oi" });
        assert_eq!(payload("https://hooks.slack.com/services/T/B/X", full.clone(), "oi"), json!({ "text": "oi" }));
        assert_eq!(payload("https://discord.com/api/webhooks/1/abc", full.clone(), "oi"), json!({ "content": "oi" }));
        assert_eq!(payload("https://discordapp.com/api/webhooks/1/abc", full.clone(), "oi"), json!({ "content": "oi" }));
        assert_eq!(payload("https://ptb.discord.com/api/webhooks/1/abc", full.clone(), "oi"), json!({ "content": "oi" }));
        assert_eq!(payload("https://example.com/hook", full.clone(), "oi"), full);
        assert_eq!(target("https://hooks.slack.com.evil.io/x"), Target::Generic);
        assert_eq!(target("https://evil.io/hooks.slack.com/x"), Target::Generic);
        assert_eq!(target("https://notdiscord.com/api/webhooks/1"), Target::Generic);
        assert_eq!(target("https://user@HOOKS.SLACK.COM:443/x"), Target::Slack);
    }

    #[test]
    fn threshold_once_per_cycle() {
        let mut tr = Tracker::default();
        let r = Some(10_000.0);
        assert!(tr.events(&on(), &snap(50.0, r), 1000.0).is_empty());
        assert_eq!(kinds(&tr.events(&on(), &snap(82.0, r), 1030.0)), [("threshold", Some(80))]);
        assert!(tr.events(&on(), &snap(85.0, r), 1060.0).is_empty());
        // resetsAt com uns segundos de diferença é o mesmo ciclo.
        assert!(tr.events(&on(), &snap(86.0, Some(10_004.0)), 1090.0).is_empty());
        assert_eq!(kinds(&tr.events(&on(), &snap(96.0, r), 1120.0)), [("threshold", Some(95))]);
        assert!(tr.events(&on(), &snap(97.0, r), 1150.0).is_empty());
        // Reabriu o app: o arquivo guarda o que já foi avisado.
        let mut again = Tracker { sent: tr.sent.clone(), ..Default::default() };
        assert!(again.events(&on(), &snap(97.0, r), 1180.0).is_empty());
        // Ciclo seguinte avisa de novo (e o reset do anterior).
        let next = Some(28_000.0);
        assert_eq!(kinds(&tr.events(&on(), &snap(81.0, next), 11_000.0)), [("reset", None), ("threshold", Some(80))]);
    }

    #[test]
    fn jump_straight_to_95_is_one_event() {
        let mut tr = Tracker::default();
        assert_eq!(kinds(&tr.events(&on(), &snap(96.0, Some(9e3)), 1000.0)), [("threshold", Some(95))]);
        assert!(tr.events(&on(), &snap(96.0, Some(9e3)), 1030.0).is_empty());
        // Só 80 ligado.
        let mut tr = Tracker::default();
        let cfg = Config { t95: false, ..on() };
        assert_eq!(kinds(&tr.events(&cfg, &snap(96.0, Some(9e3)), 1000.0)), [("threshold", Some(80))]);
    }

    #[test]
    fn reset_after_usage() {
        let mut tr = Tracker::default();
        let r = Some(2000.0);
        assert!(tr.events(&on(), &snap(40.0, r), 1000.0).is_empty());
        // Passou do horário: avisa uma vez.
        assert_eq!(kinds(&tr.events(&on(), &snap(40.0, r), 2010.0)), [("reset", None)]);
        assert!(tr.events(&on(), &snap(40.0, r), 2040.0).is_empty());
        // Chega a leitura do ciclo novo: não repete.
        assert!(tr.events(&on(), &snap(2.0, Some(20_000.0)), 2070.0).is_empty());
        // Sem uso não há reset para avisar; reset antigo (app fechado) também não.
        let mut tr = Tracker::default();
        assert!(tr.events(&on(), &snap(0.0, r), 2010.0).is_empty());
        assert!(tr.events(&on(), &snap(50.0, r), 2000.0 + RESET_FRESH + 1.0).is_empty());
        // Desligado nos ajustes.
        let mut tr = Tracker::default();
        assert!(tr.events(&Config { reset: false, ..on() }, &snap(40.0, r), 2010.0).is_empty());
    }

    #[test]
    fn texts() {
        let e = Event { kind: "threshold", threshold: Some(80), provider_id: "claude".into(), provider_name: "Claude Code".into(),
                        window: snap(82.0, Some(1000.0 + 72.0 * 60.0)).providers[0].windows[0].clone() };
        assert_eq!(event_text(&e, "pt", 1000.0), "Claude Code 5h passou de 80% (82%). Reseta em 1:12.");
        assert_eq!(event_text(&e, "en", 1000.0), "Claude Code 5h passed 80% (82%). Resets in 1:12.");
        let v = event_json(&e, "pt", 1000.0);
        assert_eq!(v.as_object().unwrap().keys().cloned().collect::<Vec<_>>(), ["event", "threshold", "provider", "window", "at", "text"]);
        assert_eq!(v["provider"], json!({ "id": "claude", "name": "Claude Code" }));
        assert_eq!(v["threshold"], 80);
        assert_eq!(v["window"]["usedNow"], 82.0);
        let r = Event { kind: "reset", threshold: None, ..e };
        assert_eq!(event_text(&r, "pt", 1000.0), "Claude Code 5h resetou. Uso agora em 82%.");
        assert!(event_json(&r, "en", 1000.0)["threshold"].is_null());
        assert_eq!(duration(59), "0:01");
        assert_eq!(duration(3 * 86400 + 4 * 3600), "3d 4h");
    }

    #[test]
    fn config_defaults_on() {
        let c: Config = serde_json::from_str(r#"{"url":"https://x"}"#).unwrap();
        assert!(c.t80 && c.t95 && c.reset);
        assert_eq!(Config::default().url, "");
    }
}
