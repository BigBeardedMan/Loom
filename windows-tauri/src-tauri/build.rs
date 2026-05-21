// Read LOOM_BUILD_CODE at compile time so the Testing Edition can stamp the
// release semver into the binary. Windows CI sets it from the `testing-*` tag.
// When unset (local `pnpm tauri dev`, IDE builds), we fall back to "dev-local"
// so the app still has a printable code.
fn main() {
    let code = std::env::var("LOOM_BUILD_CODE").unwrap_or_else(|_| "dev-local".to_string());
    let updater_key = std::env::var("TAURI_UPDATER_PUBLIC_KEY").unwrap_or_default();
    println!("cargo:rustc-env=LOOM_BUILD_CODE={code}");
    println!("cargo:rustc-env=TAURI_UPDATER_PUBLIC_KEY={updater_key}");
    println!("cargo:rerun-if-env-changed=LOOM_BUILD_CODE");
    println!("cargo:rerun-if-env-changed=TAURI_UPDATER_PUBLIC_KEY");
    tauri_build::build();
}
