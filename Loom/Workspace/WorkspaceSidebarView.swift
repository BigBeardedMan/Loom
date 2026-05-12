import SwiftUI
import SwiftData
import AppKit
import os

private let sidebarLog = Logger(subsystem: "com.chasesims.LoomTestingEdition", category: "sidebar")

struct WorkspaceSidebarView: View {
    @Query(sort: \Workspace.createdAt) private var workspaces: [Workspace]
    @Query(sort: \IdeaNote.createdAt) private var allNotes: [IdeaNote]
    @Environment(\.modelContext) private var context
    @Environment(WorkspaceLayout.self) private var layout

    @Binding var selectedWorkspaceID: UUID?
    @Binding var selectedUsageTool: CLITool?
    @State private var renamingSessionID: UUID?
    @State private var sessionRenameDraft: String = ""
    @State private var renamingNoteID: UUID?
    @State private var clearAllConfirm: ClearAllScope?
    @FocusState private var renameFocused: Bool

    private enum ClearAllScope: Identifiable {
        case terminals, ideas
        var id: Self { self }
    }

    private var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    private var selectedKind: WorkspaceKind {
        selectedWorkspace?.kind ?? .code
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            workspaceSection
            Divider().overlay(LoomTheme.hairline)
            sessionsSection
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .task { seedIfEmpty() }
        .onChange(of: workspaces.map(\.id)) { _, _ in
            ensureSelection()
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: clearAllBinding,
            titleVisibility: .visible,
            presenting: clearAllConfirm
        ) { scope in
            Button("Clear all", role: .destructive) { performClearAll(scope) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    // MARK: - Workspaces

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Workspaces", trailing: { EmptyView() })

            VStack(spacing: 6) {
                ForEach(workspaces) { ws in
                    workspaceRow(ws)
                }
            }
        }
    }

    private func workspaceRow(_ ws: Workspace) -> some View {
        let isSelected = ws.id == selectedWorkspaceID
        let hasFolder = !ws.folderPath.isEmpty

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Circle()
                    .fill(ws.color.color)
                    .frame(width: 9, height: 9)

                Text(ws.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LoomTheme.primaryText)

                Image(systemName: ws.kind.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(LoomTheme.mutedText)
                    .help(ws.kind.label)

                if hasFolder {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(ws.color.color.opacity(0.85))
                        .help(ws.folderPath)
                }

                Spacer()
            }

            if hasFolder {
                Text(ws.displayFolderPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(LoomTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 19)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? ws.color.color.opacity(0.13) : LoomTheme.softPanel.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? ws.color.color.opacity(0.65) : LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if selectedUsageTool != nil {
                selectedUsageTool = nil
                if !isSelected { selectWorkspace(ws) }
                return
            }
            if !isSelected { selectWorkspace(ws) }
        }
        .contextMenu {
            Button(hasFolder ? "Change folder…" : "Set folder…") { chooseFolder(for: ws) }
            if hasFolder {
                Button("Reveal in Finder") { revealInFinder(ws) }
                Button("Clear folder", role: .destructive) { clearFolder(for: ws) }
            }
        }
    }

    private func chooseFolder(for ws: Workspace) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for this workspace"
        if !ws.folderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: ws.folderPath)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ws.folderPath = url.path
        try? context.save()
    }

    private func clearFolder(for ws: Workspace) {
        ws.folderPath = ""
        try? context.save()
    }

    private func revealInFinder(_ ws: Workspace) {
        guard let url = ws.folderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func selectWorkspace(_ ws: Workspace) {
        selectedWorkspaceID = ws.id
        // Picking a workspace always lands on the deck, even if the user was
        // mid-look at a usage dashboard. Without this, the workspace switch
        // happens silently behind the usage overlay and the click feels like
        // a no-op until they remember to toggle the pill off.
        selectedUsageTool = nil
        // Coalesce lastOpenedAt writes during rapid switching so a click
        // doesn't queue a SwiftData save (and the @Query invalidation it
        // triggers) per click. One save once the user settles is plenty for
        // sort order.
        LastOpenedDebouncer.shared.schedule(workspace: ws, context: context)
    }

    // MARK: - Sessions section

    @ViewBuilder
    private var sessionsSection: some View {
        switch selectedKind {
        case .code:
            terminalSessionsSection
        case .ideas:
            ideaSessionsSection
        case .review:
            reviewSessionsSection
        }
    }

    private var terminalBlocks: [WorkspaceBlock] {
        layout.blocks.filter { $0.kind == .terminal }
    }

    private var terminalSessionsSection: some View {
        let sessions = terminalBlocks
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Terminal Sessions", trailing: {
                HStack(spacing: 6) {
                    countBadge(sessions.count)
                    if !sessions.isEmpty {
                        clearAllButton {
                            clearAllConfirm = .terminals
                        }
                    }
                }
            })

