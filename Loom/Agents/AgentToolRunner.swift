import Foundation

/// Executes the side-effecting tool calls the agent orchestrator routes to it:
/// file reads, file edits, and bash. Tool call inputs are validated against
/// the workspace folder so a runaway agent can't read or write outside the
/// project the user opened.
///
/// The `update_tasks` tool is *not* handled here. It's intercepted by the
/// orchestrator and applied to its own task list, identical to how Claude
/// Code's `TodoWrite` works.
struct AgentToolRunner: Sendable {
    let workspaceRoot: URL?
    /// When false, the `run_bash` tool throws `ToolError.bashDisabled` instead
    /// of executing. Default off — bash on a local model is dicey enough that
    /// we want the user to opt in via Settings.
    let allowBash: Bool

    enum ToolError: Error, LocalizedError {
        case unknownTool(String)
        case missingArgument(String)
        case decoding(String)
        case outsideWorkspace(String)
        case bashDisabled
        case bashTimeout
        case fileNotFound(String)
        case stringNotFound

        var errorDescription: String? {
            switch self {
            case .unknownTool(let name):     return "Unknown tool: \(name)"
            case .missingArgument(let key):  return "Missing argument: \(key)"
            case .decoding(let why):         return "Bad arguments: \(why)"
            case .outsideWorkspace(let p):   return "Path is outside the workspace: \(p)"
            case .bashDisabled:              return "Bash tool disabled. Enable it in Settings → Agent."
            case .bashTimeout:               return "Bash command timed out"
            case .fileNotFound(let p):       return "File not found: \(p)"
            case .stringNotFound:            return "Could not find old_string in file"
            }
        }
    }

