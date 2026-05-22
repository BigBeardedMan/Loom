import Foundation
import Observation

/// Async wrapper around the `lms` CLI shipped with LM Studio. We probe via the
/// user's interactive login shell (same trick `AgentRegistry` uses for
/// claude/codex/gemini) so a Homebrew install at `/opt/homebrew/bin` is found
/// even though Loom itself isn't launched from a shell.
///
/// Only used for *server lifecycle* and *model installation status*. Inference
/// always goes through `LMStudioProvider` over HTTP — we never shell out for
/// chat completions.
@Observable
@MainActor
final class LMStudioCLI {
    enum ServerStatus: Equatable {
        case unknown
        case stopped
        case running(port: Int)
        case lmsMissing
    }

    private(set) var status: ServerStatus = .unknown
    private(set) var installedModels: [String] = []
    private(set) var loadedModels: [String] = []
    private(set) var lastError: String?

    /// Refresh `status`, `installedModels`, and `loadedModels` in one shot.
    /// Safe to call repeatedly — each subprocess is tiny.
    func refresh() async {
        guard await isInstalled() else {
            status = .lmsMissing
            installedModels = []
            loadedModels = []
            return
        }

        async let statusProbe = probeServer()
        async let installed = listInstalledModels()
        async let loaded = listLoadedModels()

        status = await statusProbe
        installedModels = await installed
        loadedModels = await loaded
    }

    func isInstalled() async -> Bool {
        let out = (try? await runShell("command -v lms >/dev/null 2>&1 && echo yes || echo no")) ?? "no"
        return out.trimmingCharacters(in: .whitespacesAndNewlines) == "yes"
    }

    /// `lms server start --port 1234` runs synchronously and returns once the
    /// server is up. We surface failures via `lastError` so the Settings UI can
    /// show a banner; the exit status is captured by `runShell`.
    func startServer(port: Int = 1234) async {
        do {
            _ = try await runShell("lms server start --port \(port)")
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopServer() async {
        do {
            _ = try await runShell("lms server stop")
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// `lms daemon up` starts a headless service that survives Loom quitting.
    /// Preferred over `server start` when the user wants LM Studio always
    /// available without keeping the GUI open.
    func daemonUp() async {
        do {
            _ = try await runShell("lms daemon up")
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadModel(_ identifier: String, contextLength: Int? = nil, parallel: Int? = nil) async {
        let escaped = shellEscape(identifier)
        var command = "lms load \(escaped) -y"
        if let contextLength, contextLength > 0 {
            command += " -c \(contextLength)"
        }
        if let parallel, parallel > 0 {
            command += " --parallel \(parallel)"
        }
        do {
            _ = try await runShell(command)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unloadModel(_ identifier: String) async {
        let escaped = shellEscape(identifier)
        do {
            _ = try await runShell("lms unload \(escaped)")
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func optimizeForAgentWork(_ identifier: String, contextLength: Int) async {
        let escaped = shellEscape(identifier)
        let context = max(4096, contextLength)
        do {
            _ = try await runShell("lms unload \(escaped) >/dev/null 2>&1 || true; lms load \(escaped) -y -c \(context) --parallel 1 --gpu max")
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unloadAll() async {
        do {
            _ = try await runShell("lms unload --all")
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Internal

    private func probeServer() async -> ServerStatus {
        // `lms server status` exit code is 0 when running, non-zero when not.
        // Output also varies by version, so prefer exit code over parsing text.
        do {
            let out = try await runShell("lms server status 2>&1; echo __EXIT__$?")
            let exit = parseExitMarker(out)
            if exit == 0 {
                if let port = parseRunningPort(out) {
                    return .running(port: port)
                }
                return .running(port: 1234)
            } else {
                return .stopped
            }
        } catch {
            return .stopped
        }
    }

    private func parseExitMarker(_ output: String) -> Int? {
        for line in output.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("__EXIT__") {
                return Int(trimmed.dropFirst("__EXIT__".count))
            }
        }
        return nil
    }

    /// Pull a port number out of `lms server status` text. Format examples:
    ///   "The server is running on port 1234"
    ///   "Server: ON (port 1234)"
    private func parseRunningPort(_ output: String) -> Int? {
        let lower = output.lowercased()
        if let portRange = lower.range(of: "port") {
            let after = lower[portRange.upperBound...]
            let digits = after.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
            if !digits.isEmpty, let port = Int(digits) {
                return port
            }
        }
        return nil
    }

    private func listInstalledModels() async -> [String] {
        guard let out = try? await runShell("lms ls --json") else { return [] }
        return parseModelIDs(from: out)
    }

    private func listLoadedModels() async -> [String] {
        guard let out = try? await runShell("lms ps --json") else { return [] }
        return parseModelIDs(from: out)
    }

    /// `lms ls --json` and `lms ps --json` return arrays of objects with
    /// per-version, per-build varying shapes. We just want the model
    /// identifiers — pull `modelKey` first (newer builds), `path` second,
    /// `id` third.
    private func parseModelIDs(from json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let entries: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            entries = arr
        } else if let dict = root as? [String: Any], let arr = dict["data"] as? [[String: Any]] {
            entries = arr
        } else {
            return []
        }
        var ids: [String] = []
        for entry in entries {
            if let key = entry["modelKey"] as? String { ids.append(key); continue }
            if let path = entry["path"] as? String { ids.append(path); continue }
            if let id = entry["id"] as? String { ids.append(id); continue }
            if let identifier = entry["identifier"] as? String { ids.append(identifier); continue }
        }
        return ids
    }

    private func shellEscape(_ value: String) -> String {
        // Single-quote and escape any embedded single quotes. Safe enough for
        // model identifiers which are limited to alphanumerics, dashes, dots,
        // slashes, and underscores in practice.
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

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
