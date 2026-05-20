import Foundation

enum AgentRunReview {
    static func build(
        workspaceRoot: URL?,
        turns: [AgentOrchestrator.Turn]
    ) async -> String? {
        let records = turns.flatMap(\.toolCalls)
        let changedFiles = changedPaths(in: records)
        let failedTools = records.filter { !$0.succeeded }
        guard !changedFiles.isEmpty || !failedTools.isEmpty else { return nil }

        var lines: [String] = ["### Review changes"]
        if !changedFiles.isEmpty {
            lines.append("")
            lines.append("Changed files:")
            for path in changedFiles.prefix(12) {
                lines.append("- \(path)")
            }
            if changedFiles.count > 12 {
                lines.append("- …and \(changedFiles.count - 12) more")
            }
        }

        if let workspaceRoot, !changedFiles.isEmpty,
           let diff = await gitDiffStat(workspaceRoot: workspaceRoot),
           !diff.isEmpty {
            lines.append("")
            lines.append("Git diff summary:")
            lines.append("```")
            lines.append(diff)
            lines.append("```")
        }

        if !failedTools.isEmpty {
            lines.append("")
            lines.append("Tool issues:")
            for record in failedTools.prefix(6) {
                lines.append("- \(record.name): \(String(record.result.prefix(180)))")
            }
        }

        if !changedFiles.isEmpty {
            lines.append("")
            lines.append("Suggested commands:")
            lines.append("- git diff")
            if changedFiles.contains(where: looksLikeSwiftPath) {
                lines.append("- xcodebuild test")
            } else if changedFiles.contains(where: looksLikeJavaScriptPath) {
                lines.append("- npm test")
            } else if changedFiles.contains(where: looksLikeRustPath) {
                lines.append("- cargo test")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func changedPaths(in records: [AgentOrchestrator.ToolCallRecord]) -> [String] {
        var paths: [String] = []
        var seen: Set<String> = []
        for record in records where record.name == "write_file" || record.name == "edit_file" {
            guard let data = record.arguments.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let path = dict["path"] as? String,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            if seen.insert(path).inserted {
                paths.append(path)
            }
        }
        return paths
    }

    private static func gitDiffStat(workspaceRoot: URL) async -> String? {
        await Task.detached(priority: .utility) {
            let gitDir = workspaceRoot.appendingPathComponent(".git")
            guard FileManager.default.fileExists(atPath: gitDir.path) else { return nil }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["diff", "--stat", "--shortstat"]
            process.currentDirectoryURL = workspaceRoot
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }.value
    }

    private static func looksLikeSwiftPath(_ path: String) -> Bool {
        path.hasSuffix(".swift") || path.hasSuffix(".xcodeproj") || path.hasSuffix(".yml")
    }

    private static func looksLikeJavaScriptPath(_ path: String) -> Bool {
        path.hasSuffix(".js") || path.hasSuffix(".jsx") || path.hasSuffix(".ts")
            || path.hasSuffix(".tsx") || path.hasSuffix("package.json")
    }

    private static func looksLikeRustPath(_ path: String) -> Bool {
        path.hasSuffix(".rs") || path.hasSuffix("Cargo.toml")
    }
}