    /// Tool definitions handed to the provider. Schemas are inlined as JSON
    /// because `LLMTool.inputSchema` is untyped JSON data.
    static let defaultTools: [LLMTool] = [
        LLMTool(
            name: "read_file",
            description: "Read a UTF-8 text file inside the current workspace. Returns the full file contents.",
            inputSchema: jsonSchema([
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path relative to the workspace root."]
                ],
                "required": ["path"]
            ])
        ),
        LLMTool(
            name: "edit_file",
            description: "Edit a text file by replacing an exact substring. Use for small, surgical edits.",
            inputSchema: jsonSchema([
                "type": "object",
                "properties": [
                    "path":       ["type": "string", "description": "Path relative to the workspace root."],
                    "old_string": ["type": "string", "description": "The exact substring currently in the file."],
                    "new_string": ["type": "string", "description": "The replacement text."]
                ],
                "required": ["path", "old_string", "new_string"]
            ])
        ),
        LLMTool(
            name: "write_file",
            description: "Create or overwrite a UTF-8 text file inside the current workspace.",
            inputSchema: jsonSchema([
                "type": "object",
                "properties": [
                    "path":    ["type": "string", "description": "Path relative to the workspace root."],
                    "content": ["type": "string", "description": "The file contents to write."]
                ],
                "required": ["path", "content"]
            ])
        ),
        LLMTool(
            name: "list_dir",
            description: "List the entries in a directory inside the current workspace.",
            inputSchema: jsonSchema([
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Directory path relative to the workspace root. Empty string means the root."]
                ],
                "required": ["path"]
            ])
        ),
        LLMTool(
            name: "run_bash",
            description: "Execute a shell command in the workspace. Disabled by default; enable in Settings → Agent.",
            inputSchema: jsonSchema([
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "The shell command to run."],
                    "timeout_seconds": ["type": "integer", "description": "Maximum runtime in seconds. Default 30."]
                ],
                "required": ["command"]
            ])
        ),
        LLMTool(
            name: "update_tasks",
            description: "Replace the visible task list. Use this to plan multi-step work and keep the user informed of progress.",
            inputSchema: jsonSchema([
                "type": "object",
                "properties": [
                    "tasks": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "subject":     ["type": "string"],
                                "activeForm":  ["type": "string"],
                                "status":      ["type": "string", "enum": ["pending", "in_progress", "completed", "cancelled"]]
                            ],
                            "required": ["subject", "status"]
                        ]
                    ]
                ],
                "required": ["tasks"]
            ])
        )
    ]

    /// Execute one tool call and return the textual result the orchestrator
    /// will send back to the model as a tool message.
    func execute(name: String, input: Data) async throws -> String {
        switch name {
        case "read_file":     return try await readFile(input: input)
        case "write_file":    return try await writeFile(input: input)
        case "edit_file":     return try await editFile(input: input)
        case "list_dir":      return try await listDir(input: input)
        case "run_bash":      return try await runBash(input: input)
        case "update_tasks":
            // Should never reach the runner — the orchestrator intercepts it.
            throw ToolError.unknownTool(name)
        default:
            throw ToolError.unknownTool(name)
        }
    }

    // MARK: - Tools

    private func readFile(input: Data) async throws -> String {
        struct Args: Decodable { let path: String }
        let args = try decode(Args.self, from: input)
        let url = try resolve(args.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError.fileNotFound(args.path)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        // Cap the read so an accidental binary read doesn't eat the context.
        if text.count > 32_000 {
            let cap = text.index(text.startIndex, offsetBy: 32_000)
            return String(text[..<cap]) + "\n\n…(truncated at 32000 chars)"
        }
        return text
    }

    private func writeFile(input: Data) async throws -> String {
        struct Args: Decodable { let path: String; let content: String }
        let args = try decode(Args.self, from: input)
        let url = try resolve(args.path)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try args.content.write(to: url, atomically: true, encoding: .utf8)
        return "Wrote \(args.content.count) bytes to \(args.path)"
    }

    private func editFile(input: Data) async throws -> String {
        struct Args: Decodable { let path: String; let old_string: String; let new_string: String }
        let args = try decode(Args.self, from: input)
        let url = try resolve(args.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError.fileNotFound(args.path)
        }
        var text = try String(contentsOf: url, encoding: .utf8)
        guard text.contains(args.old_string) else {
            throw ToolError.stringNotFound
        }
        text = text.replacingOccurrences(of: args.old_string, with: args.new_string)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return "Replaced 1 occurrence in \(args.path)"
    }

    private func listDir(input: Data) async throws -> String {
        struct Args: Decodable { let path: String }
        let args = try decode(Args.self, from: input)
        let url = try resolve(args.path)
        let entries = try FileManager.default.contentsOfDirectory(atPath: url.path)
        return entries.sorted().joined(separator: "\n")
    }

    private func runBash(input: Data) async throws -> String {
        guard allowBash else { throw ToolError.bashDisabled }
        struct Args: Decodable {
            let command: String
            let timeout_seconds: Int?
        }
        let args = try decode(Args.self, from: input)
        let timeout = max(1, min(args.timeout_seconds ?? 30, 300))
        let workingDir = workspaceRoot?.path ?? FileManager.default.homeDirectoryForCurrentUser.path

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lic", args.command]
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = outPipe
            try process.run()

            let deadline = Date().addingTimeInterval(TimeInterval(timeout))
            while process.isRunning {
                if Date() > deadline {
                    process.terminate()
                    throw ToolError.bashTimeout
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(decoding: data, as: UTF8.self)
            let exit = process.terminationStatus
            let header = "$ \(args.command)\n[exit \(exit)]\n"
            if raw.count > 16_000 {
                let cap = raw.index(raw.startIndex, offsetBy: 16_000)
                return header + String(raw[..<cap]) + "\n…(truncated)"
            }
            return header + raw
        }.value
    }

    // MARK: - Helpers

    private func resolve(_ relativePath: String) throws -> URL {
        guard let root = workspaceRoot else {
            // No workspace bound: fall back to the user's home directory but
            // still refuse paths that would escape it.
            let home = FileManager.default.homeDirectoryForCurrentUser
            let target = home.appendingPathComponent(relativePath).standardizedFileURL
            guard target.path.hasPrefix(home.standardizedFileURL.path) else {
                throw ToolError.outsideWorkspace(relativePath)
            }
            return target
        }
        let canonical = root.standardizedFileURL
        let target = canonical.appendingPathComponent(relativePath).standardizedFileURL
        guard target.path == canonical.path || target.path.hasPrefix(canonical.path + "/") else {
            throw ToolError.outsideWorkspace(relativePath)
        }
        return target
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // Some local models emit `arguments: ""` when they want zero-arg
            // tools. Decoders fail on empty strings — give a friendlier error.
            let raw = String(decoding: data, as: UTF8.self)
            throw ToolError.decoding("\(error.localizedDescription) (raw: \(raw.prefix(200)))")
        }
    }

    private static func jsonSchema(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }
}
