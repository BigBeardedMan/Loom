import Foundation
import Observation
import SwiftUI

/// CLI agent we know how to read on-disk usage from. Add a case here to
/// surface a new vendor in the Usage view.
enum CLITool: String, CaseIterable, Identifiable, Hashable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex:  return "Codex"
        case .gemini: return "Gemini"
        }
    }

    var shortLabel: String {
        switch self {
        case .claude: return "claude"
        case .codex:  return "codex"
        case .gemini: return "gemini"
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

enum UsageTimeframe: String, CaseIterable, Identifiable, Hashable {
    case day, week, month, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
        }
    }

    /// True rolling window — Day = last 24 hours, Week = last 7 days,
    /// Month = last 30 days, Year = last 365 days.
    var bucketCount: Int {
        switch self {
        case .day:   return 24   // 24 hourly buckets
        case .week:  return 7    // 7 daily buckets
        case .month: return 30   // 30 daily buckets
        case .year:  return 12   // 12 monthly buckets across the last 365 days
        }
    }

    var headlineLabel: String {
        switch self {
        case .day:   return "Last 24 hours"
        case .week:  return "Last 7 days"
        case .month: return "Last 30 days"
        case .year:  return "Last 365 days"
        }
    }

    /// Total span this timeframe covers, used as the lower bound when
    /// scanning logs for project / prompt rollups.
    var totalSpan: TimeInterval {
        switch self {
        case .day:   return 24 * 3600
        case .week:  return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        case .year:  return 365 * 24 * 3600
        }
    }

    /// Build [bucketCount] half-open intervals walking back from `now`.
    /// Oldest bucket first. Day uses hour anchors, week/month use day
    /// anchors aligned to today, year uses month anchors.
    func boundaries(now: Date = .now, calendar: Calendar = .current) -> [BucketBoundary] {
        var cal = calendar
        cal.firstWeekday = 2 // ISO week — Mondays
        let count = bucketCount
        var anchors: [Date] = []
        let unit: Calendar.Component
        switch self {
        case .day:
            unit = .hour
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
            let hourStart = cal.date(from: comps) ?? now
            for offset in (0..<count).reversed() {
                if let d = cal.date(byAdding: .hour, value: -offset, to: hourStart) { anchors.append(d) }
            }
        case .week, .month:
            unit = .day
            let today = cal.startOfDay(for: now)
            for offset in (0..<count).reversed() {
                if let d = cal.date(byAdding: .day, value: -offset, to: today) { anchors.append(d) }
            }
        case .year:
            unit = .month
            let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
            for offset in (0..<count).reversed() {
                if let d = cal.date(byAdding: .month, value: -offset, to: monthStart) { anchors.append(d) }
            }
        }
        return anchors.compactMap { start in
            guard let end = cal.date(byAdding: unit, value: 1, to: start) else { return nil }
            return BucketBoundary(start: start, end: end, label: bucketLabel(for: start, calendar: cal))
        }
    }

    private func bucketLabel(for date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        switch self {
        case .day:   f.dateFormat = "ha"      // "9AM", "10PM"
        case .week:  f.dateFormat = "EEE"     // "Mon", "Tue"
        case .month: f.dateFormat = "M/d"     // "4/15"
        case .year:  f.dateFormat = "MMM"     // "Apr"
        }
        return f.string(from: date).lowercased()
    }
}

struct BucketBoundary: Hashable {
    let start: Date
    let end: Date
    let label: String
}

struct UsageBucket: Identifiable, Hashable {
    let start: Date
    let end: Date
    let tokens: Int
    let label: String

    var id: Date { start }
}

struct ProjectUsage: Hashable, Identifiable {
    let displayName: String
    let path: String
    let sessions: Int
    let lastActivity: Date

    var id: String { path }
}

struct ModelUsage: Hashable, Identifiable {
    let model: String
    let tokens: Int

    var id: String { model }

    /// Trim "claude-" prefix and any "-YYYYMMDD" date suffix so the bigger
    /// labels fit in the legend ("opus-4-7" instead of "claude-opus-4-7-20250515").
    var displayName: String {
        var name = model
        if name.hasPrefix("claude-") { name.removeFirst("claude-".count) }
        if let dash = name.range(of: #"-\d{8}$"#, options: .regularExpression) {
            name.removeSubrange(dash)
        }
        return name
    }
}

struct ProjectTokenSlice: Hashable, Identifiable {
    let displayName: String
    let path: String
    let tokens: Int

    var id: String { path }
}

struct PromptTopic: Hashable, Identifiable {
    let keyword: String
    let count: Int

    var id: String { keyword }
}

struct PromptPreview: Hashable, Identifiable {
    let text: String
    let timestamp: Date
    let project: String

    var id: String { "\(timestamp.timeIntervalSince1970)-\(text.prefix(20))" }
}

