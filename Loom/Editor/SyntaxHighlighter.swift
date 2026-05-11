import Foundation
import AppKit

/// Lightweight regex-based highlighter for a small set of common
/// languages. Not a full lexer — it produces a "good enough" coloring
/// for keywords, strings, numbers, comments, and types.
enum SyntaxLanguage: String, CaseIterable {
    case swift
    case javascript
    case typescript
    case json
    case python
    case rust
    case markdown
    case shell
    case plain

    static func detect(forExtension ext: String) -> SyntaxLanguage {
        switch ext.lowercased() {
        case "swift": return .swift
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "ts", "tsx": return .typescript
        case "json", "jsonc": return .json
        case "py", "pyi": return .python
        case "rs": return .rust
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh", "fish": return .shell
        default: return .plain
        }
    }

    var keywords: [String] {
        switch self {
        case .swift:
            return ["import", "let", "var", "func", "class", "struct", "enum", "actor",
                    "extension", "protocol", "if", "else", "guard", "return", "for", "while",
                    "switch", "case", "default", "break", "continue", "in", "as", "is",
                    "try", "throw", "throws", "do", "catch", "async", "await", "init",
                    "self", "Self", "super", "true", "false", "nil", "public", "private",
                    "internal", "fileprivate", "open", "static", "final", "lazy", "weak",
                    "unowned", "where", "associatedtype", "typealias", "inout", "rethrows",
                    "defer", "deinit", "subscript", "operator", "precedencegroup"]
        case .javascript, .typescript:
            return ["import", "from", "export", "default", "const", "let", "var", "function",
                    "class", "extends", "implements", "interface", "type", "enum",
                    "if", "else", "for", "while", "do", "switch", "case", "default",
                    "break", "continue", "return", "try", "catch", "finally", "throw",
                    "new", "this", "super", "true", "false", "null", "undefined", "async",
                    "await", "yield", "typeof", "instanceof", "in", "of", "as", "is",
                    "public", "private", "protected", "static", "readonly", "abstract",
                    "void", "any", "unknown", "never"]
        case .json:
            return ["true", "false", "null"]
        case .python:
            return ["import", "from", "as", "def", "class", "if", "elif", "else", "for",
                    "while", "in", "not", "and", "or", "is", "return", "yield", "try",
                    "except", "finally", "raise", "with", "pass", "break", "continue",
                    "lambda", "global", "nonlocal", "True", "False", "None", "async",
                    "await", "self"]
        case .rust:
            return ["fn", "let", "mut", "const", "static", "struct", "enum", "trait",
                    "impl", "for", "while", "loop", "if", "else", "match", "return",
                    "use", "mod", "pub", "crate", "self", "Self", "super", "as", "ref",
                    "in", "where", "break", "continue", "async", "await", "move",
                    "true", "false", "unsafe", "extern", "type", "dyn", "Box", "Result",
                    "Option", "Some", "None", "Ok", "Err"]
        case .markdown:
            return []
        case .shell:
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                    "case", "esac", "function", "return", "export", "local", "echo",
                    "set", "unset", "source", "in", "true", "false"]
        case .plain:
            return []
        }
    }
}

@MainActor
final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    private static let keywordColor = NSColor(calibratedRed: 0.78, green: 0.42, blue: 0.93, alpha: 1)
    private static let stringColor = NSColor(calibratedRed: 0.62, green: 0.86, blue: 0.49, alpha: 1)
    private static let numberColor = NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.35, alpha: 1)
    private static let commentColor = NSColor(calibratedWhite: 0.45, alpha: 1)
    private static let typeColor = NSColor(calibratedRed: 0.45, green: 0.78, blue: 0.95, alpha: 1)
    private static let defaultColor = NSColor.white.withAlphaComponent(0.86)
    private static let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static var baseAttributes: [NSAttributedString.Key: Any] {
        return [
            .font: monoFont,
            .foregroundColor: defaultColor
        ]
    }

    func highlight(_ storage: NSMutableAttributedString, language: SyntaxLanguage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        storage.beginEditing()
        storage.setAttributes(SyntaxHighlighter.baseAttributes, range: full)
        defer { storage.endEditing() }

        if language == .plain { return }

        let text = storage.string

        applyCommentPatterns(language: language, text: text, storage: storage, full: full)
        applyStrings(text: text, storage: storage, full: full)
        applyNumbers(text: text, storage: storage, full: full)
        applyKeywords(language: language, text: text, storage: storage, full: full)
        applyTypes(language: language, text: text, storage: storage, full: full)
    }

    private func applyCommentPatterns(
        language: SyntaxLanguage,
        text: String,
        storage: NSMutableAttributedString,
        full: NSRange
    ) {
        var patterns: [String] = []
        switch language {
        case .swift, .javascript, .typescript, .rust:
            patterns = ["//[^\\n]*", "/\\*[\\s\\S]*?\\*/"]
        case .python, .shell:
            patterns = ["#[^\\n]*"]
        case .markdown, .json, .plain:
            patterns = []
        }
        for p in patterns {
            apply(pattern: p, color: SyntaxHighlighter.commentColor, text: text, storage: storage, full: full)
        }
    }

    private func applyStrings(
        text: String,
        storage: NSMutableAttributedString,
        full: NSRange
    ) {
        // Double-quoted, single-quoted, and triple-quoted strings.
        let patterns = [
            "\"(?:\\\\.|[^\"\\\\])*\"",
            "'(?:\\\\.|[^'\\\\])*'",
            "`(?:\\\\.|[^`\\\\])*`"
        ]
        for p in patterns {
            apply(pattern: p, color: SyntaxHighlighter.stringColor, text: text, storage: storage, full: full)
        }
    }

    private func applyNumbers(
        text: String,
        storage: NSMutableAttributedString,
        full: NSRange
    ) {
        apply(
            pattern: "\\b\\d+(?:\\.\\d+)?\\b",
            color: SyntaxHighlighter.numberColor,
            text: text,
            storage: storage,
            full: full
        )
    }

    private func applyKeywords(
        language: SyntaxLanguage,
        text: String,
        storage: NSMutableAttributedString,
        full: NSRange
    ) {
        let kws = language.keywords
        guard !kws.isEmpty else { return }
        let escaped = kws.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = "\\b(?:\(escaped))\\b"
        apply(pattern: pattern, color: SyntaxHighlighter.keywordColor, text: text, storage: storage, full: full)
    }

    private func applyTypes(
        language: SyntaxLanguage,
        text: String,
        storage: NSMutableAttributedString,
        full: NSRange
    ) {
        // Identifiers starting with an uppercase letter — naive but
        // catches type names in Swift, Rust, TS, JS class names.
        guard language != .json && language != .python && language != .shell else { return }
        apply(
            pattern: "\\b[A-Z][A-Za-z0-9_]*\\b",
            color: SyntaxHighlighter.typeColor,
            text: text,
            storage: storage,
            full: full
        )
    }

    private func apply(
        pattern: String,
        color: NSColor,
        text: String,
        storage: NSMutableAttributedString,
        full: NSRange
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            if let r = match?.range {
                storage.addAttribute(.foregroundColor, value: color, range: r)
            }
        }
    }
}
