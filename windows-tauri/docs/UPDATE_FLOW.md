# In-place update flow — research + decision

## The problem

Pre-v1.0.1, every Loom update required the user to uninstall the previous
version via Add/Remove Programs and install the new one. Two root causes:

### 1. Mixed bundlers

`tauri.conf.json` had `"targets": ["msi", "nsis", "app", "dmg"]`. CI built
**both** MSI and NSIS installers. They install to different locations and
register as different applications:

| Installer | Mode        | Install path                          | Registry entry |
| --------- | ----------- | ------------------------------------- | -------------- |
| MSI (WiX) | perMachine  | `C:\Program Files\Loom\loom.exe`      | HKLM           |
| NSIS      | currentUser | `%LOCALAPPDATA%\Programs\Loom\loom.exe` | HKCU         |

If a user installs the MSI once and then runs an NSIS-built installer (which
is what the in-app updater downloads — `Loom_<v>_<arch>-setup.exe`), they end
up with two Looms side-by-side. The new one doesn't replace the old; it
co-installs into the per-user location.

### 2. The updater always downloads NSIS

`src-tauri/src/updater.rs::update_check` picks the asset matching
`_<arch>-setup.exe`. That's the NSIS installer. If the running app came from
the MSI, the new NSIS install can't upgrade it (different scope, different
registry hive).

## The fix in v1.0.1

1. Drop `"msi"` from `bundle.targets` in `tauri.conf.json`. CI now builds
   NSIS only.
2. NSIS's `installMode: "currentUser"` is unchanged. The first NSIS install
   lands in `%LOCALAPPDATA%\Programs\Loom\`.
3. When the user clicks Update in the running app, the updater downloads the
   new NSIS `.exe` to `%APPDATA%\com.chasesims.Loom\staging\` and spawns it
   with `exitApp = true`. The Tauri app exits.
4. The new NSIS installer is launched. Tauri's NSIS template detects the
   existing per-user install via the same `manufacturer\productName` registry
   key and runs an in-place upgrade: it silently uninstalls the old files,
   writes the new ones, and finishes with the "Run Loom" checkbox checked
   by default.
5. The user clicks Finish; Loom relaunches at the new version. No
   Add/Remove Programs visit, no UAC prompt, no second entry.

## Migration from a pre-v1.0.1 MSI install

Users who installed any v0.x or v1.0.0 MSI need to migrate once:

1. Open Settings → Apps & features (or Add/Remove Programs).
2. Uninstall **Loom** (the entry that points to `C:\Program Files\Loom`).
3. Download the v1.0.1 NSIS `-setup.exe` from the GitHub release page (or
   from the in-app update pill once v1.0.1 lands).
4. Install. From then on, every update is in-place.

## Why not silent install?

NSIS supports `/S` for silent upgrade. We don't pass it, on purpose:

- The user already saw a confirmation modal in the Tauri app before the
  installer launched. A second silent step would feel like the app
  "disappeared" briefly.
- NSIS's `/S` mode doesn't honor the "Run Loom" finish checkbox, so we'd
  need a companion shim that re-launches Loom after the installer exits.
  More moving parts to keep working across arch + emulation.
- The interactive NSIS UI is small (one Next → Install button) and
  auto-detects "this is an upgrade" so it never asks the user to pick an
  install path.

## Why not WiX patch / MSP files?

WiX patch (`.msp`) files do support delta upgrades but require us to ship
the original MSI alongside each patch, version both, and bake a patch
authoring step into CI. Single-channel NSIS is dramatically simpler with
the same UX.

## What else changed

- `windows-release.yml` no longer scans `bundle/msi/` for assets, only
  `bundle/nsis/`. Release page assets now ship NSIS `-setup.exe` for both
  arches + `latest-windows.json`.
- `update_check` returns the same `assetName` format as before, so the
  in-app modal and the GitHub URL fallback both keep working.
