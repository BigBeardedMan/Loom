import Foundation
import Observation
import os

private let cliLog = Logger(subsystem: "com.chasesims.LoomTestingEdition", category: "cli-agent")

/// Drives a chat-style CLI agent (Claude Code, Codex, or Gemini) as a
/// subprocess so the embedded chat UI can use the user's existing CLI OAuth
/// login — no API key needed. Each vendor has its own argv shape:
///
///   - claude: `claude -p [--agent <name>] (--session-id|--resume) <id> <prompt>`
///     (persistent session id reused across turns)
///   - codex:  `codex exec --skip-git-repo-check <prompt>` (stateless per turn)
///   - gemini: `gemini -p <prompt>`                         (stateless per turn)
///
/// Subprocess invocation goes through `/usr/bin/env <cli> ...` with arguments
/// passed as an array, **never** built into a shell command string. That keeps
/// any user-controlled value (prompt, agent name) from being interpreted as
/// shell syntax.
///
/// One provider instance is shared across vendors in `AgentPaneView`. The
/// Claude session id is allocated on init and only used when the selected
/// vendor is Claude — Codex/Gemini turns ignore it.
@Observable
@MainActor
final class CLIAgentProvider {
    /// Stable session id for Claude turns — reused across turns via `--resume`
    /// so Claude conversations have memory. Codex/Gemini ignore this.
    let sessionID: String = UUID().uuidString

    private(set) var hasLaunchedClaudeSession = false
    private var activeProcess: Process?
    /// Bumped on every `cancel()`. `send()` captures the value at start and
    /// refuses to deliver a response (or flip launch state) when the
    /// generation has moved on — protects against the case where `terminate()`
    /// has been issued but `waitUntilExit()` is still blocking the producer.
    private var generation: Int = 0

    /// Resolved PATH for subprocess invocations. Populated once on first send
    /// from a single login-shell echo so we can launch CLIs with a clean
    /// environment instead of re-spawning a login shell on every turn.
    private static var cachedPath: String?

    enum ProviderError: LocalizedError {
        case nonZeroExit(tool: String, code: Int32, stderr: String)
        case launchFailed(String)
        case unsupportedVendor(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let tool, let code, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty
                    ? "\(tool) exited with code \(code)"
                    : "\(tool) exited with code \(code): \(trimmed)"
            case .launchFailed(let msg):
                return "Failed to launch CLI: \(msg)"
            case .unsupportedVendor(let label):
                return "\(label) is not a CLI vendor"
            case .cancelled:
                return "Cancelled"
            }
        }
    }

    func cancel() {
        generation &+= 1
        activeProcess?.terminate()
        activeProcess = nil
    }

    /// Send one user turn and wait for the CLI to print its response. The
    /// argv shape depends on `vendor`. `agentName` is only meaningful for
    /// Claude (mapped to `--agent`); Codex/Gemini ignore it.
    func send(
        prompt: String,
        cwd: URL?,
        vendor: AgentDescriptor.Vendor,
        agentName: String? = nil
    ) async throws -> String {
        switch vendor {
        case .claude:
            return try await sendViaClaude(prompt: prompt, cwd: cwd, agentName: agentName)
        case .codex:
            return try await sendOneShot(tool: "codex", arguments: [
                "exec", "--skip-git-repo-check", prompt
            ], cwd: cwd)
        case .gemini:
            return try await sendOneShot(tool: "gemini", arguments: [
                "-p", prompt
            ], cwd: cwd)
        case .ollama, .openAICompatible, .lmstudio:
            throw ProviderError.unsupportedVendor(vendor.label)
        }
    }

    // MARK: - Claude

    private func sendViaClaude(prompt: String, cwd: URL?, agentName: String?) async throws -> String {
        let myGeneration = generation
        let resumeFlag = hasLaunchedClaudeSession ? "--resume" : "--session-id"
        let sessionID = self.sessionID

        var arguments: [String] = ["claude", "-p"]
        if let agentName, !agentName.isEmpty {
            arguments.append("--agent")
            arguments.append(agentName)
        }
        arguments.append(resumeFlag)
        arguments.append(sessionID)
        arguments.append(prompt)

        let (code, outData, errData) = try await runEnv(arguments: arguments, cwd: cwd, myGeneration: myGeneration)
        if code != 0 {
            let stderr = String(decoding: errData, as: UTF8.self)
            throw ProviderError.nonZeroExit(tool: "claude", code: code, stderr: stderr)
        }
        hasLaunchedClaudeSession = true
        return String(decoding: outData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Codex / Gemini (stateless one-shot)

    private func sendOneShot(tool: String, arguments tailArgs: [String], cwd: URL?) async throws -> String {
        let myGeneration = generation
        var arguments: [String] = [tool]
        arguments.append(contentsOf: tailArgs)
        let (code, outData, errData) = try await runEnv(arguments: arguments, cwd: cwd, myGeneration: myGeneration)
        if code != 0 {
            let stderr = String(decoding: errData, as: UTF8.self)
            throw ProviderError.nonZeroExit(tool: tool, code: code, stderr: stderr)
        }
        return String(decoding: outData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Subprocess plumbing

    private func runEnv(
        arguments: [String],
        cwd: URL?,
        myGeneration: Int
    ) async throws -> (Int32, Data, Data) {
        let path = await Self.resolvedPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        process.environment = env
        if let cwdPath = cwd?.path { process.currentDirectoryURL = URL(fileURLWithPath: cwdPath) }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        activeProcess = process
        defer {
            if activeProcess === process { activeProcess = nil }
        }

        let result = try await Self.runProcess(process, outPipe: outPipe, errPipe: errPipe)

        // If cancel() fired during the await, the captured generation is stale.
        // Don't deliver the response — the user already saw the assistant
        // placeholder vanish on cancel.
        guard myGeneration == generation else {
            throw ProviderError.cancelled
        }
        return result
    }

    /// Run `process` to completion off the main actor. Resumes via the
    /// terminationHandler so cancellation (which calls `process.terminate()`
    /// from the main actor) can actually unblock the awaiting caller — the
    /// previous `process.waitUntilExit()` form blocked indefinitely.
    private static func runProcess(
        _ process: Process,
        outPipe: Pipe,
        errPipe: Pipe
    ) async throws -> (Int32, Data, Data) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Int32, Data, Data), Error>) in
            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (proc.terminationStatus, outData, errData))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: ProviderError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Resolve the user's interactive PATH once and cache it. Falls back to
    /// the inherited PATH if the login-shell probe fails.
    private static func resolvedPath() async -> String {
        if let cached = cachedPath { return cached }
        let probe = await Task.detached(priority: .userInitiated) { () -> String? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lic", "echo $PATH"]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                cliLog.error("PATH probe failed to launch: \(error.localizedDescription, privacy: .public)")
                return nil
            }
            process.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }.value
        let resolved = probe
            ?? ProcessInfo.processInfo.environment["PATH"]
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        cachedPath = resolved
        return resolved
    }
}
