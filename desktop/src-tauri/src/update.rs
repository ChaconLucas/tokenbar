// Atualização dentro do app: procura 10 s depois de abrir e a cada 6 h (latest.json do GitHub).
// Achou versão nova: item "Atualizar para X" na bandeja e evento `update-available` para a tecla ATUALIZAR.
use crate::App;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tauri::menu::{Menu, MenuItem};
use tauri::{AppHandle, Emitter, Manager, Wry};
use tauri_plugin_updater::UpdaterExt;

static INSTALLING: AtomicBool = AtomicBool::new(false);

fn set_error(h: &AppHandle, err: Option<String>) {
    *h.state::<Arc<App>>().update_error.lock().unwrap() = err.clone();
    if let Some(e) = err { let _ = h.emit("update-error", e); }
}

async fn find(h: &AppHandle) -> Result<Option<String>, String> {
    let found = h.updater().map_err(|e| e.to_string())?.check().await.map_err(|e| e.to_string())?;
    let v = found.map(|u| u.version);
    *h.state::<Arc<App>>().update.lock().unwrap() = v.clone();
    if let Some(v) = &v { let _ = h.emit("update-available", v); }
    Ok(v)
}

/// Procura agora (botão BUSCAR ATUALIZAÇÃO). Devolve a versão nova, se houver.
#[tauri::command]
pub async fn check_update(handle: AppHandle) -> Result<Option<String>, String> {
    let r = find(&handle).await;
    set_error(&handle, r.as_ref().err().cloned());
    r
}

/// Baixa, instala (Windows: instalador sem perguntas) e abre de novo.
#[tauri::command]
pub async fn install_update(handle: AppHandle) -> Result<(), String> {
    if INSTALLING.swap(true, Ordering::SeqCst) { return Ok(()) }
    let r = install(&handle).await;
    INSTALLING.store(false, Ordering::SeqCst);
    set_error(&handle, r.as_ref().err().cloned());
    r?;
    handle.restart()
}

async fn install(h: &AppHandle) -> Result<(), String> {
    let u = h.updater().map_err(|e| e.to_string())?.check().await.map_err(|e| e.to_string())?
        .ok_or("Já está na versão mais nova")?;
    u.download_and_install(|_, _| {}, || {}).await.map_err(|e| e.to_string())
}

/// Pela bandeja: o erro fica guardado para os ajustes.
pub fn install_bg(h: &AppHandle) {
    let h = h.clone();
    tauri::async_runtime::spawn(async move { let _ = install_update(h).await; });
}

pub fn start(h: AppHandle, menu: Menu<Wry>) {
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(10));
        loop {
            match tauri::async_runtime::block_on(find(&h)) {
                Ok(Some(v)) => {
                    set_error(&h, None);
                    let text = format!("Atualizar para {v}");
                    match menu.get("update").and_then(|i| i.as_menuitem().cloned()) {
                        Some(item) => { let _ = item.set_text(text); }
                        None => if let Ok(item) = MenuItem::with_id(&h, "update", text, true, None::<&str>) { let _ = menu.insert(&item, 0); },
                    }
                }
                Ok(None) => set_error(&h, None),
                // Sem rede ou sem release: tenta de novo na próxima volta, sem incomodar.
                Err(e) => *h.state::<Arc<App>>().update_error.lock().unwrap() = Some(e),
            }
            std::thread::sleep(Duration::from_secs(6 * 3600));
        }
    });
}
