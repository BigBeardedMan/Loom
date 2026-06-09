## Changes

- Fixes runaway memory consumption: the usage dashboard, rate-limit sweep, and live-task polls re-read the entire `~/.codex/sessions` and `~/.claude/projects` trees (gigabytes for long-time CLI users) on timers and on every app activation. Polls now walk only the day directories inside their activity window, read bounded file tails, and cache parse results by file stamp, so memory no longer climbs the longer Loom runs.
- Fixes embedded CLI chat hanging forever when a turn printed more than 64KB: process output is now drained while the CLI runs instead of after it exits, so claude/codex/gemini turns can no longer deadlock on a full pipe.
- Production version metadata is now 9.0.5 on macOS and Windows.
