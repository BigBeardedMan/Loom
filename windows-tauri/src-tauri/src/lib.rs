mod agents;
mod crash;
mod db;
mod db_commands;
mod fs_walk;
mod keychain;
mod security;
mod shell_integration;
mod state;
mod terminal;
mod updater;

use anyhow::Context;
use state::AppState;
use std::sync::Arc;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tracing_subscriber::EnvFilter;

fn install_tray(app: &AppHandle) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "Show Loom", true, None::<&str>)?;
    let hide = MenuItem::with_id(app, "hide", "Hide Loom", true, None::<&str>)?;
    let sep1 = PredefinedMenuItem::separator(app)?;
    let settings = MenuItem::with_id(app, "settings", "Open Settings…", true, None::<&str>)?;
    let sep2 = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &hide, &sep1, &settings, &sep2, &quit])?;

    let icon = app
        .default_window_icon()
        .cloned()
        .ok_or_else(|| tauri::Error::Anyhow(anyhow::anyhow!("default window icon missing")))?;

    TrayIconBuilder::with_id("loom-tray")
        .icon(icon)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => {
                if let Some(w) = app.get_webview_window("main") {
                    let _ = w.show();
                    let _ = w.set_focus();
                }
            }
            "hide" => {
                if let Some(w) = app.get_webview_window("main") {
                    let _ = w.hide();
                }
            }
            "settings" => {
                if let Some(w) = app.get_webview_window("main") {
                    let _ = w.show();
                    let _ = w.set_focus();
                    let _ = w.emit("loom://open-settings", ());
                }
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(w) = app.get_webview_window("main") {
                    match w.is_visible() {
                        Ok(true) => {
                            let _ = w.hide();
                        }
                        _ => {
                            let _ = w.show();
                            let _ = w.set_focus();
                        }
                    }
                }
            }
        })
        .build(app)?;
    Ok(())
}

#[tauri::command]
fn app_version() -> &'static str {
    // Testing Edition exposes the alphanumeric LOOM_BUILD_CODE baked in by
    // build.rs. Tauri/Cargo still carry the unified Testing semver for
    // installer metadata, but the in-app build label comes from the release.
    env!("LOOM_BUILD_CODE")
}

#[tauri::command]
fn window_open(app: AppHandle, workspace_id: Option<String>) -> tauri::Result<()> {
    let count = app.webview_windows().len();
    let label = format!("loom-{count}");
    let mut builder = WebviewWindowBuilder::new(&app, &label, WebviewUrl::App("index.html".into()))
        .title("Loom Testing Edition")
        .inner_size(1280.0, 800.0)
        .min_inner_size(900.0, 600.0)
        .resizable(true);
    if let Some(ws) = workspace_id {
        builder = builder.initialization_script(&format!(
            "window.localStorage.setItem('loom.selectedWorkspaceId', '{}');",
            ws.replace('\'', "")
        ));
    }
    builder.build()?;
    Ok(())
}

#[tauri::command]
fn shell_open(state: State<'_, AppState>, target: String) -> Result<(), String> {
    let resolved = if target == "app-data" {
        state.data_dir.clone()
    } else if target.starts_with("https://") {
        let url = url::Url::parse(&target).map_err(|e| e.to_string())?;
        let host = url.host_str().unwrap_or_default();
        let allowed = url.scheme() == "https"
            && host.eq_ignore_ascii_case("github.com")
            && (url.path() == "/BigBeardedMan/Loom"
                || url.path().starts_with("/BigBeardedMan/Loom/"));
        if !allowed {
            return Err(format!("external URL is not allowed: {target}"));
        }
        return open_target(&target);
    } else {
        security::validate_app_data_path(&state, &target)?
    };
    open_target(&resolved.to_string_lossy())
}

