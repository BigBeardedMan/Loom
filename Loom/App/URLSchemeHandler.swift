import Foundation
import os

private let urlLog = Logger(subsystem: "com.chasesims.Loom", category: "url-scheme")

extension Notification.Name {
    /// Posted when a `loom://run?prompt=...` URL is opened. Userinfo carries
    /// `prompt` and `agent` (optional). The active agent pane turns it into a
    /// pending request and asks the user before dispatching it.
    static let loomURLAgentRun = Notification.Name("loom.url.agentRun")
}

/// Minimal URL handler for the `loom://` scheme. Today only `loom://run`
/// matters. It never executes directly; the agent pane must confirm first.
///
/// URL shape:
///   `loom://run?prompt=<encoded>&agent=<encoded>`
enum URLSchemeHandler {
    struct AgentRunRequest: Sendable {
        let prompt: String
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
        if items.contains(where: { $0.name == "workspace" }) {
            urlLog.info("Ignoring workspace query item in loom://run")
        }
        let agent = items.first(where: { $0.name == "agent" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentRunRequest(
            prompt: prompt,
            agentID: (agent?.isEmpty ?? true) ? nil : agent
        )
    }
}
