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
step.

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
- **LM Studio:** hits `/api/v0/models` first, then falls back to `GET <baseURL>/models`. Reports installed and loaded model counts.
- **OpenAI-compatible:** hits `GET <baseURL>/models`. Reports HTTP 200 (or the failure reason).

For LM Studio, the model menu lists loaded models first and includes available
context length, quantization, and architecture details from `/api/v0/models`.

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
- Auth tokens: macOS Keychain, service `com.chasesims.Loom`, account `local_endpoint_<UUID>`.

See [Keychain keys](../reference/keychain-keys.md).

## Auto-refresh on save

Saving (or removing) an endpoint triggers `AgentRegistry.refresh(localEndpoints:)`. The Agent pane picker updates without an app restart.
