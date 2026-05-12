// Custom updater: detect arch → check GitHub Releases → download matching
// NSIS installer → save under %APPDATA%\Loom\staging\ → prompt → run installer.
// Replaces the tauri-plugin-updater flow (left registered but unused).

use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::Command;
use tauri::{AppHandle, Emitter, Manager};

const REPO_OWNER: &str = "BigBeardedMan";
const REPO_NAME: &str = "Loom";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateInfo {
    pub version: String,
    pub current_version: String,
    pub asset_name: String,
    pub download_url: String,
    pub size_bytes: u64,
    pub release_notes_url: String,
    pub notes: Option<String>,
    pub published_at: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateProgress {
    pub downloaded: u64,
    pub total: u64,
}

#[tauri::command]
pub fn update_get_arch() -> String {
    // Compile-time default. On Windows, also probe GetNativeSystemInfo so an
    // x64 binary running under ARM emulation picks the arm64 asset.
    let compile_time = std::env::consts::ARCH;
    #[cfg(windows)]
    {
        if let Some(native) = windows_native_arch() {
            return native;
        }
    }
    match compile_time {
        "x86_64" => "x86_64".to_string(),
        "aarch64" => "aarch64".to_string(),
        other => other.to_string(),
    }
}

#[cfg(windows)]
fn windows_native_arch() -> Option<String> {
    use windows::Win32::System::SystemInformation::{
        GetNativeSystemInfo, PROCESSOR_ARCHITECTURE_AMD64, PROCESSOR_ARCHITECTURE_ARM64,
        SYSTEM_INFO,
    };
    let mut info: SYSTEM_INFO = unsafe { std::mem::zeroed() };
    unsafe { GetNativeSystemInfo(&mut info) };
    let arch = unsafe { info.Anonymous.Anonymous.wProcessorArchitecture };
    if arch == PROCESSOR_ARCHITECTURE_ARM64 {
        Some("aarch64".to_string())
    } else if arch == PROCESSOR_ARCHITECTURE_AMD64 {
        Some("x86_64".to_string())
    } else {
        None
    }
}

#[derive(Deserialize)]
struct GhAsset {
    name: String,
    browser_download_url: String,
    size: u64,
}

#[derive(Deserialize)]
struct GhRelease {
    tag_name: String,
    html_url: String,
    body: Option<String>,
    published_at: Option<String>,
    assets: Vec<GhAsset>,
}

fn parse_semver(s: &str) -> (u32, u32, u32) {
    let trimmed = s.trim_start_matches("v");
    let parts: Vec<&str> = trimmed.split('.').collect();
    let to_num = |p: Option<&&str>| -> u32 {
        p.and_then(|s| s.split('-').next().unwrap_or("0").parse::<u32>().ok())
            .unwrap_or(0)
    };
    (to_num(parts.first()), to_num(parts.get(1)), to_num(parts.get(2)))
}

fn is_newer(latest: &str, current: &str) -> bool {
    parse_semver(latest) > parse_semver(current)
}

fn arch_token(arch: &str) -> &'static str {
    match arch {
        "aarch64" => "arm64",
        _ => "x64",
    }
}

#[tauri::command]
pub async fn update_check() -> Result<Option<UpdateInfo>, String> {
    let url = format!(
        "https://api.github.com/repos/{}/{}/releases/latest",
        REPO_OWNER, REPO_NAME
    );
    let client = reqwest::Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|e| e.to_string())?;
    let resp = client.get(&url).send().await.map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("GitHub API: HTTP {}", resp.status()));
    }
    let release: GhRelease = resp.json().await.map_err(|e| e.to_string())?;

    let latest_ver = release
        .tag_name
        .strip_prefix("windows-v")
        .or_else(|| release.tag_name.strip_prefix("v"))
        .unwrap_or(&release.tag_name)
        .to_string();
    let current = env!("CARGO_PKG_VERSION");
    if !is_newer(&latest_ver, current) {
        return Ok(None);
    }

    let arch = update_get_arch();
    let token = arch_token(&arch);
    let asset = release
        .assets
        .into_iter()
        .find(|a| a.name.contains(&format!("_{}-setup.exe", token)));
    let asset = match asset {
        Some(a) => a,
        None => return Ok(None),
    };

    Ok(Some(UpdateInfo {
        version: latest_ver,
        current_version: current.to_string(),
        asset_name: asset.name,
        download_url: asset.browser_download_url,
        size_bytes: asset.size,
        release_notes_url: release.html_url,
        notes: release.body,
        published_at: release.published_at,
    }))
}

