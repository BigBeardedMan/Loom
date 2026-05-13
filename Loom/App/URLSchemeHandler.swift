import Foundation
import os

private let urlLog = Logger(subsystem: "com.chasesims.Loom", category: "url-scheme")

extension Notification.Name {
    /// Posted when a `loom://run?prompt=…` URL is opened. Userinfo carries
    /// `prompt`, `workspace` (optional), and `agent` (optional). The active
    /// agent pane subscribes and dispatches the run through the orchestrator.
    static let loomURLAgentRun = Notification.Name("loom.url.agentRun")
}

/// Minimal URL handler for the `loom://` scheme. Today only `loom://run`
/// matters — it kicks off an agent run in the active workspace.
///
/// URL shape:
///   `loom://run?prompt=<encoded>&workspace=<encoded>&agent=<encoded>`
enum URLSchemeHandler {
    struct AgentRunRequest: Sendable {
        let prompt: String
        let workspacePath: String?
        let agentID: String?
    }

    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "loom" else {
            urlLog.error("Ignoring non-loom URL scheme: \(url.scheme ?? "nil", privacy: .public)")
            return
        }
        let host = url.host?.lowercased() ?? ""
        switch host {
        case "run":
            if let request = parseAgentRun(url) {
                NotificationCenter.default.post(
                    name: .loomURLAgentRun,
                    object: nil,
                    userInfo: [
                        "prompt": request.prompt,
                        "workspace": request.workspacePath ?? "",
                        "agent": request.agentID ?? ""
                    ]
                )
            }
        default:
            urlLog.error("Unknown loom:// host: \(host, privacy: .public)")
        }
    }

    private static func parseAgentRun(_ url: URL) -> AgentRunRequest? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        guard let prompt = items.first(where: { $0.name == "prompt" })?.value,
              !prompt.isEmpty else {
            urlLog.error("loom://run missing prompt query item")
            return nil
        }
        let workspace = items.first(where: { $0.name == "workspace" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let agent = items.first(where: { $0.name == "agent" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentRunRequest(
            prompt: prompt,
            workspacePath: (workspace?.isEmpty ?? true) ? nil : workspace,
            agentID: (agent?.isEmpty ?? true) ? nil : agent
        )
    }
}
