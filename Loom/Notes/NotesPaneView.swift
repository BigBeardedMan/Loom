import SwiftUI
import SwiftData

struct NotesPaneView: View {
    @Environment(\.modelContext) private var context
    @Environment(WorkspaceContext.self) private var workspaceContext
    @Query(sort: \IdeaNote.createdAt) private var allNotes: [IdeaNote]

    var workspaceID: UUID?

    @State private var selectedNoteID: UUID?
    @State private var renamingID: UUID?
    @FocusState private var renameFocused: Bool

    private var notes: [IdeaNote] {
        guard let workspaceID else { return [] }
        return allNotes.filter { $0.workspace?.id == workspaceID }
    }

    private var selectedNote: IdeaNote? {
        notes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip

            if let note = selectedNote {
                editor(for: note)
            } else {
                emptyState
            }
        }
        .background(Color(red: 0.035, green: 0.04, blue: 0.045))
        .onAppear {
            ensureSelection()
            publishContext()
        }
        .onDisappear { clearPublishedContext() }
        .onChange(of: workspaceID) { _, _ in
            selectedNoteID = nil
            ensureSelection()
            publishContext()
        }
        .onChange(of: notes.map(\.id)) { _, _ in
            ensureSelection()
            publishContext()
        }
        .onChange(of: selectedNoteID) { _, _ in publishContext() }
        .onChange(of: selectedNote?.title) { _, _ in publishContext() }
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(notes) { note in
                        tabChip(note)
                    }
                }
                .padding(.horizontal, 6)
            }

            Button {
                addNote()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
            .help("New idea")
            .padding(.trailing, 8)
        }
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.32))
        .overlay(Divider().overlay(Color.white.opacity(0.10)), alignment: .bottom)
    }

    private func tabChip(_ note: IdeaNote) -> some View {
        let active = note.id == selectedNoteID
        let isRenaming = note.id == renamingID

        return HStack(spacing: 6) {
            Image(systemName: "lightbulb")
                .font(.system(size: 10))
                .foregroundStyle(active ? Color(red: 0.96, green: 0.77, blue: 0.20) : Color.white.opacity(0.45))

            if isRenaming {
                @Bindable var note = note
                TextField("Title", text: $note.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 140)
                    .focused($renameFocused)
                    .onAppear { renameFocused = true }
                    .onSubmit { commitRename(note) }
                    .onExitCommand { commitRename(note) }
            } else {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.6))
                    .lineLimit(1)
            }

            Button {
                deleteNote(note)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(active ? 0.7 : 0.35))
            }
            .buttonStyle(.plain)
            .help("Delete idea")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? Color.white.opacity(0.10) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(active ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(count: 2) { startRename(note) }
        .onTapGesture {
            if active && !isRenaming {
                startRename(note)
            } else {
                selectedNoteID = note.id
            }
        }
        .contextMenu {
            Button("Rename") { startRename(note) }
            Divider()
            Button("Delete", role: .destructive) { deleteNote(note) }
        }
    }

    // MARK: - Editor

    private func editor(for note: IdeaNote) -> some View {
        @Bindable var note = note

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Idea title", text: $note.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .onChange(of: note.title) { _, _ in note.updatedAt = .now; try? context.save() }

                Spacer()

                Text(timestamp(note))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            TextEditor(text: $note.body)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .foregroundStyle(Color.white.opacity(0.86))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .background(Color(red: 0.035, green: 0.04, blue: 0.045))
                .onChange(of: note.body) { _, _ in note.updatedAt = .now; try? context.save() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No ideas yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Button("Capture an idea") { addNote() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func ensureSelection() {
        if let id = selectedNoteID, notes.contains(where: { $0.id == id }) { return }
        selectedNoteID = notes.first?.id
    }

    private func addNote() {
        guard let workspaceID,
              let workspace = try? context.fetch(FetchDescriptor<Workspace>(predicate: #Predicate { $0.id == workspaceID })).first
        else { return }
        let note = IdeaNote(title: "Untitled", workspace: workspace)
        context.insert(note)
        try? context.save()
        selectedNoteID = note.id
        renamingID = note.id
    }

    private func deleteNote(_ note: IdeaNote) {
        if selectedNoteID == note.id { selectedNoteID = nil }
        context.delete(note)
        try? context.save()
        ensureSelection()
    }

    private func startRename(_ note: IdeaNote) {
        renamingID = note.id
    }

    private func commitRename(_ note: IdeaNote) {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        note.title = trimmed.isEmpty ? "Untitled" : trimmed
        try? context.save()
        renamingID = nil
        renameFocused = false
    }

    private func timestamp(_ note: IdeaNote) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "edited " + formatter.localizedString(for: note.updatedAt, relativeTo: .now)
    }

    // MARK: - Workspace context bridge

    /// Publish the active note + commit closures to `WorkspaceContext` so the
    /// agent pane knows what tab the user is in and how to write to it. The
    /// body + sibling readers resolve at send-time so the agent always sees
    /// the freshest copy of what the user has typed before pressing send.
    private func publishContext() {
        if let note = selectedNote {
            workspaceContext.activeTab = .ideaNote(id: note.id, title: note.title)
        } else {
            workspaceContext.activeTab = .none
        }
        workspaceContext.appendToActiveTab = { items in
            appendItemsToActiveNote(items)
        }
        workspaceContext.createTabsForItems = { items in
            createNoteTabsForItems(items)
        }
        workspaceContext.readActiveTabBody = {
            selectedNote?.body ?? ""
        }
        workspaceContext.readSiblingTabs = {
            let activeID = selectedNote?.id
            return notes.compactMap { note in
                guard note.id != activeID else { return nil }
                let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = title.isEmpty ? "Untitled" : title
                return WorkspaceContext.TabSummary(
                    title: displayTitle,
                    excerpt: tabExcerpt(of: note.body)
                )
            }
        }
    }

    private func clearPublishedContext() {
        workspaceContext.activeTab = .none
        workspaceContext.appendToActiveTab = nil
        workspaceContext.createTabsForItems = nil
        workspaceContext.readActiveTabBody = nil
        workspaceContext.readSiblingTabs = nil
    }

    private func tabExcerpt(of body: String, max: Int = 240) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        let cap = trimmed.index(trimmed.startIndex, offsetBy: max)
        return String(trimmed[..<cap]) + "…"
    }

    private func appendItemsToActiveNote(_ items: [String]) {
        guard let note = selectedNote, !items.isEmpty else { return }
        let bullets = items.map { "- \($0)" }.joined(separator: "\n")
        let prefix = note.body.isEmpty || note.body.hasSuffix("\n") ? "" : "\n"
        note.body += prefix + bullets + "\n"
        note.updatedAt = .now
        try? context.save()
    }

    private func createNoteTabsForItems(_ items: [String]) {
        guard let workspaceID,
              let workspace = try? context.fetch(
                FetchDescriptor<Workspace>(predicate: #Predicate { $0.id == workspaceID })
              ).first
        else { return }
        var firstNew: IdeaNote?
        for item in items {
            let note = IdeaNote(title: item, workspace: workspace)
            context.insert(note)
            if firstNew == nil { firstNew = note }
        }
        try? context.save()
        if let firstNew {
            selectedNoteID = firstNew.id
        }
    }
}
