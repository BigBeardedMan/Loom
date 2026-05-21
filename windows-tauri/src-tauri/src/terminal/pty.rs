use anyhow::{anyhow, Context, Result};
use parking_lot::Mutex;
use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::Arc;
use std::thread;
use tauri::{AppHandle, Emitter};
use uuid::Uuid;

use super::transcripts::TerminalTranscriptStore;

pub type SessionId = String;

pub struct Session {
    pub id: SessionId,
    pub master: Mutex<Box<dyn MasterPty + Send>>,
    pub writer: Mutex<Box<dyn Write + Send>>,
    pub child: Mutex<Box<dyn Child + Send + Sync>>,
    pub cwd: Mutex<Option<PathBuf>>,
    pub title: Mutex<String>,
    pub shell: String,
    pub pid: u32,
    pub transcripts: Arc<TerminalTranscriptStore>,
}

pub struct SessionRegistry {
    inner: Mutex<HashMap<SessionId, Arc<Session>>>,
}

impl SessionRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    pub fn insert(&self, session: Arc<Session>) {
        self.inner.lock().insert(session.id.clone(), session);
    }

    pub fn get(&self, id: &str) -> Option<Arc<Session>> {
        self.inner.lock().get(id).cloned()
    }

    pub fn remove(&self, id: &str) -> Option<Arc<Session>> {
        self.inner.lock().remove(id)
    }

    pub fn list(&self) -> Vec<SessionInfo> {
        self.inner
            .lock()
            .values()
            .map(|s| SessionInfo {
                id: s.id.clone(),
                shell: s.shell.clone(),
                pid: s.pid,
                cwd: s
                    .cwd
                    .lock()
                    .as_ref()
                    .map(|p| p.to_string_lossy().into_owned()),
                title: s.title.lock().clone(),
            })
            .collect()
    }
}

impl Default for SessionRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionInfo {
    pub id: SessionId,
    pub shell: String,
    pub pid: u32,
    pub cwd: Option<String>,
    pub title: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpawnOptions {
    pub session_id: Option<String>,
    pub workspace_id: Option<String>,
    pub workspace_name: Option<String>,
    pub title: Option<String>,
    pub shell: Option<String>,
    pub cwd: Option<String>,
    pub cols: u16,
    pub rows: u16,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub env: Vec<(String, String)>,
}

fn default_shell() -> String {
    #[cfg(target_os = "windows")]
    {
        which::which("pwsh.exe")
            .or_else(|_| which::which("powershell.exe"))
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| "cmd.exe".into())
    }
    #[cfg(not(target_os = "windows"))]
    {
        std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".into())
    }
}

