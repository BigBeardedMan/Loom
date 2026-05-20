# Local LLMs

Loom can stream chat from any LLM you run on `localhost` or your LAN. Three integrations are built in:

| Kind | Best for | Wire format |
| ---- | -------- | ----------- |
| **Ollama** | `ollama serve` running locally or on a homelab box | `POST /api/chat` (NDJSON stream), `GET /api/tags` for models |
| **LM Studio** | LM Studio's local server, with richer model discovery through `/api/v0/models` | OpenAI SSE stream plus LM Studio model metadata |
| **OpenAI-compatible** | llama.cpp's `llama-server`, Jan, vLLM, LocalAI, anything that speaks `/v1/chat/completions` | OpenAI SSE stream |

All three are added in [Settings → Providers](../settings/providers.md).

## Ollama setup

1. Install Ollama: `brew install ollama` (or [download](https://ollama.com/download)).
2. Pull a model: `ollama pull llama3.2:3b`.
3. Make sure the daemon is running: `ollama serve` (the GUI installer auto-launches it; brew install does not).
4. Open Loom → **Settings → Providers → Add**.
   - **Display name:** `Ollama`
   - **Kind:** Ollama
   - **Base URL:** `http://localhost:11434`
   - **Default model:** leave blank — Loom auto-discovers via `/api/tags`.
   - **Requires auth:** off.
5. **Test connection** → should report `N model(s)`.
6. **Save**.

The Agent pane picker now has a `Local · Ollama` group with one entry per pulled model. Pick one, send a prompt, watch tokens stream in.

### Network Ollama

Run `ollama serve` on another machine with `OLLAMA_HOST=0.0.0.0:11434 ollama serve`, then in Loom set **Base URL** to `http://<host>:11434`. /api/tags discovery and /api/chat streaming work the same over LAN.

## LM Studio setup

LM Studio exposes an OpenAI-shaped chat API plus a native model-discovery API that tells Loom which models are installed and loaded.

1. In LM Studio: **Developer** → **Local Server** → start the server (default port `1234`).
2. Load a model in LM Studio, or use the `lms` CLI to load one.
3. Loom → **Settings → Providers → Add**.
   - **Display name:** `LM Studio`
   - **Kind:** LM Studio
   - **Base URL:** `http://localhost:1234/v1`
   - **Default model:** optional fallback only; Loom auto-discovers installed models through `/api/v0/models`.
   - **Requires auth:** off.
4. **Test connection** → should report installed and loaded model counts.
5. **Save**.

If the LM Studio server is already running when you open **Settings → Providers**,
Loom offers an **Add LM Studio** shortcut that creates this endpoint for you.
Loaded models appear first in the Agent picker with their context and
quantization details.

> Prefer a terminal? The [`lmstudio` CLI](lmstudio-cli.md) ships with Loom and gives you a `claude`-style agent loop in any terminal, backed by the same LM Studio server. Tasks flow into Loom's Tasks pane automatically.

## OpenAI-compatible setup (llama.cpp, Jan, vLLM)

These tools expose an OpenAI-shaped HTTP API. Pick one, start its server, then add an endpoint in Loom.

### llama.cpp

```bash
./llama-server -m /path/to/model.gguf --host 0.0.0.0 --port 8080
```

In Loom, **Base URL** = `http://localhost:8080/v1`, **Model** = whatever string you want (llama-server echoes it back regardless).

### Jan

Jan exposes an OpenAI-compatible server at `http://localhost:1337/v1` by default. Same setup — paste in the model identifier from Jan's UI.

### vLLM / LocalAI

Same shape: configure **Base URL** to wherever the server listens (commonly `http://localhost:8000/v1`), set the **Model** id to whatever the server expects, save.

## Auth tokens

Some local servers (or the LAN proxies in front of them) want a bearer token. Toggle **Requires auth** in the editor and paste the token. It's stored in macOS Keychain under account `local_endpoint_<UUID>` and sent as `Authorization: Bearer <token>` on every request.

## Streaming and cancel

All HTTP providers stream tokens live into the assistant bubble. Hit the **Stop** button (top right of the agent pane during a turn) to cancel — the URLSession task is canceled and the bubble shows whatever was already emitted.

LM Studio defaults to **Agent Mode** in the Agent pane. Use the wand button to
switch back to plain chat. In Agent Mode, the permission menu supports:

- **Ask:** prompt before file edits and shell commands.
- **Plan:** allow read/list/task updates only.
- **Accept Edits:** auto-approve file edits, still ask for shell commands.
- **Bypass Permissions:** auto-approve file edits and shell commands for the
  current run.

## Troubleshooting

- **"HTTP 404"** when sending — check the Base URL. OpenAI-compatible servers expect the `/v1` path; Ollama does not.
- **"Could not connect to the server"** — daemon isn't running, or the port is wrong, or a firewall is blocking it. The **Test connection** button in the editor isolates the network problem from the model problem.
- **No models showing in the picker after Ollama add** — `/api/tags` returned empty (or the daemon isn't on the URL you typed). Make sure `ollama list` has at least one model and the URL works in `curl`.
- **Empty / hung response** — many local models don't honor `stop` tokens correctly. Check the server's logs.
