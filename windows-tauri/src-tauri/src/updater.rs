// Custom updater: detect arch → check GitHub Releases → download matching
// NSIS installer → save under %APPDATA%\com.chasesims.LoomTestingEdition\staging\ → run installer.
// Replaces the tauri-plugin-updater flow (left registered but unused).

use futures_util::StreamExt;
use regex::Regex;
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

#[derive(Clone, Deserialize)]
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

const TESTING_TAG_PREFIX: &str = "testing-";

fn arch_token(arch: &str) -> &'static str {
    match arch {
        "aarch64" => "arm64",
        _ => "x64",
    }
}

#[tauri::command]
pub async fn update_check() -> Result<Option<UpdateInfo>, String> {
    // Testing Edition: walk the last 30 releases (including pre-releases —
    // /releases/latest deliberately filters them out) and pick the newest
    // one tagged `testing-<version>`. Versions are semver (e.g. `3.3.0`);
    // we use plain string inequality below because the published tag is the
    // single source of truth, and Windows CI tags the same value the Mac
    // release script does. Downgrades would only happen if the user yanks
    // a release and republishes an older version, which is a manual choice.
    let url = format!(
        "https://api.github.com/repos/{}/{}/releases?per_page=30",
        REPO_OWNER, REPO_NAME
    );
    let client = reqwest::Client::builder()
        .user_agent(format!("LoomTestingEdition/{}", env!("LOOM_BUILD_CODE")))
        .build()
        .map_err(|e| e.to_string())?;
    let resp = client.get(&url).send().await.map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("GitHub API: HTTP {}", resp.status()));
    }
    let releases: Vec<GhRelease> = resp.json().await.map_err(|e| e.to_string())?;
    let release = match releases
        .into_iter()
        .find(|r| r.tag_name.starts_with(TESTING_TAG_PREFIX))
    {
        Some(r) => r,
        None => return Ok(None),
    };

    let latest_ver = release
        .tag_name
        .strip_prefix(TESTING_TAG_PREFIX)
        .unwrap_or(&release.tag_name)
        .to_string();
    let current = env!("LOOM_BUILD_CODE");
    if latest_ver == current {
        return Ok(None);
    }

    let arch = update_get_arch();
    let token = arch_token(&arch);
    let asset = release
        .assets
        .iter()
        .find(|a| is_valid_installer_name(&a.name, token))
        .cloned();
    let asset = match asset {
        Some(a) => a,
        None => return Ok(None),
    };
    if !is_valid_release_asset_url(&asset.browser_download_url, &asset.name) {
        return Err(format!(
            "unexpected installer URL: {}",
            asset.browser_download_url
        ));
    }
    let sig_name = format!("{}.sig", asset.name);
    let has_signature = release
        .assets
        .iter()
        .any(|a| a.name == sig_name && a.size > 0);
    if !has_signature {
        return Err(format!(
            "installer asset is missing non-empty signature: {sig_name}"
        ));
    }

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

fn canonical_staging_dir(app: &AppHandle) -> Result<PathBuf, String> {
    std::fs::canonicalize(staging_dir(app)?).map_err(|e| e.to_string())
}

fn staged_marker_path(installer: &PathBuf) -> PathBuf {
    installer.with_extension("exe.staged")
}

fn is_valid_installer_name(name: &str, token: &str) -> bool {
    if name.contains('/') || name.contains('\\') || name.contains("..") {
        return false;
    }
    let Ok(re) = Regex::new(r"(?i)^Loom[A-Za-z0-9._ -]*_(x64|arm64)-setup\.exe$") else {
        return false;
    };
    re.is_match(name)
        && name
            .to_ascii_lowercase()
            .contains(&format!("_{token}-setup.exe"))
}

fn is_valid_release_asset_url(asset_url: &str, asset_name: &str) -> bool {
    let Ok(url) = url::Url::parse(asset_url) else {
        return false;
    };
    if url.scheme() != "https" || url.host_str() != Some("github.com") {
        return false;
    }
    let path = url.path();
    let encoded_name = asset_name.replace(' ', "%20");
    path.starts_with("/BigBeardedMan/Loom/releases/download/testing-")
        && (path.ends_with(&format!("/{asset_name}"))
            || path.ends_with(&format!("/{encoded_name}")))
}