            if sessions.isEmpty {
                emptyHint("No terminal blocks open. Use ＋Terminal in the top bar.")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sessions) { block in
                            terminalRow(block)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func terminalRow(_ block: WorkspaceBlock) -> some View {
        let isRenaming = block.id == renamingSessionID

        return HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LoomTheme.green)
                .frame(width: 18)

            if isRenaming {
                TextField("Terminal name", text: $sessionRenameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LoomTheme.primaryText)
                    .focused($renameFocused)
                    .onAppear { renameFocused = true }
                    .onSubmit { commitSessionRename(block) }
                    .onExitCommand { commitSessionRename(block) }
            } else {
                Text(block.displayTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LoomTheme.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if !isRenaming, let cwd = block.terminalSession?.tabLabel {
                Text(cwd)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(LoomTheme.mutedText)
                    .lineLimit(1)
            }

            Button {
                if renamingSessionID == block.id { renamingSessionID = nil }
                layout.removeBlock(block.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LoomTheme.mutedText)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close terminal")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(LoomTheme.softPanel.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(count: 2) { startSessionRename(block) }
        .contextMenu {
            Button("Rename") { startSessionRename(block) }
            if block.customTitle != nil {
                Button("Reset name") { layout.setTitle(block.id, to: nil) }
            }
            Divider()
            Button("Close terminal", role: .destructive) {
                layout.removeBlock(block.id)
            }
        }
    }

    private func startSessionRename(_ block: WorkspaceBlock) {
        sessionRenameDraft = block.displayTitle
        renamingSessionID = block.id
    }

    private func commitSessionRename(_ block: WorkspaceBlock) {
        layout.setTitle(block.id, to: sessionRenameDraft)
        sessionRenameDraft = ""
        renamingSessionID = nil
        renameFocused = false
    }

    // MARK: - Idea sessions

    private var workspaceNotes: [IdeaNote] {
        guard let id = selectedWorkspaceID else { return [] }
        return allNotes
            .filter { $0.workspace?.id == id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var ideaSessionsSection: some View {
        let notes = workspaceNotes
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Ideas", trailing: {
                HStack(spacing: 6) {
                    countBadge(notes.count)
                    if !notes.isEmpty {
                        clearAllButton {
                            clearAllConfirm = .ideas
                        }
                    }
                }
            })

            if notes.isEmpty {
                emptyHint("No ideas yet. Open the Notes block and capture one.")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notes) { note in
                            ideaRow(note)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func ideaRow(_ note: IdeaNote) -> some View {
        let isRenaming = note.id == renamingNoteID

        return HStack(spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LoomTheme.pink)
                .frame(width: 18)

            if isRenaming {
                @Bindable var bindable = note
                TextField("Idea title", text: $bindable.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LoomTheme.primaryText)
                    .focused($renameFocused)
                    .onAppear { renameFocused = true }
                    .onSubmit { commitNoteRename(note) }
                    .onExitCommand { commitNoteRename(note) }
            } else {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LoomTheme.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                deleteNote(note)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LoomTheme.mutedText)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete idea")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(LoomTheme.softPanel.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(count: 2) { startNoteRename(note) }
        .contextMenu {
            Button("Rename") { startNoteRename(note) }
            Divider()
            Button("Delete", role: .destructive) { deleteNote(note) }
        }
    }

    private func startNoteRename(_ note: IdeaNote) {
        renamingNoteID = note.id
    }

    private func commitNoteRename(_ note: IdeaNote) {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        note.title = trimmed.isEmpty ? "Untitled" : trimmed
        note.updatedAt = .now
        try? context.save()
        renamingNoteID = nil
        renameFocused = false
    }

    private func deleteNote(_ note: IdeaNote) {
        if renamingNoteID == note.id { renamingNoteID = nil }
        context.delete(note)
        try? context.save()
    }

    // MARK: - Review sessions (placeholder)

    private var reviewSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Sessions", trailing: { EmptyView() })
            emptyHint("Review workspaces don't have sessions yet.")
        }
    }

    // MARK: - Clear all

    private var clearAllBinding: Binding<Bool> {
        Binding(
            get: { clearAllConfirm != nil },
            set: { if !$0 { clearAllConfirm = nil } }
        )
    }

    private var confirmTitle: String {
        switch clearAllConfirm {
        case .terminals: return "Close all terminals?"
        case .ideas:     return "Delete all ideas in this workspace?"
        case .none:      return ""
        }
    }

    private func performClearAll(_ scope: ClearAllScope) {
        switch scope {
        case .terminals:
            for block in terminalBlocks {
                layout.removeBlock(block.id)
            }
        case .ideas:
            for note in workspaceNotes {
                context.delete(note)
            }
            try? context.save()
        }
        clearAllConfirm = nil
    }

    // MARK: - Section helpers

    private func sectionHeader<Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(LoomTheme.mutedText)
                .tracking(0.6)
            Spacer()
            trailing()
        }
    }

    private func countBadge(_ count: Int) -> some View {
        Text(count.formatted())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(LoomTheme.mutedText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(LoomTheme.softPanel)
            .clipShape(Capsule())
    }

    private func clearAllButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LoomTheme.mutedText)
        }
        .buttonStyle(.plain)
        .help("Clear all")
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(LoomTheme.mutedText)
            .padding(.horizontal, 10)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Mutations