struct UsageLimitSnapshot: Hashable {
    let primaryUsedPercent: Double?
    let primaryWindowMinutes: Int?
    let primaryResetsAt: Date?
    let secondaryUsedPercent: Double?
    let secondaryWindowMinutes: Int?
    let secondaryResetsAt: Date?
    let planType: String?
    let credits: Double?
    let reachedType: String?
    let observedAt: Date?
}

struct CLIToolUsage: Identifiable, Hashable {
    let tool: CLITool
    let isInstalled: Bool
    /// Sessions whose log file has been touched within the "live" window.
    let activeSessions: Int
    let sessionsToday: Int
    let sessionsTotal: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let lastActivity: Date?
    let models: [String]
    /// Token totals bucketed for the currently-selected timeframe (oldest → newest).
    /// Empty when the source doesn't expose per-line timestamps.
    let chartBuckets: [UsageBucket]
    /// Top projects by recent session count. Empty for tools that don't
    /// segment by project on disk.
    let topProjects: [ProjectUsage]
    /// Tokens attributed to each model (assistant turns only). Sorted desc.
    let tokensByModel: [ModelUsage]
    /// Top projects by token volume across the current timeframe. Sorted desc.
    let tokensByProject: [ProjectTokenSlice]
    /// Most-used keywords across user prompts in the current timeframe.
    let topTopics: [PromptTopic]
    /// Recent user prompts (newest first). Capped for display.
    let recentPrompts: [PromptPreview]
    /// Tokens by hour-of-day (0..23) across the current timeframe. Shows
    /// when the user actually drives the CLI.
    let hourlyDistribution: [Int]
    /// Total user prompts the CLI received in the current timeframe.
    let promptCount: Int
    /// Locally logged CLI limit snapshot. Only Codex exposes this today.
    let limitSnapshot: UsageLimitSnapshot?

    var id: String { tool.rawValue }

    var totalTokens: Int { inputTokens + outputTokens + cachedTokens }

    static func unavailable(_ tool: CLITool) -> CLIToolUsage {
        CLIToolUsage(
            tool: tool,
            isInstalled: false,
            activeSessions: 0,
            sessionsToday: 0,
            sessionsTotal: 0,
            inputTokens: 0,
            outputTokens: 0,
            cachedTokens: 0,
            lastActivity: nil,
            models: [],
            chartBuckets: [],
            topProjects: [],
            tokensByModel: [],
            tokensByProject: [],
            topTopics: [],
            recentPrompts: [],
            hourlyDistribution: Array(repeating: 0, count: 24),
            promptCount: 0,
            limitSnapshot: nil
        )
    }
}

/// Reads on-disk usage data from local CLI agents.
///
/// Two cadences:
/// - `activeSessionCount` polls every few seconds so the sidebar badge stays
///   live with how many CLI sessions are currently running.
/// - The full per-tool snapshot (token totals, session history) is heavier;
///   it refreshes on `requestRefresh()` and stays cached otherwise.
@Observable
@MainActor
final class UsageService {
    /// How many sessions across all known CLIs were touched within
    /// `liveWindow`. Drives the Prompt-workspace badge.
    var activeSessionCount: Int = 0

    /// Per-tool usage snapshot. Populated on first refresh.
    var tools: [CLIToolUsage] = []

    /// Currently-selected chart timeframe. Drives how the dailyActivity
    /// buckets are aggregated when the snapshot is rebuilt.
    var timeframe: UsageTimeframe = .day {
        didSet {
            guard timeframe != oldValue else { return }
            requestRefresh()
        }
    }

    /// Set once a refresh completes successfully. Lets the UI show "as of …".
    var lastRefreshedAt: Date?

    /// True while a full snapshot is being recomputed. Drives the giant
    /// throbber overlay in UsageView — Year-range refreshes can take ~minute
    /// because each Claude session JSONL gets read in full.
    var isRefreshing: Bool = false

    /// Surfaces I/O failures while reading log directories.
    var lastError: String?

    /// Active = log file touched in the last 5 minutes. CLIs flush to disk on
    /// every assistant turn, so this is a reliable "is somebody actively
    /// chatting" signal without being so tight that it flickers between turns.
    private let liveWindow: TimeInterval = 5 * 60

    private var lightTimer: Timer?
    private let lightPollInterval: TimeInterval = 3.0

    private var refreshTask: Task<Void, Never>?
    /// Bumped on every `requestRefresh()` so a still-running detached snapshot
    /// can detect that a newer request superseded it. `Task.isCancelled` was
    /// unreliable here — the detached body never checkpoints, so the flag
    /// often hadn't propagated by the time the older task tried to write
    /// back its (now-stale) snapshot.
    private var refreshGeneration: Int = 0

