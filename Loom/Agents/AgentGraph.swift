import Foundation

enum AgentGraphEventType: String, Codable, Hashable {
    case graphCreated = "graph.created"
    case runStarted = "run.started"
    case runHeartbeat = "run.heartbeat"
    case runStatusChanged = "run.statusChanged"
    case runCompleted = "run.completed"
    case runFailed = "run.failed"
    case runCancelled = "run.cancelled"
    case taskCreated = "task.created"
    case taskUpdated = "task.updated"
    case taskStatusChanged = "task.statusChanged"
    case edgeCreated = "edge.created"
    case spawnRequested = "spawn.requested"
    case spawnStarted = "spawn.started"
    case spawnCompleted = "spawn.completed"
    case spawnFailed = "spawn.failed"
    case toolStarted = "tool.started"
    case toolCompleted = "tool.completed"
    case handoffWritten = "handoff.written"
    case handoffAccepted = "handoff.accepted"
    case handoffRejected = "handoff.rejected"
    case attentionRequested = "attention.requested"
    case andonPaused = "andon.paused"
    case andonResumed = "andon.resumed"
}

struct AgentGraphEvent: Identifiable, Codable, Hashable {
    var id: String { eventID }

    var schemaVersion: Int = 1
    var eventID: String = UUID().uuidString
    var type: AgentGraphEventType
    var occurredAt: Date = Date()
    var rootRunID: String
    var runID: String
    var parentRunID: String?
    var source: String?
    var workspacePath: String?
    var modelLabel: String?
    var permissionMode: String?
    var title: String?
    var summary: String?
    var payload: [String: String] = [:]
}

struct AgentGraphRunSummary: Identifiable, Hashable {
    let id: String
    var title: String
    var status: String
    var lastActivity: Date
    var startedAt: Date?
    var source: String?
    var modelLabel: String?
    var workspacePath: String?
    var ledgerPath: String
    var gitRoot: String?
    var gitBranch: String?
    var gitHead: String?
    var gitDirty: Bool?
    var eventCount: Int
    var toolEventCount: Int
    var taskCount: Int
    var toolNames: [String]
}

enum AgentGraphLedgerError: Error {
    case invalidRootRunID(String)
}

