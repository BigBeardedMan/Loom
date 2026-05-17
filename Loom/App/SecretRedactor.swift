import Foundation

enum SecretRedactor {
    private static let redaction = "[REDACTED]"

    static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var value = text
        for rule in redactRules {
            value = replace(pattern: rule.pattern, in: value, with: rule.replacement)
        }
        return value
    }

    static func shouldSkipCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        let deniedPrefixes = [
            "gh auth",
            "npm token",
            "ssh-add",
            "aws configure",
            "docker login",
            "gcloud auth",
            "az login",
            "security find-generic-password",
            "security add-generic-password",
            "pass "
        ]
        if deniedPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return true
        }
        let secretPatterns = [
            #"(?i)(^|[;&|\s])(export\s+)?[A-Z_][A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL)[A-Z0-9_]*="#,
            #"(?i)\s--(api-key|token|password|secret)(=|\s+)\S+"#,
            #"(?i)(authorization:\s*bearer\s+)\S+"#
        ]
        return secretPatterns.contains { matches(pattern: $0, in: trimmed) }
    }

    private static let redactRules: [(pattern: String, replacement: String)] = [
        (#"(?is)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----"#, "[REDACTED PRIVATE KEY]"),
        (#"(?i)(authorization:\s*bearer\s+)[A-Za-z0-9._~+/\-]+=*"#, "$1[REDACTED]"),
        (#"(?i)(--(?:api-key|token|password|secret)(?:=|\s+))([^\s"'`]+)"#, "$1[REDACTED]"),
        (#"(?i)\b(api[_-]?key|token|secret|password|passwd|credential)(\s*[:=]\s*)(["']?)([^\s"'`]+)"#, "$1$2$3[REDACTED]"),
        (#"\bsk-[A-Za-z0-9]{12,}\b"#, "[REDACTED_OPENAI_KEY]"),
        (#"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"#, "[REDACTED_GITHUB_TOKEN]"),
        (#"\bAKIA[0-9A-Z]{16}\b"#, "[REDACTED_AWS_KEY]")
    ]

    private static func matches(pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func replace(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
