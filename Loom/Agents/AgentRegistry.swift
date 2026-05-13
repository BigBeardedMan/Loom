import Foundation
import Observation

struct AgentDescriptor: Identifiable, Hashable {
    enum Vendor: String, Hashable {
        case claude
        case codex
        case gemini
        case ollama
        case openAICompatible
        case lmstudio

        var label: String {
            switch self {
            case .claude:           return "Claude Code"
            case .codex:            return "Codex"
            case .gemini:           return "Gemini"
            case .ollama:           return "Ollama"
            case .openAICompatible: return "Local"
            case .lmstudio:         return "LM Studio"
            }
        }

        var isLocalHTTP: Bool {
            switch self {
            case .ollama, .openAICompatible, .lmstudio: return true
            default:                                    return false
            }
        }
    }

    /// Unique id used in the Picker selection. Composite "<vendor>:<agent>" so
    /// adding another vendor doesn't collide with Claude's namespacing.
    let id: String
    /// CLI agent name passed via `--agent`. Empty means "vendor default".
    let cliName: String
    let displayName: String
    let vendor: Vendor
    let model: String?
    let group: String?    // "Plugin" / "Built-in" / endpoint name / nil
    /// For local-HTTP descriptors, the `LocalEndpoint.id` this descriptor
    /// targets. AgentPaneView uses this to look up the endpoint when building
    /// a provider.
    let endpointID: UUID?

    init(
        id: String,
        cliName: String,
        displayName: String,
        vendor: Vendor,
        model: String?,
        group: String?,
        endpointID: UUID? = nil
    ) {
        self.id = id
        self.cliName = cliName
        self.displayName = displayName
        self.vendor = vendor
        self.model = model
        self.group = group
        self.endpointID = endpointID
    }

    static let claudeDefault = AgentDescriptor(
        id: "claude:default",
        cliName: "",
        displayName: "Default",
        vendor: .claude,
        model: nil,
        group: nil
    )

    static let codexDefault = AgentDescriptor(
        id: "codex:default",
        cliName: "",
        displayName: "Default",
        vendor: .codex,
        model: nil,
        group: nil
    )

    static let geminiDefault = AgentDescriptor(
        id: "gemini:default",
        cliName: "",
        displayName: "Default",
        vendor: .gemini,
        model: nil,
        group: nil
    )
}

/// Pulls live agent lists from each installed CLI vendor and surfaces the
/// user's configured local LLM endpoints. Today: Claude Code via
/// `claude agents list`, plus Ollama (one descriptor per pulled model) and
/// OpenAI-compatible (one descriptor per endpoint, using its configured
/// default model).
@Observable
@MainActor
final class AgentRegistry {
    private static let selectedAgentDefaultsKey = "loom.agents.selectedID"

    var agents: [AgentDescriptor] = [.claudeDefault]
    var isRefreshing: Bool = false
    var lastRefreshError: String?

    /// Persisted selection. Lives on the registry (not on AgentPaneView) so the
    /// choice survives pane recreation and is shared across every Agent pane in
    /// the workspace. Any write hits UserDefaults immediately so a crash
    /// between turns doesn't lose the user's choice.
    var selectedAgentID: String {
        didSet {
            guard oldValue != selectedAgentID else { return }
            UserDefaults.standard.set(selectedAgentID, forKey: Self.selectedAgentDefaultsKey)
        }
    }

    /// Resolved descriptor for the persisted id. Falls back to the first known
    /// agent (or the Claude default) when the persisted id is no longer in the
    /// registry — e.g. the user uninstalled a CLI plugin between launches.
    var selectedAgent: AgentDescriptor {
        agents.first { $0.id == selectedAgentID }
            ?? agents.first
            ?? .claudeDefault
    }

    init() {
        self.selectedAgentID = UserDefaults.standard.string(forKey: Self.selectedAgentDefaultsKey)
            ?? AgentDescriptor.claudeDefault.id
    }

    func refresh(localEndpoints: [LocalEndpoint] = []) async {
        isRefreshing = true
        defer { isRefreshing = false }
        var collected: [AgentDescriptor] = []
        var firstError: String?

        // Claude: include the default whenever the CLI is on PATH, then try to
        // enumerate subagents via `claude agents list`. If the binary is
        // missing we still want to fall through to Codex/Gemini below.
        let hasClaude = await isCLIInstalled("claude")
        if hasClaude {
            collected.append(.claudeDefault)
            do {
                let claudeAgents = try await fetchClaudeAgents()
                collected.append(contentsOf: claudeAgents)
            } catch {
                firstError = error.localizedDescription
            }
        }

        // Codex / Gemini: each surfaces a single default entry — their CLIs
        // don't expose an "agents list" equivalent, so there's no subagent
        // hierarchy to enumerate. Each turn is stateless (no session resume).
        if await isCLIInstalled("codex") {
            collected.append(.codexDefault)
        }
        if await isCLIInstalled("gemini") {
            collected.append(.geminiDefault)
        }

        // Last-resort fallback: nothing detected. Keep the Claude default so
        // the picker isn't empty — sending will surface a clear error if the
        // user follows through and `claude` really isn't installed.
        if collected.isEmpty {
            collected.append(.claudeDefault)
        }

        for endpoint in localEndpoints {
            let descriptors = await descriptors(for: endpoint)
            collected.append(contentsOf: descriptors)
        }

        agents = collected
        lastRefreshError = firstError

        // Persisted id may point to a now-uninstalled agent (CLI removed,
        // endpoint deleted, plugin uninstalled). Snap to the first available
        // entry so the picker reflects what's actually selectable.
        if !collected.contains(where: { $0.id == selectedAgentID }),
           let first = collected.first {
            selectedAgentID = first.id
        }
    }

