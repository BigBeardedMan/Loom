use crate::security;
use crate::state::AppState;
use anyhow::{Context, Result};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

const SKIP_NAMES: &[&str] = &[
    ".git",
    ".svn",
    ".hg",
    "node_modules",
    "target",
    "build",
    "dist",
    ".next",
    ".vercel",
    ".turbo",
    ".cache",
    ".DS_Store",
    "Thumbs.db",
    "DerivedData",
    ".gradle",
    ".idea",
    ".vscode",
    "__pycache__",
    ".venv",
    "venv",
    ".pytest_cache",
];

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FsNode {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified_ms: i64,
    #[serde(default)]
    pub children: Vec<FsNode>,
}

#[tauri::command]
pub async fn fs_walk_tree(
    state: State<'_, AppState>,
    root: String,
    max_depth: Option<usize>,
    show_hidden: Option<bool>,
) -> Result<FsNode, String> {
    let depth = max_depth.unwrap_or(8);
    let hidden = show_hidden.unwrap_or(false);
    let root = security::validate_existing_path(&state, &root)?;
    let roots = security::allowed_roots(&state);
    walk(&root, &roots, depth, hidden, 0).map_err(|e| e.to_string())
}

fn walk(
    path: &Path,
    allowed_roots: &[PathBuf],
    max_depth: usize,
    show_hidden: bool,
    depth: usize,
) -> Result<FsNode> {
    let meta = std::fs::metadata(path).with_context(|| format!("stat {path:?}"))?;
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned());
    let modified_ms = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);

    let mut node = FsNode {
        name,
        path: path.to_string_lossy().into_owned(),
        is_dir: meta.is_dir(),
        size: if meta.is_file() { meta.len() } else { 0 },
        modified_ms,
        children: Vec::new(),
    };

    if !meta.is_dir() || depth >= max_depth {
        return Ok(node);
    }

    let entries = match std::fs::read_dir(path) {
        Ok(e) => e,
        Err(_) => return Ok(node),
    };

    let mut children: Vec<FsNode> = Vec::new();
    for entry in entries.flatten() {
        let entry_path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if !show_hidden && name.starts_with('.') {
            continue;
        }
        if SKIP_NAMES.iter().any(|s| *s == name) {
            continue;
        }
        if security::is_path_sensitive(&entry_path) {
            continue;
        }
        let Ok(canonical) = std::fs::canonicalize(&entry_path) else {
            continue;
        };
        if !allowed_roots
            .iter()
            .any(|root| security::path_is_within(&canonical, root))
        {
            continue;
        }
        if let Ok(child) = walk(&canonical, allowed_roots, max_depth, show_hidden, depth + 1) {
            children.push(child);
        }
    }
    children.sort_by(|a, b| match (a.is_dir, b.is_dir) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
    });
    node.children = children;
    Ok(node)
}

#[tauri::command]
pub async fn fs_read_file(state: State<'_, AppState>, path: String) -> Result<String, String> {
    let path = security::validate_existing_path(&state, &path)?;
    let text = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    Ok(security::redact_secrets(&text))
}

#[tauri::command]
pub async fn fs_write_file(
    state: State<'_, AppState>,
    path: String,
    contents: String,
) -> Result<(), String> {
    let path = security::validate_write_path(&state, &path)?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::write(&path, contents).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn fs_pick_workspace_seed_files(
    state: State<'_, AppState>,
    folder: String,
) -> Result<Vec<String>, String> {
    let folder = security::validate_existing_path(&state, &folder)?;
    let candidates = ["CLAUDE.md", "AGENTS.md", "GUIDE.md", "README.md"];
    let mut found = Vec::new();
    for name in candidates {
        let p = folder.join(name);
        if p.exists() {
            found.push(p.to_string_lossy().into_owned());
        }
    }
    Ok(found)
}

pub struct WatcherRegistry {
    inner: Mutex<HashMap<String, notify_debouncer_mini::Debouncer<notify::RecommendedWatcher>>>,
}

impl WatcherRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }
}

impl Default for WatcherRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FsChangeEvent {
    pub paths: Vec<String>,
}

#[tauri::command]
pub async fn fs_watch_start(
    app: AppHandle,
    state: State<'_, AppState>,
    registry: State<'_, Arc<WatcherRegistry>>,
    root: String,
) -> Result<String, String> {
    let root = security::validate_existing_path(&state, &root)?;
    let id = Uuid::new_v4().to_string();
    let app_clone = app.clone();
    let id_clone = id.clone();
    let debouncer = notify_debouncer_mini::new_debouncer(
        Duration::from_millis(250),
        move |res: notify_debouncer_mini::DebounceEventResult| {
            if let Ok(events) = res {
                let paths: Vec<String> = events
                    .into_iter()
                    .map(|e| e.path.to_string_lossy().into_owned())
                    .collect();
                if paths.is_empty() {
                    return;
                }
                let _ = app_clone.emit(&format!("fs://{id_clone}/change"), FsChangeEvent { paths });
            }
        },
    )
    .map_err(|e| e.to_string())?;

    let mut deb = debouncer;
    deb.watcher()
        .watch(&root, notify::RecursiveMode::Recursive)
        .map_err(|e| e.to_string())?;
    registry.inner.lock().insert(id.clone(), deb);
    Ok(id)
}

#[tauri::command]
pub async fn fs_watch_stop(
    registry: State<'_, Arc<WatcherRegistry>>,
    watch_id: String,
) -> Result<(), String> {
    registry.inner.lock().remove(&watch_id);
    Ok(())
}

#[tauri::command]
pub async fn dialog_pick_folder(app: AppHandle) -> Result<Option<PathBuf>, String> {
    use tauri_plugin_dialog::DialogExt;
    let (tx, rx) = tokio::sync::oneshot::channel();
    app.dialog().file().pick_folder(move |folder| {
        let _ = tx.send(folder);
    });
    let folder = rx.await.map_err(|e| e.to_string())?;
    Ok(folder.and_then(|f| f.into_path().ok()))
}
