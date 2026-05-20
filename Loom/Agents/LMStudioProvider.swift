import Foundation

/// LM Studio provider. Speaks the OpenAI v1 wire format on the chat path
/// (`{baseURL}/chat/completions`) and the LM Studio native v0 API on the
/// model-discovery path (`{root}/api/v0/models`) so the picker can show
/// per-model `loaded` status, context length, and quantization. Tool calls
/// are emitted as `LLMEvent.toolUse` so the agent orchestrator can drive
/// multi-turn loops against local code models like Qwen3-Coder, gpt-oss, and
/// DeepSeek-Coder.
struct LMStudioProvider: LLMProvider {
    let baseURL: URL
    let model: String
    var displayName: String { "LM Studio · \(model)" }

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

    // MARK: - Health

    /// Cheap GET against `/v1/models`. Used by the Settings server-status pill
    /// so the UI can flip green/red without waiting on the lms CLI.
    static func serverIsUp(baseURL: URL, timeout: TimeInterval = 1.5) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Model discovery

    struct LMStudioModel: Hashable, Sendable {
        let id: String
        let loaded: Bool
        let contextLength: Int?
        let quantization: String?
        let architecture: String?

        var displayLabel: String {
            let details = metadataSummary
            if details.isEmpty { return id }
            return "\(id) (\(details))"
        }

        var metadataSummary: String {
            var bits: [String] = []
            if loaded { bits.append("loaded") }
            if let contextLength {
                bits.append(Self.formatContext(contextLength))
            }
            if let quantization, !quantization.isEmpty {
                bits.append(quantization)
            }
            if let architecture, !architecture.isEmpty {
                bits.append(architecture)
            }
            return bits.joined(separator: " · ")
        }

        private static func formatContext(_ length: Int) -> String {
            if length >= 1000 {
                return "\(length / 1000)k ctx"
            }
            return "\(length) ctx"
        }
    }

    /// Hits `/api/v0/models` (native API) for rich metadata. Falls back to the
    /// OpenAI-compat `/v1/models` shape when the native endpoint is missing.
    static func fetchModels(baseURL: URL) async -> [LMStudioModel] {
        let nativeRoot = nativeAPIRoot(from: baseURL)
        if let models = await tryNativeModels(nativeRoot: nativeRoot), !models.isEmpty {
            return sortedModels(models)
        }
        return sortedModels(await tryOpenAIModels(baseURL: baseURL))
    }

    private static func sortedModels(_ models: [LMStudioModel]) -> [LMStudioModel] {
        models.sorted { lhs, rhs in
            if lhs.loaded != rhs.loaded {
                return lhs.loaded && !rhs.loaded
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private static func tryNativeModels(nativeRoot: URL) async -> [LMStudioModel]? {
        var request = URLRequest(url: nativeRoot.appendingPathComponent("models"))
        request.timeoutInterval = 3
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(NativeModelsResponse.self, from: data)
            return decoded.data.map { entry in
                LMStudioModel(
                    id: entry.id,
                    loaded: (entry.state ?? "").lowercased() == "loaded",
                    contextLength: entry.max_context_length ?? entry.loaded_context_length,
                    quantization: entry.quantization,
                    architecture: entry.arch
                )
            }
        } catch {
            return nil
        }
    }

    private static func tryOpenAIModels(baseURL: URL) async -> [LMStudioModel] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 3
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            return decoded.data.map { entry in
                LMStudioModel(
                    id: entry.id,
                    loaded: false,
                    contextLength: nil,
                    quantization: nil,
                    architecture: nil
                )
            }
        } catch {
            return []
        }
    }

    /// Strip a trailing `/v1` from the user-supplied base URL so the native
    /// API root sits at the same host. LM Studio exposes `/api/v0/...` and
    /// `/v1/...` as siblings of the host root.
    private static func nativeAPIRoot(from baseURL: URL) -> URL {
        let path = baseURL.path
        if path.hasSuffix("/v1") {
            let trimmed = String(path.dropLast("/v1".count))
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.path = trimmed
            if let root = components?.url {
                return root.appendingPathComponent("api/v0")
            }
        }
        return baseURL.appendingPathComponent("api/v0")
    }

    // MARK: - Streaming

