# Windows Updater Recovery Task List for 8.2.70

- [x] Re-check the old 8.2.67 helper path that opens the broad GitHub prerelease search on nonzero installer exit.
- [x] Re-check the old 8.2.68 helper path that can open the exact release page after the installer watchdog expires.
- [x] Add a signed Windows bridge updater asset that matches old updater filename validation.
- [x] Make the bridge download or use the real versioned NSIS installer, run updater mode, retry legacy silent mode, and optionally elevate.
- [x] Make the bridge return success outside CI so old helpers cannot open GitHub after recovery failure.
- [x] Keep future app builds on the real `Loom.Testing.Edition_<version>_<arch>-setup.exe` asset instead of the bridge.
- [x] Keep `latest-windows-testing.json` pinned to real versioned NSIS installers.
- [x] Build and sign bridge assets for x64 and arm64 in Windows CI.
- [x] Smoke test the bridge in CI against the real local installer before publishing.
- [x] Bump macOS Testing Edition to 8.2.70.
- [x] Bump Windows Testing Edition to 8.2.70.
