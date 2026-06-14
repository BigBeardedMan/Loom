import Foundation
import Observation

/// Bridge from the active workspace + active tab into the agent pane.
/// Lets the chat know what kind of workspace it's running in (Ideas / Code /
/// Review), what tab the user is currently on (e.g. an `IdeaNote` id), and
/// what to call when the user accepts a proposal card.
///
/// Held as a single root-level `@Observable` so any pane (NotesPaneView,
/// KanbanPaneView, AgentPaneView) can read or publish to the same instance.
@Observable
@MainActor
final class WorkspaceContext {
    enum TabTarget {
        case ideaNote(id: UUID, title: String)
        case none
    }

    /// Lightweight summary of a sibling tab in the active workspace. The agent
    /// gets the title and a short excerpt so it can reason about what's
    /// already been captured without dumping every body in full.
    struct TabSummary: Hashable {
        let title: String
        let excerpt: String
    }

    /// Frozen view of the workspace + tab state at send-time. Built by the
    /// agent pane right before composing a prompt so any text the user has
    /// just typed into the active tab is included.
    struct Snapshot {
        let workspaceName: String
        let workspaceKind: WorkspaceKind
        let folderPath: String?
        let activeTabName: String
        let activeTabBody: String
        let siblingTabs: [TabSummary]
        let projectMemory: String?

        var hasAnyContext: Bool {
            !workspaceName.isEmpty
                || folderPath?.isEmpty == false
                || !activeTabBody.isEmpty
                || !siblingTabs.isEmpty
                || projectMemory?.isEmpty == false
        }
    }

    var workspaceKind: WorkspaceKind = .code
    var workspaceID: UUID?
    var workspaceName: String = ""
    /// Absolute path to the project folder the workspace is bound to. Empty
    /// when the workspace has no folder (e.g. a free-floating Ideas board).
    var folderPath: String = ""
    var activeTab: TabTarget = .none

    /// Append bullets to the body of the currently-focused tab. Bound by
    /// NotesPaneView so the agent pane doesn't need a ModelContext directly.
    var appendToActiveTab: ((_ items: [String]) -> Void)?

    /// Create one new tab per item in the active workspace. For Ideas this
    /// means one new IdeaNote per item.
    var createTabsForItems: ((_ items: [String]) -> Void)?

    /// Read the body of the currently-focused tab. Resolved at send-time so
    /// notes the user typed since the last publish are included in the
    /// agent's context.
    var readActiveTabBody: (() -> String)?

    /// Read summaries for sibling tabs in the active workspace (everything
    /// except the focused tab). Kept short — title + first ~240 chars per
    /// sibling — so the prompt stays compact.
    var readSiblingTabs: (() -> [TabSummary])?

    var activeTabName: String {
        switch activeTab {
        case .ideaNote(_, let title): return title.isEmpty ? "Untitled" : title
        case .none: return "this tab"
        }
    }

    var hasActiveTab: Bool {
        if case .none = activeTab { return false }
        return true
    }

    /// True when this workspace supports tab-based proposals (Ideas only for
    /// now). Other workspace kinds will hide the proposal card.
    var supportsProposals: Bool {
        workspaceKind == .ideas
    }

    /// Capture the current state for prompt composition. Reads project memory
    /// (CLAUDE.md / AGENTS.md / GUIDE.md / README.md, root first and then
    /// shallow project docs) from the workspace folder on demand so the agent
    /// can ground its reply in the project the user is sitting in.
    func snapshot() -> Snapshot {
        let body = readActiveTabBody?() ?? ""
        let siblings = readSiblingTabs?() ?? []
        let memory = Self.loadProjectMemory(from: folderPath)
        return Snapshot(
            workspaceName: workspaceName,
            workspaceKind: workspaceKind,
            folderPath: folderPath.isEmpty ? nil : folderPath,
            activeTabName: activeTabName,
            activeTabBody: body,
            siblingTabs: siblings,
            projectMemory: memory
        )
    }

    private static func loadProjectMemory(from folderPath: String) -> String? {
        guard !folderPath.isEmpty else { return nil }
        return ProjectMemoryDiscovery.promptMemory(from: folderPath)
    }
}
