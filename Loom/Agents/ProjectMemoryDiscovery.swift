import Foundation

struct ProjectMemoryDocument: Hashable {
    let name: String
    let url: URL
    let relativePath: String
    let excerpt: String
    let characterCount: Int
}

enum ProjectMemoryDiscovery {
    private static let candidateNames = ["CLAUDE.md", "AGENTS.md", "GUIDE.md", "README.md"]
    private static let candidateLookup = Set(candidateNames.map { $0.lowercased() })
    private static let candidatePriority = Dictionary(
        uniqueKeysWithValues: candidateNames.enumerated().map { ($0.element.lowercased(), $0.offset) }
    )
    private static let ignoredDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg",
        "node_modules", "target", "build", "dist", "DerivedData",
        ".next", ".vercel", ".turbo", ".cache", ".swiftpm",
        ".gradle", ".idea", ".vscode", "__pycache__", ".venv", "venv", ".pytest_cache"
    ]

    static func discover(
        in folderPath: String?,
        maxFiles: Int = 8,
        maxPathComponents: Int = 3
    ) -> [ProjectMemoryDocument] {
        guard let folderPath, !folderPath.isEmpty, maxFiles > 0 else { return [] }
        let root = URL(fileURLWithPath: folderPath).standardizedFileURL
        let fm = FileManager.default
        guard fileExistsDirectory(at: root, fileManager: fm) else { return [] }

        var seen = Set<String>()
        var documents: [ProjectMemoryDocument] = []

        for name in candidateNames {
            guard documents.count < maxFiles else { break }
            appendDocument(at: root.appendingPathComponent(name), root: root, seen: &seen, into: &documents)
        }

        guard documents.count < maxFiles,
              let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return documents
        }

        var nested: [(url: URL, priority: Int, componentCount: Int, relativePath: String)] = []
        for case let url as URL in enumerator {
            let relative = relativePath(for: url, root: root)
            let components = relative.split(separator: "/").count
            let name = url.lastPathComponent
            let lowerName = name.lowercased()
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory {
                if components >= maxPathComponents || shouldSkipDirectory(name) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard components <= maxPathComponents,
                  candidateLookup.contains(lowerName) else { continue }
            let standardPath = url.standardizedFileURL.path
            guard !seen.contains(standardPath) else { continue }
            nested.append((
                url.standardizedFileURL,
                candidatePriority[lowerName] ?? candidateNames.count,
                components,
                relative
            ))
        }

        nested.sort {
            if $0.componentCount != $1.componentCount { return $0.componentCount < $1.componentCount }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }

        for candidate in nested {
            guard documents.count < maxFiles else { break }
            appendDocument(at: candidate.url, root: root, seen: &seen, into: &documents)
        }

        return documents
    }

    static func promptMemory(
        from folderPath: String,
        maxPerFileChars: Int = 1800,
        maxTotalChars: Int = 5000
    ) -> String? {
        let documents = discover(in: folderPath, maxFiles: 8, maxPathComponents: 3)
        guard !documents.isEmpty else { return nil }

        var sections: [String] = []
        var totalLength = 0
        for document in documents {
            guard let raw = try? String(contentsOf: document.url, encoding: .utf8) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let body = truncate(trimmed, max: maxPerFileChars)
            let section = "## \(document.relativePath)\n\n\(body)"
            sections.append(section)
            totalLength += section.count
            if totalLength >= maxTotalChars { break }
        }

        guard !sections.isEmpty else { return nil }
        var joined = sections.joined(separator: "\n\n")
        if joined.count > maxTotalChars {
            let cap = joined.index(joined.startIndex, offsetBy: maxTotalChars)
            joined = String(joined[..<cap]) + "\n\n...(truncated)"
        }
        return joined
    }

    private static func appendDocument(
        at url: URL,
        root: URL,
        seen: inout Set<String>,
        into documents: inout [ProjectMemoryDocument]
    ) {
        let standardURL = url.standardizedFileURL
        let standardPath = standardURL.path
        guard !seen.contains(standardPath),
              candidateLookup.contains(standardURL.lastPathComponent.lowercased()),
              FileManager.default.fileExists(atPath: standardPath),
              let handle = try? FileHandle(forReadingFrom: standardURL) else {
            return
        }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        let raw = String(decoding: data, as: UTF8.self)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        seen.insert(standardPath)
        documents.append(ProjectMemoryDocument(
            name: standardURL.lastPathComponent,
            url: standardURL,
            relativePath: relativePath(for: standardURL, root: root),
            excerpt: truncate(trimmed, max: 420),
            characterCount: fileSize(at: standardURL) ?? trimmed.count
        ))
    }

    private static func fileExistsDirectory(at url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func shouldSkipDirectory(_ name: String) -> Bool {
        ignoredDirectoryNames.contains(name) || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace")
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func fileSize(at url: URL) -> Int? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue
    }

    private static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        let end = text.index(text.startIndex, offsetBy: max)
        return String(text[..<end]) + "..."
    }
}
