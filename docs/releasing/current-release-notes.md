## Changes

- Terminal panes now support clipboard image paste for Codex workflows: image-only clipboards insert editable `--image '<path>' ` text instead of sending image bytes into the PTY.
- Finder-copied image files reuse their original file path, while raw clipboard images such as screenshots are saved as PNG files under Loom Testing Edition's Application Support folder.
- Text paste still wins when rich clipboard content includes both text and an image, so browser and document copies keep the normal text-paste behavior.
- The Testing Edition Mac release package now uses a fresh Xcode build output and validates that the app bundle version matches the `testing-<version>` tag before upload, preventing stale bundles from breaking the update pill with a version-mismatch error.
