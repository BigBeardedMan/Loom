import Foundation
import Observation

/// One shell command captured by the Loom shell-integration shim.
struct CommandRecord: Identifiable, Hashable, Sendable {
    /// Composite id keyed off start timestamp + sequence so identical
    /// commands reissued in the same second get distinct rows.
    let id: String
    let started: Date
    let ended: Date
    let exitCode: Int
    let cwd: String
    let command: String
    let sessionID: String

    var duration: TimeInterval {
        max(0, ended.timeIntervalSince(started))
    }

    var succeeded: Bool { exitCode == 0 }
}

/// Polls the JSONL log the shell shim writes and exposes the most recent
/// commands as observable state. We deliberately *don't* watch via FSEvents
/// (would require a separate sandbox entitlement); a 2-second poll keeps
/// the panel feeling live without hitting the file constantly.
@Observable
@MainActor
final class CommandHistoryService {
    var records: [CommandRecord] = []
    var lastError: String?

    /// Most-recent records first. Capped to keep the view cheap to render
    /// even after a long zsh session has appended thousands of lines.
    nonisolated static let maxRecords = 500

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0
    private let logURL: URL = ShellIntegration.historyLogURL
    private var lastSize: UInt64 = 0
    private var refreshInFlight: Bool = false

    func start() {
        guard pollTimer == nil else { return }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Force a refresh now. Skips when one is already in flight so a slow
    /// disk doesn't stack up duplicate work.
    func refresh() {
        guard !refreshInFlight else { return }
        // Cheap mtime/size check up front: skip the read entirely when the
        // file hasn't grown since the last poll.
        let url = logURL
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? UInt64) ?? 0
        if size == lastSize, !records.isEmpty { return }

        refreshInFlight = true
        Task { [weak self] in
            let parsed = await Task.detached(priority: .utility) {
                Self.readRecords(from: url)
            }.value
            guard let self else { return }
            self.refreshInFlight = false
            self.lastSize = size
            if parsed != self.records {
                self.records = parsed
            }
        }
    }

    /// Recent records filtered to a specific cwd. Used by the Commands
    /// panel when a workspace folder is set so the user sees only commands
    /// they ran inside the current project.
    func records(in cwd: String?) -> [CommandRecord] {
        guard let cwd, !cwd.isEmpty else { return records }
        return records.filter {
            $0.cwd == cwd || $0.cwd.hasPrefix(cwd + "/")
        }
    }

    nonisolated private static func readRecords(from url: URL) -> [CommandRecord] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        var out: [CommandRecord] = []
        // Walk lines newest-last (file append order). We collect into an
        // array, then trim from the front so the cap keeps the freshest
        // entries.
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard let lineData = String(raw).data(using: .utf8),
                  let payload = try? decoder.decode(StoredRecord.self, from: lineData) else { continue }
            let id = "\(payload.started)-\(index)"
            out.append(CommandRecord(
                id: id,
                started: Date(timeIntervalSince1970: TimeInterval(payload.started)),
                ended: Date(timeIntervalSince1970: TimeInterval(payload.ended)),
                exitCode: payload.exit,
                cwd: payload.cwd,
                command: payload.command,
                sessionID: payload.session
            ))
        }
        if out.count > maxRecords {
            out = Array(out.suffix(maxRecords))
        }
        // Reverse so the panel's natural top-of-list rendering shows the
        // newest first.
        return out.reversed()
    }

    private struct StoredRecord: Decodable {
        let started: Int
        let ended: Int
        let exit: Int
        let cwd: String
        let command: String
        let session: String
    }
}
