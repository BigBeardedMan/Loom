import Foundation

/// Heuristic extractor for "list of items" assistant responses. Used as a
/// fallback for providers that don't support tool-use (Ollama, Claude Code
/// CLI subprocess) so the proposal card still appears for those agents.
///
/// Returns nil when the response isn't list-shaped — in that case the chat
/// renders normally with no card.
enum ListResponseParser {
    /// Match leading bullet (`-`, `*`, `•`) or numbered (`1.`, `2)`) markers.
    private static let markerPattern: String = #"^\s{0,6}(?:[-*•·]|\d{1,3}[\.\)])\s+(.+?)\s*$"#

    static func parse(_ text: String, maxItems: Int = 25, minItems: Int = 3) -> [ItemProposal]? {
        guard !text.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(pattern: markerPattern, options: [.anchorsMatchLines]) else {
            return nil
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        guard matches.count >= minItems else { return nil }

        var seen: Set<String> = []
        var items: [ItemProposal] = []
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let raw = nsText.substring(with: match.range(at: 1))
            let cleaned = clean(raw)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            items.append(ItemProposal(text: cleaned))
            if items.count >= maxItems { break }
        }
        return items.count >= minItems ? items : nil
    }

    /// Strip markdown emphasis and trailing punctuation that show up in
    /// generated lists ("**Idea:** foo." → "foo"). Keeps inline content
    /// readable without trying to be a full markdown parser.
    private static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip bold/italic markers around the whole match.
        while s.hasPrefix("**") && s.hasSuffix("**") && s.count > 4 {
            s = String(s.dropFirst(2).dropLast(2))
        }
        while s.hasPrefix("*") && s.hasSuffix("*") && s.count > 2 {
            s = String(s.dropFirst().dropLast())
        }
        // Remove a leading bold label like "**Title:** rest".
        if let colon = s.firstIndex(of: ":"),
           s.distance(from: s.startIndex, to: colon) < 40 {
            let label = s[..<colon]
            if label.contains("**") {
                let after = s.index(after: colon)
                s = String(s[after...]).trimmingCharacters(in: .whitespaces)
            }
        }
        // Drop a single trailing period if the item is a phrase, not a sentence
        // (i.e. no other terminal punctuation inside).
        if s.hasSuffix(".") {
            let inner = s.dropLast()
            if !inner.contains(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
                s = String(inner)
            }
        }
        return s
    }
}
