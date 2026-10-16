//! Idioma: "auto" | "pt" | "en", guardado em ~/.tokenbar/lang. Os textos do Rust são escritos em
//! português e traduzidos aqui na hora de mostrar (o português é a chave; sem tradução, fica o português).

use crate::collector::tokenbar_dir;
use std::sync::Mutex;

static SETTING: Mutex<String> = Mutex::new(String::new());

fn file() -> std::path::PathBuf { tokenbar_dir().join("lang") }

fn valid(s: &str) -> Option<&'static str> {
    match s.trim() { "auto" => Some("auto"), "pt" => Some("pt"), "en" => Some("en"), _ => None }
}

/// A escolha guardada (padrão: auto).
pub fn setting() -> String {
    let mut s = SETTING.lock().unwrap();
    if s.is_empty() {
        *s = std::fs::read_to_string(file()).ok().and_then(|v| valid(&v)).unwrap_or("auto").to_string();
    }
    s.clone()
}

pub fn save(lang: &str) -> Result<(), String> {
    let lang = valid(lang).ok_or_else(|| t("Idioma inválido").to_string())?;
    std::fs::create_dir_all(tokenbar_dir()).map_err(|e| e.to_string())?;
    std::fs::write(file(), lang).map_err(|e| e.to_string())?;
    *SETTING.lock().unwrap() = lang.to_string();
    Ok(())
}

/// "auto" → português se o sistema estiver em português, senão inglês.
pub fn resolve(setting: &str, locale: Option<&str>) -> &'static str {
    match setting {
        "pt" => "pt",
        "en" => "en",
        _ => if locale.map(|l| l.to_ascii_lowercase().starts_with("pt")).unwrap_or(false) { "pt" } else { "en" },
    }
}

pub fn lang() -> &'static str { resolve(&setting(), sys_locale::get_locale().as_deref()) }

const EN: &[(&str, &str)] = &[
    ("Abrir aparelho", "Open device"),
    ("Flutuante", "Floating"),
    ("Primeiros passos", "Getting started"),
    ("Sair", "Quit"),
    ("TokenBar — sem dados", "TokenBar — no data"),
    ("Endereço inválido", "Invalid address"),
    ("Idioma inválido", "Invalid language"),
    ("Já está na versão mais nova", "Already on the latest version"),
    ("Login do Claude expirado: abra o Claude Code uma vez.", "Claude login expired: open Claude Code once."),
    ("Não achei o login do Claude Code neste computador.", "Couldn't find the Claude Code login on this computer."),
    ("Resposta inválida da Anthropic.", "Invalid response from Anthropic."),
    ("Sem conexão com a Anthropic.", "Can't reach Anthropic."),
    ("Resposta sem limites do Claude.", "The response had no Claude limits."),
    ("Informe o endereço do webhook.", "Enter the webhook address."),
    ("Nenhuma porta livre para a API local.", "No free port for the local API."),
];

/// Texto fixo do Rust no idioma atual.
pub fn t(pt: &'static str) -> &'static str {
    if lang() == "en" { EN.iter().find(|(k, _)| *k == pt).map(|(_, v)| *v).unwrap_or(pt) } else { pt }
}

/// Atualizar para {v}
pub fn update_to(v: &str) -> String {
    if lang() == "en" { format!("Update to {v}") } else { format!("Atualizar para {v}") }
}

/// Mensagem guardada em português (erros do login, do updater…) → idioma atual. Desconhecida: como veio.
pub fn tr(msg: &str) -> String {
    if lang() != "en" { return msg.to_string() }
    if let Some((_, v)) = EN.iter().find(|(k, _)| *k == msg) { return v.to_string() }
    if let Some(code) = msg.strip_prefix("A Anthropic respondeu ").and_then(|r| r.strip_suffix('.')) {
        return format!("Anthropic replied {code}.");
    }
    msg.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_follows_the_system() {
        assert_eq!(resolve("auto", Some("pt-BR")), "pt");
        assert_eq!(resolve("auto", Some("pt_PT.UTF-8")), "pt");
        assert_eq!(resolve("auto", Some("en-US")), "en");
        assert_eq!(resolve("auto", Some("de-DE")), "en");
        assert_eq!(resolve("auto", None), "en");
        assert_eq!(resolve("pt", Some("en-US")), "pt");
        assert_eq!(resolve("en", Some("pt-BR")), "en");
    }

    #[test]
    fn every_key_is_unique() {
        for (i, (k, _)) in EN.iter().enumerate() { assert!(EN[i + 1..].iter().all(|(o, _)| o != k), "{k}") }
    }
}
