import Foundation

enum LMStudioToolRepair {
    static func firstJSONObjectData(in text: String) -> Data? {
        for candidate in balancedJSONObjectCandidates(in: text) {
            guard let data = candidate.json.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) != nil else {
                continue
            }
            return data
        }
        return nil
    }

    static func inputNeedsRepair(_ input: Data, schema: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else {
            return true
        }
        let required = requiredKeys(in: schema)
        guard !required.isEmpty else { return false }
        return required.contains { key in
            object[key] == nil || object[key] is NSNull
        }
    }

    static func extractToolCalls(
        from text: String,
        tools: [LLMTool]
    ) -> [(name: String, input: Data)] {
        let knownNames = Set(tools.map(\.name))
        var calls: [(name: String, input: Data)] = []
        var seen: Set<String> = []

        for candidate in balancedJSONObjectCandidates(in: text) {
            guard let data = candidate.json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            for parsed in parseToolCalls(from: object, context: candidate.context, tools: tools, knownNames: knownNames) {
                let key = "\(parsed.name):\(String(decoding: parsed.input, as: UTF8.self))"
                if seen.insert(key).inserted {
                    calls.append(parsed)
                }
            }
        }
        return calls
    }

    static func shouldNudgeForMissingToolCall(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 80 else { return false }
        let lower = trimmed.lowercased()
        let actionHints = [
            "i will", "i'll", "i need to", "next, i", "first, i",
            "read_file", "edit_file", "write_file", "run_bash",
            "open the file", "modify", "edit", "create", "run `", "$ "
        ]
        let pathHints = [".swift", ".rs", ".ts", ".tsx", ".js", ".json", ".md", "/", "src/", "tests/"]
        return actionHints.contains { lower.contains($0) }
            && pathHints.contains { lower.contains($0) }
    }

    static func continuationNudge(toolNames: [String]) -> LLMMessage {
        let list = toolNames.sorted().joined(separator: ", ")
        return LLMMessage(
            role: .user,
            content: """
            You described workspace actions but did not call any tools. Continue by using the available tools now.
            Available tools: \(list)
            If the work is already complete, answer with final text only and do not mention tool calls.
            """
        )
    }

    static func requiredKeys(in schema: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: schema) as? [String: Any],
              let required = object["required"] as? [String] else {
            return []
        }
        return required
    }

    private struct JSONCandidate {
        let json: String
        let context: String
    }

    private static func balancedJSONObjectCandidates(in text: String) -> [JSONCandidate] {
        var candidates: [JSONCandidate] = []
        var start: String.Index?
        var depth = 0
        var inString = false
        var escaping = false
        var index = text.startIndex

        while index < text.endIndex {
            let ch = text[index]
            if inString {
                if escaping {
                    escaping = false
                } else if ch == "\\" {
                    escaping = true
                } else if ch == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }

            if ch == "\"" {
                inString = true
            } else if ch == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if ch == "}", depth > 0 {
                depth -= 1
                if depth == 0, let objectStart = start {
                    let end = text.index(after: index)
                    let json = String(text[objectStart..<end])
                    let contextStart = text.index(
                        objectStart,
                        offsetBy: -min(120, text.distance(from: text.startIndex, to: objectStart))
                    )
                    let contextEnd = text.index(
                        end,
                        offsetBy: min(120, text.distance(from: end, to: text.endIndex))
                    )
                    candidates.append(JSONCandidate(
                        json: json,
                        context: String(text[contextStart..<contextEnd])
                    ))
                    start = nil
                }
            }
            index = text.index(after: index)
        }
        return candidates
    }

    private static func parseToolCalls(
        from object: Any,
        context: String,
        tools: [LLMTool],
        knownNames: Set<String>
    ) -> [(name: String, input: Data)] {
        if let array = object as? [Any] {
            return array.flatMap { parseToolCalls(from: $0, context: context, tools: tools, knownNames: knownNames) }
        }
        guard let dict = object as? [String: Any] else { return [] }

        if let nested = dict["tool_calls"] as? [Any] {
            return nested.flatMap { parseToolCalls(from: $0, context: context, tools: tools, knownNames: knownNames) }
        }

        if let function = dict["function"] as? [String: Any],
           let name = stringValue(function["name"]),
           knownNames.contains(name),
           let input = dataForArguments(function["arguments"] ?? dict["arguments"] ?? dict["input"]) {
            return [(name, input)]
        }

        if let name = [
            stringValue(dict["name"]),
            stringValue(dict["tool"]),
            stringValue(dict["tool_name"])
        ].compactMap({ $0 }).first(where: { knownNames.contains($0) }) {
            let rawArguments = dict["arguments"] ?? dict["args"] ?? dict["input"] ?? dict["parameters"]
            if let input = dataForArguments(rawArguments) {
                return [(name, input)]
            }
        }

        for tool in tools where context.localizedCaseInsensitiveContains(tool.name) {
            let required = requiredKeys(in: tool.inputSchema)
            guard !required.isEmpty,
                  required.allSatisfy({ dict[$0] != nil }),
                  let input = dataForArguments(dict) else {
                continue
            }
            return [(tool.name, input)]
        }

        return []
    }

    private static func stringValue(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dataForArguments(_ value: Any?) -> Data? {
        guard let value else { return nil }
        if let string = value as? String {
            if let data = string.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
            return firstJSONObjectData(in: string)
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: []) else {
            return nil
        }
        return data
    }
}
