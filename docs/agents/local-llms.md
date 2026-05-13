# Local LLMs

Loom can stream chat from any LLM you run on `localhost` or your LAN. Two integrations are built in:

| Kind | Best for | Wire format |
| ---- | -------- | ----------- |
| **Ollama** | `ollama serve` running locally or on a homelab box | `POST /api/chat` (NDJSON stream), `GET /api/tags` for models |
| **OpenAI-compatible** | LM Studio, llama.cpp's `llama-server`, Jan, vLLM, LocalAI, anything that speaks `/v1/chat/completions` | OpenAI SSE stream |

Both are added in [Settings → Providers](../settings/providers.md).

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

## OpenAI-compatible setup (LM Studio, llama.cpp, Jan, vLLM)

These tools all expose an OpenAI-shaped HTTP API. Pick one, start its server, then add an endpoint in Loom.

### LM Studio

1. In LM Studio: **Developer** → **Local Server** → start the server (default port `1234`).
2. Note the **model identifier** in the active session — e.g. `lmstudio-community/Llama-3.1-8B-Instruct`.
3. Loom → **Settings → Providers → Add**.
   - **Display name:** `LM Studio`
   - **Kind:** OpenAI-compatible
   - **Base URL:** `http://localhost:1234/v1`
   - **Model:** the identifier from step 2.
   - **Requires auth:** off.
4. **Save**.

> Prefer a terminal? The [`lmstudio` CLI](lmstudio-cli.md) ships with Loom and gives you a `claude`-style agent loop in any terminal, backed by the same LM Studio server. Tasks flow into Loom's Tasks pane automatically.

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

## Troubleshooting

- **"HTTP 404"** when sending — check the Base URL. OpenAI-compatible servers expect the `/v1` path; Ollama does not.
- **"Could not connect to the server"** — daemon isn't running, or the port is wrong, or a firewall is blocking it. The **Test connection** button in the editor isolates the network problem from the model problem.
- **No models showing in the picker after Ollama add** — `/api/tags` returned empty (or the daemon isn't on the URL you typed). Make sure `ollama list` has at least one model and the URL works in `curl`.
- **Empty / hung response** — many local models don't honor `stop` tokens correctly. Check the server's logs.
