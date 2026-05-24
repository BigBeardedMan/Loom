import Foundation

/// LM Studio provider. Speaks the OpenAI v1 wire format on the tool-agent chat
/// path (`{baseURL}/chat/completions`) and LM Studio's native v1 API for model
/// discovery/load/unload/download. Native v0 remains as a compatibility
/// fallback for older LM Studio builds.
struct LMStudioProvider: LLMProvider {
    let baseURL: URL
    let model: String
    let apiKey: String?
    let previousResponseID: String?
    let nativeContextLength: Int?
    var displayName: String { "LM Studio · \(model)" }

    init(
        baseURL: URL,
        model: String,
        apiKey: String? = nil,
        previousResponseID: String? = nil,
        nativeContextLength: Int? = nil
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.previousResponseID = previousResponseID
        self.nativeContextLength = nativeContextLength
    }

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
    static func serverIsUp(baseURL: URL, apiKey: String? = nil, timeout: TimeInterval = 1.5) async -> Bool {
        var request = authorizedRequest(url: baseURL.appendingPathComponent("models"), apiKey: apiKey)
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

    /// Probe whether this LM Studio build/model accepts OpenAI-style
    /// `response_format: { type: "json_schema" }`. The result is cached per
    /// endpoint + model because older LM Studio builds reject the field, while
    /// newer ones use it to reliably repair malformed tool arguments.
    static func supportsJSONSchemaResponseFormat(baseURL: URL, model: String, apiKey: String? = nil) async -> Bool {
        let key = jsonSchemaProbeCacheKey(baseURL: baseURL, model: model)
        if let cached = UserDefaults.standard.object(forKey: key) as? Bool {
            return cached
        }
        let supported = await probeJSONSchemaResponseFormat(baseURL: baseURL, model: model, apiKey: apiKey)
        UserDefaults.standard.set(supported, forKey: key)
        return supported
    }

    func repairToolArguments(
        transcript: [LLMMessage],
        toolName: String,
        badInput: Data,
        schema: Data,
        errorMessage: String?
    ) async -> Data? {
        guard let schemaObject = try? JSONSerialization.jsonObject(with: schema),
              JSONSerialization.isValidJSONObject(schemaObject) else {
            return nil
        }

        let recent = transcript.suffix(8).map { message in
            "\(message.role.rawValue): \(String(message.content.prefix(1400)))"
        }.joined(separator: "\n\n")
        let rawInput = String(decoding: badInput, as: UTF8.self)
        let repairPrompt = """
        Repair the JSON arguments for the tool named "\(toolName)".

        Return only a JSON object that conforms to this schema. Do not include markdown.

        Schema:
        \(String(decoding: schema, as: UTF8.self))

        Invalid arguments:
        \(rawInput)

        Error:
        \(errorMessage ?? "The arguments were missing required fields or were not valid JSON.")

        Recent conversation:
        \(recent)
        """

        let supportsSchema = await Self.supportsJSONSchemaResponseFormat(baseURL: baseURL, model: model, apiKey: apiKey)
        if supportsSchema,
           let repaired = await runArgumentRepair(
                prompt: repairPrompt,
                schemaName: "loom_\(toolName)_args",
                schemaObject: schemaObject
           ) {
            return repaired
        }

        return await runArgumentRepair(
            prompt: repairPrompt,
            schemaName: nil,
            schemaObject: nil
        )
    }

    private static func probeJSONSchemaResponseFormat(baseURL: URL, model: String, apiKey: String?) async -> Bool {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "ok": ["type": "boolean"]
            ],
            "required": ["ok"],
            "additionalProperties": false
        ]
        let responseFormat = ResponseFormat(
            type: "json_schema",
            json_schema: ResponseJSONSchema(
                name: "loom_probe",
                strict: true,
                schema: AnyEncodable(schema)
            )
        )
        let messages = [
            Msg(role: "user", content: "Return {\"ok\": true}.")
        ]
        var request = authorizedRequest(url: baseURL.appendingPathComponent("chat/completions"), apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        do {
            let payload = RequestBody(
                model: model,
                stream: false,
                messages: messages,
                response_format: responseFormat,
                max_tokens: 32,
                temperature: 0
            )
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private static func jsonSchemaProbeCacheKey(baseURL: URL, model: String) -> String {
        let raw = "\(baseURL.absoluteString)|\(model)"
        let encoded = Data(raw.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "loom.lmstudio.jsonSchemaSupport.\(encoded)"
    }

    private func runArgumentRepair(
        prompt: String,
        schemaName: String?,
        schemaObject: Any?
    ) async -> Data? {
        var request = Self.authorizedRequest(url: baseURL.appendingPathComponent("chat/completions"), apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let responseFormat: ResponseFormat?
        if let schemaName, let schemaObject {
            responseFormat = ResponseFormat(
                type: "json_schema",
                json_schema: ResponseJSONSchema(
                    name: schemaName,
                    strict: true,
                    schema: AnyEncodable(schemaObject)
                )
            )
        } else {
            responseFormat = nil
        }

        let payload = RequestBody(
            model: model,
            stream: false,
            messages: [
                Msg(role: "system", content: "You repair tool-call JSON for a local coding agent."),
                Msg(role: "user", content: prompt)
            ],
            response_format: responseFormat,
            max_tokens: 1024,
            temperature: 0
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(NonStreamingResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content,
                  let repaired = LMStudioToolRepair.firstJSONObjectData(in: content),
                  (try? JSONSerialization.jsonObject(with: repaired)) != nil else {
                return nil
            }
            return repaired
        } catch {
            return nil
        }
    }

    // MARK: - Model discovery

    struct LMStudioModel: Hashable, Sendable {
        let id: String
        let displayName: String?
        let loaded: Bool
        let contextLength: Int?
        let maxContextLength: Int?
        let quantization: String?
        let architecture: String?
        let trainedForToolUse: Bool?
        let sizeBytes: Int64?
        let format: String?
        let publisher: String?
        let loadedInstanceIDs: [String]
        let apiMode: String

        var displayLabel: String {
            let details = metadataSummary
            let title = displayName?.isEmpty == false ? "\(displayName!) · \(id)" : id
            if details.isEmpty { return title }
            return "\(title) (\(details))"
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
            if trainedForToolUse == true {
                bits.append("tools")
            } else if trainedForToolUse == false {
                bits.append("no tools")
            }
            if let format, !format.isEmpty {
                bits.append(format)
            }
            if let sizeBytes, sizeBytes > 0 {
                bits.append(Self.formatBytes(sizeBytes))
            }
            return bits.joined(separator: " · ")
        }

        private static func formatContext(_ length: Int) -> String {
            if length >= 1000 {
                return "\(length / 1000)k ctx"
            }
            return "\(length) ctx"
        }

        private static func formatBytes(_ bytes: Int64) -> String {
            let gb = Double(bytes) / 1_073_741_824
            if gb >= 1 {
                return String(format: "%.1f GB", gb)
            }
            let mb = Double(bytes) / 1_048_576
            return String(format: "%.0f MB", mb)
        }
    }

    struct CapabilitySnapshot: Hashable, Sendable {
        let apiMode: String
        let supportsV1: Bool
        let supportsNativeChat: Bool
        let supportsStreamingEvents: Bool
        let supportsStatefulChat: Bool
        let supportsNativeMCP: Bool
        let supportsModelManagement: Bool
        let supportsDownloads: Bool
        let supportsAuthToken: Bool
        let lastCapabilityError: String?
    }

    /// Hits `/api/v1/models` first for model-management metadata, then v0 for
    /// older builds, then OpenAI-compatible `/v1/models` as the last fallback.
    static func fetchModels(baseURL: URL, apiKey: String? = nil) async -> [LMStudioModel] {
        let nativeV1Root = nativeAPIRoot(from: baseURL, version: "v1")
        if let models = await tryNativeV1Models(nativeRoot: nativeV1Root, apiKey: apiKey), !models.isEmpty {
            return sortedModels(models)
        }
        let nativeV0Root = nativeAPIRoot(from: baseURL, version: "v0")
        if let models = await tryNativeV0Models(nativeRoot: nativeV0Root, apiKey: apiKey), !models.isEmpty {
            return sortedModels(models)
        }
        return sortedModels(await tryOpenAIModels(baseURL: baseURL, apiKey: apiKey))
    }

    static func fetchCapabilities(baseURL: URL, apiKey: String? = nil) async -> CapabilitySnapshot {
        let nativeV1Root = nativeAPIRoot(from: baseURL, version: "v1")
        var request = authorizedRequest(url: nativeV1Root.appendingPathComponent("models"), apiKey: apiKey)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return CapabilitySnapshot(
                    apiMode: "v1",
                    supportsV1: true,
                    supportsNativeChat: true,
                    supportsStreamingEvents: true,
                    supportsStatefulChat: true,
                    supportsNativeMCP: true,
                    supportsModelManagement: true,
                    supportsDownloads: true,
                    supportsAuthToken: apiKey?.isEmpty == false,
                    lastCapabilityError: nil
                )
            }
        } catch {
            let nativeV0Root = nativeAPIRoot(from: baseURL, version: "v0")
            var fallback = authorizedRequest(url: nativeV0Root.appendingPathComponent("models"), apiKey: apiKey)
            fallback.timeoutInterval = 2
            if let (_, response) = try? await URLSession.shared.data(for: fallback),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                return CapabilitySnapshot(
                    apiMode: "v0",
                    supportsV1: false,
                    supportsNativeChat: false,
                    supportsStreamingEvents: false,
                    supportsStatefulChat: false,
                    supportsNativeMCP: false,
                    supportsModelManagement: false,
                    supportsDownloads: false,
                    supportsAuthToken: apiKey?.isEmpty == false,
                    lastCapabilityError: error.localizedDescription
                )
            }
            return CapabilitySnapshot(
                apiMode: "openai",
                supportsV1: false,
                supportsNativeChat: false,
                supportsStreamingEvents: false,
                supportsStatefulChat: false,
                supportsNativeMCP: false,
                supportsModelManagement: false,
                supportsDownloads: false,
                supportsAuthToken: apiKey?.isEmpty == false,
                lastCapabilityError: error.localizedDescription
            )
        }
        return CapabilitySnapshot(
            apiMode: "openai",
            supportsV1: false,
            supportsNativeChat: false,
            supportsStreamingEvents: false,
            supportsStatefulChat: false,
            supportsNativeMCP: false,
            supportsModelManagement: false,
            supportsDownloads: false,
            supportsAuthToken: apiKey?.isEmpty == false,
            lastCapabilityError: "Native v1 metadata endpoint was not available."
        )
    }

    @discardableResult
    static func loadModel(
        baseURL: URL,
        model: String,
        contextLength: Int?,
        apiKey: String? = nil
    ) async throws -> String {
        var request = authorizedRequest(url: nativeAPIRoot(from: baseURL, version: "v1").appendingPathComponent("models/load"), apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = [
            "model": model,
            "echo_load_config": true,
            "flash_attention": true,
            "offload_kv_cache_to_gpu": true
        ]
        if let contextLength {
            body["context_length"] = max(4_096, contextLength)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoded = try JSONDecoder().decode(NativeLoadResponse.self, from: data)
        return decoded.instance_id
    }

    @discardableResult
    static func unloadModel(
        baseURL: URL,
        instanceID: String,
        apiKey: String? = nil
    ) async throws -> String {
        var request = authorizedRequest(url: nativeAPIRoot(from: baseURL, version: "v1").appendingPathComponent("models/unload"), apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["instance_id": instanceID])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoded = try JSONDecoder().decode(NativeUnloadResponse.self, from: data)
        return decoded.instance_id
    }

    static func downloadModel(
        baseURL: URL,
        model: String,
        quantization: String?,
        apiKey: String? = nil
    ) async throws -> DownloadStatus {
        var request = authorizedRequest(url: nativeAPIRoot(from: baseURL, version: "v1").appendingPathComponent("models/download"), apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = ["model": model]
        let trimmedQuantization = quantization?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedQuantization, !trimmedQuantization.isEmpty {
            body["quantization"] = trimmedQuantization
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(DownloadStatus.self, from: data)
    }

    static func downloadStatus(
        baseURL: URL,
        jobID: String,
        apiKey: String? = nil
    ) async throws -> DownloadStatus {
        let encodedJobID = jobID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobID
        var request = authorizedRequest(url: nativeAPIRoot(from: baseURL, version: "v1").appendingPathComponent("models/download/status/\(encodedJobID)"), apiKey: apiKey)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LLMError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(DownloadStatus.self, from: data)
    }

    private static func sortedModels(_ models: [LMStudioModel]) -> [LMStudioModel] {
        models.sorted { lhs, rhs in
            if lhs.loaded != rhs.loaded {
                return lhs.loaded && !rhs.loaded
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private static func tryNativeV1Models(nativeRoot: URL, apiKey: String?) async -> [LMStudioModel]? {
        var request = authorizedRequest(url: nativeRoot.appendingPathComponent("models"), apiKey: apiKey)
        request.timeoutInterval = 3
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(NativeV1ModelsResponse.self, from: data)
            return decoded.models.map { entry in
                let firstLoaded = entry.loaded_instances.first
                return LMStudioModel(
                    id: entry.key,
                    displayName: entry.display_name,
                    loaded: !entry.loaded_instances.isEmpty,
                    contextLength: firstLoaded?.config.context_length ?? entry.max_context_length,
                    maxContextLength: entry.max_context_length,
                    quantization: entry.quantization?.name,
                    architecture: entry.architecture,
                    trainedForToolUse: entry.capabilities?.trained_for_tool_use,
                    sizeBytes: entry.size_bytes,
                    format: entry.format,
                    publisher: entry.publisher,
                    loadedInstanceIDs: entry.loaded_instances.map(\.id),
                    apiMode: "v1"
                )
            }
        } catch {
            return nil
        }
    }

    private static func tryNativeV0Models(nativeRoot: URL, apiKey: String?) async -> [LMStudioModel]? {
        var request = authorizedRequest(url: nativeRoot.appendingPathComponent("models"), apiKey: apiKey)
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
                    displayName: nil,
                    loaded: (entry.state ?? "").lowercased() == "loaded",
                    contextLength: entry.max_context_length ?? entry.loaded_context_length,
                    maxContextLength: entry.max_context_length,
                    quantization: entry.quantization,
                    architecture: entry.arch,
                    trainedForToolUse: entry.trained_for_tool_use ?? entry.trainedForToolUse,
                    sizeBytes: nil,
                    format: nil,
                    publisher: nil,
                    loadedInstanceIDs: (entry.state ?? "").lowercased() == "loaded" ? [entry.id] : [],
                    apiMode: "v0"
                )
            }
        } catch {
            return nil
        }
    }

    private static func tryOpenAIModels(baseURL: URL, apiKey: String?) async -> [LMStudioModel] {
        var request = authorizedRequest(url: baseURL.appendingPathComponent("models"), apiKey: apiKey)
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
                    displayName: nil,
                    loaded: false,
                    contextLength: nil,
                    maxContextLength: nil,
                    quantization: nil,
                    architecture: nil,
                    trainedForToolUse: nil,
                    sizeBytes: nil,
                    format: nil,
                    publisher: nil,
                    loadedInstanceIDs: [],
                    apiMode: "openai"
                )
            }
        } catch {
            return []
        }
    }

    /// Strip a trailing `/v1` from the user-supplied base URL so native API
    /// roots sit at the same host. LM Studio exposes `/api/v1/...`,
    /// `/api/v0/...`, and `/v1/...` as siblings of the host root.
    private static func nativeAPIRoot(from baseURL: URL, version: String) -> URL {
        let path = baseURL.path
        if path.hasSuffix("/v1") {
            let trimmed = String(path.dropLast("/v1".count))
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.path = trimmed
            if let root = components?.url {
                return root.appendingPathComponent("api/\(version)")
            }
        }
        return baseURL.appendingPathComponent("api/\(version)")
    }

    private static func authorizedRequest(url: URL, apiKey: String?) -> URLRequest {
        var request = URLRequest(url: url)
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        } else {
            request.setValue("Bearer lm-studio", forHTTPHeaderField: "authorization")
        }
        return request
    }

    private static var nativeV1ChatEnabled: Bool {
        if UserDefaults.standard.object(forKey: "loom.lmstudio.nativeMode") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "loom.lmstudio.nativeMode")
    }

