// Read LOOM_BUILD_CODE at compile time so the Testing Edition can stamp its
// alphanumeric build identifier into the binary. release-testing.sh sets the
// var to the first 10 chars of the current git SHA before invoking
// `pnpm tauri build`. When unset (local `pnpm tauri dev`, IDE builds), we
// fall back to "dev-local" so the app still has a printable code.
fn main() {
    let code = std::env::var("LOOM_BUILD_CODE").unwrap_or_else(|_| "dev-local".to_string());
    println!("cargo:rustc-env=LOOM_BUILD_CODE={code}");
    println!("cargo:rerun-if-env-changed=LOOM_BUILD_CODE");
    tauri_build::build();
}
