import Foundation

/// Streaming chat-completions provider for any server that speaks the
/// OpenAI v1 wire format: LM Studio, llama.cpp's `llama-server`, Jan, vLLM,
/// LocalAI, Ollama's compatibility shim, etc. The base URL should already
/// include `/v1` (e.g. `http://localhost:1234/v1`).
struct OpenAICompatibleProvider: LLMProvider {
    let baseURL: URL
    let model: String
    let apiKey: String?
    var displayName: String { "Local · \(model)" }

    func stream(
        messages: [LLMMessage],
        system: String?,
        tools: [LLMTool]
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        // Tool-use isn't wired through the OpenAI-compatible path — the chat
        // pane falls back to ListResponseParser on the finalized text instead.
        _ = tools
        return makeLLMStream { continuation in
            try await runStream(messages: messages, system: system, continuation: continuation)
        }
    }

    private func runStream(
        messages: [LLMMessage],
        system: String?,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        }

        var msgs: [Msg] = []
        if let system, !system.isEmpty {
            msgs.append(Msg(role: "system", content: system))
        }
        msgs.append(contentsOf: messages.map { Msg(role: $0.role.rawValue, content: $0.content) })

        let payload = RequestBody(model: model, stream: true, messages: msgs)
        request.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await ensureLLMSuccess(response: response, bytes: bytes)

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard !json.isEmpty else { continue }
            if json == "[DONE]" { break }
            guard let data = json.data(using: .utf8) else { continue }
            guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else { continue }
            for choice in chunk.choices {
                if let text = choice.delta.content, !text.isEmpty {
                    continuation.yield(.textDelta(text))
                }
            }
        }
    }

    private struct RequestBody: Encodable {
        let model: String
        let stream: Bool
        let messages: [Msg]
    }

    private struct Msg: Encodable {
        let role: String
        let content: String
    }

    private struct StreamChunk: Decodable {
        let choices: [Choice]
    }

    private struct Choice: Decodable {
        let delta: Delta
    }

    private struct Delta: Decodable {
        let content: String?
    }
}
