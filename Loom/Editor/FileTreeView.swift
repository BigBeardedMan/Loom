import SwiftUI

/// Process-wide cache of built file trees keyed by root path. Surviving
/// workspace switches means clicking back to a previously-visited workspace
/// shows the tree instantly while a refresh runs in the background, instead
/// of dropping to a ProgressView during the 6-deep filesystem walk.
///
/// Bounded by `maxEntries` and evicted LRU. The previous implementation
/// grew the cache forever — every unique workspace root ever visited stayed
/// resident for the app's lifetime.
@MainActor
private final class FileTreeCache {
    static let shared = FileTreeCache()
    private static let maxEntries = 16

    private var nodes: [String: FSNode] = [:]
    /// MRU at the end. Evictions trim from the front.
    private var order: [String] = []

    func node(for url: URL) -> FSNode? {
        let key = url.path
        guard let node = nodes[key] else { return nil }
        touch(key)
        return node
    }

    func store(_ node: FSNode, for url: URL) {
        let key = url.path
        nodes[key] = node
        touch(key)
        evictIfNeeded()
    }

    private func touch(_ key: String) {
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
        }
        order.append(key)
    }

    private func evictIfNeeded() {
        while order.count > Self.maxEntries {
            let dropped = order.removeFirst()
            nodes.removeValue(forKey: dropped)
        }
    }
}

struct FileTreeView: View {
    var root: URL?
    @Binding var selection: URL?
    var onOpen: (URL) -> Void

    @State private var rootNode: FSNode?
    @State private var expanded: Set<String> = []
    @State private var lastBuiltRoot: URL?

    var body: some View {
        VStack(spacing: 0) {
            header

            if root != nil {
                if let rootNode {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            if let children = rootNode.children {
                                ForEach(children) { child in
                                    FileTreeRow(
                                        node: child,
                                        depth: 0,
                                        expanded: $expanded,
                                        selection: $selection,
                                        onOpen: onOpen
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyState
            }
        }
        .background(Color.black.opacity(0.20))
        .onAppear { adoptOrRefresh() }
        .onChange(of: root) { _, _ in adoptOrRefresh() }
    }

    /// Show whatever is in the cache for this root immediately, then refresh
    /// in the background. First-time visits still show ProgressView while the
    /// initial walk runs.
    private func adoptOrRefresh() {
        guard let root else {
            rootNode = nil
            expanded.removeAll()
            lastBuiltRoot = nil
            return
        }
        if root != lastBuiltRoot {
            rootNode = FileTreeCache.shared.node(for: root)
            lastBuiltRoot = root
        }
        refreshIfNeeded(force: true)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(rootName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                refreshIfNeeded(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Refresh tree")
            .disabled(root == nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.32))
        .overlay(Divider().overlay(Color.white.opacity(0.08)), alignment: .bottom)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("No folder bound")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Set the workspace folder in the sidebar.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private var rootName: String {
        guard let root else { return "—" }
        return root.lastPathComponent
    }

    private func refreshIfNeeded(force: Bool = false) {
        guard let root else {
            rootNode = nil
            expanded.removeAll()
            lastBuiltRoot = nil
            return
        }
        if !force, lastBuiltRoot == root, rootNode != nil { return }
        let captured = root
        Task.detached(priority: .userInitiated) {
            let node = FSNode.walk(captured)
            await MainActor.run {
                FileTreeCache.shared.store(node, for: captured)
                if root == captured {
                    rootNode = node
                    lastBuiltRoot = captured
                }
            }
        }
    }
}

struct FileTreeRow: View {
    let node: FSNode
    let depth: Int
    @Binding var expanded: Set<String>
    @Binding var selection: URL?
    let onOpen: (URL) -> Void

    var body: some View {
        if node.isDirectory {
            directoryGroup
        } else {
            fileRow
        }
    }

    private var directoryGroup: some View {
        let isExpanded = expanded.contains(node.id)
        return VStack(alignment: .leading, spacing: 1) {
            Button {
                toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: 10)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.18, green: 0.50, blue: 0.96))
                    Text(node.name)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(depth) * 12 + 6)
                .padding(.trailing, 8)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileTreeRow(
                        node: child,
                        depth: depth + 1,
                        expanded: $expanded,
                        selection: $selection,
                        onOpen: onOpen
                    )
                }
            }
        }
    }

    private var fileRow: some View {
        let selected = selection == node.url
        return Button {
            selection = node.url
            onOpen(node.url)
        } label: {
            HStack(spacing: 4) {
                Color.clear.frame(width: 10)
                Image(systemName: iconName(for: node.url))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.78))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 12 + 6)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(selected ? Color.accentColor.opacity(0.30) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle() {
        if expanded.contains(node.id) {
            expanded.remove(node.id)
        } else {
            expanded.insert(node.id)
        }
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "swift":            return "swift"
        case "md", "markdown":   return "doc.richtext"
        case "json", "yml", "yaml", "toml": return "curlybraces"
        case "js", "ts", "tsx", "jsx", "mjs", "cjs": return "chevron.left.forwardslash.chevron.right"
        case "py":               return "chevron.left.forwardslash.chevron.right"
        case "rs", "go", "c", "cpp", "h", "hpp": return "chevron.left.forwardslash.chevron.right"
        case "txt":              return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "pdf":              return "doc.fill"
        case "sh", "zsh", "bash":return "terminal"
        case "lock":             return "lock.doc"
        default:                 return "doc"
        }
    }
}