pub fn spawn(
    app: AppHandle,
    registry: &SessionRegistry,
    transcripts: Arc<TerminalTranscriptStore>,
    opts: SpawnOptions,
) -> Result<SessionId> {
    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize {
            rows: opts.rows.max(2),
            cols: opts.cols.max(2),
            pixel_width: 0,
            pixel_height: 0,
        })
        .context("openpty")?;

    let shell_path = opts.shell.unwrap_or_else(default_shell);
    let mut cmd = CommandBuilder::new(&shell_path);
    let id = opts
        .session_id
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    let title = opts.title.unwrap_or_else(|| "Terminal Session".to_string());

    #[cfg_attr(not(target_os = "windows"), allow(unused_mut))]
    let mut args = opts.args;
    if args.is_empty() {
        #[cfg(target_os = "windows")]
        {
            if shell_path.to_ascii_lowercase().contains("pwsh")
                || shell_path.to_ascii_lowercase().contains("powershell")
            {
                args.push("-NoLogo".into());
            }
        }
    }
    for arg in &args {
        cmd.arg(arg);
    }

    let cwd_path = opts
        .cwd
        .clone()
        .map(PathBuf::from)
        .or_else(|| dirs::home_dir());
    if let Some(cwd) = &cwd_path {
        cmd.cwd(cwd);
    }

    // Strip credential env vars on spawn (matches Loom v1.4.0 hardening).
    cmd.env_clear();
    let mut env_passthrough = vec![
        "PATH",
        "USERPROFILE",
        "USERNAME",
        "TEMP",
        "TMP",
        "APPDATA",
        "LOCALAPPDATA",
        "PROGRAMDATA",
        "PROGRAMFILES",
        "PROGRAMFILES(X86)",
        "WINDIR",
        "SYSTEMROOT",
        "SYSTEMDRIVE",
        "COMSPEC",
        "PSMODULEPATH",
        "PATHEXT",
        "HOME",
        "LANG",
        "LC_ALL",
        "TERM",
        "SHELL",
    ];
    env_passthrough.dedup();
    for key in env_passthrough {
        if let Ok(value) = std::env::var(key) {
            cmd.env(key, value);
        }
    }
    cmd.env("TERM", "xterm-256color");
    cmd.env("LOOM_TERM", "1");
    cmd.env("LOOM_SESSION_ID", &id);
    for (k, v) in opts.env {
        cmd.env(k, v);
    }

    let child = pair.slave.spawn_command(cmd).context("spawn shell")?;
    let pid = child.process_id().unwrap_or(0);

    let writer = pair.master.take_writer().context("take pty writer")?;
    let master = pair.master;
    let mut reader = master.try_clone_reader().context("clone pty reader")?;

    let cwd_for_transcript = cwd_path
        .as_ref()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default();
    transcripts.register(
        &id,
        opts.workspace_id,
        opts.workspace_name,
        cwd_for_transcript,
        title.clone(),
    );
    let session = Arc::new(Session {
        id: id.clone(),
        master: Mutex::new(master),
        writer: Mutex::new(writer),
        child: Mutex::new(child),
        cwd: Mutex::new(cwd_path),
        title: Mutex::new(title),
        shell: shell_path,
        pid,
        transcripts: transcripts.clone(),
    });
    registry.insert(session.clone());

    let app_clone = app.clone();
    let id_clone = id.clone();
    let transcripts_read = transcripts.clone();
    thread::spawn(move || {
        let mut buf = [0u8; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    transcripts_read.append(&id_clone, &buf[..n]);
                    let chunk = buf[..n].to_vec();
                    let _ = app_clone.emit(&format!("terminal://{id_clone}/data"), chunk);
                }
                Err(_) => break,
            }
        }
        transcripts_read.close(&id_clone);
        let _ = app_clone.emit(&format!("terminal://{id_clone}/exit"), 0i32);
    });

    let app_wait = app.clone();
    let id_wait = id.clone();
    let session_wait = session.clone();
    thread::spawn(move || {
        let exit_code = session_wait
            .child
            .lock()
            .wait()
            .ok()
            .map(|s| s.exit_code() as i32)
            .unwrap_or(-1);
        session_wait.transcripts.close(&id_wait);
        let _ = app_wait.emit(&format!("terminal://{id_wait}/exit"), exit_code);
    });

    Ok(id)
}

pub fn write(registry: &SessionRegistry, id: &str, bytes: Vec<u8>) -> Result<()> {
    let session = registry
        .get(id)
        .ok_or_else(|| anyhow!("session not found: {id}"))?;
    session
        .writer
        .lock()
        .write_all(&bytes)
        .context("write to pty")?;
    Ok(())
}

pub fn resize(registry: &SessionRegistry, id: &str, cols: u16, rows: u16) -> Result<()> {
    let session = registry
        .get(id)
        .ok_or_else(|| anyhow!("session not found: {id}"))?;
    session
        .master
        .lock()
        .resize(PtySize {
            cols: cols.max(2),
            rows: rows.max(2),
            pixel_width: 0,
            pixel_height: 0,
        })
        .context("resize pty")?;
    Ok(())
}

pub fn kill(registry: &SessionRegistry, id: &str) -> Result<()> {
    if let Some(session) = registry.remove(id) {
        let _ = session.child.lock().kill();
        session.transcripts.close(id);
    }
    Ok(())
}

pub fn set_cwd(registry: &SessionRegistry, id: &str, cwd: PathBuf) -> Result<()> {
    let session = registry
        .get(id)
        .ok_or_else(|| anyhow!("session not found: {id}"))?;
    *session.cwd.lock() = Some(cwd);
    let cwd_string = session
        .cwd
        .lock()
        .as_ref()
        .map(|p| p.to_string_lossy().into_owned());
    session.transcripts.update(id, cwd_string, None);
    Ok(())
}

pub fn update_metadata(
    registry: &SessionRegistry,
    id: &str,
    cwd: Option<PathBuf>,
    title: Option<String>,
) -> Result<()> {
    let session = registry
        .get(id)
        .ok_or_else(|| anyhow!("session not found: {id}"))?;
    let cwd_string = if let Some(cwd) = cwd {
        *session.cwd.lock() = Some(cwd.clone());
        Some(cwd.to_string_lossy().into_owned())
    } else {
        None
    };
    if let Some(title) = title.as_deref().filter(|v| !v.trim().is_empty()) {
        *session.title.lock() = title.to_string();
    }
    session.transcripts.update(id, cwd_string, title);
    Ok(())
}

pub fn pid(registry: &SessionRegistry, id: &str) -> Option<u32> {
    registry.get(id).map(|s| s.pid)
}
