// Mirrors Loom/Agents/LiveAgentTasks.swift.
// Polls ~/.claude/tasks/<session>/<id>.json and ~/.codex/sessions/.../*.jsonl
// for live AI agent task state and emits a Tauri event when it changes.

use chrono::{DateTime, Local, TimeZone, Utc};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
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
    pub model_label: Option<String>,
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
    pub model_label: Option<String>,
    pub last_activity: String,
    pub headline: Option<String>,
    pub tasks: Vec<LiveAgentTask>,
}

pub struct LiveTasksState {
    pub groups: Arc<Mutex<Vec<LiveAgentTaskGroup>>>,
    pub staleness_secs: Arc<Mutex<u64>>,
    pub dismissed_sessions: Arc<Mutex<HashMap<String, i64>>>,
    dismissed_path: PathBuf,
}

impl LiveTasksState {
    pub fn new(data_dir: PathBuf) -> Self {
        let dismissed_path = data_dir.join("live_tasks_dismissed.json");
        Self {
            groups: Arc::new(Mutex::new(Vec::new())),
            staleness_secs: Arc::new(Mutex::new(60 * 60)),
            dismissed_sessions: Arc::new(Mutex::new(load_dismissed_sessions(&dismissed_path))),
            dismissed_path,
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
    Some(Utc.timestamp_opt(secs, 0).single()?.with_timezone(&Local))
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

fn normalized_model_label(raw: Option<String>) -> Option<String> {
    let trimmed = raw?.trim().to_string();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

fn identity_model_key(model_label: Option<&str>) -> String {
    model_label
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_lowercase().replace([':', '/'], "_"))
        .unwrap_or_else(|| "default".to_string())
}

fn group_id(source: &str, model_label: Option<&str>, session_id: &str) -> String {
    format!(
        "{}:{}:{}",
        source,
        identity_model_key(model_label),
        session_id
    )
}

fn headline_for(tasks: &[LiveAgentTask]) -> Option<String> {
    tasks
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
        .or_else(|| tasks.first().map(|t| t.subject.clone()))
}

fn parse_rfc3339_secs(raw: &str) -> Option<i64> {
    DateTime::parse_from_rfc3339(raw)
        .ok()
        .map(|d| d.timestamp())
}

fn load_dismissed_sessions(path: &Path) -> HashMap<String, i64> {
    read_text(path)
        .and_then(|text| serde_json::from_str::<HashMap<String, i64>>(&text).ok())
        .unwrap_or_default()
}

fn save_dismissed_sessions(path: &Path, dismissed: &HashMap<String, i64>) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(text) = serde_json::to_string_pretty(dismissed) {
        let _ = fs::write(path, text);
    }
}

fn filter_dismissed(
    groups: Vec<LiveAgentTaskGroup>,
    dismissed: &HashMap<String, i64>,
) -> Vec<LiveAgentTaskGroup> {
    groups
        .into_iter()
        .filter(|group| {
            let Some(dismissed_at) = dismissed.get(&group.id) else {
                return true;
            };
            parse_rfc3339_secs(&group.last_activity)
                .map(|last_activity| last_activity > *dismissed_at)
                .unwrap_or(true)
        })
        .collect()
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

struct SessionRef {
    id: String,
    dir: PathBuf,
    most_recent: DateTime<Local>,
}

fn active_json_task_sessions(root: &Path, cutoff: DateTime<Local>) -> Vec<SessionRef> {
    let mut out = Vec::new();
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
        let most_recent = inner
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| path.extension().and_then(|s| s.to_str()) == Some("json"))
            .filter_map(|path| file_mtime(&path))
            .max();
        let Some(most_recent) = most_recent else {
            continue;
        };
        if most_recent < cutoff {
            continue;
        }
        let id = dir
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string();
        out.push(SessionRef {
            id,
            dir,
            most_recent,
        });
    }
    out.sort_by(|a, b| b.most_recent.cmp(&a.most_recent));
    out
}

fn read_json_tasks(
    session: &SessionRef,
    source: &str,
    model_label: Option<&str>,
) -> Vec<LiveAgentTask> {
    let Ok(entries) = fs::read_dir(&session.dir) else {
        return Vec::new();
    };
    let mut tasks = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("json") {
            continue;
        }
        let Some(text) = read_text(&path) else {
            continue;
        };
        let Ok(payload) = serde_json::from_str::<ClaudeTaskFile>(&text) else {
            continue;
        };
        let status = payload.status.unwrap_or_else(|| "pending".to_string());
        if status == "deleted" {
            continue;
        }
        let task_id = payload.id.unwrap_or_default();
        let mtime = file_mtime(&path).unwrap_or(session.most_recent);
        tasks.push(LiveAgentTask {
            id: format!("{}:{}:{}", source, session.id, task_id),
            source: source.to_string(),
            model_label: model_label.map(str::to_string),
            session_id: session.id.clone(),
            task_id,
            subject: payload
                .subject
                .unwrap_or_else(|| "(no subject)".to_string()),
            description: payload.description.unwrap_or_default(),
            active_form: payload.active_form.unwrap_or_default(),
            status,
            updated_at: mtime.to_rfc3339(),
        });
    }
    tasks.sort_by(|a, b| {
        let pa = status_sort_priority(&a.status);
        let pb = status_sort_priority(&b.status);
        pa.cmp(&pb).then_with(|| b.updated_at.cmp(&a.updated_at))
    });
    tasks
}

