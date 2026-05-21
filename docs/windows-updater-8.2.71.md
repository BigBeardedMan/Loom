# Windows Updater 8.2.71

## Failure Found

The 8.2.70 installed helper can stage the downloaded asset, but it writes the staged installer path into a batch file using the Windows extended-length prefix:

```text
"\\?\C:\Users\Chase\AppData\Roaming\com.chasesims.LoomTestingEdition\staging\Loom.Bridge_8.2.70_arm64-setup.exe" /S
```

`cmd.exe` cannot execute that quoted `\\?\C:\...` form from the helper script, so it exits before the staged bridge or real installer starts. That is why the app appears to close for an update and then falls back to opening GitHub.

## Fix

- Convert `\\?\C:\...` paths back to `C:\...` before writing updater helper batch commands.
- Convert `\\?\UNC\server\share\...` paths back to `\\server\share\...`.
- Cover both conversion paths with updater tests.
- Cover the generated helper script so it cannot write `\\?\` installer or app executable paths.
- Keep the signed bridge assets in Windows releases for older builds that can reach a staged installer.

## Recovery Note

An already-installed build with the old helper may still need one manual installer run because the old helper fails before any staged asset can execute. After installing 8.2.71 manually once, future update-pill installs use the corrected helper script path handling.

## Release Checklist

- Build version metadata is 8.2.71 for macOS and Windows.
- `testing-8.2.71` is a GitHub prerelease.
- Windows release assets include signed bridge, real installer, legacy aliases, and manifest assets for x64 and arm64.
- `latest-windows-testing.json` points normal updater clients at the real `Loom.Testing.Edition_8.2.71_<arch>-setup.exe` installers.
- GitHub release ordering exposes bridge assets first for old clients that choose the first matching installer.
