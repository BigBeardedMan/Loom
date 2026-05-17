use crate::db::workspace;
use crate::state::AppState;
use regex::Regex;
use std::path::{Component, Path, PathBuf};

pub fn redact_secrets(input: &str) -> String {
    let mut out = input.to_string();
    let rules = [
        (
            r"(?is)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
            "[REDACTED PRIVATE KEY]",
        ),
        (
            r"(?i)(authorization:\s*bearer\s+)[A-Za-z0-9._~+/\-]+=*",
            "$1[REDACTED]",
        ),
        (
            r#"(?i)(--(?:api-key|token|password|secret)(?:=|\s+))([^\s"'`]+)"#,
            "$1[REDACTED]",
        ),
        (
            r#"(?i)\b(api[_-]?key|token|secret|password|passwd|credential)(\s*[:=]\s*)(["']?)([^\s"'`]+)"#,
            "$1$2$3[REDACTED]",
        ),
        (r"\bsk-[A-Za-z0-9]{12,}\b", "[REDACTED_OPENAI_KEY]"),
        (
            r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b",
            "[REDACTED_GITHUB_TOKEN]",
        ),
        (r"\bAKIA[0-9A-Z]{16}\b", "[REDACTED_AWS_KEY]"),
    ];
    for (pattern, replacement) in rules {
        if let Ok(re) = Regex::new(pattern) {
            out = re.replace_all(&out, replacement).into_owned();
        }
    }
    out
}

pub fn should_skip_command(command: &str) -> bool {
    let trimmed = command.trim();
    if trimmed.is_empty() {
        return true;
    }
    let lower = trimmed.to_ascii_lowercase();
    let denied_prefixes = [
        "gh auth",
        "npm token",
        "ssh-add",
        "aws configure",
        "docker login",
        "gcloud auth",
        "az login",
        "pass ",
    ];
    if denied_prefixes.iter().any(|p| lower.starts_with(p)) {
        return true;
    }
    let patterns = [
        r"(?i)(^|[;&|\s])(export\s+)?[A-Z_][A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL)[A-Z0-9_]*=",
        r"(?i)\s--(api-key|token|password|secret)(=|\s+)\S+",
        r"(?i)(authorization:\s*bearer\s+)\S+",
    ];
    patterns
        .iter()
        .filter_map(|p| Regex::new(p).ok())
        .any(|re| re.is_match(trimmed))
}

pub fn validate_existing_path(state: &AppState, path: impl AsRef<Path>) -> Result<PathBuf, String> {
    let requested = path.as_ref();
    reject_sensitive_path(requested)?;
    let canonical = std::fs::canonicalize(requested)
        .map_err(|e| format!("canonicalize {}: {e}", requested.display()))?;
    reject_sensitive_path(&canonical)?;
    ensure_allowed(state, &canonical)?;
    Ok(canonical)
}

pub fn validate_write_path(state: &AppState, path: impl AsRef<Path>) -> Result<PathBuf, String> {
    let requested = path.as_ref();
    reject_sensitive_path(requested)?;
    reject_traversal(requested)?;
    let canonical = canonicalize_missing(requested)?;
    reject_sensitive_path(&canonical)?;
    ensure_allowed(state, &canonical)?;
    Ok(canonical)
}

pub fn validate_app_data_path(state: &AppState, path: impl AsRef<Path>) -> Result<PathBuf, String> {
    let canonical = std::fs::canonicalize(path.as_ref())
        .map_err(|e| format!("canonicalize {}: {e}", path.as_ref().display()))?;
    let data = std::fs::canonicalize(&state.data_dir).map_err(|e| e.to_string())?;
    if path_is_within(&canonical, &data) {
        Ok(canonical)
    } else {
        Err(format!(
            "path is outside app data: {}",
            path.as_ref().display()
        ))
    }
}

pub fn is_path_sensitive(path: &Path) -> bool {
    is_sensitive_path(path)
}

pub fn path_is_within(path: &Path, root: &Path) -> bool {
    #[cfg(windows)]
    {
        let path_s = path.to_string_lossy().to_ascii_lowercase();
        let root_s = root.to_string_lossy().to_ascii_lowercase();
        path_s == root_s || path_s.starts_with(&(root_s + "\\"))
    }
    #[cfg(not(windows))]
    {
        path == root || path.starts_with(root)
    }
}

pub fn allowed_roots(state: &AppState) -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Ok(data) = std::fs::canonicalize(&state.data_dir) {
        roots.push(data);
    }
    if let Ok(logs) = std::fs::canonicalize(&state.logs_dir) {
        roots.push(logs);
    }
    if let Ok(workspaces) = workspace::list(&state.db) {
        for ws in workspaces {
            let path = ws.folder_path.trim();
            if path.is_empty() {
                continue;
            }
            if let Ok(root) = std::fs::canonicalize(path) {
                if root.is_dir() {
                    roots.push(root);
                }
            }
        }
    }
    roots
}

fn ensure_allowed(state: &AppState, canonical: &Path) -> Result<(), String> {
    if allowed_roots(state)
        .iter()
        .any(|root| path_is_within(canonical, root))
    {
        Ok(())
    } else {
        Err(format!(
            "path is outside registered workspaces: {}",
            canonical.display()
        ))
    }
}

fn canonicalize_missing(path: &Path) -> Result<PathBuf, String> {
    if path.exists() {
        return std::fs::canonicalize(path).map_err(|e| e.to_string());
    }
    let mut missing = Vec::new();
    let mut ancestor = path;
    while !ancestor.exists() {
        let name = ancestor
            .file_name()
            .ok_or_else(|| format!("no existing parent for {}", path.display()))?;
        missing.push(name.to_os_string());
        ancestor = ancestor
            .parent()
            .ok_or_else(|| format!("no existing parent for {}", path.display()))?;
    }
    let mut canonical = std::fs::canonicalize(ancestor).map_err(|e| e.to_string())?;
    for component in missing.iter().rev() {
        canonical.push(component);
    }
    Ok(canonical)
}

fn reject_traversal(path: &Path) -> Result<(), String> {
    if path.components().any(|c| matches!(c, Component::ParentDir)) {
        return Err(format!("path traversal is not allowed: {}", path.display()));
    }
    Ok(())
}

fn reject_sensitive_path(path: &Path) -> Result<(), String> {
    if is_sensitive_path(path) {
        return Err(format!("sensitive file path is denied: {}", path.display()));
    }
    Ok(())
}

fn is_sensitive_path(path: &Path) -> bool {
    let lower = path.to_string_lossy().to_ascii_lowercase();
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().to_ascii_lowercase())
        .unwrap_or_default();
    if name == ".env" || name.starts_with(".env.") {
        return true;
    }
    if [".npmrc", ".pypirc", ".netrc", ".git-credentials"].contains(&name.as_str()) {
        return true;
    }
    if ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"].contains(&name.as_str()) {
        return true;
    }
    if ["pem", "p12", "pfx", "key"]
        .iter()
        .any(|ext| name.ends_with(&format!(".{ext}")))
    {
        return true;
    }
    let sensitive_dirs = [
        "\\.ssh\\",
        "/.ssh/",
        "\\.gnupg\\",
        "/.gnupg/",
        "\\.aws\\",
        "/.aws/",
        "\\.kube\\",
        "/.kube/",
    ];
    if sensitive_dirs.iter().any(|d| lower.contains(d)) {
        return true;
    }
    lower.contains("keychain") || lower.contains("credential") || lower.contains("private_key")
}
