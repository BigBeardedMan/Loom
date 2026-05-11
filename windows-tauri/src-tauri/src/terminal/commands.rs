use super::pty::{self, SessionInfo, SpawnOptions};
use crate::state::AppState;
use std::path::PathBuf;
use tauri::{AppHandle, State};

#[tauri::command]
pub async fn terminal_spawn(
    app: AppHandle,
    state: State<'_, AppState>,
    opts: SpawnOptions,
) -> Result<String, String> {
    pty::spawn(app, &state.terminals, opts).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn terminal_write(
    state: State<'_, AppState>,
    session_id: String,
    bytes: Vec<u8>,
) -> Result<(), String> {
    pty::write(&state.terminals, &session_id, bytes).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn terminal_resize(
    state: State<'_, AppState>,
    session_id: String,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    pty::resize(&state.terminals, &session_id, cols, rows).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn terminal_kill(
    state: State<'_, AppState>,
    session_id: String,
) -> Result<(), String> {
    pty::kill(&state.terminals, &session_id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn terminal_list(state: State<'_, AppState>) -> Result<Vec<SessionInfo>, String> {
    Ok(state.terminals.list())
}

#[tauri::command]
pub async fn terminal_set_cwd(
    state: State<'_, AppState>,
    session_id: String,
    cwd: String,
) -> Result<(), String> {
    pty::set_cwd(&state.terminals, &session_id, PathBuf::from(cwd)).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn terminal_foreground_command(
    state: State<'_, AppState>,
    session_id: String,
) -> Result<Option<String>, String> {
    let Some(pid) = pty::pid(&state.terminals, &session_id) else {
        return Ok(None);
    };
    #[cfg(target_os = "windows")]
    {
        Ok(super::windows_proc::active_descendant_command(pid))
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = pid;
        Ok(None)
    }
}
