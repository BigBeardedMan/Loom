import Foundation
import SwiftData

@Model
final class IdeaNote {
    var id: UUID = UUID()
    var title: String
    var body: String = ""
    var workspace: Workspace?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(title: String = "Untitled", workspace: Workspace? = nil) {
        self.id = UUID()
        self.title = title
        self.workspace = workspace
        self.createdAt = .now
        self.updatedAt = .now
    }
}
