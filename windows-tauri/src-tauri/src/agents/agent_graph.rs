use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeSet, HashMap, HashSet};
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentGraphEvent {
    pub schema_version: u32,
    pub event_id: String,
    pub r#type: String,
    pub occurred_at: String,
    pub root_run_id: String,
    pub run_id: String,
    #[serde(default)]
    pub parent_run_id: Option<String>,
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub workspace_path: Option<String>,
    #[serde(default)]
    pub model_label: Option<String>,
    #[serde(default)]
    pub permission_mode: Option<String>,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub payload: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentGraphRunSummary {
    pub id: String,
    pub title: String,
    pub status: String,
    pub last_activity: String,
    pub started_at: Option<String>,
    pub source: Option<String>,
    pub model_label: Option<String>,
    pub workspace_path: Option<String>,
    pub ledger_path: String,
    pub git_root: Option<String>,
    pub git_branch: Option<String>,
    pub git_head: Option<String>,
    pub git_dirty: Option<bool>,
    pub event_count: usize,
    pub tool_event_count: usize,
    pub task_count: usize,
    pub tool_names: Vec<String>,
}

fn graph_root() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".loom")
        .join("agent-runs")
}

fn validate_root_run_id(root_run_id: &str) -> Result<(), String> {
    let mut components = Path::new(root_run_id).components();
    match (components.next(), components.next()) {
        (Some(Component::Normal(value)), None)
            if !value.to_string_lossy().trim().is_empty()
                && !value.to_string_lossy().starts_with('.') =>
        {
            Ok(())
        }
        _ => Err(format!("invalid root run id: {root_run_id}")),
    }
}

fn events_path(root_run_id: &str) -> Result<PathBuf, String> {
    validate_root_run_id(root_run_id)?;
    Ok(graph_root().join(root_run_id).join("events.jsonl"))
}

fn parse_event_line(line: &str) -> Option<AgentGraphEvent> {
    serde_json::from_str::<AgentGraphEvent>(line).ok().or_else(|| {
        let value = serde_json::from_str::<Value>(line).ok()?;
        Some(AgentGraphEvent {
            schema_version: value.get("schemaVersion")?.as_u64()? as u32,
            event_id: value.get("eventID")?.as_str()?.to_string(),
            r#type: value.get("type")?.as_str()?.to_string(),
            occurred_at: value.get("occurredAt")?.as_str()?.to_string(),
            root_run_id: value.get("rootRunID")?.as_str()?.to_string(),
            run_id: value.get("runID")?.as_str()?.to_string(),
            parent_run_id: value
                .get("parentRunID")
                .and_then(Value::as_str)
                .map(str::to_string),
            source: value.get("source").and_then(Value::as_str).map(str::to_string),
            workspace_path: value
                .get("workspacePath")
                .and_then(Value::as_str)
                .map(str::to_string),
            model_label: value
                .get("modelLabel")
                .and_then(Value::as_str)
                .map(str::to_string),
            permission_mode: value
                .get("permissionMode")
                .and_then(Value::as_str)
                .map(str::to_string),
            title: value.get("title").and_then(Value::as_str).map(str::to_string),
            summary: value.get("summary").and_then(Value::as_str).map(str::to_string),
            payload: value
                .get("payload")
                .and_then(Value::as_object)
                .map(|object| {
                    object
                        .iter()
                        .filter_map(|(key, value)| {
                            value.as_str().map(|s| (key.clone(), s.to_string()))
                        })
                        .collect()
                })
                .unwrap_or_default(),
        })
    })
}

fn read_events(root_run_id: &str) -> Vec<AgentGraphEvent> {
    let Ok(path) = events_path(root_run_id) else {
        return Vec::new();
    };
    let Ok(text) = fs::read_to_string(path) else {
        return Vec::new();
    };
    text.lines().filter_map(parse_event_line).collect()
}

fn parse_time(raw: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(raw)
        .ok()
        .map(|date| date.with_timezone(&Utc))
}

fn summary_title(anchor: Option<&AgentGraphEvent>, latest: &AgentGraphEvent) -> String {
    [
        anchor.and_then(|event| event.payload.get("prompt")).cloned(),
        anchor.and_then(|event| event.summary.clone()),
        latest.payload.get("prompt").cloned(),
        latest.summary.clone(),
        latest.title.clone(),
        Some(latest.root_run_id.clone()),
    ]
    .into_iter()
    .flatten()
    .find(|value| !value.trim().is_empty())
    .unwrap_or_else(|| latest.root_run_id.clone())
}

