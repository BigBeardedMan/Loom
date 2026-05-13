import Foundation
import Observation
import SwiftUI

enum AgentSource: String, Codable, Hashable {
    case claude
    case codex
    case gemini
    case lmstudio
    case ollama
    case openAICompatible

    var label: String {
        switch self {
        case .claude:           return "Claude Code"
        case .codex:            return "Codex"
        case .gemini:           return "Gemini"
        case .lmstudio:         return "LM Studio"
        case .ollama:           return "Ollama"
        case .openAICompatible: return "Local"
        }
    }

    var systemImage: String {
        switch self {
        case .claude:           return "sparkles"
        case .codex:            return "chevron.left.forwardslash.chevron.right"
        case .gemini:           return "diamond"
        case .lmstudio:         return "cpu"
        case .ollama:           return "shippingbox"
        case .openAICompatible: return "server.rack"
        }
    }

    var brandColor: Color {
        switch self {
        case .claude:           return Color(red: 0.95, green: 0.39, blue: 0.18)
        case .codex:            return Color(red: 0.23, green: 0.86, blue: 0.46)
        case .gemini:           return Color(red: 0.18, green: 0.50, blue: 0.96)
        case .lmstudio:         return Color(red: 0.62, green: 0.40, blue: 0.95)
        case .ollama:           return Color(red: 0.85, green: 0.85, blue: 0.85)
        case .openAICompatible: return Color(red: 0.55, green: 0.65, blue: 0.75)
        }
    }
}

enum LiveAgentTaskStatus: String, Codable, Hashable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
    case deleted

    var label: String {
        switch self {
        case .pending:    return "Todo"
        case .inProgress: return "In progress"
        case .completed:  return "Done"
        case .cancelled:  return "Cancelled"
        case .deleted:    return "Deleted"
        }
    }

    var sortPriority: Int {
        switch self {
        case .inProgress: return 0
        case .pending:    return 1
        case .completed:  return 2
        case .cancelled:  return 3
        case .deleted:    return 4
        }
    }
}

struct LiveAgentTask: Identifiable, Hashable {
    let id: String          // composite "<source>:<sessionID>:<taskID>"
    let source: AgentSource
    let sessionID: String
    let taskID: String
    let subject: String
    let description: String
    let activeForm: String
    let status: LiveAgentTaskStatus
    let updatedAt: Date
}

/// One concurrent agent CLI conversation. A user running `claude` in two
/// terminals at once will produce two of these — each gets its own header
/// in the Tasks pane so the user can tell them apart.
struct LiveAgentTaskGroup: Identifiable, Hashable {
    var id: String { "\(source.rawValue):\(sessionID)" }
    let sessionID: String
    let source: AgentSource
    let lastActivity: Date
    let tasks: [LiveAgentTask]

    /// Best short label for "what is this session doing" — uses the in-progress
    /// task's activeForm/subject when available, otherwise falls back to the
    /// most recent task. Returns nil if the group has nothing useful to show.
    var headline: String? {
        if let inProgress = tasks.first(where: { $0.status == .inProgress }) {
            let af = inProgress.activeForm.trimmingCharacters(in: .whitespacesAndNewlines)
            return af.isEmpty ? inProgress.subject : af
        }
        return tasks.first?.subject
    }
}

/// Watches per-CLI on-disk task state.
///
/// Claude Code writes per-task JSON files at `~/.claude/tasks/<session>/<id>.json`.
/// Codex emits an `update_plan` function call inside its rollout JSONL at
/// `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`; we surface the
/// latest plan from each active rollout. Our own `lmstudio` CLI mirrors the
/// Claude layout under `~/.loom/tasks/<session>/<id>.json`. Gemini CLI does
/// not currently log plan or task state to disk in any format we can read.
@Observable
@MainActor
final class LiveAgentTasksService {
    var groups: [LiveAgentTaskGroup] = []
    var lastError: String?

    /// Flat list of every task across all groups, kept for callers that just
    /// want a quick "is there anything to show?" check.
    var tasks: [LiveAgentTask] { groups.flatMap(\.tasks) }
    /// Most-recent session id. Compatibility shim for the old single-session
    /// header API.
    var activeSessionID: String? { groups.first?.sessionID }

