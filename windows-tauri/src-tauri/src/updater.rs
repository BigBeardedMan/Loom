// Custom updater: detect arch → check GitHub Releases → download matching
// NSIS installer → save under %APPDATA%\com.chasesims.LoomTestingEdition\staging\ → run installer.
// Replaces the tauri-plugin-updater flow (left registered but unused).

use base64::{engine::general_purpose::STANDARD, Engine as _};
use futures_util::StreamExt;
use minisign_verify::{PublicKey, Signature};
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
    draft: bool,
    prerelease: bool,
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

fn testing_version_from_tag(tag: &str) -> Option<&str> {
    tag.strip_prefix(TESTING_TAG_PREFIX)
        .filter(|version| parse_semver(version).is_some())
}

fn parse_semver(version: &str) -> Option<(u64, u64, u64)> {
    let mut parts = version.split('.');
    let major = parts.next()?.parse().ok()?;
    let minor = parts.next()?.parse().ok()?;
    let patch = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some((major, minor, patch))
}

fn is_newer_version(candidate: &str, current: &str) -> bool {
    let Some(candidate) = parse_semver(candidate) else {
        return false;
    };
    let Some(current) = parse_semver(current) else {
        return false;
    };
    candidate > current
}

#[tauri::command]
pub async fn update_check() -> Result<Option<UpdateInfo>, String> {
    // Testing Edition: walk recent releases (including pre-releases —
    // /releases/latest deliberately filters them out) and pick the highest
    // semver `testing-<version>` that has a matching Windows installer for
    // this architecture. GitHub ordering and manual release edits are not
    // trusted for update selection.
    let url = format!(
        "https://api.github.com/repos/{}/{}/releases?per_page=100",
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
    let current = env!("LOOM_BUILD_CODE");
    let arch = update_get_arch();
    let token = arch_token(&arch);

    let mut candidate: Option<((u64, u64, u64), String, GhRelease, GhAsset)> = None;
    for release in releases {
        if release.draft || !release.prerelease {
            continue;
        }
        let Some(version) = testing_version_from_tag(&release.tag_name) else {
            continue;
        };
        let Some(parsed_version) = parse_semver(version) else {
            continue;
        };
        if !is_newer_version(version, current) {
            continue;
        }

        let asset = release
            .assets
            .iter()
            .find(|asset| is_valid_installer_name(&asset.name, token, Some(version)))
            .cloned();
        let Some(asset) = asset else {
            continue;
        };
        if !is_valid_release_asset_url(&asset.browser_download_url, &asset.name, version) {
            return Err(format!(
                "unexpected installer URL for {}: {}",
                release.tag_name, asset.browser_download_url
            ));
        }
        let sig_name = format!("{}.sig", asset.name);
        let has_signature = release
            .assets
            .iter()
            .any(|a| a.name == sig_name && a.size > 0);
        if !has_signature {
            return Err(format!(
                "installer asset is missing non-empty signature on {}: {sig_name}",
                release.tag_name
            ));
        }

        if candidate
            .as_ref()
            .map_or(true, |(best, _, _, _)| parsed_version > *best)
        {
            candidate = Some((parsed_version, version.to_string(), release, asset));
        }
    }

    let Some((_parsed, latest_ver, release, asset)) = candidate else {
        return Ok(None);
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

fn canonical_staging_dir(app: &AppHandle) -> Result<PathBuf, String> {
    std::fs::canonicalize(staging_dir(app)?).map_err(|e| e.to_string())
}

fn staged_marker_path(installer: &PathBuf) -> PathBuf {
    installer.with_extension("exe.staged")
}

fn installer_parts(name: &str) -> Option<(String, String)> {
    if name.contains('/') || name.contains('\\') || name.contains("..") {
        return None;
    }
    let Ok(re) = Regex::new(r"(?i)^Loom[A-Za-z0-9._ -]*_(\d+\.\d+\.\d+)_(x64|arm64)-setup\.exe$")
    else {
        return None;
    };
    let caps = re.captures(name)?;
    let version = caps.get(1)?.as_str();
    let arch = caps.get(2)?.as_str().to_ascii_lowercase();
    parse_semver(version)?;
    Some((version.to_string(), arch))
}

#[cfg_attr(not(windows), allow(dead_code))]
fn installer_version_from_name(name: &str) -> Option<String> {
    installer_parts(name).map(|(version, _)| version)
}

fn is_valid_installer_name(name: &str, token: &str, expected_version: Option<&str>) -> bool {
    let Some((version, arch)) = installer_parts(name) else {
        return false;
    };
    arch == token.to_ascii_lowercase()
        && expected_version.map_or(true, |expected| version == expected)
}

fn release_version_from_asset_url(asset_url: &str) -> Option<String> {
    let Ok(url) = url::Url::parse(asset_url) else {
        return None;
    };
    if url.scheme() != "https" || url.host_str() != Some("github.com") {
        return None;
    }
    let path_segments = url.path_segments()?.collect::<Vec<_>>();
    if path_segments.len() < 6
        || path_segments[0] != REPO_OWNER
        || path_segments[1] != REPO_NAME
        || path_segments[2] != "releases"
        || path_segments[3] != "download"
    {
        return None;
    }
    testing_version_from_tag(path_segments[4]).map(str::to_string)
}

fn is_valid_release_asset_url(asset_url: &str, asset_name: &str, expected_version: &str) -> bool {
    let Ok(url) = url::Url::parse(asset_url) else {
        return false;
    };
    if url.scheme() != "https" || url.host_str() != Some("github.com") {
        return false;
    }
    let path = url.path();
    let encoded_name = asset_name.replace(' ', "%20");
    path.starts_with(&format!(
        "/{}/{}/releases/download/testing-{}/",
        REPO_OWNER, REPO_NAME, expected_version
    )) && (path.ends_with(&format!("/{asset_name}")) || path.ends_with(&format!("/{encoded_name}")))
}

fn updater_public_key() -> Result<PublicKey, String> {
    let key = option_env!("TAURI_UPDATER_PUBLIC_KEY").unwrap_or("").trim();
    if key.is_empty() {
        return Err("updater public key is not embedded in this build".into());
    }
    PublicKey::from_base64(key).map_err(|e| format!("invalid updater public key: {e}"))
}

fn decode_installer_signature(sig_asset: &[u8]) -> Result<Signature, String> {
    let raw = std::str::from_utf8(sig_asset)
        .map_err(|e| format!("installer signature is not UTF-8: {e}"))?
        .trim();
    if raw.is_empty() {
        return Err("installer signature is empty".into());
    }
    let signature_text = if raw.starts_with("untrusted comment:") {
        raw.to_string()
    } else {
        let decoded = STANDARD
            .decode(raw)
            .map_err(|e| format!("installer signature is not valid base64: {e}"))?;
        String::from_utf8(decoded)
            .map_err(|e| format!("decoded installer signature is not UTF-8: {e}"))?
    };
    Signature::decode(&signature_text)
        .map_err(|e| format!("installer signature could not be decoded: {e}"))
}

fn verify_installer_signature(installer: &[u8], sig_asset: &[u8]) -> Result<(), String> {
    let public_key = updater_public_key()?;
    let signature = decode_installer_signature(sig_asset)?;
    public_key
        .verify(installer, &signature, true)
        .map_err(|e| format!("installer signature verification failed: {e}"))
}

#[cfg_attr(not(windows), allow(dead_code))]
fn release_url_for_installer(installer_name: &str) -> String {
    installer_version_from_name(installer_name)
        .map(|version| {
            format!(
                "https://github.com/{}/{}/releases/tag/testing-{}",
                REPO_OWNER, REPO_NAME, version
            )
        })
        .unwrap_or_else(|| format!("https://github.com/{}/{}/releases", REPO_OWNER, REPO_NAME))
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
    let Some((_version, arch)) = installer_parts(&name) else {
        return Err(format!("unexpected installer name: {name}"));
    };
    if !is_valid_installer_name(&name, &arch, None) {
        return Err(format!("unexpected installer name: {name}"));
    }
    let marker = staged_marker_path(&canonical);
    if !marker.exists() {
        return Err("installer was not staged by Loom".into());
    }
    let installer = fs::read(&canonical).map_err(|e| format!("read staged installer: {e}"))?;
    let signature = fs::read(&marker).map_err(|e| format!("read staged signature: {e}"))?;
    verify_installer_signature(&installer, &signature)?;
    Ok(canonical)
}

#[tauri::command]
pub async fn update_download_and_stage(
    app: AppHandle,
    asset_url: String,
    asset_name: String,
) -> Result<String, String> {
    let expected_version = release_version_from_asset_url(&asset_url)
        .ok_or_else(|| format!("unexpected installer URL: {asset_url}"))?;
    if !is_valid_installer_name(
        &asset_name,
        arch_token(&update_get_arch()),
        Some(&expected_version),
    ) {
        return Err(format!("unexpected installer name: {asset_name}"));
    }
    if !is_valid_release_asset_url(&asset_url, &asset_name, &expected_version) {
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
    let mut installer_bytes = Vec::with_capacity(total.min(64 * 1024 * 1024) as usize);
    let mut downloaded: u64 = 0;
    let mut stream = resp.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let bytes = chunk.map_err(|e| e.to_string())?;
        file.write_all(&bytes).map_err(|e| e.to_string())?;
        installer_bytes.extend_from_slice(&bytes);
        downloaded += bytes.len() as u64;
        let _ = app.emit("update/progress", UpdateProgress { downloaded, total });
    }
    file.flush().map_err(|e| e.to_string())?;
    drop(file);
    if let Err(err) = verify_installer_signature(&installer_bytes, &sig) {
        let _ = fs::remove_file(&target);
        return Err(err);
    }
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
    // (2) runs the NSIS installer silently with Tauri's updater args,
    // (3) lets NSIS relaunch the freshly-installed app and falls back to
    // the current exe path if it does not.
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
        let installer_name = path
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_default();
        let release_url = release_url_for_installer(&installer_name);
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
echo closing remaining Loom Testing Edition processes >> \"%LOGFILE%\"\r\n\
taskkill /IM \"Loom Testing Edition.exe\" /T /F >> \"%LOGFILE%\" 2>&1\r\n\
echo running: \"{installer}\" /S /R /UPDATE /ARGS >> \"%LOGFILE%\"\r\n\
\"{installer}\" /S /R /UPDATE /ARGS >> \"%LOGFILE%\" 2>&1\r\n\
set INSTALL_RC=%ERRORLEVEL%\r\n\
echo installer exit code: %INSTALL_RC% >> \"%LOGFILE%\"\r\n\
if not \"%INSTALL_RC%\"==\"0\" (\r\n\
    echo silent install failed, opening exact release page >> \"%LOGFILE%\"\r\n\
    start \"\" \"{release_url}\"\r\n\
    goto cleanup\r\n\
)\r\n\
echo settling 5s for installer relaunch >> \"%LOGFILE%\"\r\n\
timeout /t 5 /nobreak >nul\r\n\
tasklist /FI \"IMAGENAME eq Loom Testing Edition.exe\" 2>nul | findstr /I /C:\"Loom Testing Edition.exe\" >nul\r\n\
if errorlevel 1 (\r\n\
    echo installer did not relaunch Loom, using fallback: \"{exe}\" >> \"%LOGFILE%\"\r\n\
    start \"\" \"{exe}\"\r\n\
) else (\r\n\
    echo installer relaunched Loom >> \"%LOGFILE%\"\r\n\
)\r\n\
echo done >> \"%LOGFILE%\"\r\n\
:cleanup\r\n\
(goto) 2>nul & del \"%~f0\"\r\n",
            pid = parent_pid,
            installer = installer_path.replace('"', ""),
            exe = exe_path.replace('"', ""),
            release_url = release_url.replace('"', ""),
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compares_testing_versions_as_semver() {
        assert!(is_newer_version("8.2.68", "8.2.67"));
        assert!(is_newer_version("8.10.0", "8.2.99"));
        assert!(!is_newer_version("8.2.67", "8.2.67"));
        assert!(!is_newer_version("8.2.0", "8.2.67"));
        assert!(!is_newer_version("8.2.68", "dev-local"));
    }

    #[test]
    fn installer_name_must_match_release_version_and_arch() {
        assert!(is_valid_installer_name(
            "Loom.Testing.Edition_8.2.67_x64-setup.exe",
            "x64",
            Some("8.2.67")
        ));
        assert!(is_valid_installer_name(
            "Loom.Testing.Edition_8.2.67_arm64-setup.exe",
            "arm64",
            Some("8.2.67")
        ));
        assert!(!is_valid_installer_name(
            "Loom.Testing.Edition_8.1.10_x64-setup.exe",
            "x64",
            Some("8.2.0")
        ));
        assert!(!is_valid_installer_name(
            "Loom.Testing.Edition_8.2.67_arm64-setup.exe",
            "x64",
            Some("8.2.67")
        ));
    }

    #[test]
    fn release_asset_url_must_match_release_and_asset() {
        let url = "https://github.com/BigBeardedMan/Loom/releases/download/testing-8.2.67/Loom.Testing.Edition_8.2.67_x64-setup.exe";
        assert_eq!(
            release_version_from_asset_url(url).as_deref(),
            Some("8.2.67")
        );
        assert!(is_valid_release_asset_url(
            url,
            "Loom.Testing.Edition_8.2.67_x64-setup.exe",
            "8.2.67"
        ));
        assert!(!is_valid_release_asset_url(
            url,
            "Loom.Testing.Edition_8.2.67_x64-setup.exe",
            "8.2.68"
        ));
        assert!(!is_valid_release_asset_url(
            "https://github.com/BigBeardedMan/Loom/releases/download/testing-8.2.67/Loom.Testing.Edition_8.1.10_x64-setup.exe",
            "Loom.Testing.Edition_8.1.10_x64-setup.exe",
            "8.2.0"
        ));
    }

    #[test]
    fn signature_decoder_accepts_tauri_base64_sig_assets() {
        let minisign_text = "untrusted comment: signature from minisign secret key
RWQf6LRCGA9i59SLOFxz6NxvASXDJeRtuZykwQepbDEGt87ig1BNpWaVWuNrm73YiIiJbq71Wi+dP9eKL8OC351vwIasSSbXxwA=
trusted comment: timestamp:1555779966\tfile:test
QtKMXWyYcwdpZAlPF7tE2ENJkRd1ujvKjlj1m9RtHTBnZPa5WKU5uWRs5GoP5M/VqE81QFuMKI5k/SfNQUaOAA==";
        let encoded = STANDARD.encode(minisign_text);
        let signature = decode_installer_signature(encoded.as_bytes())
            .expect("base64 minisign text should decode");
        assert_eq!(
            signature.trusted_comment(),
            "timestamp:1555779966\tfile:test"
        );
    }
}
