import Foundation

/// Native Ollama HTTP provider. Streams from `POST {baseURL}/api/chat` with
/// `stream: true` (newline-delimited JSON, one chunk per line). Model
/// discovery rides on `GET {baseURL}/api/tags`.
struct OllamaProvider: LLMProvider {
    let baseURL: URL
    let model: String
    var displayName: String { "Ollama · \(model)" }

    func stream(
        messages: [LLMMessage],
        system: String?,
        tools: [LLMTool]
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        // Ollama path doesn't use Anthropic-style tool-use — proposals come
        // from ListResponseParser on the finalized response instead.
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
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

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
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else { continue }
            if let text = chunk.message?.content, !text.isEmpty {
                continuation.yield(.textDelta(text))
            }
            if chunk.done == true { break }
        }
    }

    /// Fetch the list of locally pulled models from `GET /api/tags`. Returns
    /// an empty array on error so the registry can keep moving.
    static func fetchModels(baseURL: URL) async -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return [] }
            let payload = try JSONDecoder().decode(TagsResponse.self, from: data)
            return payload.models.map(\.name)
        } catch {
            return []
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
        let message: ChunkMessage?
        let done: Bool?
    }

    private struct ChunkMessage: Decodable {
        let content: String?
    }

    private struct TagsResponse: Decodable {
        let models: [Tag]
        struct Tag: Decodable {
            let name: String
        }
    }
}
