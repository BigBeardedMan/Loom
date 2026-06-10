## Changes

- The Usage panel's Limits tab now works for Claude Code: a 5-hour rolling-block monitor estimated from local token logs (current block vs your largest recent block, with reset time), labeled as a local estimate since Claude Code does not log official percentages.
- Fixes the Codex Limits panel going blank: newer Codex CLIs write `rate_limits` lines with every field null, and the newest empty line shadowed the latest real percentages. All-null lines are now ignored, so the panel shows the most recent meaningful snapshot (with its observed date) again.
- Fixes runaway memory consumption: the usage dashboard, rate-limit sweep, and live-task polls re-read the entire `~/.codex/sessions` and `~/.claude/projects` trees (gigabytes for long-time CLI users) on timers and on every app activation. Polls now walk only the day directories inside their activity window, read bounded file tails, and cache parse results by file stamp, so memory no longer climbs the longer Loom runs.
- Fixes embedded CLI chat hanging forever when a turn printed more than 64KB: process output is now drained while the CLI runs instead of after it exits, so claude/codex/gemini turns can no longer deadlock on a full pipe.
- Production version metadata is now 9.0.7 on macOS and Windows.
