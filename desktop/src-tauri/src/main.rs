// Windows: sem janela de console atrás do app.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod collector;
mod hook;
mod i18n;
mod net;
mod update;

use collector::UsageSnapshot;
use net::{Lan, Pairing};
use serde::Serialize;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder, Wry};

struct App {
    snapshot: Mutex<UsageSnapshot>,
    pairing: Mutex<Pairing>,
    lan: Arc<Mutex<Lan>>,
    push_error: Mutex<Option<String>>,
    /// Versão nova encontrada (aparece na bandeja e na tecla ATUALIZAR).
    update: Mutex<Option<String>>,
    update_error: Mutex<Option<String>>,
    /// Menu da bandeja (os textos mudam ao trocar de idioma).
    menu: Mutex<Option<Menu<Wry>>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Status {
    snapshot: UsageSnapshot,
    link: String,
    qr_svg: String,
    code: String,
    server: Option<String>,
    claude_connected: bool,
    /// O Claude Code existe neste computador (a pasta ~/.claude): se não chega número, vale oferecer o login.
    claude_installed: bool,
    claude_login: bool,
    claude_login_error: Option<String>,
    /// GitHub Copilot pela API do GitHub (opcional, desligado por padrão).
    copilot_on: bool,
    copilot_error: Option<String>,
    push_error: Option<String>,
    last_client_ago: Option<u64>,
    version: String,
    update: Option<String>,
    update_error: Option<String>,
    /// Escolha guardada ("auto" | "pt" | "en") e o idioma em uso ("pt" | "en").
    lang: String,
    lang_resolved: String,
}

fn qr_svg(text: &str) -> String {
    qrcode::QrCode::new(text.as_bytes()).map(|q| q.render::<qrcode::render::svg::Color>()
        .min_dimensions(180, 180).dark_color(qrcode::render::svg::Color("#000")).light_color(qrcode::render::svg::Color("#fff")).build())
        .unwrap_or_default()
}

#[tauri::command]
fn status(app: State<Arc<App>>, handle: AppHandle) -> Status {
    let p = app.pairing.lock().unwrap().clone();
    let link = p.link();
    let qr_svg = qr_svg(&link);
    let (code, last_client_ago) = {
        let mut l = app.lan.lock().unwrap();
        (l.current_code(), l.last_client.map(|t| t.elapsed().as_secs()))
    };
    let claude_login = collector::claude_login_on();
    Status {
        snapshot: app.snapshot.lock().unwrap().clone(),
        link, qr_svg,
        code,
        server: p.server,
        claude_connected: hook::is_installed(),
        claude_installed: collector::home().join(".claude").is_dir(),
        claude_login,
        claude_login_error: if claude_login { collector::claude_login_error().map(|e| i18n::tr(&e)) } else { None },
        copilot_on: collector::copilot_on(),
        copilot_error: if collector::copilot_on() { collector::copilot_error() } else { None },
        push_error: app.push_error.lock().unwrap().clone(),
        last_client_ago,
        version: handle.package_info().version.to_string(),
        update: app.update.lock().unwrap().clone(),
        update_error: app.update_error.lock().unwrap().as_deref().map(i18n::tr),
        lang: i18n::setting(),
        lang_resolved: i18n::lang().into(),
    }
}

/// QR de qualquer texto (o guia usa para o link do app Android).
#[tauri::command]
fn qr(text: String) -> String { qr_svg(&text) }

#[tauri::command]
fn connect_claude() -> Result<(), String> { hook::install() }

#[tauri::command]
fn disconnect_claude(app: State<Arc<App>>, handle: AppHandle) -> Result<(), String> {
    hook::uninstall()?;
    let snap = collector::collect();
    *app.snapshot.lock().unwrap() = snap.clone();
    let _ = handle.emit("snapshot", &snap);
    Ok(())
}

/// Desconecta todos os aparelhos: chave nova e reinício (o anúncio no Wi-Fi leva a chave nova).
#[tauri::command]
fn reset_pairing(app: State<Arc<App>>, handle: AppHandle) {
    app.pairing.lock().unwrap().renew();
    handle.restart();
}

/// Ler o Claude pelo login salvo (para quem usa o painel do VS Code). Ao ligar, já tenta uma leitura.
#[tauri::command]
fn set_claude_login(app: State<Arc<App>>, handle: AppHandle, on: bool) -> Result<(), String> {
    let r = collector::set_claude_login(on).map_err(|e| i18n::tr(&e));
    let snap = collector::collect();
    *app.snapshot.lock().unwrap() = snap.clone();
    let _ = handle.emit("snapshot", &snap);
    r
}

/// Ler o GitHub Copilot com o login do gh. Ao ligar, já tenta uma leitura.
#[tauri::command]
fn set_copilot(app: State<Arc<App>>, handle: AppHandle, on: bool) -> Result<(), String> {
    let r = collector::set_copilot(on);
    let snap = collector::collect();
    *app.snapshot.lock().unwrap() = snap.clone();
    let _ = handle.emit("snapshot", &snap);
    r
}

/// Campo vazio desliga o servidor (fica só o Wi-Fi local).
#[tauri::command]
fn set_server(app: State<Arc<App>>, url: String) -> Result<(), String> {
    let url = url.trim().to_string();
    if !url.is_empty() && !url.starts_with("http") { return Err(i18n::t("Endereço inválido").into()) }
    let mut p = app.pairing.lock().unwrap();
    p.server = if url.is_empty() { None } else { Some(url) };
    p.save();
    app.lan.lock().unwrap().link = p.link();
    Ok(())
}

/// Troca o idioma: guarda, refaz os textos da bandeja e avisa todas as janelas.
#[tauri::command]
fn set_lang(app: State<Arc<App>>, handle: AppHandle, lang: String) -> Result<String, String> {
    i18n::save(&lang)?;
    tray_texts(&handle, &app);
    let resolved = i18n::lang();
    let _ = handle.emit("lang-changed", serde_json::json!({ "lang": i18n::setting(), "langResolved": resolved }));
    Ok(resolved.into())
}

fn tray_texts(h: &AppHandle, app: &App) {
    if let Some(menu) = app.menu.lock().unwrap().as_ref() {
        let update = app.update.lock().unwrap().clone();
        for (id, text) in [("main", i18n::t("Abrir aparelho").to_string()), ("mini", i18n::t("Flutuante").into()),
                           ("guide", i18n::t("Primeiros passos").into()), ("quit", i18n::t("Sair").into()),
                           ("update", update.as_deref().map(i18n::update_to).unwrap_or_default())] {
            if let Some(item) = menu.get(id).and_then(|i| i.as_menuitem().cloned()) { let _ = item.set_text(text); }
        }
    }
    if let Some(tray) = h.tray_by_id("tokenbar") { let _ = tray.set_tooltip(Some(tooltip(&app.snapshot.lock().unwrap()))); }
}

#[tauri::command]
fn open_mini(handle: AppHandle) { show_mini(&handle) }

#[tauri::command]
fn open_main(handle: AppHandle) { show_main(&handle) }

fn show_main(h: &AppHandle) {
    if let Some(w) = h.get_webview_window("main") { let _ = w.show(); let _ = w.set_focus(); }
    if let Some(m) = h.get_webview_window("mini") { let _ = m.close(); }
}

/// Flutuante: pequeno, sem moldura, sempre na frente e em todas as áreas de trabalho.
fn show_mini(h: &AppHandle) {
    if let Some(w) = h.get_webview_window("mini") { let _ = w.show(); let _ = w.set_focus(); return }
    let w = WebviewWindowBuilder::new(h, "mini", WebviewUrl::App("index.html?mini=1".into()))
        .title("TokenBar")
        .inner_size(360.0, 128.0)
        .min_inner_size(220.0, 78.0)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .visible_on_all_workspaces(true)
        .skip_taskbar(true)
        .resizable(true)
        .build();
    if w.is_ok() { if let Some(m) = h.get_webview_window("main") { let _ = m.hide(); } }
}

/// Ícone da bandeja: anel de 12 pontos aceso até o maior gasto (o mesmo dos controles do Mac).
fn tray_icon(pct: f64) -> Image<'static> {
    let n = 32u32;
    let mut px = vec![0u8; (n * n * 4) as usize];
    let lit = ((pct / 100.0) * 12.0).round().clamp(0.0, 12.0) as usize;
    let color = if pct >= 85.0 { [255, 70, 70] } else { [176, 120, 255] };
    for i in 0..12 {
        let a = i as f64 / 12.0 * std::f64::consts::TAU - std::f64::consts::FRAC_PI_2;
        let (cx, cy) = (16.0 + 12.0 * a.cos(), 16.0 + 12.0 * a.sin());
        let (r, rgb, filled) = if i < lit { (3.6, color, true) } else { (3.0, [200, 200, 210], false) };
        for y in 0..n { for x in 0..n {
            let d = ((x as f64 + 0.5 - cx).powi(2) + (y as f64 + 0.5 - cy).powi(2)).sqrt();
            let inside = if filled { d <= r } else { d <= r && d >= r - 1.4 };
            if inside {
                let k = ((y * n + x) * 4) as usize;
                px[k] = rgb[0]; px[k + 1] = rgb[1]; px[k + 2] = rgb[2]; px[k + 3] = 255;
            }
        } }
    }
    Image::new_owned(px, n, n)
}