fn ensure_staged_installer(app: &AppHandle, installer_path: &str) -> Result<PathBuf, String> {
    let staging = canonical_staging_dir(app)?;
    let path = PathBuf::from(installer_path);
    let canonical = std::fs::canonicalize(&path).map_err(|e| e.to_string())?;
    let inside = {
        #[cfg(windows)]
        {
            let path_s = canonical.to_string_lossy().to_ascii_lowercase();
            let root_s = staging.to_string_lossy().to_ascii_lowercase();
            path_s == root_s || path_s.starts_with(&(root_s + "\\"))
        }
        #[cfg(not(windows))]
        {
            canonical.starts_with(&staging)
        }
    };
    if !inside {
        return Err(format!(
            "installer is outside staging: {}",
            canonical.display()
        ));
    }
    let name = canonical
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .ok_or_else(|| "installer has no file name".to_string())?;
    let arch = if name.to_ascii_lowercase().contains("_arm64-setup.exe") {
        "arm64"
    } else {
        "x64"
    };
    if !is_valid_installer_name(&name, arch) {
        return Err(format!("unexpected installer name: {name}"));
    }
    let marker = staged_marker_path(&canonical);
    if !marker.exists() {
        return Err("installer was not staged by Loom".into());
    }
    Ok(canonical)
}

#[tauri::command]
pub async fn update_download_and_stage(
    app: AppHandle,
    asset_url: String,
    asset_name: String,
) -> Result<String, String> {
    if !is_valid_installer_name(&asset_name, arch_token(&update_get_arch())) {
        return Err(format!("unexpected installer name: {asset_name}"));
    }
    if !is_valid_release_asset_url(&asset_url, &asset_name) {
        return Err(format!("unexpected installer URL: {asset_url}"));
    }
    let staging = staging_dir(&app)?;
    let target = staging.join(&asset_name);
    let canonical_staging = canonical_staging_dir(&app)?;
    let canonical_parent = std::fs::canonicalize(
        target
            .parent()
            .ok_or_else(|| "installer path has no parent".to_string())?,
    )
    .map_err(|e| e.to_string())?;
    if canonical_parent != canonical_staging {
        return Err("installer target escaped staging".into());
    }
    if target.exists() {
        fs::remove_file(&target).map_err(|e| e.to_string())?;
    }
    let marker = staged_marker_path(&target);
    if marker.exists() {
        fs::remove_file(&marker).map_err(|e| e.to_string())?;
    }

    let client = reqwest::Client::builder()
        .user_agent(format!("LoomTestingEdition/{}", env!("LOOM_BUILD_CODE")))
        .build()
        .map_err(|e| e.to_string())?;
    let sig_url = format!("{asset_url}.sig");
    let sig_resp = client
        .get(&sig_url)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !sig_resp.status().is_success() {
        return Err(format!("signature download: HTTP {}", sig_resp.status()));
    }
    let sig = sig_resp.bytes().await.map_err(|e| e.to_string())?;
    if sig.is_empty() {
        return Err("installer signature is empty".into());
    }

    let resp = client
        .get(&asset_url)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("download: HTTP {}", resp.status()));
    }
    let total = resp.content_length().unwrap_or(0);

    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&target)
        .map_err(|e| e.to_string())?;
    let mut downloaded: u64 = 0;
    let mut stream = resp.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let bytes = chunk.map_err(|e| e.to_string())?;
        file.write_all(&bytes).map_err(|e| e.to_string())?;
        downloaded += bytes.len() as u64;
        let _ = app.emit("update/progress", UpdateProgress { downloaded, total });
    }
    file.flush().map_err(|e| e.to_string())?;
    fs::write(&marker, sig).map_err(|e| e.to_string())?;
    Ok(target.to_string_lossy().to_string())
}

