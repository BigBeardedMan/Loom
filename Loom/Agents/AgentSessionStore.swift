import Foundation
import Observation

@Observable
@MainActor
final class AgentSessionStore {
    struct SessionSummary: Identifiable, Codable, Hashable {
        let id: UUID
        var title: String
        var workspaceKey: String
        var workspaceName: String
        var modelLabel: String?
        var updatedAt: Date
        var messageCount: Int
        var compactedCount: Int
        var lastPreview: String
        var finalStatus: String?
        var changedFiles: [String]?
        var verificationSummary: String?
    }

    struct CLISessionSummary: Identifiable, Hashable {
        let id: String
        let path: URL
        let title: String
        let workspacePath: String
        let modelLabel: String?
        let savedAt: Date
        let messageCount: Int
        let preview: String
    }

    private struct StoredRecord: Codable {
        var summary: SessionSummary
        var messages: [StoredMessage]
    }

    private struct StoredMessage: Codable {
        var role: String
        var text: String
        var createdAt: Date
    }

    private struct CLISessionPayload: Decodable {
        var saved_at: String?
        var model: String?
        var workspace: String?
        var session_id: String?
        var transcript: [CLIMessage]?
    }

    private struct CLIMessage: Decodable {
        var role: String?
        var content: String?
    }

    var summaries: [SessionSummary] = []
    var cliSessions: [CLISessionSummary] = []
    var currentSessionID: UUID?

    private let root: URL
    private let cliRoot: URL

    init() {
        root = UpdateService.appSupportRoot.appendingPathComponent("lmstudio-agent-sessions", isDirectory: true)
        cliRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".loom/sessions", isDirectory: true)
    }

    static func workspaceKey(workspaceID: UUID?, folderPath: String, workspaceName: String) -> String {
        if let workspaceID {
            return workspaceID.uuidString
        }
        let fallback = folderPath.isEmpty ? workspaceName : folderPath
        guard !fallback.isEmpty else { return "global" }
        return Data(fallback.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    func load(workspaceKey: String, workspacePath: String?) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []
        summaries = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let record = try? JSONDecoder().decode(StoredRecord.self, from: data),
                      record.summary.workspaceKey == workspaceKey else {
                    return nil
                }
                return record.summary
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        if let currentSessionID,
           !summaries.contains(where: { $0.id == currentSessionID }) {
            self.currentSessionID = nil
        }
        refreshCLISessions(workspacePath: workspacePath)
    }

    func startNew() {
        currentSessionID = nil
    }

    func save(
        messages: [AgentMessage],
        workspaceKey: String,
        workspaceName: String,
        workspacePath: String?,
        modelLabel: String?,
        compactedCount: Int,
        finalStatus: String? = nil,
        changedFiles: [String] = [],
        verificationSummary: String? = nil
    ) {
        let storable = messages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { message in
                StoredMessage(
                    role: roleString(message.role),
                    text: message.text,
                    createdAt: Date()
                )
            }
        guard !storable.isEmpty else { return }

        let id = currentSessionID ?? UUID()
        currentSessionID = id
        let existing = loadRecord(id: id)
        let title = existing?.summary.title ?? makeTitle(from: messages)
        let preview = messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = SessionSummary(
            id: id,
            title: title,
            workspaceKey: workspaceKey,
            workspaceName: workspaceName,
            modelLabel: modelLabel,
            updatedAt: Date(),
            messageCount: storable.count,
            compactedCount: compactedCount,
            lastPreview: String(preview.prefix(180)),
            finalStatus: finalStatus,
            changedFiles: changedFiles,
            verificationSummary: verificationSummary
        )
        persist(StoredRecord(summary: summary, messages: storable))
        load(workspaceKey: workspaceKey, workspacePath: workspacePath)
    }

    func resume(_ summary: SessionSummary) -> [AgentMessage] {
        guard let record = loadRecord(id: summary.id) else { return [] }
        currentSessionID = summary.id
        return record.messages.map { stored in
            AgentMessage(role: role(from: stored.role), text: stored.text)
        }
    }

    func renameCurrent(to title: String, workspaceKey: String, workspacePath: String?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let id = currentSessionID,
              var record = loadRecord(id: id) else {
            return
        }
        record.summary.title = trimmed
        record.summary.updatedAt = Date()
        persist(record)
        load(workspaceKey: workspaceKey, workspacePath: workspacePath)
    }

    func deleteCurrent(workspaceKey: String, workspacePath: String?) {
        guard let id = currentSessionID else { return }
        try? FileManager.default.removeItem(at: url(for: id))
        currentSessionID = nil
        load(workspaceKey: workspaceKey, workspacePath: workspacePath)
    }

    func delete(_ summary: SessionSummary, workspaceKey: String, workspacePath: String?) {
        try? FileManager.default.removeItem(at: url(for: summary.id))
        if currentSessionID == summary.id {
            currentSessionID = nil
        }
        load(workspaceKey: workspaceKey, workspacePath: workspacePath)
    }

    func resumeCLI(_ summary: CLISessionSummary) -> [AgentMessage] {
        guard let payload = loadCLIPayload(from: summary.path),
              let transcript = payload.transcript else {
            return []
        }
        currentSessionID = nil
        return transcript.compactMap { message in
            guard let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                return nil
            }
            return AgentMessage(role: role(from: message.role ?? "system"), text: content)
        }
    }

    private func persist(_ record: StoredRecord) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url(for: record.summary.id), options: .atomic)
    }

    private func loadRecord(id: UUID) -> StoredRecord? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? JSONDecoder().decode(StoredRecord.self, from: data)
    }

    private func url(for id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func refreshCLISessions(workspacePath: String?) {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: cliRoot,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let normalizedWorkspace = workspacePath.flatMap { URL(fileURLWithPath: $0).standardizedFileURL.path }
        cliSessions = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> CLISessionSummary? in
                guard let payload = loadCLIPayload(from: url) else { return nil }
                let workspace = payload.workspace ?? ""
                if let normalizedWorkspace,
                   !workspace.isEmpty,
                   URL(fileURLWithPath: workspace).standardizedFileURL.path != normalizedWorkspace {
                    return nil
                }
                let transcript = payload.transcript ?? []
                let preview = transcript.reversed().compactMap(\.content).first ?? ""
                let title = transcript.first(where: { $0.role == "user" })?.content
                    ?? url.deletingPathExtension().lastPathComponent
                return CLISessionSummary(
                    id: url.path,
                    path: url,
                    title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(56)),
                    workspacePath: workspace,
                    modelLabel: payload.model,
                    savedAt: date(from: payload.saved_at) ?? modificationDate(for: url),
                    messageCount: transcript.count,
                    preview: String(preview.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
                )
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    private func loadCLIPayload(from url: URL) -> CLISessionPayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CLISessionPayload.self, from: data)
    }

    private func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? Date.distantPast
    }

    private func date(from raw: String?) -> Date? {
        guard let raw else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    private func makeTitle(from messages: [AgentMessage]) -> String {
        let firstUser = messages.first { $0.role == .user }?.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = firstUser?.isEmpty == false ? firstUser! : "LM Studio Session"
        return String(title.prefix(56))
    }

    private func roleString(_ role: AgentMessage.Role) -> String {
        switch role {
        case .user:      return "user"
        case .assistant: return "assistant"
        case .system:    return "system"
        }
    }

    private func role(from raw: String) -> AgentMessage.Role {
        switch raw.lowercased() {
        case "user":      return .user
        case "assistant": return .assistant
        default:          return .system
        }
    }
}
