use crate::db::{kanban, notes, workspace};
use crate::state::AppState;
use tauri::State;

#[tauri::command]
pub async fn workspace_list(
    state: State<'_, AppState>,
) -> Result<Vec<workspace::Workspace>, String> {
    workspace::list(&state.db).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn workspace_create(
    state: State<'_, AppState>,
    input: workspace::WorkspaceInput,
) -> Result<workspace::Workspace, String> {
    workspace::create(&state.db, input).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn workspace_update(
    state: State<'_, AppState>,
    id: String,
    patch: workspace::WorkspacePatch,
) -> Result<Option<workspace::Workspace>, String> {
    workspace::update(&state.db, &id, patch).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn workspace_delete(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    workspace::delete(&state.db, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn workspace_touch_last_opened(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    workspace::touch_last_opened(&state.db, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn layout_save(
    state: State<'_, AppState>,
    workspace_id: String,
    layout_json: String,
) -> Result<(), String> {
    workspace::save_layout(&state.db, &workspace_id, &layout_json).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn layout_get(
    state: State<'_, AppState>,
    workspace_id: String,
) -> Result<Option<String>, String> {
    workspace::get_layout(&state.db, &workspace_id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn kanban_get_board(
    state: State<'_, AppState>,
    workspace_id: String,
) -> Result<kanban::KanbanBoard, String> {
    kanban::get_or_create_board(&state.db, &workspace_id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn kanban_create_card(
    state: State<'_, AppState>,
    input: kanban::CardInput,
) -> Result<kanban::KanbanCard, String> {
    kanban::create_card(&state.db, input).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn kanban_update_card(
    state: State<'_, AppState>,
    id: String,
    patch: kanban::CardPatch,
) -> Result<(), String> {
    kanban::update_card(&state.db, &id, patch).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn kanban_move_card(
    state: State<'_, AppState>,
    card_id: String,
    new_column_id: String,
) -> Result<(), String> {
    kanban::move_card(&state.db, &card_id, &new_column_id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn kanban_delete_card(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    kanban::delete_card(&state.db, &id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn note_list(
    state: State<'_, AppState>,
    workspace_id: String,
) -> Result<Vec<notes::IdeaNote>, String> {
    notes::list(&state.db, &workspace_id).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn note_upsert(
    state: State<'_, AppState>,
    input: notes::NoteInput,
) -> Result<notes::IdeaNote, String> {
    notes::upsert(&state.db, input).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn note_delete(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    notes::delete(&state.db, &id).map_err(|e| e.to_string())
}