    private var timer: Timer?
    private let pollInterval: TimeInterval = 2.0
    private let claudeTasksRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/tasks", isDirectory: true)
    }()
    private let codexSessionsRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }()
    private let loomTasksRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".loom/tasks", isDirectory: true)
    }()
    private var refreshInFlight: Bool = false

    /// Sessions older than this are presumed dead — even if they still have
    /// task files on disk, we don't want them to reappear in the pane.
    /// Default is intentionally short: a CLI session that hasn't moved in an
    /// hour is almost always a zombie (crashed, killed, or just abandoned).
    /// Configurable from Settings → Tasks (`loom.tasks.staleHours`).
    private var activeWindow: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "loom.tasks.staleHours")
        let hours = stored > 0 ? stored : 1
        return hours * 60 * 60
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Force a refresh, used after the user types a new prompt so the live
    /// view feels responsive without waiting for the next tick. The walk and
    /// JSON decode runs off the main actor; only the final assignment hops
    /// back. Skips when a refresh is already in flight so a slow disk doesn't
    /// stack up duplicate work.
    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let claudeRoot = claudeTasksRoot
        let codexRoot = codexSessionsRoot
        let loomRoot = loomTasksRoot
        let cutoff = Date().addingTimeInterval(-activeWindow)
        Task { [weak self] in
            let sorted = await Task.detached(priority: .utility) {
                Self.collectAllGroups(
                    claudeRoot: claudeRoot,
                    codexRoot: codexRoot,
                    loomRoot: loomRoot,
                    cutoff: cutoff
                )
            }.value
            guard let self else { return }
            self.refreshInFlight = false
            if sorted != self.groups { self.groups = sorted }
        }
    }

    /// Delete the on-disk task files for every visible Claude session and
    /// refresh. Live Claude sessions will rewrite their files on the next
    /// turn, so this only "sticks" for crashed/zombie sessions. Codex
    /// sessions are skipped: their plan lives inside the same JSONL as the
    /// rest of the conversation, so deleting it would also delete the
    /// session history.
    func clearAll() {
        for group in groups {
            deleteTaskFiles(for: group)
        }
        refresh()
    }

    /// Wipe a single Claude session's task files (the dir stays so the lock
    /// file is undisturbed). For Codex this is a no-op; the UI hides the
    /// per-row × on Codex groups.
    func clear(group: LiveAgentTaskGroup) {
        deleteTaskFiles(for: group)
        refresh()
    }

    private func deleteTaskFiles(for group: LiveAgentTaskGroup) {
        let rootForGroup: URL?
        switch group.source {
        case .claude:   rootForGroup = claudeTasksRoot
        case .lmstudio: rootForGroup = loomTasksRoot
        default:        rootForGroup = nil
        }
        guard let root = rootForGroup else { return }
        let sessionDir = root.appendingPathComponent(group.sessionID, isDirectory: true)
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil, options: [])) ?? []
        for url in entries where url.pathExtension == "json" {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Combined collector

    /// Walk every supported on-disk source and assemble the merged set of
    /// session groups, newest activity first. `nonisolated` so the 2-second
    /// poll can run it on a utility-priority detached task instead of
    /// blocking the main thread on disk I/O and JSON decoding.
    nonisolated static func collectAllGroups(
        claudeRoot: URL,
        codexRoot: URL,
        loomRoot: URL,
        cutoff: Date
    ) -> [LiveAgentTaskGroup] {
        var collected: [LiveAgentTaskGroup] = []
        collected.append(contentsOf: collectClaudeGroups(root: claudeRoot, cutoff: cutoff))
        collected.append(contentsOf: collectCodexGroups(root: codexRoot, cutoff: cutoff))
        collected.append(contentsOf: collectLoomGroups(root: loomRoot, cutoff: cutoff))
        return collected.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Loom (lmstudio CLI)

    /// `~/.loom/tasks/<session>/<id>.json` mirrors the Claude layout exactly,
    /// so we reuse the same scanner and just stamp `source = .lmstudio`. Our
    /// `lmstudio` CLI is the writer.
    nonisolated static func collectLoomGroups(root: URL, cutoff: Date) -> [LiveAgentTaskGroup] {
        var collected: [LiveAgentTaskGroup] = []
        for session in activeClaudeSessions(root: root, cutoff: cutoff) {
            let tasks = readLoomTasks(in: session)
            guard !tasks.isEmpty else { continue }
            collected.append(LiveAgentTaskGroup(
                sessionID: session.id,
                source: .lmstudio,
                lastActivity: session.mostRecentMtime,
                tasks: tasks
            ))
        }
        return collected
    }

    nonisolated private static func readLoomTasks(in session: ClaudeSessionRef) -> [LiveAgentTask] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: session.url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()
        var tasks: [LiveAgentTask] = []
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let payload = try? decoder.decode(ClaudeTaskFile.self, from: data) else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
            let status = LiveAgentTaskStatus(rawValue: payload.status ?? "pending") ?? .pending
            if status == .deleted { continue }
            let composite = "lmstudio:\(session.id):\(payload.id)"
            tasks.append(LiveAgentTask(
                id: composite,
                source: .lmstudio,
                sessionID: session.id,
                taskID: payload.id,
                subject: payload.subject ?? "(no subject)",
                description: payload.description ?? "",
                activeForm: payload.activeForm ?? "",
                status: status,
                updatedAt: mtime
            ))
        }
        return tasks.sorted { lhs, rhs in
            if lhs.status.sortPriority != rhs.status.sortPriority {
                return lhs.status.sortPriority < rhs.status.sortPriority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    // MARK: - Claude

    private struct ClaudeSessionRef: Hashable, Sendable {
        let id: String
        let url: URL
        let mostRecentMtime: Date
    }

    nonisolated static func collectClaudeGroups(root: URL, cutoff: Date) -> [LiveAgentTaskGroup] {
        var collected: [LiveAgentTaskGroup] = []
        for session in activeClaudeSessions(root: root, cutoff: cutoff) {
            let tasks = readClaudeTasks(in: session)
            guard !tasks.isEmpty else { continue }
            collected.append(LiveAgentTaskGroup(
                sessionID: session.id,
                source: .claude,
                lastActivity: session.mostRecentMtime,
                tasks: tasks
            ))
        }
        return collected
    }

    /// All Claude sessions whose latest *task* activity is within the
    /// staleness window, sorted newest-first.
    ///
    /// Deliberately ignores `.lock` and `.highwatermark` mtimes — Claude Code
    /// touches those even on dormant sessions, which would keep long-completed
    /// sessions looking "alive". Only `.json` task-file mtimes count as activity.
    nonisolated private static func activeClaudeSessions(root: URL, cutoff: Date) -> [ClaudeSessionRef] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var refs: [ClaudeSessionRef] = []
        for dir in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let inner = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: []
            )) ?? []
            let jsonFiles = inner.filter { $0.pathExtension == "json" }
            guard !jsonFiles.isEmpty else { continue }
            var mostRecent: Date?
            for url in jsonFiles {
                guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
                if mostRecent == nil || mtime > mostRecent! { mostRecent = mtime }
            }
            guard let mtime = mostRecent, mtime >= cutoff else { continue }
            refs.append(ClaudeSessionRef(id: dir.lastPathComponent, url: dir, mostRecentMtime: mtime))
        }
        return refs.sorted { $0.mostRecentMtime > $1.mostRecentMtime }
    }

    private struct ClaudeTaskFile: Decodable {
        let id: String
        let subject: String?
        let description: String?
        let activeForm: String?
        let status: String?
    }

    nonisolated private static func readClaudeTasks(in session: ClaudeSessionRef) -> [LiveAgentTask] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: session.url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()
        var tasks: [LiveAgentTask] = []
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let payload = try? decoder.decode(ClaudeTaskFile.self, from: data) else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
            let status = LiveAgentTaskStatus(rawValue: payload.status ?? "pending") ?? .pending
            // Hide soft-deleted tasks — the user wouldn't expect to see them.
            if status == .deleted { continue }
            let composite = "claude:\(session.id):\(payload.id)"
            tasks.append(LiveAgentTask(
                id: composite,
                source: .claude,
                sessionID: session.id,
                taskID: payload.id,
                subject: payload.subject ?? "(no subject)",
                description: payload.description ?? "",
                activeForm: payload.activeForm ?? "",
                status: status,
                updatedAt: mtime
            ))
        }
        return tasks.sorted { lhs, rhs in
            if lhs.status.sortPriority != rhs.status.sortPriority {
                return lhs.status.sortPriority < rhs.status.sortPriority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    // MARK: - Codex

    /// Walk `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` and surface the
    /// most recent `update_plan` from each rollout that's been touched
    /// inside the active window.
    nonisolated static func collectCodexGroups(root: URL, cutoff: Date) -> [LiveAgentTaskGroup] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var collected: [LiveAgentTaskGroup] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { continue }
            guard mtime >= cutoff else { continue }

            let sessionID = codexSessionID(from: url)
            guard let plan = readLatestCodexPlan(at: url), !plan.isEmpty else { continue }

            let tasks: [LiveAgentTask] = plan.enumerated().map { index, step in
                let status = mapCodexStatus(step.status)
                return LiveAgentTask(
                    id: "codex:\(sessionID):\(index)",
                    source: .codex,
                    sessionID: sessionID,
                    taskID: String(index),
                    subject: step.step,
                    description: "",
                    activeForm: step.step,
                    status: status,
                    updatedAt: mtime
                )
            }
            collected.append(LiveAgentTaskGroup(
                sessionID: sessionID,
                source: .codex,
                lastActivity: mtime,
                tasks: tasks
            ))
        }
        return collected
    }

    /// Codex rollout filenames look like
    /// `rollout-2026-05-01T18-19-31-019de5a0-286c-7ce0-9585-a33e69923a3c.jsonl`.
    /// The trailing 36 chars before `.jsonl` are the session UUID. Falls
    /// back to the full base name when the pattern doesn't match so we
    /// still produce a stable id rather than an empty string.
    nonisolated private static func codexSessionID(from url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        if base.count >= 36 {
            let candidate = String(base.suffix(36))
            // Lightweight UUID shape check: 8-4-4-4-12.
            let parts = candidate.split(separator: "-")
            if parts.count == 5,
               parts[0].count == 8, parts[1].count == 4, parts[2].count == 4,
               parts[3].count == 4, parts[4].count == 12 {
                return candidate
            }
        }
        return base
    }

    private struct CodexPlanLine: Decodable {
        struct Payload: Decodable {
            let type: String?
            let name: String?
            let arguments: String?
        }
        let payload: Payload?
    }

    private struct CodexPlanArguments: Decodable {
        let plan: [CodexPlanStep]
    }

    private struct CodexPlanStep: Decodable {
        let step: String
        let status: String
    }

    /// Scan a rollout JSONL for `function_call` lines whose `name` is
    /// `update_plan`. Returns the most recent plan, or nil if the rollout
    /// never emitted one.
    nonisolated private static func readLatestCodexPlan(at url: URL) -> [CodexPlanStep]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }

        let decoder = JSONDecoder()
        var latest: [CodexPlanStep]?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // Cheap byte-level filter so 99% of lines never touch the JSON
            // decoder. Codex flushes every event in the conversation here,
            // and a long session can be thousands of lines.
            guard line.contains("\"update_plan\"") else { continue }
            guard let lineData = String(line).data(using: .utf8) else { continue }
            guard let parsed = try? decoder.decode(CodexPlanLine.self, from: lineData) else { continue }
            guard parsed.payload?.type == "function_call",
                  parsed.payload?.name == "update_plan",
                  let args = parsed.payload?.arguments,
                  let argsData = args.data(using: .utf8) else { continue }
            guard let envelope = try? decoder.decode(CodexPlanArguments.self, from: argsData) else { continue }
            latest = envelope.plan
        }
        return latest
    }

    nonisolated private static func mapCodexStatus(_ raw: String) -> LiveAgentTaskStatus {
        switch raw {
        case "in_progress": return .inProgress
        case "completed":   return .completed
        case "cancelled":   return .cancelled
        default:            return .pending
        }
    }
}