fn staging_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let data = app.path().app_data_dir().map_err(|e| e.to_string())?;
    let dir = data.join("staging");
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

#[tauri::command]
pub async fn update_download_and_stage(
    app: AppHandle,
    asset_url: String,
    asset_name: String,
) -> Result<String, String> {
    let staging = staging_dir(&app)?;
    let target = staging.join(&asset_name);

    let client = reqwest::Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|e| e.to_string())?;
    let resp = client.get(&asset_url).send().await.map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("download: HTTP {}", resp.status()));
    }
    let total = resp.content_length().unwrap_or(0);

    let mut file = fs::File::create(&target).map_err(|e| e.to_string())?;
    let mut downloaded: u64 = 0;
    let mut stream = resp.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let bytes = chunk.map_err(|e| e.to_string())?;
        file.write_all(&bytes).map_err(|e| e.to_string())?;
        downloaded += bytes.len() as u64;
        let _ = app.emit("update/progress", UpdateProgress { downloaded, total });
    }
    file.flush().map_err(|e| e.to_string())?;
    Ok(target.to_string_lossy().to_string())
}

#[tauri::command]
pub fn update_run_installer(
    app: AppHandle,
    installer_path: String,
    exit_app: bool,
) -> Result<(), String> {
    let path = PathBuf::from(&installer_path);
    if !path.exists() {
        return Err(format!("installer missing: {}", installer_path));
    }

    // Goal: one-click in-place update. Spawn a detached helper that
    // (1) waits for this Loom.exe to exit so NSIS can overwrite the binary,
    // (2) runs the NSIS installer silently with /S, and
    // (3) relaunches the freshly-installed Loom.exe. No wizard, no
    // post-install user action. Mirrors what auto-updaters in other apps do.
    #[cfg(windows)]
    {
        let exe = std::env::current_exe()
            .map_err(|e| format!("current_exe: {e}"))?;
        let exe_path = exe.to_string_lossy().to_string();
        let parent_pid = std::process::id();

        let temp = std::env::temp_dir();
        let batch_path = temp.join(format!("loom-update-{}.bat", parent_pid));

        // Self-deleting batch: poll tasklist for the parent PID, run the
        // installer silently, relaunch Loom, then delete itself.
        let script = format!(
            "@echo off\r\n\
:waitloop\r\n\
tasklist /FI \"PID eq {pid}\" 2>nul | findstr /C:\" {pid} \" >nul\r\n\
if not errorlevel 1 (\r\n\
    timeout /t 1 /nobreak >nul\r\n\
    goto waitloop\r\n\
)\r\n\
timeout /t 1 /nobreak >nul\r\n\
\"{installer}\" /S\r\n\
timeout /t 2 /nobreak >nul\r\n\
start \"\" \"{exe}\"\r\n\
(goto) 2>nul & del \"%~f0\"\r\n",
            pid = parent_pid,
            installer = installer_path.replace('"', ""),
            exe = exe_path.replace('"', ""),
        );

        fs::write(&batch_path, script).map_err(|e| format!("write helper: {e}"))?;

        use std::os::windows::process::CommandExt;
        // CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS — survives parent exit.
        const DETACHED_PROCESS: u32 = 0x00000008;
        const CREATE_NEW_PROCESS_GROUP: u32 = 0x00000200;
        Command::new("cmd")
            .arg("/c")
            .arg(&batch_path)
            .creation_flags(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP)
            .spawn()
            .map_err(|e| format!("spawn helper: {e}"))?;
    }

    #[cfg(not(windows))]
    {
        // Non-Windows builds (rare in practice for this Tauri target) fall
        // back to launching the installer directly; the user finishes it.
        Command::new(&path)
            .spawn()
            .map_err(|e| format!("spawn installer: {e}"))?;
    }

    if exit_app {
        app.exit(0);
    }
    Ok(())
}

// Kept for backwards compatibility with old callers; never resolves to a
// working install path now that we drive download/install ourselves.
#[tauri::command]
pub async fn update_apply() -> Result<(), String> {
    Err("update_apply is deprecated; use download_and_stage + run_installer".into())
}