fn open_target(target: &str) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    let mut cmd = {
        let mut c = std::process::Command::new("explorer.exe");
        c.arg(target);
        c
    };
    #[cfg(target_os = "macos")]
    let mut cmd = {
        let mut c = std::process::Command::new("open");
        c.arg(target);
        c
    };
    #[cfg(all(not(target_os = "windows"), not(target_os = "macos")))]
    let mut cmd = {
        let mut c = std::process::Command::new("xdg-open");
        c.arg(target);
        c
    };

    cmd.spawn()
        .map(|_| ())
        .map_err(|e| format!("open target: {e}"))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,loom_lib=debug")),
        )
        .with_target(false)
        .try_init();
    crash::install_hook();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            let data_dir = app.path().app_data_dir().context("resolve app data dir")?;
            std::fs::create_dir_all(&data_dir).context("create data dir")?;

            let logs_dir = data_dir.join("logs");
            std::fs::create_dir_all(&logs_dir).context("create logs dir")?;
            crash::set_log_dir(logs_dir.clone());
            crash::consume_prior_crash();

            let db_path = data_dir.join("loom.db");
            let db = db::Db::open(&db_path).context("open sqlite")?;

            let watcher_registry = Arc::new(fs_walk::WatcherRegistry::new());

            app.manage(AppState::new(db, data_dir.clone(), logs_dir.clone()));
            app.manage(watcher_registry);
            app.manage(agents::live_tasks::LiveTasksState::new(data_dir.clone()));
            agents::live_tasks::start_poller(app.handle().clone());

            install_tray(app.handle())?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            app_version,
            window_open,
            shell_open,
            db_commands::workspace_list,
            db_commands::workspace_create,
            db_commands::workspace_update,
            db_commands::workspace_delete,
            db_commands::workspace_touch_last_opened,
            db_commands::layout_save,
            db_commands::layout_get,
            db_commands::kanban_get_board,
            db_commands::kanban_create_card,
            db_commands::kanban_update_card,
            db_commands::kanban_move_card,
            db_commands::kanban_delete_card,
            db_commands::note_list,
            db_commands::note_upsert,
            db_commands::note_delete,
            db_commands::endpoint_list,
            db_commands::endpoint_upsert,
            db_commands::endpoint_delete,
            db_commands::endpoint_test,
            terminal::commands::terminal_spawn,
            terminal::commands::terminal_write,
            terminal::commands::terminal_resize,
            terminal::commands::terminal_kill,
            terminal::commands::terminal_list,
            terminal::commands::terminal_set_cwd,
            terminal::commands::terminal_update_metadata,
            terminal::commands::terminal_foreground_command,
            terminal::transcripts::terminal_transcripts_recent,
            terminal::transcripts::terminal_transcript_read,
            terminal::transcripts::terminal_transcript_restore,
            terminal::transcripts::terminal_transcript_move_to_deleted,
            terminal::transcripts::terminal_transcript_recover_deleted,
            terminal::transcripts::terminal_transcript_delete_permanently,
            terminal::transcripts::terminal_transcripts_prune,
            terminal::transcripts::terminal_transcripts_config,
            terminal::transcripts::terminal_transcripts_set_config,
            terminal::transcripts::terminal_transcripts_folder,
            terminal::command_history::command_history_list,
            terminal::command_history::command_history_read_output,
            fs_walk::fs_walk_tree,
            fs_walk::fs_read_file,
            fs_walk::fs_write_file,
            fs_walk::fs_pick_workspace_seed_files,
            fs_walk::fs_watch_start,
            fs_walk::fs_watch_stop,
            fs_walk::dialog_pick_folder,
            agents::cli::agent_cli_send,
            agents::cli::agent_registry_refresh,
            agents::anthropic::agent_http_send,
            agents::openai::agent_openai_send,
            agents::mcp::mcp_list,
            agents::mcp::mcp_add,
            agents::mcp::mcp_remove,
            agents::usage_service::usage_read,
            agents::live_tasks::live_tasks_list,
            agents::live_tasks::live_tasks_set_staleness,
            agents::live_tasks::live_tasks_clear_group,
            agents::live_tasks::live_tasks_clear_all,
            keychain::keychain_get,
            keychain::keychain_set,
            keychain::keychain_delete,
            shell_integration::shell_integration_install,
            updater::update_check,
            updater::update_apply,
            updater::update_get_arch,
            updater::update_download_and_stage,
            updater::update_run_installer,
            crash::crash_get_last,
            crash::crash_record_frontend,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
