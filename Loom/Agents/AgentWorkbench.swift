import Foundation

struct AgentWorkbenchEvent: Identifiable, Hashable, Sendable {
    enum Status: String, Hashable, Sendable {
        case running
        case succeeded
        case failed
        case info

        var label: String {
            switch self {
            case .running:   return "Running"
            case .succeeded: return "Done"
            case .failed:    return "Failed"
            case .info:      return "Info"
            }
        }
    }

    let id = UUID()
    let date = Date()
    var title: String
    var detail: String
    var status: Status
    var systemImage: String
}

struct AgentVerificationResult: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case diff
        case test
        case preview
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var command: String?
    var succeeded: Bool
    var output: String
    var duration: TimeInterval
}

enum AgentVerificationService {
    static func run(
        workspaceRoot: URL?,
        changedFiles: [String],
        previewURL: URL?
    ) async -> [AgentVerificationResult] {
        guard let workspaceRoot else { return [] }
        var results: [AgentVerificationResult] = []

        if isGitRepo(workspaceRoot) {
            if let diff = await runCommand("git diff --stat --shortstat", workspaceRoot: workspaceRoot, timeout: 20) {
                results.append(AgentVerificationResult(
                    kind: .diff,
                    title: "Git diff summary",
                    command: "git diff --stat --shortstat",
                    succeeded: diff.exitCode == 0,
                    output: diff.output,
                    duration: diff.duration
                ))
            }
            if let check = await runCommand("git diff --check", workspaceRoot: workspaceRoot, timeout: 20) {
                results.append(AgentVerificationResult(
                    kind: .diff,
                    title: "Whitespace check",
                    command: "git diff --check",
                    succeeded: check.exitCode == 0,
                    output: check.output.isEmpty ? "No whitespace errors." : check.output,
                    duration: check.duration
                ))
            }
        }

        if let testCommand = inferTestCommand(workspaceRoot: workspaceRoot, changedFiles: changedFiles),
           let test = await runCommand(testCommand, workspaceRoot: workspaceRoot, timeout: 240) {
            results.append(AgentVerificationResult(
                kind: .test,
                title: "Inferred verification",
                command: testCommand,
                succeeded: test.exitCode == 0,
                output: test.output,
                duration: test.duration
            ))
        }

        if let previewURL,
           isLocalPreviewURL(previewURL),
           let preview = await checkPreview(url: previewURL) {
            results.append(preview)
        }

        return results
    }

    private struct CommandResult: Sendable {
        let exitCode: Int32
        let output: String
        let duration: TimeInterval
    }

    private static func isGitRepo(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    private static func inferTestCommand(workspaceRoot: URL, changedFiles: [String]) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: workspaceRoot.appendingPathComponent("package.json").path) {
            return "npm test"
        }
        if fm.fileExists(atPath: workspaceRoot.appendingPathComponent("Cargo.toml").path) {
            return "cargo test"
        }
        if fm.fileExists(atPath: workspaceRoot.appendingPathComponent("Package.swift").path) {
            return "swift test"
        }
        if changedFiles.contains(where: { $0.hasSuffix(".swift") }) {
            let project = firstFile(withExtension: "xcodeproj", in: workspaceRoot)
            if let project {
                let scheme = project.deletingPathExtension().lastPathComponent
                return "xcodebuild -project \(shellEscape(project.lastPathComponent)) -scheme \(shellEscape(scheme)) -configuration Debug -quiet build"
            }
        }
        return nil
    }

    private static func firstFile(withExtension ext: String, in root: URL) -> URL? {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { $0.pathExtension == ext }
            .sorted { lhs, rhs in
                let leftDuplicate = lhs.lastPathComponent.contains(" 2.")
                let rightDuplicate = rhs.lastPathComponent.contains(" 2.")
                if leftDuplicate != rightDuplicate { return !leftDuplicate && rightDuplicate }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .first
    }

    private static func isLocalPreviewURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return ["localhost", "127.0.0.1", "0.0.0.0", "::1"].contains(host)
    }

    private static func runCommand(
        _ command: String,
        workspaceRoot: URL,
        timeout: TimeInterval
    ) async -> CommandResult? {
        await Task.detached(priority: .userInitiated) {
            let started = Date()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lic", command]
            process.currentDirectoryURL = workspaceRoot
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning {
                    if Date() > deadline {
                        process.terminate()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = SecretRedactor.redact(String(decoding: data, as: UTF8.self))
                return CommandResult(
                    exitCode: process.terminationStatus,
                    output: truncate(output),
                    duration: Date().timeIntervalSince(started)
                )
            } catch {
                return CommandResult(
                    exitCode: 1,
                    output: error.localizedDescription,
                    duration: Date().timeIntervalSince(started)
                )
            }
        }.value
    }

    private static func checkPreview(url: URL) async -> AgentVerificationResult? {
        let started = Date()
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(decoding: data.prefix(4096), as: UTF8.self)
            let title = extractHTMLTitle(body) ?? url.absoluteString
            return AgentVerificationResult(
                kind: .preview,
                title: "Preview check",
                command: url.absoluteString,
                succeeded: (200..<400).contains(status),
                output: "HTTP \(status) · \(title)",
                duration: Date().timeIntervalSince(started)
            )
        } catch {
            return AgentVerificationResult(
                kind: .preview,
                title: "Preview check",
                command: url.absoluteString,
                succeeded: false,
                output: error.localizedDescription,
                duration: Date().timeIntervalSince(started)
            )
        }
    }

    private static func extractHTMLTitle(_ html: String) -> String? {
        guard let start = html.range(of: "<title", options: [.caseInsensitive]),
              let closeStart = html[start.upperBound...].range(of: ">"),
              let end = html[closeStart.upperBound...].range(of: "</title>", options: [.caseInsensitive]) else {
            return nil
        }
        return String(html[closeStart.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ text: String, max: Int = 12_000) -> String {
        guard text.count > max else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let cap = text.index(text.startIndex, offsetBy: max)
        return String(text[..<cap]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n...(truncated)"
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
