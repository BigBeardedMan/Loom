# Custom providers

Need to point Loom at something that isn't Claude Code, Ollama, or an OpenAI-compatible server? You have two options today: add it as an OpenAI-compatible endpoint (often works) or write a new `LLMProvider` in code.

## Try OpenAI-compatible first

A surprising number of "weird" LLM servers actually speak the OpenAI wire format. If your server has any of these in its docs, add it as **OpenAI-compatible** in [Settings → Providers](../settings/providers.md):

- "OpenAI-compatible API"
- "OpenAI proxy"
- A `POST /v1/chat/completions` endpoint
- A `POST /chat/completions` endpoint (set Base URL to the parent — Loom appends `/chat/completions`)

This covers: vLLM, LocalAI, OpenRouter (with their key), Together, Groq, Mistral's chat endpoint, Anyscale, Perplexity, Fireworks, DeepInfra, and dozens more.

## Adding a new provider in code

If your target speaks a non-OpenAI wire format, drop a file into `Loom/Agents/` that conforms to `LLMProvider`:

```swift
// Loom/Agents/MyCoolProvider.swift
import Foundation

struct MyCoolProvider: LLMProvider {
    let baseURL: URL
    let model: String
    var displayName: String { "MyCool · \(model)" }

    func stream(
        messages: [LLMMessage],
        system: String?
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Build URLRequest, call URLSession.shared.bytes(for:),
                    // parse the wire format, yield .textDelta(...) per token.
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

Then:

1. Add a vendor case to `AgentDescriptor.Vendor` in `Loom/Agents/AgentRegistry.swift` (mark it `isLocalHTTP` if it's HTTP-streamed).
2. Surface the provider in the registry — either by registering it from a `LocalEndpoint` kind or adding a hardcoded descriptor.
3. Wire it into `AgentPaneView.sendViaLocalHTTP` (or write a parallel send method if it has unique requirements).
4. Run `xcodegen generate` to regenerate the project after adding the file.

See `OllamaProvider.swift` and `OpenAICompatibleProvider.swift` for two complete reference implementations.

## Why not a plugin system?

Loom is a personal tool. A plugin system has its own surface area (signing, sandboxing, distribution) that doesn't pay back for a single-user app. Editing the source and rebuilding is the supported extension path.
