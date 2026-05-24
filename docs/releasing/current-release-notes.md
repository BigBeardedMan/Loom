## Changes

- Fixes live task sessions that stayed visible after a Codex turn had already emitted a final answer or `task_complete`.
- Hides Claude Code and LM Studio task groups once every task is terminal, instead of waiting for the stale-window timeout.
- Production version metadata is now 9.0.4 on macOS and Windows.