    private func seedIfEmpty() {
        let v08MigrationKey = "loom.workspaceSeed.v0_8"
        let v09MigrationKey = "loom.workspaceSeed.v0_9"
        let v10MigrationKey = "loom.workspaceSeed.v0_10"
        let existing = (try? context.fetch(FetchDescriptor<Workspace>())) ?? []
        var keepers = existing

        // Each migration block runs its mutations, then attempts to save. The
        // UserDefaults migration key is flipped only on a *successful* save —
        // otherwise a write failure (locked store, schema mismatch, disk
        // full) would silently mark the migration "done" and the work would
        // never re-run, leaving the model in a half-migrated state.
        if !UserDefaults.standard.bool(forKey: v08MigrationKey) {
            let legacyDefaultNames: Set<String> = ["Ship", "Review"]
            for ws in existing where legacyDefaultNames.contains(ws.name) {
                let cardCount = ws.boards.flatMap(\.columns).flatMap(\.cards).count
                if cardCount == 0 && ws.notes.isEmpty {
                    context.delete(ws)
                    keepers.removeAll { $0.id == ws.id }
                }
            }
            if commitMigration(key: v08MigrationKey, label: "v0.8 seed cleanup") == false { return }
        }

        if !UserDefaults.standard.bool(forKey: v09MigrationKey) {
            for ws in keepers {
                if ws.kindRaw == "build" {
                    ws.kindRaw = WorkspaceKind.review.rawValue
                    if ws.name == "Build" { ws.name = "Review" }
                }
            }
            if commitMigration(key: v09MigrationKey, label: "v0.9 build → review") == false { return }
        }

        if !UserDefaults.standard.bool(forKey: v10MigrationKey) {
            for ws in keepers where ws.kind == .code && ws.name == "Code" {
                ws.name = "Prompt"
            }
            if commitMigration(key: v10MigrationKey, label: "v0.10 Code → Prompt") == false { return }
        }

        let seeds: [(String, WorkspaceColor, WorkspaceKind)] = [
            ("Prompt", .blue,   .code),
            ("Ideas",  .pink,   .ideas),
            ("Review", .orange, .review)
        ]

        for (name, color, kind) in seeds {
            let alreadyExists = keepers.contains { $0.kind == kind }
            if !alreadyExists {
                let ws = Workspace(name: name, color: color, kind: kind)
                context.insert(ws)
                keepers.append(ws)
            }
        }

        do {
            try context.save()
        } catch {
            sidebarLog.error("Workspace seed save failed: \(error.localizedDescription, privacy: .public)")
        }
        ensureSelection()
    }

    /// Saves the SwiftData context and only sets the migration UserDefaults
    /// key on success. Returns true when the seed flow can continue, false
    /// when the migration failed and we should bail out (so subsequent
    /// migrations aren't blocked by partially-committed state).
    private func commitMigration(key: String, label: String) -> Bool {
        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: key)
            return true
        } catch {
            sidebarLog.error("Migration \(label, privacy: .public) save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func ensureSelection() {
        if let id = selectedWorkspaceID, workspaces.contains(where: { $0.id == id }) { return }
        selectedWorkspaceID = workspaces.first?.id
    }

}

/// Coalesces lastOpenedAt writes during rapid workspace switching so a click
/// only triggers a SwiftData save (and the resulting @Query invalidation) once
/// the user has settled on a workspace for a moment.
@MainActor
private final class LastOpenedDebouncer {
    static let shared = LastOpenedDebouncer()
    private var pending: (workspace: Workspace, context: ModelContext)?
    private var task: Task<Void, Never>?

    func schedule(workspace: Workspace, context: ModelContext) {
        pending = (workspace, context)
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, let pending = self.pending else { return }
            pending.workspace.lastOpenedAt = .now
            try? pending.context.save()
            self.pending = nil
        }
    }
}
