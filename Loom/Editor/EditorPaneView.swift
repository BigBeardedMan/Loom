import SwiftUI
import AppKit

struct EditorPaneView: View {
    var rootURL: URL?

    @State private var fileURL: URL?
    @State private var text: String = ""
    @State private var isDirty: Bool = false
    @State private var error: String?
    @State private var loadedAt: Date?
    @State private var diskBaseline: String = ""
    @State private var externalChange: Bool = false
    @State private var watcher: FileWatcher?

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            HStack(spacing: 0) {
                FileTreeView(root: rootURL, selection: $fileURL) { url in
                    load(url: url)
                }
                .frame(width: 220)

                Divider().overlay(Color.white.opacity(0.08))

                if fileURL == nil {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        if externalChange {
                            externalChangeBanner
                        }
                        editor
                    }
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
            }
        }
    }

    private var externalChangeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Color.yellow)
            Text("File changed on disk")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Button("Reload") {
                if let url = fileURL { reload(url: url) }
            }
            .controlSize(.small)
            Button("Keep mine") {
                externalChange = false
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.white.opacity(0.08)),
            alignment: .bottom
        )
    }

    private var paneHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
            Text("Editor")
                .font(.system(size: 12, weight: .medium))

            if let fileURL {
                Text(displayPath(fileURL))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if isDirty {
                Circle()
                    .fill(Color(red: 0.95, green: 0.77, blue: 0.20))
                    .frame(width: 6, height: 6)
            }

            Spacer()

            Button { openViaPanel() } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Open file…")

            Button { save() } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(fileURL == nil || !isDirty)
            .help("Save (⌘S)")

            Button { close() } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .disabled(fileURL == nil)
            .help("Close file")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.18))
        .overlay(Divider().overlay(Color.white.opacity(0.12)), alignment: .bottom)
    }

    private var editor: some View {
        EditorView(text: $text, language: detectLanguage())
            .background(Color(red: 0.035, green: 0.04, blue: 0.045))
            .onChange(of: text) { _, _ in
                if loadedAt != nil { isDirty = true }
            }
    }

    private func detectLanguage() -> SyntaxLanguage {
        guard let url = fileURL else { return .plain }
        return SyntaxLanguage.detect(forExtension: url.pathExtension)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(rootURL == nil ? "No folder bound" : "Pick a file from the tree")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if rootURL == nil {
                Button("Open File…") { openViaPanel() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.04, blue: 0.045))
    }

    // MARK: - File operations

    private func openViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Open a text or source file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    private func load(url: URL) {
        guard !isBinary(url) else {
            error = "Binary files aren't supported in the editor yet."
            return
        }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            text = contents
            fileURL = url
            isDirty = false
            error = nil
            loadedAt = .now
            diskBaseline = contents
            externalChange = false
            startWatching(url: url)
        } catch {
            self.error = "Couldn't read file: \(error.localizedDescription)"
        }
    }

    private func reload(url: URL) {
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            text = contents
            diskBaseline = contents
            isDirty = false
            externalChange = false
        } catch {
            self.error = "Couldn't reload: \(error.localizedDescription)"
        }
    }

    private func startWatching(url: URL) {
        let w = FileWatcher {
            handleFileEvent(url: url)
        }
        w.watch(url: url)
        watcher = w
    }

    private func handleFileEvent(url: URL) {
        guard let onDisk = try? String(contentsOf: url, encoding: .utf8) else { return }
        if onDisk == diskBaseline || onDisk == text { return }
        if isDirty {
            externalChange = true
        } else {
            text = onDisk
            diskBaseline = onDisk
            externalChange = false
        }
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            error = nil
            diskBaseline = text
            externalChange = false
        } catch {
            self.error = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func close() {
        watcher?.stop()
        watcher = nil
        fileURL = nil
        text = ""
        isDirty = false
        loadedAt = nil
        error = nil
        diskBaseline = ""
        externalChange = false
    }

    private func displayPath(_ url: URL) -> String {
        if let rootURL, url.path.hasPrefix(rootURL.path) {
            let suffix = url.path.dropFirst(rootURL.path.count)
            return rootURL.lastPathComponent + suffix
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func isBinary(_ url: URL) -> Bool {
        let binaryExts: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "heic", "icns",
            "pdf", "zip", "tar", "gz", "dmg", "app",
            "mp3", "mp4", "mov", "wav", "flac",
            "ttf", "otf", "woff", "woff2",
            "sqlite", "db", "store", "data"
        ]
        return binaryExts.contains(url.pathExtension.lowercased())
    }
}
