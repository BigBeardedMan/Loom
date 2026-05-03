# Keychain keys

Loom stores secrets in macOS Keychain under service `com.chasesims.Loom`. Every secret uses `kSecClassGenericPassword`.

## Account names

| Account | Set by | Purpose |
| ------- | ------ | ------- |
| `anthropic_api_key` | Settings → Advanced | Anthropic API key for direct-API agent provider. |
| `local_endpoint_<UUID>` | Settings → Providers (when **Requires auth** is on) | Bearer token for an OpenAI-compatible local endpoint. |

`<UUID>` is the `LocalEndpoint.id` (a `UUID().uuidString`). Each endpoint gets its own Keychain item; deleting an endpoint deletes its item.

## CRUD via the CLI

```bash
# View what Loom has stored
security dump-keychain | grep -A1 "com.chasesims.Loom"

# Read a specific value (shows the password in stdout)
security find-generic-password -s com.chasesims.Loom -a anthropic_api_key -w

# Delete one
security delete-generic-password -s com.chasesims.Loom -a anthropic_api_key

# Delete every Loom secret in one go
security dump-keychain | awk -F\" '/svce.*com.chasesims.Loom/{getline; print $4}' | \
  xargs -I{} security delete-generic-password -s com.chasesims.Loom -a {}
```

The bulk-delete one-liner is destructive — it nukes the Anthropic key and every local-endpoint token. Use it only when fully resetting Loom.

## Why Keychain instead of UserDefaults?

UserDefaults values land in `~/Library/Preferences/com.chasesims.Loom.plist` as plain text — readable by any process running as your user, including any wayward backup. Keychain encrypts the values at rest with the user's login keychain key, prompts on cross-app access, and survives backup/restore cleanly.

## What's NOT in Keychain

- The Claude Code OAuth token. That lives in `~/.claude/credentials.json`, managed by the Claude Code CLI itself. Loom doesn't read or modify it.
- Workspace data (kanban, notes) — SwiftData, on disk.
- Settings (theme, stale window) — UserDefaults.
