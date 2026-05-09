import Foundation
import Observation

/// One MCP server as Claude Code knows about it. Loom doesn't speak MCP
/// directly; we shell out to `claude mcp` to read and mutate the user's
/// global server registry. That keeps Claude Code's robust transport
/// implementation as the single source of truth and lets Loom focus on
/// surfacing it cleanly.
struct MCPServer: Identifiable, Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case connected
        case needsAuth
        case failed(String)
        case unknown
    }

    let name: String
    /// Either a URL (for HTTP/SSE transports) or a stdio command string.
    let target: String
    let transportLabel: String
    let status: Status

    var id: String { name }
}

/// Reads and mutates the Claude Code MCP server registry by shelling out
/// to the `claude` CLI. Stays main-actor for the SwiftUI binding and pushes
/// the actual subprocess invocation onto utility-priority detached tasks
/// so a slow `claude mcp list` (which round-trips to every configured
/// server) doesn't stall the settings sheet.
@Observable
@MainActor
final class MCPService {
    var servers: [MCPServer] = []
    var lastError: String?
    var isRefreshing: Bool = false

    /// Path to the `claude` binary. Resolved lazily so we don't probe disk
    /// on app launch. Settings → MCP only fires this when the user opens
    /// the tab, which is the only time we need it.
    private var resolvedClaudePath: String?

    /// Pull the current registry from `claude mcp list` and parse it.
    /// Coalesces back-to-back calls: a refresh already in flight wins;
    /// duplicate requests reuse its result by waiting on the same task.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let path = try resolveClaude()
            let output = try await Self.runProcess(path: path, args: ["mcp", "list"])
            servers = Self.parseList(output)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Add an MCP server via `claude mcp add <name> <command> [args...]`.
    /// Returns true on success; the caller refreshes afterwards so the
    /// Just-added server appears with its initial status.
    @discardableResult
    func add(name: String, command: String, args: [String]) async -> Bool {
        guard !name.isEmpty, !command.isEmpty else {
            lastError = "Name and command are both required"
            return false
        }
        do {
            let path = try resolveClaude()
            // The `--` separator stops `claude` from interpreting our
            // server-side flags as its own.
            var argv = ["mcp", "add", name, command]
            if !args.isEmpty {
                argv.append("--")
                argv.append(contentsOf: args)
            }
            _ = try await Self.runProcess(path: path, args: argv)
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Remove a server by name. Loom doesn't try to second-guess Claude
    /// Code's behavior, so this is a thin wrapper around
    /// `claude mcp remove <name>`.
    @discardableResult
    func remove(name: String) async -> Bool {
        do {
            let path = try resolveClaude()
            _ = try await Self.runProcess(path: path, args: ["mcp", "remove", name])
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Internals

    private func resolveClaude() throws -> String {
        if let cached = resolvedClaudePath { return cached }
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            resolvedClaudePath = path
            return path
        }
        throw MCPError.claudeNotFound
    }

    nonisolated private static func runProcess(path: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus != 0 {
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let message = trimmed.isEmpty
                        ? "claude exited with status \(process.terminationStatus)"
                        : trimmed
                    continuation.resume(throwing: MCPError.subprocessFailed(message))
                } else {
                    continuation.resume(returning: output)
                }
            }
        }
    }

    /// Parse `claude mcp list` output. Format observed in 2026 Claude Code:
    ///
    ///   Checking MCP server health…
    ///
    ///   <name>: <target> - <status-line>
    ///   <name>: <target> (HTTP) - <status-line>
    ///   ...
    ///
    /// We're tolerant: lines that don't match the pattern are skipped
    /// rather than treated as parse errors.
    nonisolated static func parseList(_ raw: String) -> [MCPServer] {
        var out: [MCPServer] = []
        for line in raw.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  !text.hasPrefix("Checking"),
                  let colonRange = text.range(of: ": ") else { continue }
            let name = String(text[..<colonRange.lowerBound])
            let rest = String(text[colonRange.upperBound...])
            // Split target from status on " - ", but only on the *last*
            // occurrence — server URLs sometimes contain hyphens.
            guard let dashRange = rest.range(of: " - ", options: .backwards) else { continue }
            var target = String(rest[..<dashRange.lowerBound])
            var transportLabel = "stdio"
            // Detect inline transport tag: "<target> (HTTP)" or "(SSE)".
            if let openParen = target.range(of: " ("),
               let closeParen = target.range(of: ")", options: .backwards),
               closeParen.upperBound == target.endIndex,
               openParen.lowerBound < closeParen.lowerBound {
                transportLabel = String(target[openParen.upperBound..<closeParen.lowerBound])
                target = String(target[..<openParen.lowerBound])
            } else if target.hasPrefix("http://") || target.hasPrefix("https://") {
                transportLabel = "HTTP"
            }
            let statusLine = String(rest[dashRange.upperBound...])
            out.append(MCPServer(
                name: name,
                target: target,
                transportLabel: transportLabel,
                status: parseStatus(statusLine)
            ))
        }
        return out
    }

    nonisolated private static func parseStatus(_ raw: String) -> MCPServer.Status {
        let lower = raw.lowercased()
        if lower.contains("connected") || lower.contains("✓") {
            return .connected
        }
        if lower.contains("authentication") || lower.contains("auth") {
            return .needsAuth
        }
        if lower.contains("failed") || lower.contains("error") || lower.contains("✗") {
            return .failed(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return .unknown
    }
}

enum MCPError: LocalizedError {
    case claudeNotFound
    case subprocessFailed(String)

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Couldn't find the `claude` CLI. Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code"
        case .subprocessFailed(let message):
            return message
        }
    }
}
