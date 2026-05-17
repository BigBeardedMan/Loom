## Changes

- Claude, Codex, and Gemini Usage now have a dedicated **Limits** button beside Day, Week, Month, and Year, so limit signals live in their own dashboard instead of being mixed into timeframe charts.
- Codex Limits now reads the latest locally logged Codex rate-limit snapshot on both Mac and Windows, including primary and secondary meters, reset times, plan type, credit balance, reached-limit status, and observation time.
- Claude and Gemini Limits now show a clear no-local-signal state instead of fake quota numbers when their local CLI logs do not expose readable limit data.
- The Usage Dashboard guide now documents the Limits mode and makes clear that Loom reads local logs only; it does not call Anthropic, OpenAI, or Gemini billing APIs for live quota lookup.
- Tasks now separate live sessions by product, model, and session id, so Claude Code and Codex can run side by side without sharing one ambiguous monitor.
- Clearing Codex task groups now works without deleting rollout history: Loom hides the cleared product/model/session until its log advances, while Claude and LM Studio still clear their task JSON files.
- The clear confirmation and help text now describe the actual visible products/models instead of hard-coding Claude-only wording.
