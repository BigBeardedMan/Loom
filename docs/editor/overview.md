# Editor

The Editor pane today is a **file tree with breadcrumb**. Real text editing is on the roadmap via [CodeEdit](https://github.com/CodeEditApp/CodeEdit) integration.

## What it does today

- Browse the workspace folder.
- Click a file to open it in the system default editor (Xcode, VS Code, etc., depending on the file type).
- Breadcrumb at the top shows the current selection path with click-to-jump.

## What it doesn't do (yet)

- Inline text editing inside the pane.
- Syntax highlighting.
- Save / autosave.
- Diff / git decoration.

## Workflow today

The Prompt workspace already has Terminal + Tasks + Agent. The Editor pane is the file-system index — a quick navigator. For actual edits, click through to your editor of choice (Loom doesn't fight you here) or have the agent issue the edits.

## CodeEdit integration

CodeEdit is a Swift-native editor that wraps a real `NSTextView`-based code editing surface. Pulling it in gives Loom:

- In-pane editing with syntax highlighting.
- Save inside the workspace.
- A consistent design language (Loom and CodeEdit share macOS-native control idioms).

The integration is staged for a future minor version. Track it in the GitHub repo's issues.
