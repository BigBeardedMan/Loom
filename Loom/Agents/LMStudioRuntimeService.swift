import Foundation
import Observation

@Observable
@MainActor
final class LMStudioRuntimeService {
    enum ServerState: Equatable, Sendable {
        case unknown
        case missingCLI
        case stopped
        case running

        var label: String {
            switch self {
            case .unknown:    return "Checking"
            case .missingCLI: return "lms missing"
            case .stopped:    return "Stopped"
            case .running:    return "Running"
            }
        }
    }

    struct ModelSnapshot: Identifiable, Hashable, Sendable {
        let id: String
        let loaded: Bool
        let contextLength: Int?
        let quantization: String?
        let architecture: String?
        let trainedForToolUse: Bool?
        var schemaSupported: Bool?

        var detail: String {
            var bits: [String] = []
            if loaded { bits.append("loaded") }
            if let contextLength { bits.append("\(contextLength / 1000)k ctx") }
            if let quantization, !quantization.isEmpty { bits.append(quantization) }
            if let architecture, !architecture.isEmpty { bits.append(architecture) }
            if trainedForToolUse == true { bits.append("tools") }
            if let schemaSupported { bits.append(schemaSupported ? "schema" : "no schema") }
            return bits.joined(separator: " · ")
        }
    }

    private(set) var serverState: ServerState = .unknown
    private(set) var models: [ModelSnapshot] = []
    private(set) var selectedModelID: String?
    private(set) var preparedModelID: String?
    private(set) var lastError: String?
    private(set) var isRefreshing: Bool = false
    private(set) var isPreparing: Bool = false

    var loadedModels: [ModelSnapshot] {
        models.filter(\.loaded)
    }

    var recommendedModel: ModelSnapshot? {
        chooseModel(preferredModel: selectedModelID)
    }

    func refresh(baseURL: URL?, selectedModel: String?) async {
        selectedModelID = selectedModel
        guard let baseURL else {
            serverState = .unknown
            models = []
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        async let cliInstalled = isLMSInstalled()
        async let serverUp = LMStudioProvider.serverIsUp(baseURL: baseURL)
        let installed = await cliInstalled
        let reachable = await serverUp

        if reachable {
            serverState = .running
            let fetched = await LMStudioProvider.fetchModels(baseURL: baseURL)
            var snapshots = fetched.map { model in
                ModelSnapshot(
                    id: model.id,
                    loaded: model.loaded,
                    contextLength: model.contextLength,
                    quantization: model.quantization,
                    architecture: model.architecture,
                    trainedForToolUse: model.trainedForToolUse,
                    schemaSupported: nil
                )
            }
            if let probeID = selectedModel ?? snapshots.first(where: \.loaded)?.id ?? snapshots.first?.id,
               let index = snapshots.firstIndex(where: { $0.id == probeID }) {
                let supported = await LMStudioProvider.supportsJSONSchemaResponseFormat(baseURL: baseURL, model: probeID)
                snapshots[index].schemaSupported = supported
            }
            models = snapshots
        } else {
            serverState = installed ? .stopped : .missingCLI
            models = []
        }
    }

    @discardableResult
    func prepareForAgentWork(
        baseURL: URL?,
        preferredModel: String?,
        contextTarget: Int,
        autoScale: Bool
    ) async -> String? {
        guard let baseURL else {
            lastError = "No LM Studio endpoint is configured."
            return nil
        }
        guard await isLMSInstalled() else {
            serverState = .missingCLI
            lastError = "`lms` CLI not found on PATH."
            return nil
        }

        isPreparing = true
        defer { isPreparing = false }
        lastError = nil

        if !(await LMStudioProvider.serverIsUp(baseURL: baseURL)) {
            do {
                _ = try await runShell("lms daemon up")
                if !(await waitForServer(baseURL: baseURL, timeout: 10)) {
                    lastError = "LM Studio daemon started, but the local server did not become reachable."
                    await refresh(baseURL: baseURL, selectedModel: preferredModel)
                    return nil
                }
            } catch {
                lastError = "Could not start LM Studio daemon: \(error.localizedDescription)"
                await refresh(baseURL: baseURL, selectedModel: preferredModel)
                return nil
            }
        }

        await refresh(baseURL: baseURL, selectedModel: preferredModel)
        let target = chooseModel(preferredModel: preferredModel)
        guard let target else {
            lastError = "No local LM Studio models were found."
            return nil
        }

        let escaped = shellEscape(target.id)
        let context = max(4_096, contextTarget)
        let command: String
        if autoScale {
            command = "lms unload \(escaped) >/dev/null 2>&1 || true; lms load \(escaped) -y -c \(context) --parallel 1 --gpu max"
        } else {
            command = "lms load \(escaped) -y"
        }

        do {
            _ = try await runShell(command)
            preparedModelID = target.id
            await refresh(baseURL: baseURL, selectedModel: target.id)
            return target.id
        } catch {
            lastError = "Could not load \(target.id): \(error.localizedDescription)"
            await refresh(baseURL: baseURL, selectedModel: preferredModel)
            return nil
        }
    }

    private func chooseModel(preferredModel: String?) -> ModelSnapshot? {
        if let preferredModel,
           let exact = models.first(where: { $0.id == preferredModel }) {
            return exact
        }
        return models.sorted { lhs, rhs in
            if lhs.loaded != rhs.loaded { return lhs.loaded && !rhs.loaded }
            let leftTool = lhs.trainedForToolUse == true
            let rightTool = rhs.trainedForToolUse == true
            if leftTool != rightTool { return leftTool && !rightTool }
            let leftCoder = isCoderModel(lhs.id) || isCoderModel(lhs.architecture ?? "")
            let rightCoder = isCoderModel(rhs.id) || isCoderModel(rhs.architecture ?? "")
            if leftCoder != rightCoder { return leftCoder && !rightCoder }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }.first
    }

    private func isCoderModel(_ value: String) -> Bool {
        let lower = value.lowercased()
        return ["qwen", "deepseek", "codestral", "coder", "code", "gpt-oss"].contains {
            lower.contains($0)
        }
    }

    private func isLMSInstalled() async -> Bool {
        let out = (try? await runShell("command -v lms >/dev/null 2>&1 && echo yes || echo no")) ?? "no"
        return out.trimmingCharacters(in: .whitespacesAndNewlines) == "yes"
    }

    private func waitForServer(baseURL: URL, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await LMStudioProvider.serverIsUp(baseURL: baseURL) {
                return true
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        return await LMStudioProvider.serverIsUp(baseURL: baseURL)
    }

    private func runShell(_ command: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lic", command]
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            try process.run()
            process.waitUntilExit()
            let output = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if process.terminationStatus == 0 {
                return output
            }
            let error = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw RuntimeError.shell(error.isEmpty ? output : error)
        }.value
    }

    private func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private enum RuntimeError: Error, LocalizedError {
        case shell(String)

        var errorDescription: String? {
            switch self {
            case .shell(let message):
                return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
