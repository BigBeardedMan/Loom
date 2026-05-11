use serde::{Deserialize, Serialize};
use tokio::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpServer {
    pub name: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub kind: String,
}

fn claude_binary() -> Result<String, String> {
    #[cfg(target_os = "windows")]
    let candidates = ["claude.exe", "claude.cmd", "claude"];
    #[cfg(not(target_os = "windows"))]
    let candidates = ["claude"];

    for c in candidates {
        if which::which(c).is_ok() {
            return Ok(c.to_string());
        }
    }
    Err("claude CLI not found on PATH".into())
}

#[tauri::command]
pub async fn mcp_list() -> Result<Vec<McpServer>, String> {
    let bin = claude_binary()?;
    let output = Command::new(&bin)
        .args(["mcp", "list"])
        .output()
        .await
        .map_err(|e| e.to_string())?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(parse_mcp_list(&stdout))
}

#[tauri::command]
pub async fn mcp_add(
    name: String,
    command: String,
    args: Vec<String>,
) -> Result<(), String> {
    let bin = claude_binary()?;
    let mut cmd = Command::new(&bin);
    cmd.args(["mcp", "add", &name, &command]);
    for a in &args {
        cmd.arg(a);
    }
    let status = cmd.status().await.map_err(|e| e.to_string())?;
    if !status.success() {
        return Err(format!("claude mcp add exited with {status}"));
    }
    Ok(())
}

#[tauri::command]
pub async fn mcp_remove(name: String) -> Result<(), String> {
    let bin = claude_binary()?;
    let status = Command::new(&bin)
        .args(["mcp", "remove", &name])
        .status()
        .await
        .map_err(|e| e.to_string())?;
    if !status.success() {
        return Err(format!("claude mcp remove exited with {status}"));
    }
    Ok(())
}

pub fn parse_mcp_list(stdout: &str) -> Vec<McpServer> {
    let mut servers = Vec::new();
    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some((name, rest)) = trimmed.split_once(':') {
            let parts: Vec<String> = rest
                .trim()
                .split_whitespace()
                .map(|s| s.to_string())
                .collect();
            if parts.is_empty() {
                continue;
            }
            let command = parts[0].clone();
            let args = parts[1..].to_vec();
            servers.push(McpServer {
                name: name.trim().to_string(),
                command,
                args,
                kind: "stdio".into(),
            });
        }
    }
    servers
}
