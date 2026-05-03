import Foundation
import SwiftData

enum KanbanStatus: String, CaseIterable, Identifiable, Codable {
    case todo
    case inProgress
    case inReview
    case complete
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .complete: return "Complete"
        case .cancelled: return "Cancelled"
        }
    }
}

@Model
final class KanbanBoard {
    var name: String
    var createdAt: Date
    var workspace: Workspace?
    @Relationship(deleteRule: .cascade, inverse: \KanbanColumn.board)
    var columns: [KanbanColumn] = []

    init(name: String, workspace: Workspace? = nil) {
        self.name = name
        self.createdAt = .now
        self.workspace = workspace
    }
}

@Model
final class KanbanColumn {
    var name: String
    var position: Int
    var board: KanbanBoard?
    @Relationship(deleteRule: .cascade, inverse: \KanbanCard.column)
    var cards: [KanbanCard] = []

    init(name: String, position: Int) {
        self.name = name
        self.position = position
    }
}

@Model
final class KanbanCard {
    var id: UUID = UUID()
    var title: String
    var instructions: String = ""
    var taskKnowledge: String = ""
    var statusRaw: String = KanbanStatus.todo.rawValue
    var agentName: String = "Loom Agent"
    var projectPath: String = ""
    var createdAt: Date
    var updatedAt: Date = Date.now
    var column: KanbanColumn?

    init(
        title: String,
        instructions: String = "",
        taskKnowledge: String = "",
        status: KanbanStatus = .todo,
        agentName: String = "Loom Agent",
        projectPath: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.instructions = instructions
        self.taskKnowledge = taskKnowledge
        self.statusRaw = status.rawValue
        self.agentName = agentName
        self.projectPath = projectPath
        self.createdAt = .now
        self.updatedAt = .now
    }

    var status: KanbanStatus {
        get { KanbanStatus(rawValue: statusRaw) ?? .todo }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}
