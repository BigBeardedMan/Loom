import Foundation
import os

private let llmLog = Logger(subsystem: "com.chasesims.Loom", category: "llm")

struct LLMMessage: Hashable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    let role: Role
    let content: String
}

enum LLMEvent: Sendable {
    case textDelta(String)
    /// Provider invoked a tool. `input` is the raw JSON payload the model
    /// produced for the tool's parameters; the consumer decodes it.
    case toolUse(name: String, input: Data)
    case done
}

/// Tool the agent may invoke during a stream. Only Anthropic-backed providers
/// honor this today; other providers ignore the parameter.
struct LLMTool: Sendable {
    let name: String
    let description: String
    /// JSON Schema describing the tool's input. Encoded as a JSON object.
    let inputSchema: Data
}

protocol LLMProvider: Sendable {
    var displayName: String { get }
    func stream(
        messages: [LLMMessage],
        system: String?,
        tools: [LLMTool]
    ) -> AsyncThrowingStream<LLMEvent, Error>
}

extension LLMProvider {
    /// Convenience overload for callers that don't need tools (the existing
    /// ones — Ollama, OpenAI-compatible, Claude Code subprocess).
    func stream(messages: [LLMMessage], system: String?) -> AsyncThrowingStream<LLMEvent, Error> {
        stream(messages: messages, system: system, tools: [])
    }
}

enum LLMError: LocalizedError {
    case missingAPIKey
    /// Surfaced HTTP failure. The body is logged privately via `llmLog` and
    /// intentionally **not** exposed in `errorDescription` — provider error
    /// payloads can contain account or billing identifiers we don't want to
    /// paint into the chat UI.
    case httpStatus(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured. Open Settings to add one."
        case .httpStatus(let code):
            return "HTTP \(code)"
        case .decoding(let msg):
            return "Decode error: \(msg)"
        }
    }
}

/// Shared streaming wrapper used by every HTTP `LLMProvider`. Spawns the
/// supplied `body`, yields `.done` on clean completion, and forwards
/// cancellation back to the underlying task when the consumer tears down.
func makeLLMStream(
    _ body: @Sendable @escaping (AsyncThrowingStream<LLMEvent, Error>.Continuation) async throws -> Void
) -> AsyncThrowingStream<LLMEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                try await body(continuation)
                continuation.yield(.done)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Drain a streaming HTTP response and convert any non-2xx into `LLMError.httpStatus`.
/// The response body is logged privately so we don't leak it into the UI.
func ensureLLMSuccess(
    response: URLResponse,
    bytes: URLSession.AsyncBytes
) async throws {
    guard let http = response as? HTTPURLResponse else {
        throw LLMError.decoding("Non-HTTP response")
    }
    guard (200..<300).contains(http.statusCode) else {
        var body = ""
        for try await line in bytes.lines {
            body += line + "\n"
            if body.count > 4096 { break }
        }
        if !body.isEmpty {
            llmLog.error("HTTP \(http.statusCode, privacy: .public): \(body, privacy: .private)")
        } else {
            llmLog.error("HTTP \(http.statusCode, privacy: .public) with empty body")
        }
        throw LLMError.httpStatus(http.statusCode)
    }
}
