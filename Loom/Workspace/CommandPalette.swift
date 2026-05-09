import SwiftUI
import SwiftData
import AppKit

extension Notification.Name {
    /// Posted by ⌘K from the menu bar so any open WorkspaceView can flip
    /// its sheet state. Going through NotificationCenter avoids hoisting
    /// palette state into LoomApp just to thread a binding back down.
    static let loomOpenPalette = Notification.Name("loom.openPalette")
}

/// Fuzzy-style command palette. Aggregates the most-likely actions from
/// across the app into a single search-and-execute surface so the user
/// rarely has to reach for the mouse: switch workspaces, rerun a command
/// from history, add a block to the current workspace, jump to docs.
struct CommandPalette: View {
    @Environment(WorkspaceLayout.self) private var layout
    @Environment(CommandHistoryService.self) private var history
    @Query(sort: \Workspace.lastOpenedAt, order: .reverse) private var workspaces: [Workspace]

    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            list
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial)
        .onExitCommand { dismiss() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Type a workspace, command, or action…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .onSubmit { runSelected() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSections) { section in
                        sectionHeader(section.title)
                        ForEach(section.items) { item in
                            row(item)
                                .id(item.id)
                        }
                    }
                    if filteredSections.isEmpty {
                        empty
                    }
                }
            }
            .onChange(of: query) { _, _ in
                selectedID = filteredSections.first?.items.first?.id
                if let id = selectedID {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
            .onAppear {
                selectedID = filteredSections.first?.items.first?.id
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text("Nothing matches.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Try a workspace name, a command you've run, or `add `.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func row(_ item: PaletteItem) -> some View {
        Button {
            execute(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(item.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                if selectedID == item.id {
                    Image(systemName: "return")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(selectedID == item.id ? Color.accentColor.opacity(0.18) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { selectedID = item.id }
        }
    }

    // MARK: - Items

    private var filteredSections: [PaletteSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allSections = [
            workspaceSection(),
            recentCommandsSection(),
            addBlockSection(),
            quickActionsSection()
        ]
        if q.isEmpty { return allSections.filter { !$0.items.isEmpty } }
        return allSections.compactMap { section in
            let filtered = section.items.filter { item in
                item.title.lowercased().contains(q)
                || (item.subtitle?.lowercased().contains(q) ?? false)
            }
            return filtered.isEmpty ? nil : PaletteSection(title: section.title, items: filtered)
        }
    }

    private func workspaceSection() -> PaletteSection {
        let items = workspaces.prefix(20).map { ws in
            PaletteItem(
                id: "ws:\(ws.id.uuidString)",
                title: ws.name.isEmpty ? "Untitled" : ws.name,
                subtitle: ws.displayFolderPath.isEmpty ? nil : ws.displayFolderPath,
                systemImage: ws.kind.systemImage,
                tint: ws.color.color,
                action: .switchWorkspace(ws.id)
            )
        }
        return PaletteSection(title: "Workspaces", items: Array(items))
    }

    private func recentCommandsSection() -> PaletteSection {
        let items = history.records.prefix(20).map { record in
            PaletteItem(
                id: "cmd:\(record.id)",
                title: record.command,
                subtitle: shortCwd(record.cwd),
                systemImage: record.succeeded ? "checkmark.circle" : "xmark.circle",
                tint: record.succeeded ? .green : .orange,
                action: .rerunCommand(record.command)
            )
        }
        return PaletteSection(title: "Recent Commands", items: Array(items))
    }

    private func addBlockSection() -> PaletteSection {
        let items = layout.currentKind.availablePanels.map { panel in
            PaletteItem(
                id: "panel:\(panel.rawValue)",
                title: "Add \(panel.label) block",
                subtitle: nil,
                systemImage: panel.systemImage,
                tint: .accentColor,
                action: .addBlock(panel)
            )
        }
        return PaletteSection(title: "Add Block", items: items)
    }

    private func quickActionsSection() -> PaletteSection {
        return PaletteSection(title: "Actions", items: [
            PaletteItem(
                id: "act:settings",
                title: "Open Settings",
                subtitle: nil,
                systemImage: "gearshape",
                tint: .accentColor,
                action: .openSettings
            ),
            PaletteItem(
                id: "act:help",
                title: "Loom Help",
                subtitle: "Open GUIDE.md on GitHub",
                systemImage: "questionmark.circle",
                tint: .accentColor,
                action: .openURL("https://github.com/BigBeardedMan/Loom/blob/main/GUIDE.md")
            ),
            PaletteItem(
                id: "act:repo",
                title: "Open Repo",
                subtitle: "github.com/BigBeardedMan/Loom",
                systemImage: "globe",
                tint: .accentColor,
                action: .openURL("https://github.com/BigBeardedMan/Loom")
            )
        ])
    }

    private func runSelected() {
        guard let id = selectedID,
              let item = filteredSections.flatMap(\.items).first(where: { $0.id == id }) else { return }
        execute(item)
    }

    private func execute(_ item: PaletteItem) {
        switch item.action {
        case .switchWorkspace(let id):
            layout.selectedWorkspaceID = id
        case .rerunCommand(let cmd):
            layout.firstTerminalSession()?.submit(cmd, capture: true)
        case .addBlock(let panel):
            layout.addBlock(panel)
        case .openSettings:
            // SwiftUI's standard openSettings keyboard hits this same path
            // via the macOS app menu; using NSApp keeps the binding clean
            // without needing an Environment hop.
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .openURL(let raw):
            if let url = URL(string: raw) {
                NSWorkspace.shared.open(url)
            }
        }
        dismiss()
    }

    private func dismiss() {
        isPresented = false
    }

    private func shortCwd(_ raw: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if raw == home { return "~" }
        if raw.hasPrefix(home) { return "~" + raw.dropFirst(home.count) }
        return raw
    }
}

private struct PaletteSection: Identifiable {
    let title: String
    let items: [PaletteItem]
    var id: String { title }
}

private struct PaletteItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let action: PaletteAction

    static func == (lhs: PaletteItem, rhs: PaletteItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private enum PaletteAction: Hashable {
    case switchWorkspace(UUID)
    case rerunCommand(String)
    case addBlock(PanelKind)
    case openSettings
    case openURL(String)
}
