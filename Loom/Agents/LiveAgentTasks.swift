import Foundation
import Observation
import SwiftUI

enum AgentSource: String, Codable, Hashable {
    case claude
    case codex
    case gemini

    var label: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex:  return "Codex"
        case .gemini: return "Gemini"
        }
    }

    var systemImage: String {
        switch self {
        case .claude: return "sparkles"
        case .codex:  return "chevron.left.forwardslash.chevron.right"
        case .gemini: return "diamond"
        }
    }

    var brandColor: Color {
        switch self {
        case .claude: return Color(red: 0.95, green: 0.39, blue: 0.18)
        case .codex:  return Color(red: 0.23, green: 0.86, blue: 0.46)
        case .gemini: return Color(red: 0.18, green: 0.50, blue: 0.96)
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
    let modelLabel: String?
    let sessionID: String
    let taskID: String
    let subject: String
    let description: String
    let activeForm: String
    let status: LiveAgentTaskStatus
    let updatedAt: Date

    var sourceLabel: String {
        LiveAgentTaskGroup.displayName(source: source, modelLabel: modelLabel)
    }
}

/// One concurrent agent CLI conversation. A user running `claude` in two
/// terminals at once will produce two of these — each gets its own header
/// in the Tasks pane so the user can tell them apart.
struct LiveAgentTaskGroup: Identifiable, Hashable {
    var id: String { "\(source.rawValue):\(modelKey):\(sessionID)" }
    let sessionID: String
    let source: AgentSource
    let modelLabel: String?
    let lastActivity: Date
    let tasks: [LiveAgentTask]

    var displayName: String {
        Self.displayName(source: source, modelLabel: modelLabel)
    }

    private var modelKey: String {
        Self.identityModelKey(modelLabel)
    }

    static func displayName(source: AgentSource, modelLabel: String?) -> String {
        guard let modelLabel = normalizedModelLabel(modelLabel) else {
            return "\(source.label) · Default"
        }
        return "\(source.label) · \(modelLabel)"
    }

    private static func identityModelKey(_ modelLabel: String?) -> String {
        normalizedModelLabel(modelLabel)?
            .lowercased()
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            ?? "default"
    }

    static func normalizedModelLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

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
/// latest plan from each active rollout. Gemini CLI does not currently log
/// plan or task state to disk in any format we can read.
///
/// Clearing a session works for all sources. Claude gets a file-level delete
/// (the live session rewrites on its next turn). Codex/Gemini can't be
/// deleted without losing conversation history, so we record a dismissal
/// timestamp and hide the session until its on-disk activity advances past
/// that mark.
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
    private let claudeProjectsRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }()
    private let codexSessionsRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }()
    private var refreshInFlight: Bool = false

    /// Sessions the user has explicitly cleared, mapped to the `lastActivity`
    /// timestamp at the moment they were cleared. A group stays hidden until
    /// its source emits newer task activity, which means live sessions
    /// naturally reappear on their next plan/task update while truly
    /// stuck/zombie ones stay gone. Used for sources where we can't safely
    /// delete the underlying files (Codex, Gemini) and as a belt-and-suspenders
    /// for Claude.
    private static let dismissedSessionsKey = "loom.tasks.dismissedSessions"
    private var dismissedSessions: [String: Date] = {
        let raw = UserDefaults.standard.dictionary(forKey: LiveAgentTasksService.dismissedSessionsKey)
            as? [String: TimeInterval] ?? [:]
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }()

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
        let claudeProjectsRoot = claudeProjectsRoot
        let codexRoot = codexSessionsRoot
        let cutoff = Date().addingTimeInterval(-activeWindow)
        let dismissed = dismissedSessions
        Task { [weak self] in
            let sorted = await Task.detached(priority: .utility) {
                Self.collectAllGroups(
                    claudeRoot: claudeRoot,
                    claudeProjectsRoot: claudeProjectsRoot,
                    codexRoot: codexRoot,
                    cutoff: cutoff,
                    dismissed: dismissed
                )
            }.value
            guard let self else { return }
            self.refreshInFlight = false
            if sorted != self.groups { self.groups = sorted }
        }
    }

    /// Clear every visible session and refresh. For Claude this deletes the
    /// on-disk task JSON files (the live session will rewrite them on its
    /// next turn, so the clear only "sticks" for crashed/zombie sessions).
    /// For Codex/Gemini we can't delete files without losing conversation
    /// history, so we record a dismissal timestamp; the session stays hidden
    /// until its on-disk activity advances past that mark.
    func clearAll() {
        for group in groups {
            dismiss(group: group)
        }
        saveDismissed()
        refresh()
    }

    /// Clear a single session and refresh. Same per-source semantics as
    /// `clearAll()`: Claude gets a file delete, Codex/Gemini get hidden until
    /// the underlying rollout/session moves forward.
    func clear(group: LiveAgentTaskGroup) {
        dismiss(group: group)
        saveDismissed()
        refresh()
    }

    private func dismiss(group: LiveAgentTaskGroup) {
        if group.source == .claude {
            deleteTaskFiles(for: group)
        }
        dismissedSessions[group.id] = group.lastActivity
    }

    private func saveDismissed() {
        let raw = dismissedSessions.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(raw, forKey: Self.dismissedSessionsKey)
    }

    private func deleteTaskFiles(for group: LiveAgentTaskGroup) {
        guard group.source == .claude else { return }
        let sessionDir = claudeTasksRoot.appendingPathComponent(group.sessionID, isDirectory: true)
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
        claudeProjectsRoot: URL,
        codexRoot: URL,
        cutoff: Date,
        dismissed: [String: Date]
    ) -> [LiveAgentTaskGroup] {
        var collected: [LiveAgentTaskGroup] = []
        collected.append(contentsOf: collectClaudeGroups(
            root: claudeRoot,
            projectsRoot: claudeProjectsRoot,
            cutoff: cutoff
        ))
        collected.append(contentsOf: collectCodexGroups(root: codexRoot, cutoff: cutoff))
        let filtered = collected.filter { group in
            guard let dismissedAt = dismissed[group.id] else { return true }
            return group.lastActivity > dismissedAt
        }
        return filtered.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Claude

    private struct ClaudeSessionRef: Hashable, Sendable {
        let id: String
        let url: URL
        let mostRecentMtime: Date
    }

    nonisolated static func collectClaudeGroups(root: URL, projectsRoot: URL, cutoff: Date) -> [LiveAgentTaskGroup] {
        var collected: [LiveAgentTaskGroup] = []
        let sessions = activeClaudeSessions(root: root, cutoff: cutoff)
        let modelLabels = collectClaudeModelLabels(projectsRoot: projectsRoot, sessionIDs: Set(sessions.map(\.id)))
        for session in sessions {
            let modelLabel = modelLabels[session.id]
            let tasks = readClaudeTasks(in: session, modelLabel: modelLabel)
            guard !tasks.isEmpty else { continue }
            collected.append(LiveAgentTaskGroup(
                sessionID: session.id,
                source: .claude,
                modelLabel: modelLabel,
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

    nonisolated private static func readClaudeTasks(in session: ClaudeSessionRef, modelLabel: String?) -> [LiveAgentTask] {
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
                modelLabel: modelLabel,
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

    private struct ClaudeProjectLine: Decodable {
        struct Message: Decodable {
            let model: String?
        }
        let message: Message?
    }

    nonisolated private static func collectClaudeModelLabels(
        projectsRoot: URL,
        sessionIDs: Set<String>
    ) -> [String: String] {
        guard !sessionIDs.isEmpty else { return [:] }
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsRoot.path) else { return [:] }
        guard let enumerator = fm.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var labels: [String: String] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let sessionID = url.deletingPathExtension().lastPathComponent
            guard sessionIDs.contains(sessionID) else { continue }
            if let model = readLatestClaudeModelLabel(at: url) {
                labels[sessionID] = model
            }
            if labels.count == sessionIDs.count { break }
        }
        return labels
    }

    nonisolated private static func readLatestClaudeModelLabel(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }

        let decoder = JSONDecoder()
        var latest: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("\"model\"") else { continue }
            guard let lineData = String(line).data(using: .utf8),
                  let parsed = try? decoder.decode(ClaudeProjectLine.self, from: lineData),
                  let model = LiveAgentTaskGroup.normalizedModelLabel(parsed.message?.model) else { continue }
            latest = model
        }
        return latest
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
            guard let snapshot = readLatestCodexPlanSnapshot(at: url, fallbackActivity: mtime),
                  !snapshot.plan.isEmpty,
                  snapshot.planActivity >= cutoff else { continue }
            let modelLabel = snapshot.modelLabel

            let tasks: [LiveAgentTask] = snapshot.plan.enumerated().map { index, step in
                let status = mapCodexStatus(step.status)
                return LiveAgentTask(
                    id: "codex:\(sessionID):\(index)",
                    source: .codex,
                    modelLabel: modelLabel,
                    sessionID: sessionID,
                    taskID: String(index),
                    subject: step.step,
                    description: "",
                    activeForm: step.step,
                    status: status,
                    updatedAt: snapshot.planActivity
                )
            }
            guard tasks.contains(where: { $0.status == .pending || $0.status == .inProgress }) else {
                continue
            }
            collected.append(LiveAgentTaskGroup(
                sessionID: sessionID,
                source: .codex,
                modelLabel: modelLabel,
                lastActivity: snapshot.planActivity,
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
            struct CollaborationMode: Decodable {
                struct Settings: Decodable {
                    let model: String?
                }
                let settings: Settings?
            }
            let type: String?
            let name: String?
            let arguments: String?
            let model: String?
            let collaborationMode: CollaborationMode?

            enum CodingKeys: String, CodingKey {
                case type
                case name
                case arguments
                case model
                case collaborationMode = "collaboration_mode"
            }
        }
        let timestamp: String?
        let type: String?
        let payload: Payload?
    }

    private struct CodexPlanArguments: Decodable {
        let plan: [CodexPlanStep]
    }

    private struct CodexPlanStep: Decodable {
        let step: String
        let status: String
    }

    private struct CodexPlanSnapshot {
        let plan: [CodexPlanStep]
        let modelLabel: String?
        let planActivity: Date
    }

    /// Scan a rollout JSONL for `function_call` lines whose `name` is
    /// `update_plan`. Returns the most recent plan, or nil if the rollout
    /// never emitted one.
    nonisolated private static func readLatestCodexPlanSnapshot(
        at url: URL,
        fallbackActivity: Date
    ) -> CodexPlanSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }

        let decoder = JSONDecoder()
        var latest: [CodexPlanStep]?
        var modelLabel: String?
        var planActivity: Date?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("\"update_plan\"") || line.contains("\"turn_context\"") else { continue }
            guard let lineData = String(line).data(using: .utf8) else { continue }
            guard let parsed = try? decoder.decode(CodexPlanLine.self, from: lineData) else { continue }
            if parsed.type == "turn_context" {
                modelLabel = LiveAgentTaskGroup.normalizedModelLabel(
                    parsed.payload?.model ?? parsed.payload?.collaborationMode?.settings?.model
                ) ?? modelLabel
            }

            // Cheap byte-level filter so 99% of lines never touch the JSON
            // decoder. Codex flushes every event in the conversation here,
            // and a long session can be thousands of lines.
            guard line.contains("\"update_plan\"") else { continue }
            guard parsed.payload?.type == "function_call",
                  parsed.payload?.name == "update_plan",
                  let args = parsed.payload?.arguments,
                  let argsData = args.data(using: .utf8) else { continue }
            guard let envelope = try? decoder.decode(CodexPlanArguments.self, from: argsData) else { continue }
            latest = envelope.plan
            planActivity = parseCodexTimestamp(parsed.timestamp) ?? planActivity
        }
        guard let latest else { return nil }
        return CodexPlanSnapshot(
            plan: latest,
            modelLabel: modelLabel,
            planActivity: planActivity ?? fallbackActivity
        )
    }

    nonisolated private static func parseCodexTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }

        let wholeSecond = ISO8601DateFormatter()
        wholeSecond.formatOptions = [.withInternetDateTime]
        return wholeSecond.date(from: raw)
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
