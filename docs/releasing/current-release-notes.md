## Changes

- Codex Usage now reads local Codex session logs line by line, so the dashboard shows timeframe activity bars, token mix, model and project breakdowns, recent prompts, top topics, and hour-of-day usage instead of only lifetime token totals.
- Codex Usage now shows the latest locally logged Codex rate-limit snapshot when available, including primary and secondary meters, reset times, plan type, credit balance, and observation time.
- The Usage Dashboard guide now documents the fuller Codex local-log reader and makes clear that no Anthropic or OpenAI API call is made for live quota lookup.
- Tasks now separate live sessions by product, model, and session id, so Claude Code and Codex can run side by side without sharing one ambiguous monitor.
- Clearing Codex task groups now works without deleting rollout history: Loom hides the cleared product/model/session until its log advances, while Claude still clears its task JSON files.
- The clear confirmation and help text now describe the actual visible products/models instead of hard-coding Claude-only wording.
