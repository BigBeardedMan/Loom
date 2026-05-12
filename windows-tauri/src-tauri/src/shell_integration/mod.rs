use anyhow::{Context, Result};
use std::path::PathBuf;

pub const POWERSHELL_PROFILE_SHIM: &str = include_str!("powershell.ps1");

fn powershell_profile_path() -> Result<PathBuf> {
    let documents = dirs::document_dir().context("no documents dir")?;
    Ok(documents
        .join("PowerShell")
        .join("Microsoft.PowerShell_profile.ps1"))
}

#[tauri::command]
pub async fn shell_integration_install() -> Result<String, String> {
    let path = powershell_profile_path().map_err(|e| e.to_string())?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let marker = "# >>> Loom Testing Edition shell integration >>>";
    let existing = std::fs::read_to_string(&path).unwrap_or_default();
    if existing.contains(marker) {
        return Ok(path.to_string_lossy().into_owned());
    }
    let block = format!(
        "\n{marker}\n. \"$env:LOCALAPPDATA\\Loom Testing Edition\\loom-shell.ps1\"\n# <<< Loom Testing Edition shell integration <<<\n"
    );
    std::fs::write(&path, format!("{existing}{block}")).map_err(|e| e.to_string())?;

    let local = dirs::data_local_dir()
        .ok_or("no LOCALAPPDATA")?
        .join("Loom Testing Edition")
        .join("loom-shell.ps1");
    if let Some(parent) = local.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::write(&local, POWERSHELL_PROFILE_SHIM).map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().into_owned())
}
