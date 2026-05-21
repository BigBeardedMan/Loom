use crate::state::AppState;
use anyhow::{Context, Result};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::fs::{self, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use tauri::State;

const DEFAULT_STORAGE_LIMIT_BYTES: i64 = 1_073_741_824;
const DEFAULT_PREVIEW_LIMIT_BYTES: usize = 2_000_000;
const RESTORE_IMPORT_LIMIT_BYTES: usize = 10_000_000;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TerminalTranscriptSession {
    pub id: String,
    pub workspace_id: Option<String>,
    pub workspace_name: Option<String>,
    pub cwd: String,
    pub title: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub closed_at: Option<i64>,
    pub deleted_at: Option<i64>,
    pub state: String,
    pub byte_count: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalTranscriptRestore {
    pub session_id: String,
    pub cwd: String,
    pub title: String,
    pub transcript_text: String,
    pub was_truncated: bool,
    pub imported_byte_limit: usize,
    pub transcript_byte_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalTranscriptConfig {
    pub enabled: bool,
    pub max_bytes: i64,
    pub total_bytes: i64,
    pub base_dir: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalTranscriptConfigPatch {
    pub enabled: Option<bool>,
    pub max_bytes: Option<i64>,
}

#[derive(Debug)]
struct TranscriptInner {
    sessions: Vec<TerminalTranscriptSession>,
    enabled: bool,
    max_bytes: i64,
}

#[derive(Debug)]
pub struct TerminalTranscriptStore {
    base_dir: PathBuf,
    transcripts_dir: PathBuf,
    metadata_path: PathBuf,
    config_path: PathBuf,
    inner: Mutex<TranscriptInner>,
}

impl TerminalTranscriptStore {
    pub fn new(base_dir: PathBuf) -> Self {
        let transcripts_dir = base_dir.join("transcripts");
        let metadata_path = base_dir.join("sessions.json");
        let config_path = base_dir.join("config.json");
        let _ = fs::create_dir_all(&transcripts_dir);

        let sessions =
            read_json::<Vec<TerminalTranscriptSession>>(&metadata_path).unwrap_or_default();
        let config = read_json::<SavedConfig>(&config_path).unwrap_or_default();
        let store = Self {
            base_dir,
            transcripts_dir,
            metadata_path,
            config_path,
            inner: Mutex::new(TranscriptInner {
                sessions,
                enabled: config.enabled.unwrap_or(true),
                max_bytes: config
                    .max_bytes
                    .unwrap_or(DEFAULT_STORAGE_LIMIT_BYTES)
                    .max(50_000_000),
            }),
        };
        store.sweep_orphaned_active_sessions();
        store.refresh_usage();
        store.enforce_storage_limit();
        store
    }

    pub fn register(
        &self,
        session_id: &str,
        workspace_id: Option<String>,
        workspace_name: Option<String>,
        cwd: String,
        title: String,
    ) {
        if !self.is_enabled() {
            return;
        }
        self.ensure_dirs();
        let now = now_ms();
        let transcript_path = self.transcript_path(session_id);
        if !transcript_path.exists() {
            let _ = fs::File::create(&transcript_path);
        }
        let size = file_size(&transcript_path);
        let mut inner = self.inner.lock();
        if let Some(existing) = inner.sessions.iter_mut().find(|s| s.id == session_id) {
            existing.workspace_id = workspace_id;
            existing.workspace_name = workspace_name;
            existing.cwd = cwd;
            if !title.trim().is_empty() {
                existing.title = title;
            }
            existing.state = "active".to_string();
            existing.closed_at = None;
            existing.deleted_at = None;
            existing.updated_at = now;
            existing.byte_count = size;
        } else {
            inner.sessions.push(TerminalTranscriptSession {
                id: session_id.to_string(),
                workspace_id,
                workspace_name,
                cwd,
                title,
                created_at: now,
                updated_at: now,
                closed_at: None,
                deleted_at: None,
                state: "active".to_string(),
                byte_count: size,
            });
        }
        drop(inner);
        self.save_sessions();
    }

    pub fn append(&self, session_id: &str, bytes: &[u8]) {
        if bytes.is_empty() || !self.is_enabled() {
            return;
        }
        self.ensure_dirs();
        let path = self.transcript_path(session_id);
        if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&path) {
            let _ = file.write_all(bytes);
        }
    }

    pub fn update(&self, session_id: &str, cwd: Option<String>, title: Option<String>) {
        let mut changed = false;
        let now = now_ms();
        {
            let mut inner = self.inner.lock();
            if let Some(existing) = inner.sessions.iter_mut().find(|s| s.id == session_id) {
                if let Some(cwd) = cwd.filter(|v| !v.trim().is_empty()) {
                    existing.cwd = cwd;
                    changed = true;
                }
                if let Some(title) = title.filter(|v| !v.trim().is_empty()) {
                    existing.title = title;
                    changed = true;
                }
                if changed {
                    existing.updated_at = now;
                    existing.byte_count = file_size(&self.transcript_path(session_id));
                }
            }
        }
        if changed {
            self.save_sessions();
        }
    }

    pub fn close(&self, session_id: &str) {
        let mut changed = false;
        let now = now_ms();
        {
            let mut inner = self.inner.lock();
            if let Some(existing) = inner.sessions.iter_mut().find(|s| s.id == session_id) {
                if existing.state == "active" {
                    existing.state = "closed".to_string();
                    existing.closed_at = Some(now);
                    existing.updated_at = now;
                    existing.byte_count = file_size(&self.transcript_path(session_id));
                    changed = true;
                }
            }
        }
        if changed {
            self.save_sessions();
            self.enforce_storage_limit();
        }
    }

    pub fn list_recent(
        &self,
        state_filter: &str,
        workspace_id: Option<&str>,
        limit: usize,
    ) -> Vec<TerminalTranscriptSession> {
        let mut sessions: Vec<_> = self
            .inner
            .lock()
            .sessions
            .iter()
            .filter(|s| s.state == state_filter)
            .filter(|s| {
                workspace_id
                    .filter(|id| !id.is_empty())
                    .map(|id| s.workspace_id.as_deref() == Some(id))
                    .unwrap_or(true)
            })
            .cloned()
            .collect();
        sessions.sort_by(|a, b| {
            let at = if state_filter == "deleted" {
                a.deleted_at.unwrap_or(a.updated_at)
            } else {
                a.closed_at.unwrap_or(a.updated_at)
            };
            let bt = if state_filter == "deleted" {
                b.deleted_at.unwrap_or(b.updated_at)
            } else {
                b.closed_at.unwrap_or(b.updated_at)
            };
            bt.cmp(&at)
        });
        if limit > 0 && sessions.len() > limit {
            sessions.truncate(limit);
        }
        sessions
    }

    pub fn move_to_deleted(&self, session_id: &str) {
        let now = now_ms();
        let mut changed = false;
        {
            let mut inner = self.inner.lock();
            if let Some(existing) = inner.sessions.iter_mut().find(|s| s.id == session_id) {
                existing.state = "deleted".to_string();
                existing.deleted_at = Some(now);
                existing.updated_at = now;
                changed = true;
            }
        }
        if changed {
            self.save_sessions();
            self.enforce_storage_limit();
        }
    }

    pub fn recover_deleted(&self, session_id: &str) {
        let now = now_ms();
        let mut changed = false;
        {
            let mut inner = self.inner.lock();
            if let Some(existing) = inner.sessions.iter_mut().find(|s| s.id == session_id) {
                existing.state = "closed".to_string();
                existing.deleted_at = None;
                existing.updated_at = now;
                changed = true;
            }
        }
        if changed {
            self.save_sessions();
        }
    }

    pub fn delete_permanently(&self, session_id: &str) {
        let _ = fs::remove_file(self.transcript_path(session_id));
        {
            let mut inner = self.inner.lock();
            inner.sessions.retain(|s| s.id != session_id);
        }
        self.save_sessions();
    }

    pub fn restore_closed(
        &self,
        session_id: &str,
        fallback_cwd: &str,
    ) -> Option<TerminalTranscriptRestore> {
        let saved = {
            let inner = self.inner.lock();
            inner
                .sessions
                .iter()
                .find(|s| s.id == session_id && s.state == "closed")
                .cloned()
        }?;
        let transcript_byte_count = file_size(&self.transcript_path(session_id));
        let restore = TerminalTranscriptRestore {
            session_id: saved.id.clone(),
            cwd: resolved_directory(&saved.cwd, fallback_cwd),
            title: display_title(&saved.title),
            transcript_text: self.read_text(session_id, Some(RESTORE_IMPORT_LIMIT_BYTES), false),
            was_truncated: transcript_byte_count > RESTORE_IMPORT_LIMIT_BYTES as i64,
            imported_byte_limit: RESTORE_IMPORT_LIMIT_BYTES,
            transcript_byte_count,
        };
        let now = now_ms();
        {
            let mut inner = self.inner.lock();
            if let Some(existing) = inner.sessions.iter_mut().find(|s| s.id == session_id) {
                existing.state = "active".to_string();
                existing.closed_at = None;
                existing.deleted_at = None;
                existing.updated_at = now;
                existing.byte_count = transcript_byte_count;
            }
        }
        self.save_sessions();
        Some(restore)
    }

    pub fn read_text(
        &self,
        session_id: &str,
        max_bytes: Option<usize>,
        include_trim_notice: bool,
    ) -> String {
        let path = self.transcript_path(session_id);
        let Ok(mut file) = fs::File::open(&path) else {
            return "(transcript file missing)".to_string();
        };
        let size = file.seek(SeekFrom::End(0)).unwrap_or(0);
        let offset = match max_bytes {
            Some(limit) if size > limit as u64 => size - limit as u64,
            _ => 0,
        };
        let _ = file.seek(SeekFrom::Start(offset));
        let mut bytes = Vec::new();
        let _ = file.read_to_end(&mut bytes);
        let text = ansi_plain_text(&bytes);
        if include_trim_notice && offset > 0 {
            format!(
                "... earlier transcript trimmed in this viewer; the saved file is larger\n\n{text}"
            )
        } else if text.trim().is_empty() {
            "(empty transcript)".to_string()
        } else {
            text
        }
    }

    pub fn prune_saved_history(&self) {
        let now = now_ms();
        let active_ids: Vec<String> = {
            let mut inner = self.inner.lock();
            let active_ids: Vec<String> = inner
                .sessions
                .iter()
                .filter(|s| s.state == "active")
                .map(|s| s.id.clone())
                .collect();
            for session in &mut inner.sessions {
                if session.state == "active" {
                    let path = self.transcript_path(&session.id);
                    let _ = OpenOptions::new()
                        .create(true)
                        .write(true)
                        .truncate(true)
                        .open(path);
                    session.byte_count = 0;
                    session.updated_at = now;
                } else {
                    let _ = fs::remove_file(self.transcript_path(&session.id));
                }
            }
            inner.sessions.retain(|s| s.state == "active");
            active_ids
        };
        for id in active_ids {
            let path = self.transcript_path(&id);
            if !path.exists() {
                let _ = fs::File::create(path);
            }
        }
        self.save_sessions();
    }

    pub fn config(&self) -> TerminalTranscriptConfig {
        let total = self.refresh_usage();
        let inner = self.inner.lock();
        TerminalTranscriptConfig {
            enabled: inner.enabled,
            max_bytes: inner.max_bytes,
            total_bytes: total,
            base_dir: self.base_dir.to_string_lossy().into_owned(),
        }
    }

    pub fn patch_config(&self, patch: TerminalTranscriptConfigPatch) -> TerminalTranscriptConfig {
        {
            let mut inner = self.inner.lock();
            if let Some(enabled) = patch.enabled {
                inner.enabled = enabled;
            }
            if let Some(max_bytes) = patch.max_bytes {
                inner.max_bytes = max_bytes.max(50_000_000);
            }
        }
        self.save_config();
        self.enforce_storage_limit();
        self.config()
    }

    fn is_enabled(&self) -> bool {
        self.inner.lock().enabled
    }

    fn ensure_dirs(&self) {
        let _ = fs::create_dir_all(&self.transcripts_dir);
    }

    fn transcript_path(&self, session_id: &str) -> PathBuf {
        self.transcripts_dir.join(format!("{session_id}.ansi"))
    }

    fn save_sessions(&self) {
        self.ensure_dirs();
        let sessions = self.inner.lock().sessions.clone();
        if let Ok(data) = serde_json::to_vec_pretty(&sessions) {
            let _ = fs::write(&self.metadata_path, data);
        }
    }

    fn save_config(&self) {
        self.ensure_dirs();
        let inner = self.inner.lock();
        let config = SavedConfig {
            enabled: Some(inner.enabled),
            max_bytes: Some(inner.max_bytes),
        };
        if let Ok(data) = serde_json::to_vec_pretty(&config) {
            let _ = fs::write(&self.config_path, data);
        }
    }

    fn sweep_orphaned_active_sessions(&self) {
        let now = now_ms();
        let mut changed = false;
        {
            let mut inner = self.inner.lock();
            for session in &mut inner.sessions {
                if session.state == "active" {
                    session.state = "closed".to_string();
                    session.closed_at = session.closed_at.or(Some(now));
                    session.updated_at = now;
                    changed = true;
                }
            }
        }
        if changed {
            self.save_sessions();
        }
    }

    fn refresh_usage(&self) -> i64 {
        let snapshots: Vec<(String, i64)> = {
            let inner = self.inner.lock();
            inner
                .sessions
                .iter()
                .map(|s| (s.id.clone(), file_size(&self.transcript_path(&s.id))))
                .collect()
        };
        let total = snapshots.iter().map(|(_, size)| *size).sum();
        {
            let mut inner = self.inner.lock();
            for (id, size) in snapshots {
                if let Some(session) = inner.sessions.iter_mut().find(|s| s.id == id) {
                    session.byte_count = size;
                }
            }
        }
        self.save_sessions();
        total
    }

    fn enforce_storage_limit(&self) {
        let total = self.refresh_usage();
        let limit = self.inner.lock().max_bytes;
        if total <= limit {
            return;
        }
        let mut candidates: Vec<_> = {
            let inner = self.inner.lock();
            inner
                .sessions
                .iter()
                .filter(|s| s.state != "active")
                .cloned()
                .collect()
        };
        candidates.sort_by(|a, b| {
            if a.state != b.state {
                return if a.state == "deleted" {
                    std::cmp::Ordering::Less
                } else {
                    std::cmp::Ordering::Greater
                };
            }
            a.updated_at.cmp(&b.updated_at)
        });
        for session in candidates {
            self.delete_permanently(&session.id);
            if self.refresh_usage() <= limit {
                break;
            }
        }
    }
}

#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SavedConfig {
    enabled: Option<bool>,
    max_bytes: Option<i64>,
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Option<T> {
    let data = fs::read(path).ok()?;
    serde_json::from_slice(&data).ok()
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn file_size(path: &Path) -> i64 {
    fs::metadata(path).map(|m| m.len() as i64).unwrap_or(0)
}

fn display_title(title: &str) -> String {
    let trimmed = title.trim();
    if trimmed.is_empty() {
        "Terminal Session".to_string()
    } else {
        trimmed.to_string()
    }
}

fn resolved_directory(saved: &str, fallback: &str) -> String {
    let saved_path = PathBuf::from(saved);
    if saved_path.is_dir() {
        return saved_path.to_string_lossy().into_owned();
    }
    let fallback_path = PathBuf::from(fallback);
    if fallback_path.is_dir() {
        fallback_path.to_string_lossy().into_owned()
    } else {
        dirs::home_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .to_string_lossy()
            .into_owned()
    }
}

fn ansi_plain_text(bytes: &[u8]) -> String {
    let text = String::from_utf8_lossy(bytes);
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\u{1b}' {
            match chars.peek().copied() {
                Some(']') => {
                    let _ = chars.next();
                    while let Some(next) = chars.next() {
                        if next == '\u{7}' {
                            break;
                        }
                        if next == '\u{1b}' && chars.peek() == Some(&'\\') {
                            let _ = chars.next();
                            break;
                        }
                    }
                }
                _ => {
                    while let Some(next) = chars.next() {
                        let value = next as u32;
                        if (0x40..=0x7e).contains(&value) {
                            break;
                        }
                    }
                }
            }
            continue;
        }
        match ch {
            '\r' => out.push('\n'),
            '\u{8}' => {
                let _ = out.pop();
            }
            '\u{7}' => {}
            _ => out.push(ch),
        }
    }
    out.replace("\n\n\n", "\n\n")
        .lines()
        .map(|line| line.trim_matches(char::is_control))
        .collect::<Vec<_>>()
        .join("\n")
}

#[tauri::command]
pub fn terminal_transcripts_recent(
    state: State<'_, AppState>,
    transcript_state: String,
    workspace_id: Option<String>,
    limit: Option<usize>,
) -> Result<Vec<TerminalTranscriptSession>, String> {
    Ok(state.terminal_transcripts.list_recent(
        &transcript_state,
        workspace_id.as_deref(),
        limit.unwrap_or(0),
    ))
}

#[tauri::command]
pub fn terminal_transcript_read(
    state: State<'_, AppState>,
    session_id: String,
    max_bytes: Option<usize>,
) -> Result<String, String> {
    Ok(state.terminal_transcripts.read_text(
        &session_id,
        Some(max_bytes.unwrap_or(DEFAULT_PREVIEW_LIMIT_BYTES)),
        true,
    ))
}

#[tauri::command]
pub fn terminal_transcript_restore(
    state: State<'_, AppState>,
    session_id: String,
    fallback_cwd: String,
) -> Result<Option<TerminalTranscriptRestore>, String> {
    Ok(state
        .terminal_transcripts
        .restore_closed(&session_id, &fallback_cwd))
}

#[tauri::command]
pub fn terminal_transcript_move_to_deleted(
    state: State<'_, AppState>,
    session_id: String,
) -> Result<(), String> {
    state.terminal_transcripts.move_to_deleted(&session_id);
    Ok(())
}

#[tauri::command]
pub fn terminal_transcript_recover_deleted(
    state: State<'_, AppState>,
    session_id: String,
) -> Result<(), String> {
    state.terminal_transcripts.recover_deleted(&session_id);
    Ok(())
}

#[tauri::command]
pub fn terminal_transcript_delete_permanently(
    state: State<'_, AppState>,
    session_id: String,
) -> Result<(), String> {
    state.terminal_transcripts.delete_permanently(&session_id);
    Ok(())
}

#[tauri::command]
pub fn terminal_transcripts_prune(state: State<'_, AppState>) -> Result<(), String> {
    state.terminal_transcripts.prune_saved_history();
    Ok(())
}

#[tauri::command]
pub fn terminal_transcripts_config(
    state: State<'_, AppState>,
) -> Result<TerminalTranscriptConfig, String> {
    Ok(state.terminal_transcripts.config())
}

#[tauri::command]
pub fn terminal_transcripts_set_config(
    state: State<'_, AppState>,
    patch: TerminalTranscriptConfigPatch,
) -> Result<TerminalTranscriptConfig, String> {
    Ok(state.terminal_transcripts.patch_config(patch))
}

#[tauri::command]
pub fn terminal_transcripts_folder(state: State<'_, AppState>) -> Result<String, String> {
    state
        .terminal_transcripts
        .base_dir
        .canonicalize()
        .or_else(|_| Ok::<PathBuf, anyhow::Error>(state.terminal_transcripts.base_dir.clone()))
        .map(|p| p.to_string_lossy().into_owned())
        .context("terminal transcript folder")
        .map_err(|e| e.to_string())
}
