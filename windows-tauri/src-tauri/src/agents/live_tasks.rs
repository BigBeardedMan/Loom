// Mirrors Loom/Agents/LiveAgentTasks.swift.
// Polls ~/.claude/tasks/<session>/<id>.json and ~/.codex/sessions/.../*.jsonl
// for live AI agent task state and emits a Tauri event when it changes.

use chrono::{DateTime, Local, TimeZone, Utc};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager};

#[derive(Debug, Clone, Serialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub struct LiveAgentTask {
    pub id: String,
    pub source: String,
    pub session_id: String,
    pub task_id: String,
    pub subject: String,
    pub description: String,
    pub active_form: String,
    pub status: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub struct LiveAgentTaskGroup {
    pub id: String,
    pub session_id: String,
    pub source: String,
    pub last_activity: String,
    pub headline: Option<String>,
    pub tasks: Vec<LiveAgentTask>,
}

pub struct LiveTasksState {
    pub groups: Arc<Mutex<Vec<LiveAgentTaskGroup>>>,
    pub staleness_secs: Arc<Mutex<u64>>,
}

impl Default for LiveTasksState {
    fn default() -> Self {
        Self {
            groups: Arc::new(Mutex::new(Vec::new())),
            staleness_secs: Arc::new(Mutex::new(60 * 60)),
        }
    }
}

fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from("."))
}

fn file_mtime(path: &Path) -> Option<DateTime<Local>> {
    let md = fs::metadata(path).ok()?;
    let modified = md.modified().ok()?;
    let secs = modified
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_secs() as i64;
    Some(
        Utc.timestamp_opt(secs, 0)
            .single()?
            .with_timezone(&Local),
    )
}

fn read_text(path: &Path) -> Option<String> {
    let mut f = fs::File::open(path).ok()?;
    let mut s = String::new();
    f.read_to_string(&mut s).ok()?;
    Some(s)
}

fn status_sort_priority(status: &str) -> u8 {
    match status {
        "in_progress" => 0,
        "pending" => 1,
        "completed" => 2,
        "cancelled" => 3,
        _ => 4,
    }
}

#[derive(Deserialize)]
struct ClaudeTaskFile {
    id: Option<String>,
    subject: Option<String>,
    description: Option<String>,
    #[serde(rename = "activeForm")]
    active_form: Option<String>,
    status: Option<String>,
}

fn collect_claude_groups(root: &Path, cutoff: DateTime<Local>) -> Vec<LiveAgentTaskGroup> {
    let mut out: Vec<LiveAgentTaskGroup> = Vec::new();
    let Ok(entries) = fs::read_dir(root) else {
        return out;
    };
    for entry in entries.flatten() {
        let dir = entry.path();
        if !dir.is_dir() {
            continue;
        }
        let Ok(inner) = fs::read_dir(&dir) else {
            continue;
        };
        let mut json_files: Vec<(PathBuf, DateTime<Local>)> = Vec::new();
        for f in inner.flatten() {
            let p = f.path();
            if p.extension().and_then(|s| s.to_str()) != Some("json") {
                continue;
            }
            if let Some(m) = file_mtime(&p) {
                json_files.push((p, m));
            }
        }
        if json_files.is_empty() {
            continue;
        }
        let most_recent = json_files.iter().map(|(_, m)| *m).max().unwrap();
        if most_recent < cutoff {
            continue;
        }

        let session_id = dir
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string();
        let mut tasks: Vec<LiveAgentTask> = Vec::new();
        for (path, mtime) in json_files {
            let Some(text) = read_text(&path) else { continue };
            let Ok(payload) = serde_json::from_str::<ClaudeTaskFile>(&text) else {
                continue;
            };
            let status = payload.status.unwrap_or_else(|| "pending".to_string());
            if status == "deleted" {
                continue;
            }
            let task_id = payload.id.unwrap_or_default();
            let composite = format!("claude:{}:{}", session_id, task_id);
            tasks.push(LiveAgentTask {
                id: composite,
                source: "claude".to_string(),
                session_id: session_id.clone(),
                task_id,
                subject: payload.subject.unwrap_or_else(|| "(no subject)".to_string()),
                description: payload.description.unwrap_or_default(),
                active_form: payload.active_form.unwrap_or_default(),
                status,
                updated_at: mtime.to_rfc3339(),
            });
        }
        if tasks.is_empty() {
            continue;
        }
        tasks.sort_by(|a, b| {
            let pa = status_sort_priority(&a.status);
            let pb = status_sort_priority(&b.status);
            pa.cmp(&pb).then_with(|| b.updated_at.cmp(&a.updated_at))
        });
        let headline = tasks
            .iter()
            .find(|t| t.status == "in_progress")
            .map(|t| {
                let af = t.active_form.trim();
                if af.is_empty() {
                    t.subject.clone()
                } else {
                    af.to_string()
                }
            })
            .or_else(|| tasks.first().map(|t| t.subject.clone()));

        out.push(LiveAgentTaskGroup {
            id: format!("claude:{}", session_id),
            session_id,
            source: "claude".to_string(),
            last_activity: most_recent.to_rfc3339(),
            headline,
            tasks,
        });
    }
    out
}

#[derive(Deserialize)]
struct CodexLinePayload {
    #[serde(rename = "type")]
    ty: Option<String>,
    name: Option<String>,
    arguments: Option<String>,
}

#[derive(Deserialize)]
struct CodexLine {
    payload: Option<CodexLinePayload>,
}

#[derive(Deserialize)]
struct CodexPlanArgs {
    plan: Vec<CodexPlanStep>,
}

