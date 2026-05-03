import Foundation

struct FSNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [FSNode]?  // nil = leaf; non-nil = directory (possibly empty)

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    static let skipNames: Set<String> = [
        ".git", ".svn", ".hg", ".DS_Store",
        "node_modules", "DerivedData", "build", ".build", ".swiftpm",
        ".next", ".nuxt", ".cache", "__pycache__", ".venv", "venv",
        ".idea", ".vscode", ".history"
    ]

    static func walk(_ url: URL, depth: Int = 0, maxDepth: Int = 6) -> FSNode {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists else {
            return FSNode(url: url, isDirectory: false, children: nil)
        }

        if !isDir.boolValue {
            return FSNode(url: url, isDirectory: false, children: nil)
        }

        if depth >= maxDepth {
            return FSNode(url: url, isDirectory: true, children: [])
        }

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let options: FileManager.DirectoryEnumerationOptions = []

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            return FSNode(url: url, isDirectory: true, children: [])
        }

        let filtered = contents
            .filter { item in
                let name = item.lastPathComponent
                if name.hasPrefix(".") && !showHidden { return false }
                if skipNames.contains(name) { return false }
                return true
            }
            .map { $0.standardizedFileURL }

        let children = filtered
            .map { FSNode.walk($0, depth: depth + 1, maxDepth: maxDepth) }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        return FSNode(url: url, isDirectory: true, children: children)
    }

    private static let showHidden = false
}
