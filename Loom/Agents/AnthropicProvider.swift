import Foundation

struct AnthropicProvider: LLMProvider {
    let apiKey: String
    var model: String = "claude-opus-4-7"
    var maxTokens: Int = 4096
    var displayName: String { "Claude · \(model)" }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    func stream(
        messages: [LLMMessage],
        system: String?,
        tools: [LLMTool]
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        makeLLMStream { continuation in
            try await runStream(
                messages: messages,
                system: system,
                tools: tools,
                continuation: continuation
            )
        }
    }

    private func runStream(
        messages: [LLMMessage],
        system: String?,
        tools: [LLMTool],
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) async throws {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        let toolPayload: [ToolPayload] = tools.compactMap { tool in
            guard let schema = try? JSONSerialization.jsonObject(with: tool.inputSchema) else {
                return nil
            }
            return ToolPayload(
                name: tool.name,
                description: tool.description,
                input_schema: AnyEncodable(schema)
            )
        }

        let payload = RequestBody(
            model: model,
            max_tokens: maxTokens,
            stream: true,
            system: system,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            tools: toolPayload.isEmpty ? nil : toolPayload
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await ensureLLMSuccess(response: response, bytes: bytes)

        // Per-content-block buffers. Anthropic streams interleave events for
        // multiple blocks via `index`, so each block id buffers its own
        // tool-use input JSON until `content_block_stop`.
        var toolBlocks: [Int: ToolBlockBuffer] = [:]

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard !json.isEmpty, json != "[DONE]" else { continue }
            guard let data = json.data(using: .utf8) else { continue }
            guard let evt = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }

            switch evt.type {
            case "content_block_start":
                if let block = evt.content_block, block.type == "tool_use",
                   let idx = evt.index, let name = block.name {
                    toolBlocks[idx] = ToolBlockBuffer(name: name, json: "")
                }

            case "content_block_delta":
                guard let delta = evt.delta else { continue }
                if delta.type == "text_delta", let text = delta.text {
                    continuation.yield(.textDelta(text))
                } else if delta.type == "input_json_delta",
                          let partial = delta.partial_json,
                          let idx = evt.index,
                          var buf = toolBlocks[idx] {
                    buf.json += partial
                    toolBlocks[idx] = buf
                }

            case "content_block_stop":
                if let idx = evt.index, let buf = toolBlocks.removeValue(forKey: idx) {
                    let inputData = buf.json.data(using: .utf8) ?? Data("{}".utf8)
                    continuation.yield(.toolUse(name: buf.name, input: inputData))
                }

            default:
                continue
            }
        }
    }

    // MARK: - Wire types

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let stream: Bool
        let system: String?
        let messages: [Msg]
        let tools: [ToolPayload]?
        struct Msg: Encodable { let role: String; let content: String }
    }

    private struct ToolPayload: Encodable {
        let name: String
        let description: String
        let input_schema: AnyEncodable
    }

    private struct StreamEvent: Decodable {
        let type: String
        let index: Int?
        let delta: Delta?
        let content_block: ContentBlock?
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let partial_json: String?
        }
        struct ContentBlock: Decodable {
            let type: String
            let name: String?
        }
    }

    private struct ToolBlockBuffer {
        let name: String
        var json: String
    }
}

/// Tiny `Encodable` wrapper that re-encodes any JSON value (decoded via
/// `JSONSerialization`) back into the request body. Used to pass through the
/// caller-supplied JSON Schema for a tool without re-modeling every keyword.
struct AnyEncodable: Encodable {
    private let value: Any

    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        try json.encode(to: encoder)
    }

    private enum JSONValue: Codable {
        case null
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            if let b = try? c.decode(Bool.self) { self = .bool(b); return }
            if let i = try? c.decode(Int.self) { self = .int(i); return }
            if let d = try? c.decode(Double.self) { self = .double(d); return }
            if let s = try? c.decode(String.self) { self = .string(s); return }
            if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
            if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
            self = .null
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .null:        try c.encodeNil()
            case .bool(let v): try c.encode(v)
            case .int(let v):  try c.encode(v)
            case .double(let v): try c.encode(v)
            case .string(let v): try c.encode(v)
            case .array(let v):  try c.encode(v)
            case .object(let v): try c.encode(v)
            }
        }
    }
}
