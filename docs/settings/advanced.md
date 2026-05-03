# Settings → Advanced

Anthropic API key, for the optional [Anthropic API direct provider](../agents/anthropic-api.md).

## API key field

- **SecureField** — input is masked.
- **Save** — writes to macOS Keychain (service `com.chasesims.Loom`, account `anthropic_api_key`).
- **Clear** — deletes the Keychain item.
- A green "Saved" badge appears for ~2 seconds after a successful save.

## When you don't need it

Loom's default Agent provider is Claude Code via OAuth subprocess — no API key required. Most users never touch this tab.

Set the API key only when you want:

- Token-streamed responses (Claude Code's `-p` mode is one-shot).
- Direct API access without `claude` on `PATH`.
- A model that the Claude Code CLI doesn't expose.

## Storage

The key never leaves macOS Keychain. Loom reads it just-in-time when an `AnthropicProvider` instance is built — there's no in-memory cache. Cleaning the Keychain item via the Clear button or via `security delete-generic-password -s com.chasesims.Loom -a anthropic_api_key` makes the next direct-API send fail with `LLMError.missingAPIKey`.
