import Foundation
import SwiftData
import SwiftUI

enum WorkspaceColor: String, CaseIterable, Codable, Identifiable {
    case orange, green, blue, pink, yellow, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .orange: return Color(red: 0.95, green: 0.39, blue: 0.18)
        case .green:  return Color(red: 0.23, green: 0.86, blue: 0.46)
        case .blue:   return Color(red: 0.18, green: 0.50, blue: 0.96)
        case .pink:   return Color(red: 0.95, green: 0.20, blue: 0.55)
        case .yellow: return Color(red: 0.96, green: 0.77, blue: 0.20)
        case .purple: return Color(red: 0.62, green: 0.34, blue: 0.94)
        }
    }
}

enum WorkspaceKind: String, CaseIterable, Codable, Identifiable {
    case code
    case ideas
    case review

    var id: String { rawValue }

    var label: String {
        switch self {
        case .code:   return "Prompt"
        case .ideas:  return "Ideas"
        case .review: return "Review"
        }
    }

    var systemImage: String {
        switch self {
        case .code:   return "text.cursor"
        case .ideas:  return "lightbulb"
        case .review: return "magnifyingglass"
        }
    }

    var availablePanels: [PanelKind] {
        switch self {
        case .code:   return [.terminal, .editor, .tasks, .agent]
        case .ideas:  return [.notes, .agent]
        case .review: return [.preview, .agent]
        }
    }
}

@Model
final class Workspace {
    var id: UUID = UUID()
    var name: String
    var folderPath: String = ""
    var colorName: String = WorkspaceColor.blue.rawValue
    var kindRaw: String = WorkspaceKind.code.rawValue
    var previewURL: String = ""
    var taskBadge: Int = 0
    var lastOpenedAt: Date = Date.now
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \KanbanBoard.workspace)
    var boards: [KanbanBoard] = []

    @Relationship(deleteRule: .cascade, inverse: \IdeaNote.workspace)
    var notes: [IdeaNote] = []

    init(
        name: String,
        folderPath: String = "",
        color: WorkspaceColor = .blue,
        kind: WorkspaceKind = .code,
        previewURL: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.folderPath = folderPath
        self.colorName = color.rawValue
        self.kindRaw = kind.rawValue
        self.previewURL = previewURL
        self.taskBadge = 0
        self.lastOpenedAt = .now
        self.createdAt = .now
    }

    var color: WorkspaceColor {
        WorkspaceColor(rawValue: colorName) ?? .blue
    }

    var kind: WorkspaceKind {
        get {
            // Back-compat: v0.8 used "build" raw value; v0.9+ uses "review".
            if kindRaw == "build" { return .review }
            return WorkspaceKind(rawValue: kindRaw) ?? .code
        }
        set { kindRaw = newValue.rawValue }
    }

    var folderURL: URL? {
        folderPath.isEmpty ? nil : URL(fileURLWithPath: folderPath)
    }

    var displayFolderPath: String {
        guard !folderPath.isEmpty else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if folderPath == home { return "~" }
        if folderPath.hasPrefix(home) { return "~" + folderPath.dropFirst(home.count) }
        return folderPath
    }

}