    private let claudeProjectsRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }()

    private let codexSessionsRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }()

    private let geminiRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
    }()

    func start() {
        guard lightTimer == nil else { return }
        refreshActiveCountInBackground()
        lightTimer = Timer.scheduledTimer(
            withTimeInterval: lightPollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshActiveCountInBackground() }
        }
    }

    func stop() {
        lightTimer?.invalidate()
        lightTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Recompute the full per-tool snapshot off the main actor.
    func requestRefresh() {
        refreshTask?.cancel()
        refreshGeneration &+= 1
        let myGeneration = refreshGeneration
        let live = liveWindow
        let claudeRoot = claudeProjectsRoot
        let codexRoot = codexSessionsRoot
        let geminiRoot = geminiRoot
        let boundaries = timeframe.boundaries()
        let span = timeframe.totalSpan
        isRefreshing = true
        refreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                Self.computeSnapshot(
                    claudeRoot: claudeRoot,
                    codexRoot: codexRoot,
                    geminiRoot: geminiRoot,
                    liveWindow: live,
                    boundaries: boundaries,
                    timeframeSpan: span
                )
            }.value
            guard let self else { return }
            // A newer refresh has superseded us — don't write back stale
            // tools or flip the spinner off (the newer task still owns it).
            guard myGeneration == self.refreshGeneration else { return }
            self.tools = snapshot
            self.activeSessionCount = snapshot.reduce(0) { $0 + $1.activeSessions }
            self.lastRefreshedAt = .now
            self.isRefreshing = false
        }
    }

    // MARK: - Light path (active count only)

    private func refreshActiveCountInBackground() {
        let live = liveWindow
        let claudeRoot = claudeProjectsRoot
        let codexRoot = codexSessionsRoot
        Task { [weak self] in
            let total = await Task.detached(priority: .utility) {
                let cutoff = Date().addingTimeInterval(-live)
                let claude = Self.countActiveJSONL(in: claudeRoot, cutoff: cutoff, recursive: false)
                let codex  = Self.countActiveJSONL(in: codexRoot,  cutoff: cutoff, recursive: true)
                return claude + codex
            }.value
            guard let self else { return }
            if self.activeSessionCount != total {
                self.activeSessionCount = total
            }
        }
    }

    /// Walk a directory and count `.jsonl` files modified after `cutoff`.
    /// Recursive walks are needed for Codex (sessions are nested by date).
    private nonisolated static func countActiveJSONL(
        in root: URL,
        cutoff: Date,
        recursive: Bool
    ) -> Int {
        let fm = FileManager.default
        var count = 0
        guard fm.fileExists(atPath: root.path) else { return 0 }

        if recursive {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return 0 }
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else { continue }
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                if let mtime, mtime >= cutoff { count += 1 }
            }
        } else {
            // Claude: ~/.claude/projects/<slug>/<id>.jsonl — one level down.
            let projectDirs = (try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for projectDir in projectDirs {
                let inner = (try? fm.contentsOfDirectory(
                    at: projectDir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for url in inner where url.pathExtension == "jsonl" {
                    let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                    if let mtime, mtime >= cutoff { count += 1 }
                }
            }
        }
        return count
    }

    // MARK: - Full snapshot

    private nonisolated static func computeSnapshot(
        claudeRoot: URL,
        codexRoot: URL,
        geminiRoot: URL,
        liveWindow: TimeInterval,
        boundaries: [BucketBoundary],
        timeframeSpan: TimeInterval
    ) -> [CLIToolUsage] {
        let cutoff = Date().addingTimeInterval(-liveWindow)
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let windowStart = Date().addingTimeInterval(-timeframeSpan)

        let claude = readClaudeUsage(
            root: claudeRoot,
            liveCutoff: cutoff,
            startOfToday: startOfToday,
            boundaries: boundaries,
            windowStart: windowStart
        )
        let codex = readCodexUsage(
            root: codexRoot,
            liveCutoff: cutoff,
            startOfToday: startOfToday,
            boundaries: boundaries
        )
        let gemini = readGeminiUsage(root: geminiRoot)
        return [claude, codex, gemini]
    }

    // MARK: - Claude reader

    private nonisolated static func readClaudeUsage(
        root: URL,
        liveCutoff: Date,
        startOfToday: Date,
        boundaries: [BucketBoundary],
        windowStart: Date
    ) -> CLIToolUsage {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else {
            return .unavailable(.claude)
        }

        var sessionsTotal = 0
        var sessionsToday = 0
        var activeSessions = 0
        var inputTokens = 0
        var outputTokens = 0
        var cachedTokens = 0
        var lastActivity: Date?
        var models: Set<String> = []

        var bucketTokens = [Int](repeating: 0, count: boundaries.count)
        var hourlyDistribution = [Int](repeating: 0, count: 24)
        var modelTokens: [String: Int] = [:]
        var projectTokens: [URL: Int] = [:]
        var projectSessionCount: [URL: Int] = [:]
        var projectLastActivity: [URL: Date] = [:]
        var topicCounts: [String: Int] = [:]
        var promptCount = 0
        var recentPrompts: [PromptPreview] = []

        let calendar = Calendar.current
        let projectDirs = (try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for projectDir in projectDirs {
            let projectName = friendlyProjectName(projectDir.lastPathComponent)
            let inner = (try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in inner where url.pathExtension == "jsonl" {
                guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate else { continue }
                sessionsTotal += 1
                if mtime >= startOfToday { sessionsToday += 1 }
                if mtime >= liveCutoff   { activeSessions += 1 }
                if lastActivity == nil || mtime > lastActivity! { lastActivity = mtime }

                if mtime >= windowStart {
                    projectSessionCount[projectDir, default: 0] += 1
                    if let prev = projectLastActivity[projectDir] {
                        if mtime > prev { projectLastActivity[projectDir] = mtime }
                    } else {
                        projectLastActivity[projectDir] = mtime
                    }
                }

                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8) else { continue }

                // Per-line scan: pulls out usage events (with their own
                // timestamps + models) and user prompts. Lets us bucket by the
                // turn's actual timestamp instead of the file mtime, which
                // matters once a session spans multiple days.
                parseClaudeFile(
                    text: text,
                    fileMtime: mtime,
                    windowStart: windowStart,
                    boundaries: boundaries,
                    calendar: calendar,
                    projectURL: projectDir,
                    projectName: projectName,
                    inputTokens: &inputTokens,
                    outputTokens: &outputTokens,
                    cachedTokens: &cachedTokens,
                    models: &models,
                    bucketTokens: &bucketTokens,
                    hourlyDistribution: &hourlyDistribution,
                    modelTokens: &modelTokens,
                    projectTokens: &projectTokens,
                    topicCounts: &topicCounts,
                    promptCount: &promptCount,
                    recentPrompts: &recentPrompts
                )
            }
        }

        let chartBuckets: [UsageBucket] = zip(boundaries, bucketTokens).map { boundary, tokens in
            UsageBucket(start: boundary.start, end: boundary.end, tokens: tokens, label: boundary.label)
        }

        let topProjects: [ProjectUsage] = projectSessionCount
            .compactMap { url, count -> ProjectUsage? in
                guard let last = projectLastActivity[url] else { return nil }
                return ProjectUsage(
                    displayName: friendlyProjectName(url.lastPathComponent),
                    path: url.path,
                    sessions: count,
                    lastActivity: last
                )
            }
            .sorted { $0.lastActivity > $1.lastActivity }
            .prefix(5)
            .map { $0 }

        let tokensByModel: [ModelUsage] = modelTokens
            .map { ModelUsage(model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }

        let tokensByProject: [ProjectTokenSlice] = projectTokens
            .map { url, tokens in
                ProjectTokenSlice(
                    displayName: friendlyProjectName(url.lastPathComponent),
                    path: url.path,
                    tokens: tokens
                )
            }
            .sorted { $0.tokens > $1.tokens }

        let topTopics: [PromptTopic] = topicCounts
            .filter { $0.value >= 2 }
            .map { PromptTopic(keyword: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(12)
            .map { $0 }

        let trimmedRecent = recentPrompts
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(8)
            .map { $0 }

        return CLIToolUsage(
            tool: .claude,
            isInstalled: true,
            activeSessions: activeSessions,
            sessionsToday: sessionsToday,
            sessionsTotal: sessionsTotal,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens,
            lastActivity: lastActivity,
            models: models.sorted(),
            chartBuckets: chartBuckets,
            topProjects: topProjects,
            tokensByModel: tokensByModel,
            tokensByProject: tokensByProject,
            topTopics: topTopics,
            recentPrompts: trimmedRecent,
            hourlyDistribution: hourlyDistribution,
            promptCount: promptCount,
            limitSnapshot: nil
        )
    }

    /// Find which bucket `date` falls into. Returns nil when outside the
    /// timeframe.
    private nonisolated static func bucketIndex(
        for date: Date,
        in boundaries: [BucketBoundary]
    ) -> Int? {
        for (i, b) in boundaries.enumerated() where date >= b.start && date < b.end {
            return i
        }
        return nil
    }

    /// Claude Code mangles project paths into directory names like
    /// `-Users-chasesims-Documents-Xcode-Loom`. Strip the leading dash and
    /// keep just the last two segments — that's enough to recognize the repo.
    private nonisolated static func friendlyProjectName(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("-") { s.removeFirst() }
        let segments = s.split(separator: "-").map(String.init)
        guard !segments.isEmpty else { return raw }
        let tail = segments.suffix(2).joined(separator: "/")
        return tail
    }

    /// Per-line scan of a single Claude JSONL session file. Aggregates token
    /// totals + per-bucket counts + per-model + per-project + topic frequency
    /// + recent-prompt previews in one pass.
    ///
    /// We scan line-by-line because we need each event's *own* timestamp and
    /// model — a single session can span multiple days, and the file mtime
    /// only tells us when the session was last touched.
    private nonisolated static func parseClaudeFile(
        text: String,
        fileMtime: Date,
        windowStart: Date,
        boundaries: [BucketBoundary],
        calendar: Calendar,
        projectURL: URL,
        projectName: String,
        inputTokens: inout Int,
        outputTokens: inout Int,
        cachedTokens: inout Int,
        models: inout Set<String>,
        bucketTokens: inout [Int],
        hourlyDistribution: inout [Int],
        modelTokens: inout [String: Int],
        projectTokens: inout [URL: Int],
        topicCounts: inout [String: Int],
        promptCount: inout Int,
        recentPrompts: inout [PromptPreview]
    ) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // Cheap substring filters before invoking regex — keeps the
            // common case (boilerplate lines) at byte-scan speed.
            if line.contains("\"usage\":{") {
                parseAssistantLine(
                    line: String(line),
                    fileMtime: fileMtime,
                    windowStart: windowStart,
                    boundaries: boundaries,
                    calendar: calendar,
                    projectURL: projectURL,
                    inputTokens: &inputTokens,
                    outputTokens: &outputTokens,
                    cachedTokens: &cachedTokens,
                    models: &models,
                    bucketTokens: &bucketTokens,
                    hourlyDistribution: &hourlyDistribution,
                    modelTokens: &modelTokens,
                    projectTokens: &projectTokens
                )
            } else if line.contains("\"role\":\"user\"") && !line.contains("\"tool_use_id\"") {
                parseUserPromptLine(
                    line: String(line),
                    windowStart: windowStart,
                    projectName: projectName,
                    topicCounts: &topicCounts,
                    promptCount: &promptCount,
                    recentPrompts: &recentPrompts
                )
            }
        }
    }

    private nonisolated static func parseAssistantLine(
        line: String,
        fileMtime: Date,
        windowStart: Date,
        boundaries: [BucketBoundary],
        calendar: Calendar,
        projectURL: URL,
        inputTokens: inout Int,
        outputTokens: inout Int,
        cachedTokens: inout Int,
        models: inout Set<String>,
        bucketTokens: inout [Int],
        hourlyDistribution: inout [Int],
        modelTokens: inout [String: Int],
        projectTokens: inout [URL: Int]
    ) {
        guard let usageRegex = Self.claudeUsageRegex else { return }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = usageRegex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 5 else { return }

        let lineInput  = parseInt(nsLine, range: match.range(at: 1))
        let lineCached = parseInt(nsLine, range: match.range(at: 2)) + parseInt(nsLine, range: match.range(at: 3))
        let lineOutput = parseInt(nsLine, range: match.range(at: 4))
        let lineTotal  = lineInput + lineCached + lineOutput

        inputTokens  += lineInput
        cachedTokens += lineCached
        outputTokens += lineOutput

        var model: String?
        if let modelRegex = Self.claudeModelRegex,
           let m = modelRegex.firstMatch(in: line, options: [], range: range),
           m.numberOfRanges >= 2 {
            let r = m.range(at: 1)
            if r.location != NSNotFound {
                let name = nsLine.substring(with: r)
                models.insert(name)
                model = name
            }
        }

        // Prefer the line's own timestamp; fall back to the file mtime when
        // the timestamp field isn't present (rare — usually internal events).
        let timestamp = parseClaudeTimestamp(line: line, fallback: fileMtime)

        if let model {
            modelTokens[model, default: 0] += lineTotal
        }
        if timestamp >= windowStart, lineTotal > 0 {
            projectTokens[projectURL, default: 0] += lineTotal
            if let idx = bucketIndex(for: timestamp, in: boundaries) {
                bucketTokens[idx] += lineTotal
            }
            let hour = calendar.component(.hour, from: timestamp)
            if hour >= 0 && hour < 24 {
                hourlyDistribution[hour] += lineTotal
            }
        }
    }

    private nonisolated static func parseUserPromptLine(
        line: String,
        windowStart: Date,
        projectName: String,
        topicCounts: inout [String: Int],
        promptCount: inout Int,
        recentPrompts: inout [PromptPreview]
    ) {
        guard let promptRegex = Self.claudeUserPromptRegex else { return }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = promptRegex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2 else { return }
        let r = match.range(at: 1)
        guard r.location != NSNotFound else { return }

        let raw = nsLine.substring(with: r)
        let unescaped = unescapeJSON(raw)
        let cleaned = unescaped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let timestamp = parseClaudeTimestamp(line: line, fallback: .now)
        guard timestamp >= windowStart else { return }

        promptCount += 1
        for word in extractTopicKeywords(from: cleaned) {
            topicCounts[word, default: 0] += 1
        }

        let preview = cleaned
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(140)
        recentPrompts.append(
            PromptPreview(
                text: String(preview),
                timestamp: timestamp,
                project: projectName
            )
        )
    }

    /// Pull a `"timestamp":"ISO8601"` value out of a single JSONL line.
    private nonisolated static func parseClaudeTimestamp(line: String, fallback: Date) -> Date {
        guard let regex = Self.claudeTimestampRegex else { return fallback }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2 else { return fallback }
        let r = match.range(at: 1)
        guard r.location != NSNotFound else { return fallback }
        let iso = nsLine.substring(with: r)
        return parseISO8601(iso) ?? fallback
    }

    /// Walk a user prompt and pull out lowercase topic words. Filters
    /// stopwords, very short tokens, and code fragments.
    private nonisolated static func extractTopicKeywords(from text: String) -> [String] {
        let lowered = text.lowercased()
        var seen: Set<String> = []
        var out: [String] = []
        var current = ""
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                if shouldKeep(word: current), !seen.contains(current) {
                    seen.insert(current)
                    out.append(current)
                }
                current = ""
            }
        }
        if shouldKeep(word: current), !seen.contains(current) {
            seen.insert(current)
            out.append(current)
        }
        return out
    }

    private nonisolated static func shouldKeep(word: String) -> Bool {
        guard word.count >= 4, word.count <= 24 else { return false }
        if word.allSatisfy(\.isNumber) { return false }
        return !claudeStopwords.contains(word)
    }

    /// Stopwords pruned from prompt-keyword frequency. Hand-curated from a
    /// real Claude prompt corpus — common English glue plus interface verbs
    /// that show up in nearly every prompt and aren't useful as topics.
    nonisolated private static let claudeStopwords: Set<String> = [
        "this", "that", "with", "have", "from", "your", "into",
        "about", "where", "when", "what", "would", "could", "should",
        "there", "their", "they", "them", "then", "than", "also",
        "just", "like", "want", "need", "make", "made", "more",
        "some", "very", "well", "going", "still", "thing", "things",
        "really", "think", "back", "down", "much", "many", "most",
        "good", "right", "wrong", "okay", "sure", "yeah", "actually",
        "claude", "code", "please", "thanks", "thank", "hello",
        "look", "looks", "look", "show", "shows", "let", "let's",
        "doesn", "didn", "won", "haven", "isn", "aren", "wasn",
        "weren", "the", "and", "but", "for", "are", "was", "were",
        "been", "being", "does", "did", "use", "used", "uses", "using",
        "get", "got", "see", "saw", "seen", "way", "out", "off", "now",
        "yes", "did", "say", "said", "tell", "told", "give", "given",
        "currently", "current", "needs", "needed", "must", "might",
        "since", "before", "after", "while", "still"
    ]

    nonisolated private static let claudeUsageRegex: NSRegularExpression? = {
        let pattern = #""usage":\{"input_tokens":(\d+),"cache_creation_input_tokens":(\d+),"cache_read_input_tokens":(\d+),"output_tokens":(\d+)"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    nonisolated private static let claudeModelRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #""model":"(claude-[^"]+)""#)
    }()

    nonisolated private static let claudeUserPromptRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #""role":"user","content":"((?:[^"\\]|\\.)*)""#)
    }()

    nonisolated private static let claudeTimestampRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #""timestamp":"([^"]+)""#)
    }()

    /// Sendable parsing strategy — switched from ISO8601DateFormatter so the
    /// detached-task scan compiles cleanly under Swift 6 strict concurrency.
    nonisolated private static let iso8601Strategy: Date.ISO8601FormatStyle = {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    }()

    private nonisolated static func parseISO8601(_ s: String) -> Date? {
        if let d = try? iso8601Strategy.parse(s) { return d }
        // Some Claude lines emit no fractional seconds — fall back.
        return try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(s)
    }

    private nonisolated static func unescapeJSON(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var iterator = s.unicodeScalars.makeIterator()
        while let c = iterator.next() {
            if c != "\\" { out.unicodeScalars.append(c); continue }
            guard let next = iterator.next() else { break }
            switch next {
            case "n":  out.append("\n")
            case "t":  out.append("\t")
            case "r":  out.append("\r")
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            case "/":  out.append("/")
            case "u":
                var hex = ""
                for _ in 0..<4 { if let h = iterator.next() { hex.unicodeScalars.append(h) } }
                if let val = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(val) {
                    out.unicodeScalars.append(scalar)
                }
            default:
                out.unicodeScalars.append(next)
            }
        }
        return out
    }

    // MARK: - Codex reader

    private nonisolated static func readCodexUsage(
        root: URL,
        liveCutoff: Date,
        startOfToday: Date,
        boundaries: [BucketBoundary]
    ) -> CLIToolUsage {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else {
            return .unavailable(.codex)
        }

        var sessionsTotal = 0
        var sessionsToday = 0
        var activeSessions = 0
        var inputTokens = 0
        var outputTokens = 0
        var cachedTokens = 0
        var lastActivity: Date?
        var models: Set<String> = []
        var latestLimitSnapshot: UsageLimitSnapshot?

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .unavailable(.codex)
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { continue }
            sessionsTotal += 1
            if mtime >= startOfToday { sessionsToday += 1 }
            if mtime >= liveCutoff   { activeSessions += 1 }
            if lastActivity == nil || mtime > lastActivity! { lastActivity = mtime }

            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                let totals = parseCodexLastTotals(in: text)
                inputTokens  += totals.input
                outputTokens += totals.output
                cachedTokens += totals.cached
                if let model = parseCodexModel(in: text) {
                    models.insert(model)
                }
                if let snapshot = parseCodexLatestLimitSnapshot(in: text, fallback: mtime) {
                    let observedAt = snapshot.observedAt ?? .distantPast
                    if latestLimitSnapshot?.observedAt.map({ observedAt > $0 }) ?? true {
                        latestLimitSnapshot = snapshot
                    }
                }
            }
        }

        return CLIToolUsage(
            tool: .codex,
            isInstalled: true,
            activeSessions: activeSessions,
            sessionsToday: sessionsToday,
            sessionsTotal: sessionsTotal,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens,
            lastActivity: lastActivity,
            models: models.sorted(),
            chartBuckets: [],
            topProjects: [],
            tokensByModel: [],
            tokensByProject: [],
            topTopics: [],
            recentPrompts: [],
            hourlyDistribution: Array(repeating: 0, count: 24),
            promptCount: 0,
            limitSnapshot: latestLimitSnapshot
        )
    }

    /// Codex emits a `token_count` event on every turn. The last one in a
    /// rollout file holds cumulative `total_token_usage`, so we just need to
    /// find the most recent match.
    private nonisolated static func parseCodexLastTotals(
        in text: String
    ) -> (input: Int, output: Int, cached: Int) {
        guard let regex = Self.codexTotalsRegex else { return (0, 0, 0) }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var last: (Int, Int, Int) = (0, 0, 0)
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 4 else { return }
            let input  = parseInt(nsText, range: match.range(at: 1))
            let cached = parseInt(nsText, range: match.range(at: 2))
            let output = parseInt(nsText, range: match.range(at: 3))
            last = (input, output, cached)
        }
        return last
    }

    private nonisolated static func parseCodexModel(in text: String) -> String? {
        guard let regex = Self.codexModelRegex else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2 else { return nil }
        let r = match.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        return nsText.substring(with: r)
    }

    nonisolated private static let codexTotalsRegex: NSRegularExpression? = {
        let pattern = #""total_token_usage":\{"input_tokens":(\d+),"cached_input_tokens":(\d+),"output_tokens":(\d+)"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    nonisolated private static let codexModelRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #""model":"([^"]+)""#)
    }()

    private nonisolated static func parseCodexLatestLimitSnapshot(
        in text: String,
        fallback: Date
    ) -> UsageLimitSnapshot? {
        guard text.contains("rate_limits")
            || text.contains("used_percent")
            || text.contains("rate_limit_reached_type")
            || text.contains(#""credits""#)
            || text.contains("plan_type") else {
            return nil
        }

        var latest: UsageLimitSnapshot?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard rawLine.contains("rate_limits")
                || rawLine.contains("used_percent")
                || rawLine.contains("rate_limit_reached_type")
                || rawLine.contains(#""credits""#)
                || rawLine.contains("plan_type") else {
                continue
            }
            guard let data = String(rawLine).data(using: .utf8),
                  let rawJSON = try? JSONSerialization.jsonObject(with: data),
                  let json = rawJSON as? [String: Any] else {
                continue
            }
            let observedAt = stringValue(json, path: ["timestamp"]).flatMap(parseISO8601) ?? fallback
            guard var snapshot = parseCodexLimitSnapshot(from: json, observedAt: observedAt) else {
                continue
            }
            snapshot = fillCodexLimitMetadata(snapshot, from: json)
            if latest?.observedAt.map({ observedAt > $0 }) ?? true {
                latest = snapshot
            }
        }
        return latest
    }

    private nonisolated static func parseCodexLimitSnapshot(
        from root: [String: Any],
        observedAt: Date
    ) -> UsageLimitSnapshot? {
        guard let value = codexRateLimitDictionary(from: root),
              hasCodexRateLimitFields(value) else {
            return nil
        }

        let primary = value["primary"] as? [String: Any]
        let secondary = value["secondary"] as? [String: Any]
        return UsageLimitSnapshot(
            primaryUsedPercent: doubleValue(primary?["used_percent"]),
            primaryWindowMinutes: intValue(primary?["window_minutes"]),
            primaryResetsAt: resetDate(primary?["resets_at"]),
            secondaryUsedPercent: doubleValue(secondary?["used_percent"]),
            secondaryWindowMinutes: intValue(secondary?["window_minutes"]),
            secondaryResetsAt: resetDate(secondary?["resets_at"]),
            planType: stringValue(value["plan_type"]),
            credits: doubleValue(value["credits"]),
            reachedType: stringValue(value["rate_limit_reached_type"]),
            observedAt: observedAt
        )
    }

    private nonisolated static func fillCodexLimitMetadata(
        _ snapshot: UsageLimitSnapshot,
        from root: [String: Any]
    ) -> UsageLimitSnapshot {
        UsageLimitSnapshot(
            primaryUsedPercent: snapshot.primaryUsedPercent,
            primaryWindowMinutes: snapshot.primaryWindowMinutes,
            primaryResetsAt: snapshot.primaryResetsAt,
            secondaryUsedPercent: snapshot.secondaryUsedPercent,
            secondaryWindowMinutes: snapshot.secondaryWindowMinutes,
            secondaryResetsAt: snapshot.secondaryResetsAt,
            planType: snapshot.planType
                ?? stringValue(root, path: ["payload", "plan_type"])
                ?? stringValue(root, path: ["plan_type"]),
            credits: snapshot.credits
                ?? doubleValue(root, path: ["payload", "credits"])
                ?? doubleValue(root, path: ["credits"]),
            reachedType: snapshot.reachedType
                ?? stringValue(root, path: ["payload", "rate_limit_reached_type"])
                ?? stringValue(root, path: ["rate_limit_reached_type"]),
            observedAt: snapshot.observedAt
        )
    }

    private nonisolated static func codexRateLimitDictionary(from root: [String: Any]) -> [String: Any]? {
        let candidates = [
            dictValue(root, path: ["payload", "rate_limits"]),
            dictValue(root, path: ["rate_limits"]),
            dictValue(root, path: ["payload"]),
            root
        ]
        return candidates.compactMap { $0 }.first(where: hasCodexRateLimitFields)
    }

    private nonisolated static func hasCodexRateLimitFields(_ value: [String: Any]) -> Bool {
        value["primary"] != nil
            || value["secondary"] != nil
            || doubleValue(value["credits"]) != nil
            || stringValue(value["plan_type"]) != nil
            || stringValue(value["rate_limit_reached_type"]) != nil
    }

    private nonisolated static func dictValue(
        _ dict: [String: Any],
        path: [String]
    ) -> [String: Any]? {
        var current: Any = dict
        for key in path {
            guard let next = (current as? [String: Any])?[key] else { return nil }
            current = next
        }
        return current as? [String: Any]
    }

    private nonisolated static func stringValue(
        _ dict: [String: Any],
        path: [String]
    ) -> String? {
        var current: Any = dict
        for key in path {
            guard let next = (current as? [String: Any])?[key] else { return nil }
            current = next
        }
        return stringValue(current)
    }

    private nonisolated static func doubleValue(
        _ dict: [String: Any],
        path: [String]
    ) -> Double? {
        var current: Any = dict
        for key in path {
            guard let next = (current as? [String: Any])?[key] else { return nil }
            current = next
        }
        return doubleValue(current)
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        (value as? String)?.nilIfEmpty
    }

    private nonisolated static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private nonisolated static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private nonisolated static func resetDate(_ value: Any?) -> Date? {
        if let seconds = doubleValue(value) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let string = stringValue(value) {
            return parseISO8601(string)
        }
        return nil
    }

    // MARK: - Gemini

    /// Gemini CLI doesn't currently log usage we can read locally — surface
    /// it as installed-but-no-data rather than hiding it, so users know the
    /// row exists.
    private nonisolated static func readGeminiUsage(root: URL) -> CLIToolUsage {
        let fm = FileManager.default
        let installed = fm.fileExists(atPath: root.path)
        return CLIToolUsage(
            tool: .gemini,
            isInstalled: installed,
            activeSessions: 0,
            sessionsToday: 0,
            sessionsTotal: 0,
            inputTokens: 0,
            outputTokens: 0,
            cachedTokens: 0,
            lastActivity: nil,
            models: [],
            chartBuckets: [],
            topProjects: [],
            tokensByModel: [],
            tokensByProject: [],
            topTopics: [],
            recentPrompts: [],
            hourlyDistribution: Array(repeating: 0, count: 24),
            promptCount: 0,
            limitSnapshot: nil
        )
    }

    // MARK: - Helpers

    private nonisolated static func parseInt(_ text: NSString, range: NSRange) -> Int {
        guard range.location != NSNotFound else { return 0 }
        return Int(text.substring(with: range)) ?? 0
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