#[derive(Deserialize, Clone)]
struct CodexPlanStep {
    step: String,
    status: String,
}

fn codex_session_id(path: &Path) -> String {
    let base = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_string();
    // Rollout filenames end with a UUID: 8-4-4-4-12 (36 ASCII chars).
    if base.is_ascii() && base.len() >= 36 {
        let candidate = &base[base.len() - 36..];
        let parts: Vec<&str> = candidate.split('-').collect();
        if parts.len() == 5
            && parts[0].len() == 8
            && parts[1].len() == 4
            && parts[2].len() == 4
            && parts[3].len() == 4
            && parts[4].len() == 12
        {
            return candidate.to_string();
        }
    }
    base
}

fn map_codex_status(raw: &str) -> &'static str {
    match raw {
        "in_progress" => "in_progress",
        "completed" => "completed",
        "cancelled" => "cancelled",
        _ => "pending",
    }
}

fn read_latest_codex_plan(path: &Path) -> Option<Vec<CodexPlanStep>> {
    let text = read_text(path)?;
    let mut latest: Option<Vec<CodexPlanStep>> = None;
    for line in text.lines() {
        if !line.contains("\"update_plan\"") {
            continue;
        }
        let Ok(parsed) = serde_json::from_str::<CodexLine>(line) else {
            continue;
        };
        let Some(payload) = parsed.payload else { continue };
        if payload.ty.as_deref() != Some("function_call") {
            continue;
        }
        if payload.name.as_deref() != Some("update_plan") {
            continue;
        }
        let Some(args) = payload.arguments else { continue };
        let Ok(envelope) = serde_json::from_str::<CodexPlanArgs>(&args) else {
            continue;
        };
        latest = Some(envelope.plan);
    }
    latest
}

fn walk_jsonl(root: &Path, visit: &mut dyn FnMut(&Path)) {
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            walk_jsonl(&path, visit);
        } else if path.extension().and_then(|s| s.to_str()) == Some("jsonl") {
            visit(&path);
        }
    }
}

fn collect_codex_groups(root: &Path, cutoff: DateTime<Local>) -> Vec<LiveAgentTaskGroup> {
    let mut out: Vec<LiveAgentTaskGroup> = Vec::new();
    if !root.exists() {
        return out;
    }
    let mut paths: Vec<(PathBuf, DateTime<Local>)> = Vec::new();
    walk_jsonl(root, &mut |p| {
        if let Some(m) = file_mtime(p) {
            if m >= cutoff {
                paths.push((p.to_path_buf(), m));
            }
        }
    });
    for (path, mtime) in paths {
        let session_id = codex_session_id(&path);
        let Some(plan) = read_latest_codex_plan(&path) else {
            continue;
        };
        if plan.is_empty() {
            continue;
        }
        let tasks: Vec<LiveAgentTask> = plan
            .into_iter()
            .enumerate()
            .map(|(i, step)| LiveAgentTask {
                id: format!("codex:{}:{}", session_id, i),
                source: "codex".to_string(),
                session_id: session_id.clone(),
                task_id: i.to_string(),
                subject: step.step.clone(),
                description: String::new(),
                active_form: step.step.clone(),
                status: map_codex_status(&step.status).to_string(),
                updated_at: mtime.to_rfc3339(),
            })
            .collect();
        let headline = tasks
            .iter()
            .find(|t| t.status == "in_progress")
            .map(|t| t.subject.clone())
            .or_else(|| tasks.first().map(|t| t.subject.clone()));
        out.push(LiveAgentTaskGroup {
            id: format!("codex:{}", session_id),
            session_id: session_id.clone(),
            source: "codex".to_string(),
            last_activity: mtime.to_rfc3339(),
            headline,
            tasks,
        });
    }
    out
}

pub fn collect_all_groups(staleness_secs: u64) -> Vec<LiveAgentTaskGroup> {
    let h = home();
    let cutoff = Local::now() - chrono::Duration::seconds(staleness_secs as i64);
    let mut groups = Vec::new();
    groups.extend(collect_claude_groups(&h.join(".claude").join("tasks"), cutoff));
    groups.extend(collect_codex_groups(&h.join(".codex").join("sessions"), cutoff));
    groups.sort_by(|a, b| b.last_activity.cmp(&a.last_activity));
    groups
}

pub fn start_poller(app: AppHandle) {
    let state = app.state::<LiveTasksState>().inner().groups.clone();
    let staleness = app.state::<LiveTasksState>().inner().staleness_secs.clone();
    let app2 = app.clone();
    tokio::spawn(async move {
        loop {
            let secs = *staleness.lock();
            let groups = tokio::task::spawn_blocking(move || collect_all_groups(secs))
                .await
                .unwrap_or_default();
            let changed = {
                let mut prev = state.lock();
                if *prev != groups {
                    *prev = groups.clone();
                    true
                } else {
                    false
                }
            };
            if changed {
                let _ = app2.emit("live_tasks/changed", &groups);
            }
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
    });
}

#[tauri::command]
pub fn live_tasks_list(
    state: tauri::State<'_, LiveTasksState>,
    staleness_secs: Option<u64>,
) -> Vec<LiveAgentTaskGroup> {
    if let Some(s) = staleness_secs {
        *state.staleness_secs.lock() = s;
    }
    state.groups.lock().clone()
}

#[tauri::command]
pub fn live_tasks_set_staleness(state: tauri::State<'_, LiveTasksState>, secs: u64) {
    *state.staleness_secs.lock() = secs;
}