    private static var nativeStatefulChatsEnabled: Bool {
        if UserDefaults.standard.object(forKey: "loom.lmstudio.statefulSessions") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "loom.lmstudio.statefulSessions")
    }

    private func nativeChatFallbackReason(messages: [LLMMessage], tools: [LLMTool]) -> String? {
        if !Self.nativeV1ChatEnabled {
            return "Native v1 chat disabled in LM Studio settings."
        }
        if !tools.isEmpty {
            return "Native v1 chat does not accept Loom's custom tool schemas yet; using OpenAI-compatible tool calling."
        }
        if previousResponseID?.hasPrefix("resp_") == true {
            return nil
        }
        if messages.count > 1 {
            return "Native v1 chat cannot replay assistant history without a response id; using OpenAI-compatible history."
        }
        return nil
    }

    private func latestUserInput(from messages: [LLMMessage]) -> String {
        messages.last(where: { $0.role == .user })?.content
            ?? messages.last?.content
            ?? ""
    }

    private func runNativeV1Stream(
        messages: [LLMMessage],
        system: String?,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) async throws {
        var request = Self.authorizedRequest(url: Self.nativeAPIRoot(from: baseURL, version: "v1").appendingPathComponent("chat"), apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")

        let payload = NativeChatRequest(
            model: model,
            input: latestUserInput(from: messages),
            system_prompt: system?.isEmpty == false ? system : nil,
            stream: true,
            temperature: 0,
            context_length: nativeContextLength.map { max(4_096, $0) },
            store: Self.nativeStatefulChatsEnabled,
            previous_response_id: Self.nativeStatefulChatsEnabled && previousResponseID?.hasPrefix("resp_") == true ? previousResponseID : nil
        )
        request.httpBody = try JSONEncoder().encode(payload)

        continuation.yield(.providerNotice("LM Studio native v1 chat active."))
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await ensureLLMSuccess(response: response, bytes: bytes)

        var eventName: String?
        var dataLines: [String] = []

        func flushEvent() throws {
            guard !dataLines.isEmpty else {
                eventName = nil
                return
            }
            let payload = dataLines.joined(separator: "\n")
            try handleNativeEvent(name: eventName, payload: payload, continuation: continuation)
            eventName = nil
            dataLines.removeAll(keepingCapacity: true)
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty {
                try flushEvent()
                continue
            }
            if line.hasPrefix("event:") {
                eventName = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces))
            }
        }
        try flushEvent()
    }

    private func handleNativeEvent(
        name: String?,
        payload: String,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) throws {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let type = (object["type"] as? String) ?? name ?? ""
        switch type {
        case "chat.start":
            let detail = object["model_instance_id"] as? String
            continuation.yield(.providerProgress(LLMProviderProgress(
                phase: "native-chat",
                label: "Native chat started",
                detail: detail,
                progress: nil
            )))
        case "model_load.start":
            continuation.yield(.providerProgress(LLMProviderProgress(
                phase: "model-load",
                label: "Loading model",
                detail: object["model_instance_id"] as? String,
                progress: 0
            )))
        case "model_load.progress":
            continuation.yield(.providerProgress(LLMProviderProgress(
                phase: "model-load",
                label: "Loading model",
                detail: object["model_instance_id"] as? String,
                progress: object["progress"] as? Double
            )))
        case "model_load.end":
            let seconds = object["load_time_seconds"] as? Double
            continuation.yield(.providerProgress(LLMProviderProgress(
                phase: "model-load",
                label: "Model loaded",
                detail: seconds.map { String(format: "%.1fs", $0) },
                progress: 1
            )))
        case "prompt_processing.start":
            continuation.yield(.providerProgress(LLMProviderProgress(
                phase: "prompt-processing",
                label: "Processing prompt",
                detail: nil,
                progress: 0
            )))
        case "prompt_processing.progress":
            continuation.yield(.providerProgress(LLMProviderProgress(
                phase: "prompt-processing",
                label: "Processing prompt",
                detail: nil,
                progress: object["progress"] as? Double
            )))
        case "prompt_processing.end":
            continuation.yield(.providerProgress(LLMProviderProgress(
                phase: "prompt-processing",
                label: "Prompt processed",
                detail: nil,
                progress: 1
            )))
        case "reasoning.start":
            continuation.yield(.providerProgress(LLMProviderProgress(
                phase: "reasoning",
                label: "Reasoning",
                detail: nil,
                progress: nil
            )))
        case "reasoning.delta":
            if let content = object["content"] as? String, !content.isEmpty {
                continuation.yield(.reasoningDelta(content))
            }
        case "message.delta":
            if let content = object["content"] as? String, !content.isEmpty {
                continuation.yield(.textDelta(content))
            }
        case "tool_call.start", "tool_call.arguments", "tool_call.success":
            let toolName = object["tool"] as? String ?? "tool"
            continuation.yield(.providerProgress(LLMProviderProgress(
                phase: "native-tool",
                label: toolName,
                detail: type.replacingOccurrences(of: "tool_call.", with: ""),
                progress: nil
            )))
        case "tool_call.failure":
            let reason = object["reason"] as? String ?? "Native tool call failed."
            continuation.yield(.providerNotice(reason))
        case "error":
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                continuation.yield(.providerNotice("LM Studio native event error: \(message)"))
            }
        case "chat.end":
            if let result = object["result"] as? [String: Any] {
                if let stats = result["stats"] as? [String: Any] {
                    continuation.yield(.usage(LLMProviderUsageStats(
                        inputTokens: stats["input_tokens"] as? Int,
                        outputTokens: stats["total_output_tokens"] as? Int,
                        reasoningTokens: stats["reasoning_output_tokens"] as? Int,
                        tokensPerSecond: stats["tokens_per_second"] as? Double,
                        timeToFirstTokenSeconds: stats["time_to_first_token_seconds"] as? Double,
                        modelLoadTimeSeconds: stats["model_load_time_seconds"] as? Double,
                        responseID: result["response_id"] as? String
                    )))
                } else if let responseID = result["response_id"] as? String {
                    continuation.yield(.usage(LLMProviderUsageStats(
                        inputTokens: nil,
                        outputTokens: nil,
                        reasoningTokens: nil,
                        tokensPerSecond: nil,
                        timeToFirstTokenSeconds: nil,
                        modelLoadTimeSeconds: nil,
                        responseID: responseID
                    )))
                }
            }
        default:
            break
        }
    }

    // MARK: - Streaming

    private func runStream(
        messages: [LLMMessage],
        system: String?,
        tools: [LLMTool],
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) async throws {
        if let reason = nativeChatFallbackReason(messages: messages, tools: tools) {
            if Self.nativeV1ChatEnabled {
                continuation.yield(.providerNotice(reason))
            }
        } else {
            do {
                try await runNativeV1Stream(messages: messages, system: system, continuation: continuation)
                return
            } catch {
                continuation.yield(.providerNotice("LM Studio native v1 chat failed; falling back to OpenAI-compatible chat."))
            }
        }

        var request = Self.authorizedRequest(url: baseURL.appendingPathComponent("chat/completions"), apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")

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

        let payload = RequestBody(
            model: model,
            stream: true,
            messages: msgs,
            tools: toolDefs,
            tool_choice: toolDefs == nil ? nil : "auto"
        )
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
        let tool_choice: String?
        let response_format: ResponseFormat?
        let max_tokens: Int?
        let temperature: Double?

        init(
            model: String,
            stream: Bool,
            messages: [Msg],
            tools: [ToolDef]? = nil,
            tool_choice: String? = nil,
            response_format: ResponseFormat? = nil,
            max_tokens: Int? = nil,
            temperature: Double? = nil
        ) {
            self.model = model
            self.stream = stream
            self.messages = messages
            self.tools = tools
            self.tool_choice = tool_choice
            self.response_format = response_format
            self.max_tokens = max_tokens
            self.temperature = temperature
        }
    }

    private struct NativeChatRequest: Encodable {
        let model: String
        let input: String
        let system_prompt: String?
        let stream: Bool
        let temperature: Double?
        let context_length: Int?
        let store: Bool
        let previous_response_id: String?
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

    private struct ResponseFormat: Encodable {
        let type: String
        let json_schema: ResponseJSONSchema
    }

    private struct ResponseJSONSchema: Encodable {
        let name: String
        let strict: Bool
        let schema: AnyEncodable
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
        let trained_for_tool_use: Bool?
        let trainedForToolUse: Bool?
    }

    private struct OpenAIModelsResponse: Decodable {
        let data: [OpenAIModelEntry]
    }

    private struct OpenAIModelEntry: Decodable {
        let id: String
    }

    private struct NonStreamingResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String?
        }
    }
}
    struct DownloadStatus: Decodable, Hashable, Sendable {
        let job_id: String?
        let status: String
        let total_size_bytes: Int64?
        let downloaded_bytes: Int64?
        let bytes_per_second: Int64?
        let started_at: String?
        let completed_at: String?
        let estimated_completion: String?
    }

    private struct NativeLoadResponse: Decodable {
        let instance_id: String
    }

    private struct NativeUnloadResponse: Decodable {
        let instance_id: String
    }

    private struct NativeV1ModelsResponse: Decodable {
        let models: [NativeV1ModelEntry]
    }

    private struct NativeV1ModelEntry: Decodable {
        let type: String?
        let publisher: String?
        let key: String
        let display_name: String?
        let architecture: String?
        let quantization: Quantization?
        let size_bytes: Int64?
        let params_string: String?
        let loaded_instances: [LoadedInstance]
        let max_context_length: Int?
        let format: String?
        let capabilities: Capabilities?

        struct Quantization: Decodable {
            let name: String?
            let bits_per_weight: Double?
        }

        struct LoadedInstance: Decodable {
            let id: String
            let config: LoadedConfig
        }

        struct LoadedConfig: Decodable {
            let context_length: Int?
        }

        struct Capabilities: Decodable {
            let vision: Bool?
            let trained_for_tool_use: Bool?
        }
    }