fn summary_payload_value(
    key: &str,
    anchor: Option<&AgentGraphEvent>,
    latest: &AgentGraphEvent,
) -> Option<String> {
    anchor
        .and_then(|event| event.payload.get(key).cloned())
        .or_else(|| latest.payload.get(key).cloned())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

#[tauri::command]
pub fn agent_graph_list() -> Result<Vec<AgentGraphRunSummary>, String> {
    let root = graph_root();
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(_) => return Ok(Vec::new()),
    };
    let mut summaries: Vec<AgentGraphRunSummary> = entries
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let root_run_id = entry.file_name().to_string_lossy().to_string();
            let events = read_events(&root_run_id);
            let ledger_path = events_path(&root_run_id).ok()?;
            let mut sorted_events: Vec<&AgentGraphEvent> = events.iter().collect();
            sorted_events.sort_by_key(|event| parse_time(&event.occurred_at));
            let latest = sorted_events.last().copied()?;
            let anchor = sorted_events
                .iter()
                .copied()
                .filter(|event| event.r#type == "run.started" || event.r#type == "graph.created")
                .next()
                .or_else(|| sorted_events.first().copied());
            let status = sorted_events
                .iter()
                .rev()
                .copied()
                .find_map(|event| match event.r#type.as_str() {
                    "run.completed" => Some("completed".to_string()),
                    "run.failed" => Some("failed".to_string()),
                    "run.cancelled" => Some("cancelled".to_string()),
                    "run.started" | "run.heartbeat" | "run.statusChanged" => {
                        event.payload.get("status").cloned()
                    }
                    _ => None,
                })
                .unwrap_or_else(|| "running".to_string());
            let tool_names: Vec<String> = events
                .iter()
                .filter_map(|event| event.payload.get("tool").cloned())
                .collect::<BTreeSet<_>>()
                .into_iter()
                .collect();
            let task_count = events
                .iter()
                .filter_map(|event| event.payload.get("taskID").cloned())
                .collect::<HashSet<_>>()
                .len();
            let git_dirty = summary_payload_value("gitDirty", anchor, latest)
                .map(|value| value == "true");
            Some(AgentGraphRunSummary {
                id: latest.root_run_id.clone(),
                title: summary_title(anchor, latest),
                status,
                last_activity: latest.occurred_at.clone(),
                started_at: anchor.map(|event| event.occurred_at.clone()),
                source: anchor
                    .and_then(|event| event.source.clone())
                    .or_else(|| latest.source.clone()),
                model_label: anchor
                    .and_then(|event| event.model_label.clone())
                    .or_else(|| latest.model_label.clone()),
                workspace_path: anchor
                    .and_then(|event| event.workspace_path.clone())
                    .or_else(|| latest.workspace_path.clone()),
                ledger_path: ledger_path.to_string_lossy().to_string(),
                git_root: summary_payload_value("gitRoot", anchor, latest),
                git_branch: summary_payload_value("gitBranch", anchor, latest),
                git_head: summary_payload_value("gitHead", anchor, latest),
                git_dirty,
                event_count: events.len(),
                tool_event_count: events
                    .iter()
                    .filter(|event| event.r#type == "tool.started" || event.r#type == "tool.completed")
                    .count(),
                task_count,
                tool_names,
            })
        })
        .collect();
    summaries.sort_by(|a, b| b.last_activity.cmp(&a.last_activity));
    Ok(summaries)
}

#[tauri::command]
pub fn agent_graph_read(root_run_id: String) -> Result<Vec<AgentGraphEvent>, String> {
    validate_root_run_id(&root_run_id)?;
    Ok(read_events(&root_run_id))
}

#[tauri::command]
pub fn agent_graph_reveal(root_run_id: String) -> Result<(), String> {
    let path = events_path(&root_run_id)?;
    if !path.exists() {
        return Err(format!("ledger not found: {}", path.display()));
    }
    #[cfg(target_os = "windows")]
    let status = Command::new("explorer.exe")
        .arg(format!("/select,{}", path.display()))
        .status()
        .map_err(|e| e.to_string())?;
    #[cfg(target_os = "macos")]
    let status = Command::new("open")
        .arg("-R")
        .arg(&path)
        .status()
        .map_err(|e| e.to_string())?;
    #[cfg(all(not(target_os = "windows"), not(target_os = "macos")))]
    let status = Command::new("xdg-open")
        .arg(path.parent().unwrap_or_else(|| Path::new(".")))
        .status()
        .map_err(|e| e.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("open failed with status {status}"))
    }
}
