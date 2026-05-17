## Changes

- Claude, Codex, and Gemini Usage now have a dedicated **Limits** button beside Day, Week, Month, and Year, so limit signals live in their own dashboard instead of being mixed into timeframe charts.
- Codex Limits now reads the latest locally logged Codex rate-limit snapshot on both Mac and Windows, including primary and secondary meters, reset times, plan type, credit balance, reached-limit status, and observation time.
- Claude and Gemini Limits now show a clear no-local-signal state instead of fake quota numbers when their local CLI logs do not expose readable limit data.
- The Usage Dashboard guide now documents the Limits mode and makes clear that Loom reads local logs only; it does not call Anthropic, OpenAI, or Gemini billing APIs for live quota lookup.
