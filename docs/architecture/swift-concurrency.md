# Swift concurrency

Loom builds with `SWIFT_STRICT_CONCURRENCY: complete` on Swift 6. Every value that crosses an actor boundary is `Sendable`. Here's how the codebase deals with it.

## Default isolation

- **App-level state** (workspace layout, agent registry, live tasks, settings) is `@MainActor`. SwiftUI views read these directly; mutations land on the main actor.
- **Pure data types** (`LocalEndpoint`, `LLMMessage`, `LLMEvent`, `KanbanCard`) are structs / enums marked `Sendable`. They cross actors freely.
- **HTTP providers** (`AnthropicProvider`, `OllamaProvider`, `OpenAICompatibleProvider`) are structs. The `stream(...)` method returns an `AsyncThrowingStream` whose continuation is closed-over by a `Task`; cancellation flows through `continuation.onTermination`.

## Subprocess providers

`ClaudeCodeProvider` is `@MainActor` `final class` — it owns mutable state (`activeProcess`, `hasLaunchedSession`, `sessionID`). The actual subprocess work is dispatched off main via `Task.detached(priority: .userInitiated) { ... }` inside `send(...)`, with a tuple return type that's already `Sendable`.

## Streaming

`AsyncThrowingStream<LLMEvent, Error>` is the streaming primitive. Its continuation is `@unchecked Sendable` (Apple's contract; we trust it). Each provider builds a stream like:

```swift
AsyncThrowingStream { continuation in
    let task = Task {
        do {
            try await runStream(..., continuation: continuation)
            continuation.yield(.done)
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
    continuation.onTermination = { _ in task.cancel() }
}
```

Cancelation is two-way:

- The caller drops the stream → `onTermination` fires → inner Task cancels → URLSession's `bytes(for:)` throws `CancellationError`.
- The inner Task hits an HTTP error → it calls `continuation.finish(throwing:)` → the caller's `for try await` rethrows.

## URLSession.bytes(for:)

The streaming body iterator. Crucially, it propagates `Task.cancel()` into the underlying URLSessionDataTask, so we get clean teardown without manually tracking the task. We do call `try Task.checkCancellation()` inside the inner loop as belt-and-suspenders.

## Static parsing helpers

Where parsing is pure, the function is marked `nonisolated static` so it can run off any actor and be unit-tested in isolation. Example: `AgentRegistry.parseClaudeAgentsList(_:)`.

## `nonisolated(unsafe)` — avoided

Loom does not use `nonisolated(unsafe)` to silence concurrency warnings. Anything that's tempting becomes a `@MainActor` access, a `Sendable` struct, or a `Task.detached`.

## SwiftData on the main actor

All `ModelContext` access is `@MainActor`. The schema (`Workspace`, `KanbanBoard`, `KanbanColumn`, `KanbanCard`, `IdeaNote`) is on the main actor. We don't fan out to background contexts — the data volume doesn't warrant it.
