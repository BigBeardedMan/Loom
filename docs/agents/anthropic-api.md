# Anthropic API

Loom can talk directly to `https://api.anthropic.com/v1/messages` using an Anthropic API key. This is provider-direct (no Claude Code CLI in the loop) and gives you live token streaming.

## When to use it

Use the direct API when:

- You want streamed tokens.
- You want to use a model that isn't yet exposed through the Claude Code CLI's `-p` mode.
- You're running on a machine without `claude` on `PATH`.

For day-to-day work the Claude Code provider is preferred — it uses your existing OAuth login (no key management) and exposes the full sub-agent system.

## Setup

1. Get an API key from [console.anthropic.com](https://console.anthropic.com).
2. Open **Settings → Advanced**.
3. Paste the key into the **Anthropic API Key** field.
4. Click **Save**.

The key is stored in macOS Keychain under service `com.chasesims.Loom`, account `anthropic_api_key`. See [Keychain keys](../reference/keychain-keys.md).

## Wire format

The provider sends:

```http
POST https://api.anthropic.com/v1/messages
content-type: application/json
x-api-key: <your key>
anthropic-version: 2023-06-01
```

with `stream: true`. SSE events of type `content_block_delta` with `delta.type == "text_delta"` are emitted as tokens.

## Default model

`claude-opus-4-7`, max tokens `4096`. Both are tunable in code (`AnthropicProvider`) but not yet exposed in Settings — open an issue if you need that today.

## Cost

Direct API calls bill against your Anthropic account, separate from any Claude Code subscription. The Usage indicator in Loom's top bar reflects Claude Code's local OAuth quota — it does **not** track direct-API usage.