actor AgentGraphLedger {
    static let shared = AgentGraphLedger()

    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL = AgentGraphLedger.defaultRootURL()) {
        self.rootURL = rootURL
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    nonisolated static func defaultRootURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".loom/agent-runs", isDirectory: true)
    }

    func append(_ event: AgentGraphEvent) throws {
        try Self.validateRootRunID(event.rootRunID)
        let dir = rootURL.appendingPathComponent(event.rootRunID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("events.jsonl", isDirectory: false)
        var data = try encoder.encode(event)
        data.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func events(rootRunID: String) throws -> [AgentGraphEvent] {
        try Self.validateRootRunID(rootRunID)
        let url = rootURL
            .appendingPathComponent(rootRunID, isDirectory: true)
            .appendingPathComponent("events.jsonl", isDirectory: false)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n")
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(AgentGraphEvent.self, from: data)
            }
    }

    func summaries() throws -> [AgentGraphRunSummary] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.compactMap { dir -> AgentGraphRunSummary? in
            guard let events = try? events(rootRunID: dir.lastPathComponent), !events.isEmpty else {
                return nil
            }
            let ledgerPath = dir.appendingPathComponent("events.jsonl", isDirectory: false).path
            let sorted = events.sorted { $0.occurredAt < $1.occurredAt }
            guard let latest = sorted.last else { return nil }
            let anchor = sorted.first {
                $0.type == .runStarted || $0.type == .graphCreated
            } ?? sorted.first
            let status = sorted.reversed().compactMap { event -> String? in
                switch event.type {
                case .runCompleted: return "completed"
                case .runFailed: return "failed"
                case .runCancelled: return "cancelled"
                case .runStarted, .runHeartbeat, .runStatusChanged: return event.payload["status"]
                default: return nil
                }
            }.first ?? "running"
            let title = Self.summaryTitle(anchor: anchor, latest: latest)
            let source = anchor?.source ?? latest.source
            let modelLabel = anchor?.modelLabel ?? latest.modelLabel
            let workspacePath = anchor?.workspacePath ?? latest.workspacePath
            let gitRoot = Self.summaryPayloadValue("gitRoot", anchor: anchor, latest: latest)
            let gitBranch = Self.summaryPayloadValue("gitBranch", anchor: anchor, latest: latest)
            let gitHead = Self.summaryPayloadValue("gitHead", anchor: anchor, latest: latest)
            let gitDirty = Self.summaryPayloadValue("gitDirty", anchor: anchor, latest: latest).map {
                $0 == "true"
            }
            let toolNames = Array(Set(events.compactMap { $0.payload["tool"] })).sorted()
            let taskIDs = Set(events.compactMap { $0.payload["taskID"] })
            return AgentGraphRunSummary(
                id: latest.rootRunID,
                title: title,
                status: status,
                lastActivity: latest.occurredAt,
                startedAt: anchor?.occurredAt,
                source: source,
                modelLabel: modelLabel,
                workspacePath: workspacePath,
                ledgerPath: ledgerPath,
                gitRoot: gitRoot,
                gitBranch: gitBranch,
                gitHead: gitHead,
                gitDirty: gitDirty,
                eventCount: events.count,
                toolEventCount: events.filter { $0.type == .toolStarted || $0.type == .toolCompleted }.count,
                taskCount: taskIDs.count,
                toolNames: toolNames
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    private nonisolated static func validateRootRunID(_ rootRunID: String) throws {
        let trimmed = rootRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/\\")
        guard trimmed == rootRunID,
              !trimmed.isEmpty,
              !trimmed.hasPrefix("."),
              rootRunID.rangeOfCharacter(from: forbidden) == nil else {
            throw AgentGraphLedgerError.invalidRootRunID(rootRunID)
        }
    }

    private nonisolated static func summaryTitle(anchor: AgentGraphEvent?, latest: AgentGraphEvent) -> String {
        let candidates = [
            anchor?.payload["prompt"],
            anchor?.summary,
            latest.payload["prompt"],
            latest.summary,
            latest.title,
            latest.rootRunID
        ]
        for candidate in candidates {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return latest.rootRunID
    }

    private nonisolated static func summaryPayloadValue(
        _ key: String,
        anchor: AgentGraphEvent?,
        latest: AgentGraphEvent
    ) -> String? {
        let value = anchor?.payload[key] ?? latest.payload[key]
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum AgentGraphProjection {
    static func taskGroups(from events: [AgentGraphEvent]) -> [LiveAgentTaskGroup] {
        let taskEvents = events.filter { event in
            event.type == .taskCreated || event.type == .taskUpdated || event.type == .taskStatusChanged
        }
        guard !taskEvents.isEmpty else { return [] }

        let tasks = taskEvents.compactMap { event -> LiveAgentTask? in
            guard let taskID = event.payload["taskID"] ?? event.payload["id"] else { return nil }
            let status = LiveAgentTaskStatus(rawValue: event.payload["status"] ?? "pending") ?? .pending
            let source = AgentSource(rawValue: event.source ?? "") ?? .lmstudio
            return LiveAgentTask(
                id: "\(source.rawValue):\(event.runID):\(taskID)",
                source: source,
                modelLabel: event.modelLabel,
                sessionID: event.runID,
                taskID: taskID,
                subject: event.title ?? event.payload["subject"] ?? "Agent task",
                description: event.summary ?? "",
                activeForm: event.payload["activeForm"] ?? event.title ?? "Agent task",
                status: status,
                updatedAt: event.occurredAt
            )
        }

        let latestTasks = Dictionary(grouping: tasks, by: \.id).compactMap { _, snapshots in
            snapshots.max { $0.updatedAt < $1.updatedAt }
        }
        let workspacePathsBySession = Dictionary(grouping: taskEvents, by: \.runID).compactMapValues { events in
            events.sorted { $0.occurredAt > $1.occurredAt }
                .compactMap(\.workspacePath)
                .first { !$0.isEmpty }
        }

        let grouped = Dictionary(grouping: latestTasks, by: \.sessionID)
        return grouped.map { sessionID, tasks in
            let source = tasks.first?.source ?? .lmstudio
            let modelLabel = tasks.first?.modelLabel
            return LiveAgentTaskGroup(
                sessionID: sessionID,
                source: source,
                modelLabel: modelLabel,
                workspacePath: workspacePathsBySession[sessionID],
                lastActivity: tasks.map(\.updatedAt).max() ?? Date(),
                tasks: tasks.sorted {
                    if $0.status.sortPriority != $1.status.sortPriority {
                        return $0.status.sortPriority < $1.status.sortPriority
                    }
                    return $0.updatedAt > $1.updatedAt
                }
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }
}