    /// True when `tool` resolves on the user's interactive PATH. Uses the
    /// login-shell PATH (same probe as the provider) so a Homebrew install at
    /// /opt/homebrew/bin is found even though Loom itself isn't launched from
    /// a shell.
    private func isCLIInstalled(_ tool: String) async -> Bool {
        let output = (try? await runShell("command -v \(tool) >/dev/null 2>&1 && echo yes || echo no")) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "yes"
    }

    // MARK: - Local endpoints

    private func descriptors(for endpoint: LocalEndpoint) async -> [AgentDescriptor] {
        guard let url = endpoint.resolvedBaseURL else { return [] }
        let group = "Local · \(endpoint.displayName)"

        switch endpoint.kind {
        case .ollama:
            let models = await OllamaProvider.fetchModels(baseURL: url)
            if !models.isEmpty {
                return models.map { model in
                    AgentDescriptor(
                        id: "ollama:\(endpoint.id.uuidString):\(model)",
                        cliName: "",
                        displayName: model,
                        vendor: .ollama,
                        model: model,
                        group: group,
                        endpointID: endpoint.id
                    )
                }
            }
            // /api/tags failed or returned nothing — fall back to defaultModel
            // if the user supplied one, so the endpoint isn't invisible.
            let fallback = endpoint.defaultModel.trimmingCharacters(in: .whitespaces)
            guard !fallback.isEmpty else { return [] }
            return [AgentDescriptor(
                id: "ollama:\(endpoint.id.uuidString):\(fallback)",
                cliName: "",
                displayName: fallback,
                vendor: .ollama,
                model: fallback,
                group: group,
                endpointID: endpoint.id
            )]

        case .openAICompatible:
            let model = endpoint.defaultModel.trimmingCharacters(in: .whitespaces)
            guard !model.isEmpty else { return [] }
            return [AgentDescriptor(
                id: "openai-compat:\(endpoint.id.uuidString):\(model)",
                cliName: "",
                displayName: model,
                vendor: .openAICompatible,
                model: model,
                group: group,
                endpointID: endpoint.id
            )]

        case .lmstudio:
            let models = await LMStudioProvider.fetchModels(baseURL: url)
            if !models.isEmpty {
                return models.map { entry in
                    AgentDescriptor(
                        id: "lmstudio:\(endpoint.id.uuidString):\(entry.id)",
                        cliName: "",
                        displayName: entry.displayLabel,
                        vendor: .lmstudio,
                        model: entry.id,
                        group: group,
                        endpointID: endpoint.id
                    )
                }
            }
            // Server down or no models loaded yet. Surface the configured
            // default model so the endpoint still appears in the picker, the
            // same fallback shape Ollama uses above.
            let fallback = endpoint.defaultModel.trimmingCharacters(in: .whitespaces)
            guard !fallback.isEmpty else { return [] }
            return [AgentDescriptor(
                id: "lmstudio:\(endpoint.id.uuidString):\(fallback)",
                cliName: "",
                displayName: fallback,
                vendor: .lmstudio,
                model: fallback,
                group: group,
                endpointID: endpoint.id
            )]
        }
    }

    // MARK: - Claude

    private func fetchClaudeAgents() async throws -> [AgentDescriptor] {
        // Read stdout only — merging stderr into the parsed output (the
        // previous `2>&1`) let zsh startup warnings or `claude` diagnostics
        // get parsed as agent names whenever they happened to begin with
        // whitespace.
        let output = try await runShell("claude agents list")
        return Self.parseClaudeAgentsList(output)
    }

    /// Parses the textual layout of `claude agents list`:
    ///
    ///     N active agents
    ///
    ///     Plugin agents:
    ///       feature-dev:code-architect · sonnet
    ///
    ///     Built-in agents:
    ///       Explore · haiku
    ///
    /// `nonisolated` so we can unit-test it independently.
    nonisolated static func parseClaudeAgentsList(_ output: String) -> [AgentDescriptor] {
        var current: String?
        var results: [AgentDescriptor] = []
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasSuffix(" agents:") {
                current = String(trimmed.dropLast(" agents:".count))
                continue
            }
            // Only count rows that start with whitespace — skip headers like
            // "10 active agents".
            guard line.first == " " || line.first == "\t" else { continue }
            // Format: "<name> · <model>" or just "<name>".
            let parts = trimmed.components(separatedBy: " · ")
            let name = parts[0]
            let model = parts.count > 1 ? parts[1] : nil
            results.append(AgentDescriptor(
                id: "claude:\(name)",
                cliName: name,
                displayName: name,
                vendor: .claude,
                model: model,
                group: current
            ))
        }
        return results
    }

    // MARK: - Shell helper

    private func runShell(_ command: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lic", command]
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
