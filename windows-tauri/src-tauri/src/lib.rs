mod agents;
mod db;
mod db_commands;
mod fs_walk;
mod keychain;
mod shell_integration;
mod state;
mod terminal;
mod updater;

use anyhow::Context;
use state::AppState;
use std::sync::Arc;
use tauri::Manager;
use tracing_subscriber::EnvFilter;

#[tauri::command]
fn app_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info,loom_lib=debug")))
        .with_target(false)
        .try_init();

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
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            let data_dir = app
                .path()
                .app_data_dir()
                .context("resolve app data dir")?;
            std::fs::create_dir_all(&data_dir).context("create data dir")?;

            let logs_dir = data_dir.join("logs");
            std::fs::create_dir_all(&logs_dir).context("create logs dir")?;

            let db_path = data_dir.join("loom.db");
            let db = db::Db::open(&db_path).context("open sqlite")?;

            let watcher_registry = Arc::new(fs_walk::WatcherRegistry::new());

            app.manage(AppState::new(db, data_dir.clone(), logs_dir.clone()));
            app.manage(watcher_registry);
            app.manage(agents::live_tasks::LiveTasksState::default());
            agents::live_tasks::start_poller(app.handle().clone());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            app_version,
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
            terminal::commands::terminal_spawn,
            terminal::commands::terminal_write,
            terminal::commands::terminal_resize,
            terminal::commands::terminal_kill,
            terminal::commands::terminal_list,
            terminal::commands::terminal_set_cwd,
            terminal::commands::terminal_foreground_command,
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
            agents::mcp::mcp_list,
            agents::mcp::mcp_add,
            agents::mcp::mcp_remove,
            agents::usage_service::usage_read,
            agents::live_tasks::live_tasks_list,
            agents::live_tasks::live_tasks_set_staleness,
            keychain::keychain_get,
            keychain::keychain_set,
            keychain::keychain_delete,
            shell_integration::shell_integration_install,
            updater::update_check,
            updater::update_apply,
            updater::update_get_arch,
            updater::update_download_and_stage,
            updater::update_run_installer,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
