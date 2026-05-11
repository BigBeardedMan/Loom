use crate::state::AppState;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Stdio;
use tauri::{AppHandle, Emitter, State};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Vendor {
    Claude,
    Codex,
    Gemini,
    Ollama,
}

impl Vendor {
    fn binary(self) -> &'static str {
        match self {
            Vendor::Claude => "claude",
            Vendor::Codex => "codex",
            Vendor::Gemini => "gemini",
            Vendor::Ollama => "ollama",
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CliSendArgs {
    pub vendor: Vendor,
    pub prompt: String,
    pub cwd: String,
    pub agent_name: Option<String>,
    pub session_id: Option<String>,
    #[serde(default)]
    pub extra_args: Vec<String>,
}

fn resolve_binary(vendor: Vendor) -> Result<PathBuf, String> {
    let base = vendor.binary();
    #[cfg(target_os = "windows")]
    let candidates = [
        format!("{base}.exe"),
        format!("{base}.cmd"),
        format!("{base}.bat"),
        base.to_string(),
    ];
    #[cfg(not(target_os = "windows"))]
    let candidates = [base.to_string()];

    for c in &candidates {
        if let Ok(path) = which::which(c) {
            return Ok(path);
        }
    }
    Err(format!("{base} CLI not found on PATH"))
}

#[tauri::command]
pub async fn agent_cli_send(
    app: AppHandle,
    _state: State<'_, AppState>,
    args: CliSendArgs,
) -> Result<String, String> {
    let stream_id = Uuid::new_v4().to_string();
    let app_clone = app.clone();
    let stream_id_clone = stream_id.clone();

    let bin = resolve_binary(args.vendor)?;

    tokio::spawn(async move {
        let mut cmd = Command::new(&bin);
        cmd.current_dir(&args.cwd);
        cmd.stdin(Stdio::piped());
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());
        cmd.kill_on_drop(true);

        match args.vendor {
            Vendor::Claude => {
                cmd.args(["--output-format", "stream-json", "--verbose"]);
                if let Some(name) = &args.agent_name {
                    cmd.args(["--agent", name]);
                }
                if let Some(sid) = &args.session_id {
                    cmd.args(["--resume", sid]);
                }
                cmd.arg("--print");
                cmd.arg(&args.prompt);
            }
            Vendor::Codex => {
                cmd.args(["exec", "--cd", &args.cwd, &args.prompt]);
            }
            Vendor::Gemini => {
                cmd.args(["--prompt", &args.prompt]);
            }
            Vendor::Ollama => {
                cmd.args(["run", args.agent_name.as_deref().unwrap_or("llama3"), &args.prompt]);
            }
        }
        for arg in &args.extra_args {
            cmd.arg(arg);
        }

        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => {
                let _ = app_clone.emit(
                    &format!("agent://{stream_id_clone}/error"),
                    e.to_string(),
                );
                let _ = app_clone.emit(&format!("agent://{stream_id_clone}/done"), 1i32);
                return;
            }
        };

        let stdout = child.stdout.take().expect("stdout");
        let stderr = child.stderr.take().expect("stderr");

        let app_a = app_clone.clone();
        let id_a = stream_id_clone.clone();
        tokio::spawn(async move {
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                let _ = app_a.emit(&format!("agent://{id_a}/chunk"), line);
            }
        });
        let app_b = app_clone.clone();
        let id_b = stream_id_clone.clone();
        tokio::spawn(async move {
            let mut reader = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                let _ = app_b.emit(&format!("agent://{id_b}/stderr"), line);
            }
        });

        let status = child.wait().await.ok().and_then(|s| s.code()).unwrap_or(-1);
        let _ = app_clone.emit(&format!("agent://{stream_id_clone}/done"), status);
    });

    Ok(stream_id)
}

#[tauri::command]
pub async fn agent_registry_refresh() -> Result<Vec<super::parser::AgentDescriptor>, String> {
    let bin = match resolve_binary(Vendor::Claude) {
        Ok(p) => p,
        Err(_) => return Ok(Vec::new()),
    };
    let output = Command::new(&bin)
        .args(["agents", "list"])
        .output()
        .await
        .map_err(|e| e.to_string())?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(super::parser::parse_claude_agents_list(&stdout))
}
