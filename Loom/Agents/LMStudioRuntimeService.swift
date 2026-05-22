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
        var schemaSupported: Bool?

        var detail: String {
            var bits: [String] = []
            if loaded { bits.append("loaded") }
            if let contextLength { bits.append("\(contextLength / 1000)k ctx") }
            if let quantization, !quantization.isEmpty { bits.append(quantization) }
            if let architecture, !architecture.isEmpty { bits.append(architecture) }
            if trainedForToolUse == true { bits.append("tools") }
            if let schemaSupported { bits.append(schemaSupported ? "schema" : "no schema") }
            if let format, !format.isEmpty { bits.append(format) }
            if let sizeBytes, sizeBytes > 0 { bits.append(Self.formatBytes(sizeBytes)) }
            return bits.joined(separator: " · ")
        }

        var title: String {
            displayName?.isEmpty == false ? "\(displayName!) · \(id)" : id
        }

        var unloadTarget: String {
            loadedInstanceIDs.first ?? id
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

    struct DownloadSnapshot: Hashable, Sendable {
        let jobID: String?
        let status: String
        let totalSizeBytes: Int64?
        let downloadedBytes: Int64?

        var progressText: String {
            if let totalSizeBytes, let downloadedBytes, totalSizeBytes > 0 {
                let pct = (Double(downloadedBytes) / Double(totalSizeBytes)) * 100
                return "\(status) · \(Int(pct.rounded()))%"
            }
            return status
        }
    }

    private(set) var serverState: ServerState = .unknown
    private(set) var models: [ModelSnapshot] = []
    private(set) var selectedModelID: String?
    private(set) var preparedModelID: String?
    private(set) var apiMode: String = "unknown"
    private(set) var supportsV1: Bool = false
    private(set) var supportsModelManagement: Bool = false
    private(set) var supportsDownloads: Bool = false
    private(set) var supportsAuthToken: Bool = false
    private(set) var lastCapabilityError: String?
    private(set) var lastDownload: DownloadSnapshot?
    private(set) var lastError: String?
    private(set) var isRefreshing: Bool = false
    private(set) var isPreparing: Bool = false
    private(set) var isManagingModel: Bool = false

    var loadedModels: [ModelSnapshot] {
        models.filter(\.loaded)
    }

    var recommendedModel: ModelSnapshot? {
        chooseModel(preferredModel: selectedModelID)
    }

    func refresh(baseURL: URL?, selectedModel: String?, apiKey: String? = nil) async {
        selectedModelID = selectedModel
        guard let baseURL else {
            serverState = .unknown
            models = []
            apiMode = "unknown"
            supportsV1 = false
            supportsModelManagement = false
            supportsDownloads = false
            lastCapabilityError = nil
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        async let cliInstalled = isLMSInstalled()
        async let serverUp = LMStudioProvider.serverIsUp(baseURL: baseURL, apiKey: apiKey)
        let installed = await cliInstalled
        let reachable = await serverUp

        if reachable {
            serverState = .running
            let capabilities = await LMStudioProvider.fetchCapabilities(baseURL: baseURL, apiKey: apiKey)
            apiMode = capabilities.apiMode
            supportsV1 = capabilities.supportsV1
            supportsModelManagement = capabilities.supportsModelManagement
            supportsDownloads = capabilities.supportsDownloads
            supportsAuthToken = capabilities.supportsAuthToken
            lastCapabilityError = capabilities.lastCapabilityError
            let fetched = await LMStudioProvider.fetchModels(baseURL: baseURL, apiKey: apiKey)
            var snapshots = fetched.map { model in
                ModelSnapshot(
                    id: model.id,
                    displayName: model.displayName,
                    loaded: model.loaded,
                    contextLength: model.contextLength,
                    maxContextLength: model.maxContextLength,
                    quantization: model.quantization,
                    architecture: model.architecture,
                    trainedForToolUse: model.trainedForToolUse,
                    sizeBytes: model.sizeBytes,
                    format: model.format,
                    publisher: model.publisher,
                    loadedInstanceIDs: model.loadedInstanceIDs,
                    apiMode: model.apiMode,
                    schemaSupported: nil
                )
            }
            if let probeID = selectedModel ?? snapshots.first(where: \.loaded)?.id ?? snapshots.first?.id,
               let index = snapshots.firstIndex(where: { $0.id == probeID }) {
                let supported = await LMStudioProvider.supportsJSONSchemaResponseFormat(baseURL: baseURL, model: probeID, apiKey: apiKey)
                snapshots[index].schemaSupported = supported
            }
            models = snapshots
        } else {
            serverState = installed ? .stopped : .missingCLI
            models = []
            apiMode = installed ? "offline" : "missing-cli"
            supportsV1 = false
            supportsModelManagement = false
            supportsDownloads = false
            supportsAuthToken = apiKey?.isEmpty == false
        }
    }

    @discardableResult
    func prepareForAgentWork(
        baseURL: URL?,
        preferredModel: String?,
        contextTarget: Int,
        autoScale: Bool,
        apiKey: String? = nil
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

        if !(await LMStudioProvider.serverIsUp(baseURL: baseURL, apiKey: apiKey)) {
            do {
                _ = try await runShell("lms daemon up")
                if !(await waitForServer(baseURL: baseURL, apiKey: apiKey, timeout: 10)) {
                    lastError = "LM Studio daemon started, but the local server did not become reachable."
                    await refresh(baseURL: baseURL, selectedModel: preferredModel, apiKey: apiKey)
                    return nil
                }
            } catch {
                lastError = "Could not start LM Studio daemon: \(error.localizedDescription)"
                await refresh(baseURL: baseURL, selectedModel: preferredModel, apiKey: apiKey)
                return nil
            }
        }

        await refresh(baseURL: baseURL, selectedModel: preferredModel, apiKey: apiKey)
        let target = chooseModel(preferredModel: preferredModel)
        guard let target else {
            lastError = "No local LM Studio models were found."
            return nil
        }

        let context = max(4_096, contextTarget)

        do {
            if supportsModelManagement {
                if autoScale, target.loaded {
                    _ = try? await LMStudioProvider.unloadModel(baseURL: baseURL, instanceID: target.unloadTarget, apiKey: apiKey)
                }
                _ = try await LMStudioProvider.loadModel(
                    baseURL: baseURL,
                    model: target.id,
                    contextLength: autoScale ? context : nil,
                    apiKey: apiKey
                )
            } else {
                let escaped = shellEscape(target.id)
                let command = autoScale
                    ? "lms unload \(escaped) >/dev/null 2>&1 || true; lms load \(escaped) -y -c \(context) --parallel 1 --gpu max"
                    : "lms load \(escaped) -y"
                _ = try await runShell(command)
            }
            preparedModelID = target.id
            await refresh(baseURL: baseURL, selectedModel: target.id, apiKey: apiKey)
            return target.id
        } catch {
            lastError = "Could not load \(target.id): \(error.localizedDescription)"
            await refresh(baseURL: baseURL, selectedModel: preferredModel, apiKey: apiKey)
            return nil
        }
    }

    func loadModel(baseURL: URL?, modelID: String, contextTarget: Int, apiKey: String? = nil) async {
        guard let baseURL else { return }
        isManagingModel = true
        defer { isManagingModel = false }
        lastError = nil
        do {
            if supportsModelManagement {
                _ = try await LMStudioProvider.loadModel(
                    baseURL: baseURL,
                    model: modelID,
                    contextLength: contextTarget,
                    apiKey: apiKey
                )
            } else {
                await loadWithCLI(modelID, contextLength: contextTarget)
            }
            await refresh(baseURL: baseURL, selectedModel: modelID, apiKey: apiKey)
        } catch {
            lastError = "Could not load \(modelID): \(error.localizedDescription)"
        }
    }

    func unloadModel(baseURL: URL?, modelID: String, instanceID: String?, apiKey: String? = nil) async {
        guard let baseURL else { return }
        isManagingModel = true
        defer { isManagingModel = false }
        lastError = nil
        do {
            if supportsModelManagement {
                _ = try await LMStudioProvider.unloadModel(
                    baseURL: baseURL,
                    instanceID: instanceID ?? modelID,
                    apiKey: apiKey
                )
            } else {
                _ = try await runShell("lms unload \(shellEscape(modelID))")
            }
            await refresh(baseURL: baseURL, selectedModel: selectedModelID, apiKey: apiKey)
        } catch {
            lastError = "Could not unload \(modelID): \(error.localizedDescription)"
        }
    }

    func downloadModel(baseURL: URL?, model: String, quantization: String?, apiKey: String? = nil) async {
        guard let baseURL else { return }
        isManagingModel = true
        defer { isManagingModel = false }
        lastError = nil
        do {
            let status = try await LMStudioProvider.downloadModel(
                baseURL: baseURL,
                model: model,
                quantization: quantization,
                apiKey: apiKey
            )
            lastDownload = DownloadSnapshot(
                jobID: status.job_id,
                status: status.status,
                totalSizeBytes: status.total_size_bytes,
                downloadedBytes: status.downloaded_bytes
            )
            await refresh(baseURL: baseURL, selectedModel: selectedModelID, apiKey: apiKey)
        } catch {
            lastError = "Could not start download: \(error.localizedDescription)"
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

    private func waitForServer(baseURL: URL, apiKey: String?, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await LMStudioProvider.serverIsUp(baseURL: baseURL, apiKey: apiKey) {
                return true
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        return await LMStudioProvider.serverIsUp(baseURL: baseURL, apiKey: apiKey)
    }

    private func loadWithCLI(_ identifier: String, contextLength: Int) async {
        let escaped = shellEscape(identifier)
        _ = try? await runShell("lms load \(escaped) -y -c \(max(4096, contextLength))")
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