#[tauri::command]
pub fn update_run_installer(
    app: AppHandle,
    installer_path: String,
    exit_app: bool,
) -> Result<(), String> {
    let path = ensure_staged_installer(&app, &installer_path)?;

    // Goal: one-click in-place update. Spawn a detached helper that
    // (1) waits for this Loom.exe to exit so NSIS can overwrite the binary,
    // (2) runs the NSIS installer silently with /S,
    // (3) relaunches the freshly-installed Loom.exe.
    //
    // Everything the helper does is mirrored to %TEMP%\loom-update-<pid>.log
    // so when (not if) it fails on someone else's machine we can ask for the
    // log instead of guessing. Two reliability tweaks past the v3.1.1 helper:
    // a longer post-exit settle (5s) so Loom.exe's handles fully release
    // before NSIS overwrites it, and a fallback that opens the GitHub
    // release page in the user's browser if the silent installer returns a
    // non-zero exit code (most often UAC denied or AV quarantined).
    #[cfg(windows)]
    {
        let installer_path = path.to_string_lossy().to_string();
        let exe = std::env::current_exe().map_err(|e| format!("current_exe: {e}"))?;
        let exe_path = exe.to_string_lossy().to_string();
        let parent_pid = std::process::id();

        let temp = std::env::temp_dir();
        let batch_path = temp.join(format!(
            "loom-update-{}-{}.bat",
            parent_pid,
            uuid::Uuid::new_v4()
        ));

        let script = format!(
            "@echo off\r\n\
set LOGFILE=%TEMP%\\loom-update-{pid}.log\r\n\
echo === loom updater %DATE% %TIME% === > \"%LOGFILE%\"\r\n\
echo waiting for pid {pid} to exit >> \"%LOGFILE%\"\r\n\
:waitloop\r\n\
tasklist /FI \"PID eq {pid}\" 2>nul | findstr /C:\" {pid} \" >nul\r\n\
if not errorlevel 1 (\r\n\
    timeout /t 1 /nobreak >nul\r\n\
    goto waitloop\r\n\
)\r\n\
echo pid {pid} exited, settling 5s for file locks >> \"%LOGFILE%\"\r\n\
timeout /t 5 /nobreak >nul\r\n\
echo running: \"{installer}\" /S >> \"%LOGFILE%\"\r\n\
\"{installer}\" /S >> \"%LOGFILE%\" 2>&1\r\n\
set INSTALL_RC=%ERRORLEVEL%\r\n\
echo installer exit code: %INSTALL_RC% >> \"%LOGFILE%\"\r\n\
if not \"%INSTALL_RC%\"==\"0\" (\r\n\
    echo silent install failed, opening release page >> \"%LOGFILE%\"\r\n\
    start \"\" \"https://github.com/BigBeardedMan/Loom/releases?q=prerelease%3Atrue&expanded=true\"\r\n\
    goto cleanup\r\n\
)\r\n\
echo settling 2s before relaunch >> \"%LOGFILE%\"\r\n\
timeout /t 2 /nobreak >nul\r\n\
echo relaunching: \"{exe}\" >> \"%LOGFILE%\"\r\n\
start \"\" \"{exe}\"\r\n\
echo done >> \"%LOGFILE%\"\r\n\
:cleanup\r\n\
(goto) 2>nul & del \"%~f0\"\r\n",
            pid = parent_pid,
            installer = installer_path.replace('"', ""),
            exe = exe_path.replace('"', ""),
        );

        {
            let mut helper = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&batch_path)
                .map_err(|e| format!("write helper: {e}"))?;
            helper
                .write_all(script.as_bytes())
                .map_err(|e| format!("write helper: {e}"))?;
            helper.flush().map_err(|e| format!("write helper: {e}"))?;
        }

        use std::os::windows::process::CommandExt;
        // CREATE_NO_WINDOW gives cmd a hidden console (the black boxes the
        // v3.1.1 helper flashed were a missing flag, not a real failure).
        // CREATE_NEW_PROCESS_GROUP keeps the helper alive after Loom exits.
        // DETACHED_PROCESS and CREATE_NO_WINDOW are mutually exclusive in
        // CreateProcess (the latter is ignored when the former is set), so
        // we drop DETACHED_PROCESS to keep the window hidden.
        const CREATE_NO_WINDOW: u32 = 0x08000000;
        const CREATE_NEW_PROCESS_GROUP: u32 = 0x00000200;
        Command::new("cmd")
            .arg("/c")
            .arg(&batch_path)
            .creation_flags(CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP)
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