    private func runStream(
        messages: [LLMMessage],
        system: String?,
        tools: [LLMTool],
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        // LM Studio accepts the literal "lm-studio" Bearer or no auth at all.
        // Sending it makes proxies that strip empty headers happy.
        request.setValue("Bearer lm-studio", forHTTPHeaderField: "authorization")

        var msgs: [Msg] = []
        if let system, !system.isEmpty {
            msgs.append(Msg(role: "system", content: system))
        }
        msgs.append(contentsOf: messages.map { Msg(role: $0.role.rawValue, content: $0.content) })

        let toolDefs: [ToolDef]? = tools.isEmpty ? nil : tools.compactMap { tool in
            guard let schema = try? JSONSerialization.jsonObject(with: tool.inputSchema) else {
                return nil
            }
            return ToolDef(
                type: "function",
                function: ToolFunctionDef(
                    name: tool.name,
                    description: tool.description,
                    parameters: AnyEncodable(schema)
                )
            )
        }

        let payload = RequestBody(model: model, stream: true, messages: msgs, tools: toolDefs)
        request.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await ensureLLMSuccess(response: response, bytes: bytes)

        // Tool calls arrive across many SSE chunks. Each chunk's `arguments`
        // string is a fragment that must be concatenated until the choice
        // emits `finish_reason: "tool_calls"`. Indexed by `tool_calls[*].index`.
        var pendingToolCalls: [Int: PendingToolCall] = [:]

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
                if let toolDeltas = choice.delta.tool_calls {
                    for tc in toolDeltas {
                        let index = tc.index ?? 0
                        var entry = pendingToolCalls[index] ?? PendingToolCall()
                        if let name = tc.function?.name { entry.name = name }
                        if let args = tc.function?.arguments { entry.arguments += args }
                        pendingToolCalls[index] = entry
                    }
                }
                if let reason = choice.finish_reason, reason == "tool_calls" {
                    let sorted = pendingToolCalls.sorted { $0.key < $1.key }
                    for (_, entry) in sorted {
                        guard let name = entry.name else { continue }
                        let argsData = entry.arguments.data(using: .utf8) ?? Data("{}".utf8)
                        continuation.yield(.toolUse(name: name, input: argsData))
                    }
                    pendingToolCalls.removeAll()
                }
            }
        }
    }

    // MARK: - Wire types

    private struct PendingToolCall {
        var name: String?
        var arguments: String = ""
    }

    private struct RequestBody: Encodable {
        let model: String
        let stream: Bool
        let messages: [Msg]
        let tools: [ToolDef]?
    }

    private struct Msg: Encodable {
        let role: String
        let content: String
    }

    private struct ToolDef: Encodable {
        let type: String
        let function: ToolFunctionDef
    }

    private struct ToolFunctionDef: Encodable {
        let name: String
        let description: String
        let parameters: AnyEncodable
    }

    /// Wraps a Foundation JSON object so it can be re-encoded inside Codable.
    private struct AnyEncodable: Encodable {
        let value: Any
        init(_ value: Any) { self.value = value }
        func encode(to encoder: Encoder) throws {
            let data = try JSONSerialization.data(withJSONObject: value)
            var container = encoder.singleValueContainer()
            if let object = try? JSONDecoder().decode(JSONValue.self, from: data) {
                try container.encode(object)
            } else {
                try container.encode([String: String]())
            }
        }
    }

    private indirect enum JSONValue: Codable {
        case null, bool(Bool), int(Int), double(Double), string(String)
        case array([JSONValue]), object([String: JSONValue])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            if let b = try? c.decode(Bool.self) { self = .bool(b); return }
            if let i = try? c.decode(Int.self) { self = .int(i); return }
            if let d = try? c.decode(Double.self) { self = .double(d); return }
            if let s = try? c.decode(String.self) { self = .string(s); return }
            if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
            if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .null: try c.encodeNil()
            case .bool(let b): try c.encode(b)
            case .int(let i): try c.encode(i)
            case .double(let d): try c.encode(d)
            case .string(let s): try c.encode(s)
            case .array(let a): try c.encode(a)
            case .object(let o): try c.encode(o)
            }
        }
    }

    private struct StreamChunk: Decodable {
        let choices: [Choice]
    }

    private struct Choice: Decodable {
        let delta: Delta
        let finish_reason: String?
    }

    private struct Delta: Decodable {
        let content: String?
        let tool_calls: [ToolCallDelta]?
    }

    private struct ToolCallDelta: Decodable {
        let index: Int?
        let id: String?
        let function: FunctionDelta?
    }

    private struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }

    private struct NativeModelsResponse: Decodable {
        let data: [NativeModelEntry]
    }

    private struct NativeModelEntry: Decodable {
        let id: String
        let state: String?
        let max_context_length: Int?
        let loaded_context_length: Int?
        let quantization: String?
        let arch: String?
    }

    private struct OpenAIModelsResponse: Decodable {
        let data: [OpenAIModelEntry]
    }

    private struct OpenAIModelEntry: Decodable {
        let id: String
    }
}
