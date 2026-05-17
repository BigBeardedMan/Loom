## Changes

- Fixes production auto-update validation so the downloaded Mac app bundle carries the `Loom` display name expected by existing installations.
- Adds a release-script bundle metadata check to prevent publishing a Mac DMG that the in-app updater would reject.
- Terminal panes now support screenshot/image paste for Codex workflows: image-only clipboards insert editable `--image '<path>' ` text instead of sending image bytes into the PTY.
- Finder-copied image files reuse their original file path, while raw clipboard screenshots are saved as PNG files under Loom's Application Support folder.
- Dragged image files or raw image data now use the same editable `--image '<path>' ` argument behavior and never auto-submit the command.
- Text paste still wins when rich clipboard content includes both text and an image, so browser and document copies keep the normal text-paste behavior.