fn tooltip(s: &UsageSnapshot) -> String {
    let t = collector::now();
    let parts: Vec<String> = s.providers.iter().filter_map(|p| {
        let w = p.windows.first()?;
        let used = if w.resets_at.map(|r| r <= t).unwrap_or(false) { 0.0 } else { w.used_percent };
        Some(format!("{} {}%", p.name, used.round()))
    }).collect();
    if parts.is_empty() { i18n::t("TokenBar — sem dados").into() } else { format!("TokenBar · {}", parts.join(" · ")) }
}

fn main() {
    let pairing = Pairing::load_or_create();
    let lan = Arc::new(Mutex::new(Lan::new(&pairing)));
    net::start(lan.clone(), pairing.lan_id());
    let state = Arc::new(App {
        snapshot: Mutex::new(UsageSnapshot::default()),
        pairing: Mutex::new(pairing),
        lan,
        push_error: Mutex::new(None),
        update: Mutex::new(None),
        update_error: Mutex::new(None),
        menu: Mutex::new(None),
    });

    tauri::Builder::default()
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .manage(state.clone())
        .invoke_handler(tauri::generate_handler![status, connect_claude, disconnect_claude, reset_pairing, set_claude_login, set_copilot, set_server, set_lang, open_mini, open_main, qr,
            update::check_update, update::install_update])
        .setup(move |app| {
            let h = app.handle().clone();
            let open = MenuItem::with_id(app, "main", i18n::t("Abrir aparelho"), true, None::<&str>)?;
            let mini = MenuItem::with_id(app, "mini", i18n::t("Flutuante"), true, None::<&str>)?;
            let guide = MenuItem::with_id(app, "guide", i18n::t("Primeiros passos"), true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", i18n::t("Sair"), true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &mini, &guide, &quit])?;
            TrayIconBuilder::with_id("tokenbar")
                .icon(tray_icon(0.0))
                .tooltip("TokenBar")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|h, e| match e.id.as_ref() {
                    "main" => show_main(h),
                    "mini" => show_mini(h),
                    "guide" => { show_main(h); let _ = h.emit_to("main", "show-guide", ()); }
                    "update" => update::install_bg(h),
                    "quit" => h.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|t, e| {
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = e {
                        show_main(t.app_handle());
                    }
                })
                .build(app)?;
            *state.menu.lock().unwrap() = Some(menu.clone());
            update::start(h.clone(), menu);

            // Coleta a cada 30 s: atualiza janelas, bandeja, Wi-Fi e servidor.
            let st = state.clone();
            std::thread::spawn(move || {
                let mut last_push: Option<Instant> = None;
                let mut last_pushed: Option<UsageSnapshot> = None;
                loop {
                    let snap = collector::collect();
                    st.lan.lock().unwrap().body = serde_json::to_string(&snap).unwrap_or_default();
                    let top = snap.providers.iter().filter_map(|p| p.windows.first()).map(|w| w.used_percent).fold(0.0, f64::max);
                    if let Some(tray) = h.tray_by_id("tokenbar") {
                        let _ = tray.set_icon(Some(tray_icon(top)));
                        let _ = tray.set_tooltip(Some(tooltip(&snap)));
                    }
                    let changed = last_pushed.as_ref().map(|p| p.providers != snap.providers).unwrap_or(true);
                    let stale = last_push.map(|t| t.elapsed() > Duration::from_secs(600)).unwrap_or(true);
                    if changed || stale {
                        let p = st.pairing.lock().unwrap().clone();
                        let r = net::push(&p, &snap);
                        *st.push_error.lock().unwrap() = r.err();
                        last_push = Some(Instant::now());
                        last_pushed = Some(snap.clone());
                    }
                    *st.snapshot.lock().unwrap() = snap.clone();
                    let _ = h.emit("snapshot", &snap);
                    // Cópia para a extensão do VS Code e scripts (datas em segundos Unix).
                    if let Ok(json) = serde_json::to_string(&snap) {
                        let tmp = collector::tokenbar_dir().join("snapshot.json.tmp");
                        if std::fs::write(&tmp, json).is_ok() { let _ = std::fs::rename(&tmp, collector::tokenbar_dir().join("snapshot.json")); }
                    }
                    std::thread::sleep(Duration::from_secs(30));
                }
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("erro ao abrir o TokenBar");
}