fn collect_claude_groups(
    root: &Path,
    projects_root: &Path,
    cutoff: DateTime<Local>,
) -> Vec<LiveAgentTaskGroup> {
    let mut out: Vec<LiveAgentTaskGroup> = Vec::new();
    let sessions = active_json_task_sessions(root, cutoff);
    let session_ids: HashSet<String> = sessions.iter().map(|s| s.id.clone()).collect();
    let model_labels = collect_claude_model_labels(projects_root, &session_ids);
    for session in sessions {
        let model_label = model_labels.get(&session.id).cloned();
        let tasks = read_json_tasks(&session, "claude", model_label.as_deref());
        if tasks.is_empty() {
            continue;
        }
        let headline = headline_for(&tasks);

        out.push(LiveAgentTaskGroup {
            id: group_id("claude", model_label.as_deref(), &session.id),
            session_id: session.id,
            source: "claude".to_string(),
            model_label,
            last_activity: session.most_recent.to_rfc3339(),
            headline,
            tasks,
        });
    }
    out
}

#[derive(Deserialize)]
struct ClaudeProjectLine {
    message: Option<ClaudeProjectMessage>,
}

#[derive(Deserialize)]
struct ClaudeProjectMessage {
    model: Option<String>,
}

fn collect_claude_model_labels(
    projects_root: &Path,
    session_ids: &HashSet<String>,
) -> HashMap<String, String> {
    let mut labels = HashMap::new();
    if session_ids.is_empty() || !projects_root.exists() {
        return labels;
    }
    walk_jsonl(projects_root, &mut |path| {
        let Some(session_id) = path.file_stem().and_then(|s| s.to_str()) else {
            return;
        };
        if !session_ids.contains(session_id) || labels.contains_key(session_id) {
            return;
        }
        if let Some(model) = read_latest_claude_model_label(path) {
            labels.insert(session_id.to_string(), model);
        }
    });
    labels
}

fn read_latest_claude_model_label(path: &Path) -> Option<String> {
    let text = read_text(path)?;
    let mut latest: Option<String> = None;
    for line in text.lines() {
        if !line.contains("\"model\"") {
            continue;
        }
        let Ok(parsed) = serde_json::from_str::<ClaudeProjectLine>(line) else {
            continue;
        };
        if let Some(model) = normalized_model_label(parsed.message.and_then(|m| m.model)) {
            latest = Some(model);
        }
    }
    latest
}

