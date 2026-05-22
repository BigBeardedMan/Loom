# Windows Updater Recovery Task List for 8.2.69

- [x] Trace the pill click path from React `UpdatePill` to Rust updater commands.
- [x] Confirm the browser opens only from updater fallback behavior, not from the pill itself.
- [x] Compare installed-version updater behavior from `testing-8.2.0`, `testing-8.2.67`, and `testing-8.2.68`.
- [x] Identify old updater compatibility gap for legacy installer asset names.
- [x] Replace the Windows helper's browser fallback with installer-mode retry plus app relaunch.
- [x] Use Tauri's NSIS updater arguments: `/S /R /UPDATE /ARGS`.
- [x] Keep a legacy `/S` retry for older installer expectations.
- [x] Add a Rust unit test that prevents GitHub/browser fallback from returning.
- [x] Publish versioned Windows installer assets for the hardened updater.
- [x] Publish legacy Windows installer alias assets for older installed builds.
- [x] Smoke test legacy `/S` installer mode in Windows CI.
- [x] Smoke test updater `/S /R /UPDATE /ARGS` mode in Windows CI.
- [x] Ensure `latest-windows-testing.json` continues to point at strict versioned assets.
- [x] Bump macOS Testing Edition to 8.2.69.
- [x] Bump Windows Testing Edition to 8.2.69.
