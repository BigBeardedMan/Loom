// Normalize the updater public key at compile time so release builds accept
// either raw minisign keys or minisign.pub file contents from GitHub secrets.
// LOOM_BUILD_CODE is kept for compatibility with older UI/about surfaces.
fn main() {
    let code = std::env::var("LOOM_BUILD_CODE").unwrap_or_else(|_| "dev-local".to_string());
    let updater_key = std::env::var("TAURI_UPDATER_PUBLIC_KEY")
        .map(|key| normalize_minisign_public_key(&key))
        .unwrap_or_default();
    println!("cargo:rustc-env=LOOM_BUILD_CODE={code}");
    println!("cargo:rustc-env=TAURI_UPDATER_PUBLIC_KEY={updater_key}");
    println!("cargo:rerun-if-env-changed=LOOM_BUILD_CODE");
    println!("cargo:rerun-if-env-changed=TAURI_UPDATER_PUBLIC_KEY");
    tauri_build::build();
}

fn normalize_minisign_public_key(input: &str) -> String {
    let trimmed = input.trim();
    if trimmed.starts_with("untrusted comment:") {
        return trimmed
            .lines()
            .map(str::trim)
            .find(|line| !line.is_empty() && !line.starts_with("untrusted comment:"))
            .unwrap_or("")
            .to_string();
    }
    trimmed.lines().next().unwrap_or("").trim().to_string()
}