fn collect_lmstudio_groups(root: &Path, cutoff: DateTime<Local>) -> Vec<LiveAgentTaskGroup> {
    let mut out = Vec::new();
    for session in active_json_task_sessions(root, cutoff) {
        let tasks = read_json_tasks(&session, "lmstudio", None);
        if tasks.is_empty() {
            continue;
        }
        let headline = headline_for(&tasks);
        out.push(LiveAgentTaskGroup {
            id: group_id("lmstudio", None, &session.id),
            session_id: session.id,
            source: "lmstudio".to_string(),
            model_label: None,
            last_activity: session.most_recent.to_rfc3339(),
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
    model: Option<String>,
    #[serde(rename = "collaboration_mode")]
    collaboration_mode: Option<CodexCollaborationMode>,
}

#[derive(Deserialize)]
struct CodexLine {
    timestamp: Option<String>,
    #[serde(rename = "type")]
    ty: Option<String>,
    payload: Option<CodexLinePayload>,
}

#[derive(Deserialize)]
struct CodexCollaborationMode {
    settings: Option<CodexCollaborationSettings>,
}

#[derive(Deserialize)]
struct CodexCollaborationSettings {
    model: Option<String>,
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

struct CodexPlanSnapshot {
    plan: Vec<CodexPlanStep>,
    model_label: Option<String>,
    plan_activity: DateTime<Local>,
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

fn parse_codex_timestamp(raw: Option<&str>) -> Option<DateTime<Local>> {
    DateTime::parse_from_rfc3339(raw?)
        .ok()
        .map(|d| d.with_timezone(&Local))
}

fn read_latest_codex_plan_snapshot(
    path: &Path,
    fallback_activity: DateTime<Local>,
) -> Option<CodexPlanSnapshot> {
    let text = read_text(path)?;
    let mut latest: Option<Vec<CodexPlanStep>> = None;
    let mut model_label: Option<String> = None;
    let mut plan_activity: Option<DateTime<Local>> = None;
    for line in text.lines() {
        if !line.contains("\"update_plan\"") && !line.contains("\"turn_context\"") {
            continue;
        }
        let Ok(parsed) = serde_json::from_str::<CodexLine>(line) else {
            continue;
        };
        let Some(payload) = parsed.payload else {
            continue;
        };
        if parsed.ty.as_deref() == Some("turn_context") {
            let candidate = payload.model.as_deref().or_else(|| {
                payload
                    .collaboration_mode
                    .as_ref()
                    .and_then(|mode| mode.settings.as_ref())
                    .and_then(|settings| settings.model.as_deref())
            });
            if let Some(model) = normalized_model_label(candidate.map(str::to_string)) {
                model_label = Some(model);
            }
        }
        if !line.contains("\"update_plan\"") {
            continue;
        }
        if payload.ty.as_deref() != Some("function_call") {
            continue;
        }
        if payload.name.as_deref() != Some("update_plan") {
            continue;
        }
        let Some(args) = payload.arguments else {
            continue;
        };
        let Ok(envelope) = serde_json::from_str::<CodexPlanArgs>(&args) else {
            continue;
        };
        latest = Some(envelope.plan);
        plan_activity = parse_codex_timestamp(parsed.timestamp.as_deref()).or(plan_activity);
    }
    latest.map(|plan| CodexPlanSnapshot {
        plan,
        model_label,
        plan_activity: plan_activity.unwrap_or(fallback_activity),
    })
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
        let Some(snapshot) = read_latest_codex_plan_snapshot(&path, mtime) else {
            continue;
        };
        if snapshot.plan.is_empty() || snapshot.plan_activity < cutoff {
            continue;
        }
        let model_label = snapshot.model_label.clone();
        let tasks: Vec<LiveAgentTask> = snapshot
            .plan
            .into_iter()
            .enumerate()
            .map(|(i, step)| LiveAgentTask {
                id: format!("codex:{}:{}", session_id, i),
                source: "codex".to_string(),
                model_label: model_label.clone(),
                session_id: session_id.clone(),
                task_id: i.to_string(),
                subject: step.step.clone(),
                description: String::new(),
                active_form: step.step.clone(),
                status: map_codex_status(&step.status).to_string(),
                updated_at: snapshot.plan_activity.to_rfc3339(),
            })
            .collect();
        if !tasks
            .iter()
            .any(|t| t.status == "pending" || t.status == "in_progress")
        {
            continue;
        }
        let headline = tasks
            .iter()
            .find(|t| t.status == "in_progress")
            .map(|t| t.subject.clone())
            .or_else(|| tasks.first().map(|t| t.subject.clone()));
        out.push(LiveAgentTaskGroup {
            id: group_id("codex", model_label.as_deref(), &session_id),
            session_id: session_id.clone(),
            source: "codex".to_string(),
            model_label,
            last_activity: snapshot.plan_activity.to_rfc3339(),
            headline,
            tasks,
        });
    }
    out
}

pub fn collect_all_groups(
    staleness_secs: u64,
    dismissed: &HashMap<String, i64>,
) -> Vec<LiveAgentTaskGroup> {
    let h = home();
    let cutoff = Local::now() - chrono::Duration::seconds(staleness_secs as i64);
    let mut groups = Vec::new();
    groups.extend(collect_claude_groups(
        &h.join(".claude").join("tasks"),
        &h.join(".claude").join("projects"),
        cutoff,
    ));
    groups.extend(collect_codex_groups(
        &h.join(".codex").join("sessions"),
        cutoff,
    ));
    groups.extend(collect_lmstudio_groups(
        &h.join(".loom").join("tasks"),
        cutoff,
    ));
    let mut groups = filter_dismissed(groups, dismissed);
    groups.sort_by(|a, b| b.last_activity.cmp(&a.last_activity));
    groups
}

pub fn start_poller(app: AppHandle) {
    let state = app.state::<LiveTasksState>().inner().groups.clone();
    let staleness = app.state::<LiveTasksState>().inner().staleness_secs.clone();
    let dismissed = app
        .state::<LiveTasksState>()
        .inner()
        .dismissed_sessions
        .clone();
    let app2 = app.clone();
    // Use Tauri's runtime — setup runs before any tokio runtime is live, so
    // tokio::spawn would panic with "there is no reactor running."
    tauri::async_runtime::spawn(async move {
        loop {
            let secs = *staleness.lock();
            let dismissed_snapshot = dismissed.lock().clone();
            let groups = tauri::async_runtime::spawn_blocking(move || {
                collect_all_groups(secs, &dismissed_snapshot)
            })
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

#[tauri::command]
pub fn live_tasks_clear_group(
    state: tauri::State<'_, LiveTasksState>,
    group_id: String,
) -> Vec<LiveAgentTaskGroup> {
    let group = state
        .groups
        .lock()
        .iter()
        .find(|group| group.id == group_id)
        .cloned();
    if let Some(group) = group {
        dismiss_group(&state, &group);
        let mut groups = state.groups.lock();
        groups.retain(|existing| existing.id != group.id);
        groups.clone()
    } else {
        state.groups.lock().clone()
    }
}

#[tauri::command]
pub fn live_tasks_clear_all(state: tauri::State<'_, LiveTasksState>) -> Vec<LiveAgentTaskGroup> {
    let groups = state.groups.lock().clone();
    for group in &groups {
        dismiss_group(&state, group);
    }
    state.groups.lock().clear();
    Vec::new()
}

fn dismiss_group(state: &tauri::State<'_, LiveTasksState>, group: &LiveAgentTaskGroup) {
    delete_task_files_for(group);
    let last_activity =
        parse_rfc3339_secs(&group.last_activity).unwrap_or_else(|| Local::now().timestamp());
    let mut dismissed = state.dismissed_sessions.lock();
    dismissed.insert(group.id.clone(), last_activity);
    save_dismissed_sessions(&state.dismissed_path, &dismissed);
}

fn delete_task_files_for(group: &LiveAgentTaskGroup) {
    let root = match group.source.as_str() {
        "claude" => Some(home().join(".claude").join("tasks")),
        "lmstudio" => Some(home().join(".loom").join("tasks")),
        _ => None,
    };
    let Some(root) = root else { return };
    let dir = root.join(&group.session_id);
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("json") {
            let _ = fs::remove_file(path);
        }
    }
}
