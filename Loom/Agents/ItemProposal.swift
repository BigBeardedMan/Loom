import Foundation

/// One item the agent has proposed to add to the user's active workspace tab.
/// Created by either the Anthropic `propose_items` tool or the fallback list
/// parser; rendered as a checkbox row in `ProposalCard`.
struct ItemProposal: Identifiable, Hashable {
    let id: UUID
    var text: String
    var accepted: Bool

    init(id: UUID = UUID(), text: String, accepted: Bool = true) {
        self.id = id
        self.text = text
        self.accepted = accepted
    }
}

/// What the user wants to do with the accepted items.
enum ProposalMode: String, CaseIterable, Identifiable {
    case createNewTabs
    case appendToActive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .createNewTabs:  return "Create as new tabs"
        case .appendToActive: return "Append to active tab"
        }
    }
}
