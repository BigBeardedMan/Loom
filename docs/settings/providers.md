# Settings → Providers

Manages the local LLM endpoints that show up in the Agent pane's picker. See [Local LLMs](../agents/local-llms.md) for end-to-end setup.

## Listing endpoints

The Providers tab lists every configured endpoint with its kind, base URL, and a row of actions:

- **Edit** — opens the editor sheet pre-filled.
- **Trash icon** — removes the endpoint and clears its Keychain auth token (if any).

Empty state shows a hint pointing at Add.

If LM Studio's default server is already running on `localhost:1234` and no
LM Studio endpoint exists yet, Loom shows an **LM Studio server detected**
callout. Click **Add LM Studio** to save the standard local endpoint in one
step. Windows also keeps an **Add LM Studio** shortcut in the endpoint toolbar
so the standard `http://localhost:1234/v1` endpoint is one click away.

## Adding an endpoint

Click **Add** to open the editor:

| Field | Notes |
| ----- | ----- |
| **Display name** | Free-form. Shown as the menu group header (`Local · <name>`). |
| **Kind** | Ollama, LM Studio, or OpenAI-compatible. Switching kinds swaps the default base URL hint. |
| **Base URL** | Full URL. Trailing slash is stripped. Ollama defaults to `http://localhost:11434`; LM Studio and OpenAI-compatible default to `http://localhost:1234/v1`. |
| **Default model / Model** | For Ollama and LM Studio, optional fallback if discovery fails. For OpenAI-compatible, required (the model id sent in the request body). |
| **Requires auth token** | Toggle. When on, reveals a SecureField for a bearer token. |

### Test connection

Click **Test connection** before saving:

- **Ollama:** hits `GET <baseURL>/api/tags`. Reports the number of models (or "No models / unreachable").
- **LM Studio:** hits native `/api/v1/models` first, then `/api/v0/models`, then `GET <baseURL>/models`. Reports installed and loaded model counts plus native capability details when available.
- **OpenAI-compatible:** hits `GET <baseURL>/models`. Reports HTTP 200 (or the failure reason).

For LM Studio, the model menu lists loaded models first and includes available
context length, quantization, architecture, tool-use, and native API details.
When the server supports native v1 chat, chat-mode runs can show model-load
progress, prompt-processing progress, stateful response IDs, and token-speed
stats. Agent Mode still uses OpenAI-compatible tool calling so Loom's file,
shell, git, test, and preview tools keep the same workspace and permission
guards.

On Windows, the Agent pane can also start the `lms` server, load the selected
model, and show native chat progress from the LM Studio runtime strip.

Test does **not** save the endpoint. You still have to click Save.

## Editing

Selecting **Edit** on an existing row pre-fills the form, including the auth token (read from Keychain). Save overwrites the existing endpoint.

## Removing

The trash icon:

1. Removes the endpoint from `UserDefaults` (`loom.localEndpoints`).
2. Deletes the matching Keychain item (account `local_endpoint_<UUID>`).
3. Triggers an agent registry refresh so the Agent pane picker drops any descriptors tied to it.

## Storage

- Endpoint metadata: `UserDefaults` under key `loom.localEndpoints`, JSON-encoded `[LocalEndpoint]`.
- Auth tokens: macOS Keychain or Windows Credential Manager, scoped to the endpoint UUID.

See [Keychain keys](../reference/keychain-keys.md).

## Auto-refresh on save

Saving (or removing) an endpoint triggers `AgentRegistry.refresh(localEndpoints:)`. The Agent pane picker updates without an app restart.
