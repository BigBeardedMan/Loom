import Foundation

/// User-configured local LLM endpoint reachable over HTTP on localhost or the
/// LAN. Two shapes are supported today: native Ollama and any OpenAI-compatible
/// chat-completions server (LM Studio, llama.cpp's `llama-server`, Jan, vLLM,
/// LocalAI). Auth tokens, when needed, live in Keychain — `LocalEndpoint`
/// itself only stores `requiresAuth` so the UI knows to render the field.
struct LocalEndpoint: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
        case ollama
        case openAICompatible

        var id: String { rawValue }

        var label: String {
            switch self {
            case .ollama:           return "Ollama"
            case .openAICompatible: return "OpenAI-compatible"
            }
        }

        var defaultBaseURL: String {
            switch self {
            case .ollama:           return "http://localhost:11434"
            case .openAICompatible: return "http://localhost:1234/v1"
            }
        }

        var modelHint: String {
            switch self {
            case .ollama:           return "auto-discovered via /api/tags"
            case .openAICompatible: return "set the model id used in chat requests"
            }
        }
    }

    let id: UUID
    var displayName: String
    var kind: Kind
    var baseURL: String
    /// For OpenAI-compatible: the model id sent in the request body. For Ollama:
    /// optional fallback when /api/tags fails — empty string means "auto only".
    var defaultModel: String
    var requiresAuth: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        kind: Kind,
        baseURL: String,
        defaultModel: String = "",
        requiresAuth: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.requiresAuth = requiresAuth
    }

    /// Resolved URL with trailing slash trimmed. Returns nil if `baseURL` is
    /// not a valid URL or fails the safety filter (`isAllowedURL`). The UI
    /// surfaces this on save/test so the user knows when an endpoint is
    /// rejected outright vs. unreachable.
    var resolvedBaseURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let stripped = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let url = URL(string: stripped) else { return nil }
        guard Self.isAllowedURL(url) else { return nil }
        return url
    }

    /// Conservative allow-list. The endpoint UI is intended for *local* LLM
    /// servers (Ollama, LM Studio, llama.cpp, Jan, vLLM) reachable on
    /// loopback or the user's LAN. We refuse:
    ///   - non-http(s) schemes (file://, ftp://, etc. — `file://` would let
    ///     a poorly-validated request body double as a local file read);
    ///   - cloud-metadata IPs (169.254.169.254, fd00:ec2::254) that have
    ///     no business in a developer-tool config;
    ///   - empty hosts.
    static func isAllowedURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        let blocked: Set<String> = [
            "169.254.169.254",         // AWS / GCP / Azure IMDS
            "metadata.google.internal",
            "metadata",
            "fd00:ec2::254"
        ]
        if blocked.contains(host) { return false }
        return true
    }

    /// Keychain account name for this endpoint's auth token.
    var keychainAccount: String { "local_endpoint_\(id.uuidString)" }
}
