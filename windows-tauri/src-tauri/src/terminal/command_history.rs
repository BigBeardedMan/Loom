// Mirrors Loom/Terminal/CommandHistoryService.swift.
// Reads %LOCALAPPDATA%\Loom\history.jsonl (written by the PowerShell shim
// installed via shell_integration::shell_integration_install) and returns
// the most recent commands as a struct list.

use crate::security;
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use tauri::State;

const MAX_RECORDS: usize = 500;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandRecord {
    pub id: String,
    pub command: String,
    pub cwd: String,
    pub shell: String,
    pub exit_code: i32,
    pub started_at: i64,
    pub ended_at: i64,
    pub duration_ms: i64,
    pub output_path: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StoredRecord {
    id: Option<String>,
    command: String,
    cwd: String,
    shell: Option<String>,
    exit_code: Option<i32>,
    started_at: Option<i64>,
    ended_at: Option<i64>,
    duration_ms: Option<i64>,
    output_path: Option<String>,
}

fn history_path() -> Option<PathBuf> {
    dirs::data_local_dir().map(|d| d.join("Loom").join("history.jsonl"))
}

fn read_records(path: &PathBuf) -> Vec<CommandRecord> {
    let Ok(text) = fs::read_to_string(path) else {
        return Vec::new();
    };
    let mut out: Vec<CommandRecord> = Vec::new();
    for (idx, line) in text.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Ok(s) = serde_json::from_str::<StoredRecord>(line) else {
            continue;
        };
        let started = s.started_at.unwrap_or(0);
        let id = s.id.unwrap_or_else(|| format!("{started}-{idx}"));
        if security::should_skip_command(&s.command) {
            continue;
        }
        out.push(CommandRecord {
            id,
            command: security::redact_secrets(&s.command),
            cwd: s.cwd,
            shell: s.shell.unwrap_or_else(|| "pwsh".to_string()),
            exit_code: s.exit_code.unwrap_or(0),
            started_at: started,
            ended_at: s.ended_at.unwrap_or(started),
            duration_ms: s.duration_ms.unwrap_or(0),
            output_path: s.output_path,
        });
    }
    // newest first
    out.reverse();
    out.truncate(MAX_RECORDS);
    out
}

#[tauri::command]
pub fn command_history_list(workspace_path: Option<String>) -> Vec<CommandRecord> {
    let Some(path) = history_path() else {
        return Vec::new();
    };
    let all = read_records(&path);
    match workspace_path {
        Some(cwd) if !cwd.is_empty() => {
            let cwd_norm = cwd.replace('/', "\\");
            all.into_iter()
                .filter(|r| {
                    let r_cwd = r.cwd.replace('/', "\\");
                    r_cwd.eq_ignore_ascii_case(&cwd_norm)
                        || r_cwd
                            .to_ascii_lowercase()
                            .starts_with(&format!("{}\\", cwd_norm.to_ascii_lowercase()))
                })
                .collect()
        }
        _ => all,
    }
}

#[tauri::command]
pub fn command_history_read_output(
    state: State<'_, AppState>,
    path: String,
) -> Result<String, String> {
    const MAX_BYTES: usize = 1_048_576;
    let path = security::validate_app_data_path(&state, &path)?;
    let bytes = fs::read(&path).map_err(|e| e.to_string())?;
    if bytes.len() <= MAX_BYTES {
        return Ok(security::redact_secrets(&String::from_utf8_lossy(&bytes)));
    }
    let trimmed = &bytes[..MAX_BYTES];
    let dropped = bytes.len() - MAX_BYTES;
    let prefix = security::redact_secrets(&String::from_utf8_lossy(trimmed));
    Ok(format!("{prefix}\n\n... ({dropped} more bytes truncated)"))
}
