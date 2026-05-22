import AppKit
import Foundation
import Observation

enum TerminalTranscriptState: String, Codable, Sendable {
    case active
    case closed
    case deleted
}

struct TerminalTranscriptSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var workspaceID: UUID?
    var workspaceName: String?
    var cwd: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var closedAt: Date?
    var deletedAt: Date?
    var state: TerminalTranscriptState
    var byteCount: Int64

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Terminal Session" : title
    }

    var displayCwd: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd == home { return "~" }
        if cwd.hasPrefix(home) { return "~" + cwd.dropFirst(home.count) }
        return cwd
    }
}

struct TerminalTranscriptRestore: Sendable {
    let sessionID: UUID
    let cwd: URL
    let title: String
    let transcriptText: String
    let wasTruncated: Bool
    let importedByteLimit: Int
    let transcriptByteCount: Int64
}

final class TerminalTranscriptRecorder: @unchecked Sendable {
    private let url: URL
    private let queue: DispatchQueue
    private var handle: FileHandle?

    init(url: URL, sessionID: UUID) {
        self.url = url
        self.queue = DispatchQueue(label: "loom.terminal-transcript.\(sessionID.uuidString)")
    }

    func append(_ slice: ArraySlice<UInt8>) {
        guard TerminalTranscriptStore.persistenceEnabled else { return }
        let bytes = Data(slice)
        guard !bytes.isEmpty else { return }
        let url = self.url
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                let h: FileHandle
                if let existing = self.handle {
                    h = existing
                } else {
                    h = try FileHandle(forWritingTo: url)
                    self.handle = h
                }
                try h.seekToEnd()
                try h.write(contentsOf: bytes)
            } catch {
                try? self.handle?.close()
                self.handle = nil
            }
        }
    }

    func close() {
        queue.async { [weak self] in
            try? self?.handle?.close()
            self?.handle = nil
        }
    }
}

@Observable
@MainActor
final class TerminalTranscriptStore {
    nonisolated static let enabledDefaultsKey = "loom.terminalHistory.enabled"
    nonisolated static let maxBytesDefaultsKey = "loom.terminalHistory.maxBytes"
    nonisolated static let defaultStorageLimitBytes: Double = 1_073_741_824
    nonisolated static let defaultPreviewLimitBytes = 2_000_000
    nonisolated static let restoreImportLimitBytes = 10_000_000

    var sessions: [TerminalTranscriptSession] = []
    var totalBytes: Int64 = 0
    var lastError: String?

    private var pruneTimer: Timer?

    nonisolated static var persistenceEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
    }

    nonisolated static var storageLimitBytes: Int64 {
        let raw = UserDefaults.standard.object(forKey: maxBytesDefaultsKey) as? Double
            ?? defaultStorageLimitBytes
        return max(50_000_000, Int64(raw))
    }

    static var baseDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Loom"
        return base
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Terminal History", isDirectory: true)
    }

    static var transcriptDirectory: URL {
        baseDirectory.appendingPathComponent("transcripts", isDirectory: true)
    }

    private static var metadataURL: URL {
        baseDirectory.appendingPathComponent("sessions.json", isDirectory: false)
    }

    func start() {
        load()
        sweepOrphanedActiveSessions()
        refreshUsage()
        enforceStorageLimit()
        guard pruneTimer == nil else { return }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshUsage()
                self?.enforceStorageLimit()
            }
        }
    }

    func stop() {
        pruneTimer?.invalidate()
        pruneTimer = nil
    }

    func register(
        sessionID: UUID,
        workspaceID: UUID?,
        workspaceName: String?,
        cwd: URL,
        title: String
    ) -> URL {
        ensureDirectories()
        let now = Date()
        let transcriptURL = transcriptURL(for: sessionID)
        if !FileManager.default.fileExists(atPath: transcriptURL.path) {
            FileManager.default.createFile(atPath: transcriptURL.path, contents: nil)
        }

        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].workspaceID = workspaceID
            sessions[idx].workspaceName = workspaceName
            sessions[idx].cwd = cwd.path
            sessions[idx].title = title
            sessions[idx].updatedAt = now
            sessions[idx].state = .active
            sessions[idx].closedAt = nil
            sessions[idx].deletedAt = nil
            sessions[idx].byteCount = fileSize(at: transcriptURL)
        } else {
            sessions.append(TerminalTranscriptSession(
                id: sessionID,
                workspaceID: workspaceID,
                workspaceName: workspaceName,
                cwd: cwd.path,
                title: title,
                createdAt: now,
                updatedAt: now,
                closedAt: nil,
                deletedAt: nil,
                state: .active,
                byteCount: fileSize(at: transcriptURL)
            ))
        }
        save()
        return transcriptURL
    }

    func update(sessionID: UUID, cwd: URL? = nil, title: String? = nil) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if let cwd { sessions[idx].cwd = cwd.path }
        if let title, !title.isEmpty { sessions[idx].title = title }
        sessions[idx].updatedAt = Date()
        save()
    }

    func close(sessionID: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard sessions[idx].state == .active else { return }
        let now = Date()
        sessions[idx].state = .closed
        sessions[idx].closedAt = now
        sessions[idx].updatedAt = now
        sessions[idx].byteCount = fileSize(at: transcriptURL(for: sessionID))
        save()
        refreshUsage()
    }

    func moveToDeleted(_ session: TerminalTranscriptSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        let now = Date()
        sessions[idx].state = .deleted
        sessions[idx].deletedAt = now
        sessions[idx].updatedAt = now
        save()
    }

    func recoverDeleted(_ session: TerminalTranscriptSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].state = .closed
        sessions[idx].deletedAt = nil
        sessions[idx].updatedAt = Date()
        save()
    }

    func restoreClosedSession(
        _ session: TerminalTranscriptSession,
        fallbackCwd: URL
    ) -> TerminalTranscriptRestore? {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }),
              sessions[idx].state == .closed else { return nil }

        let saved = sessions[idx]
        let now = Date()
        let byteCount = fileSize(at: transcriptURL(for: saved.id))
        let restore = TerminalTranscriptRestore(
            sessionID: saved.id,
            cwd: resolvedDirectory(saved.cwd, fallback: fallbackCwd),
            title: saved.displayTitle,
            transcriptText: readTranscriptText(
                for: saved,
                maxBytes: Self.restoreImportLimitBytes,
                includeTrimNotice: false
            ),
            wasTruncated: byteCount > Int64(Self.restoreImportLimitBytes),
            importedByteLimit: Self.restoreImportLimitBytes,
            transcriptByteCount: byteCount
        )

        sessions[idx].state = .active
        sessions[idx].closedAt = nil
        sessions[idx].deletedAt = nil
        sessions[idx].updatedAt = now
        sessions[idx].byteCount = byteCount
        save()
        refreshUsage()
        return restore
    }

    func deletePermanently(_ session: TerminalTranscriptSession) {
        try? FileManager.default.removeItem(at: transcriptURL(for: session.id))
        sessions.removeAll { $0.id == session.id }
        save()
        refreshUsage()
    }

    func pruneSavedHistory() {
        let now = Date()
        for idx in sessions.indices {
            let url = transcriptURL(for: sessions[idx].id)
            if sessions[idx].state == .active {
                truncateFile(at: url)
                sessions[idx].byteCount = 0
                sessions[idx].updatedAt = now
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        sessions.removeAll { $0.state != .active }
        save()
        refreshUsage()
    }

    func enforceStorageLimit() {
        refreshUsage()
        let limit = Self.storageLimitBytes
        guard totalBytes > limit else { return }

        let candidates = sessions
            .filter { $0.state != .active }
            .sorted { lhs, rhs in
                if lhs.state != rhs.state {
                    return lhs.state == .deleted
                }
                return lhs.updatedAt < rhs.updatedAt
            }

        for session in candidates {
            deletePermanently(session)
            if totalBytes <= limit { break }
        }
    }

    func recentlyClosed(workspaceID: UUID?) -> [TerminalTranscriptSession] {
        sessions
            .filter { $0.state == .closed && (workspaceID == nil || $0.workspaceID == workspaceID) }
            .sorted { ($0.closedAt ?? $0.updatedAt) > ($1.closedAt ?? $1.updatedAt) }
    }

    func recentlyDeleted(workspaceID: UUID?) -> [TerminalTranscriptSession] {
        sessions
            .filter { $0.state == .deleted && (workspaceID == nil || $0.workspaceID == workspaceID) }
            .sorted { ($0.deletedAt ?? $0.updatedAt) > ($1.deletedAt ?? $1.updatedAt) }
    }

    func readTranscriptText(
        for session: TerminalTranscriptSession,
        maxBytes: Int? = TerminalTranscriptStore.defaultPreviewLimitBytes,
        includeTrimNotice: Bool = true
    ) -> String {
        let url = transcriptURL(for: session.id)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "(transcript file missing)"
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset: UInt64
        if let maxBytes, size > UInt64(maxBytes) {
            offset = size - UInt64(maxBytes)
        } else {
            offset = 0
        }
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = TerminalTranscriptSanitizer.plainText(from: data)
        if includeTrimNotice, offset > 0 {
            return "... earlier transcript trimmed in this viewer; the saved file is larger\n\n" + text
        }
        return text.isEmpty ? "(empty transcript)" : text
    }

    func revealTranscript(_ session: TerminalTranscriptSession) {
        ensureDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([transcriptURL(for: session.id)])
    }

    func revealHistoryFolder() {
        ensureDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([Self.baseDirectory])
    }

    func refreshUsage() {
        var next = sessions
        var total: Int64 = 0
        for idx in next.indices {
            let size = fileSize(at: transcriptURL(for: next[idx].id))
            next[idx].byteCount = size
            total += size
        }
        sessions = next
        totalBytes = total
    }

    private func load() {
        ensureDirectories()
        guard let data = try? Data(contentsOf: Self.metadataURL),
              let decoded = try? JSONDecoder().decode([TerminalTranscriptSession].self, from: data)
        else {
            sessions = []
            return
        }
        sessions = decoded
    }

    private func save() {
        ensureDirectories()
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: Self.metadataURL, options: [.atomic])
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func sweepOrphanedActiveSessions() {
        var changed = false
        let now = Date()
        for idx in sessions.indices where sessions[idx].state == .active {
            sessions[idx].state = .closed
            sessions[idx].closedAt = sessions[idx].closedAt ?? now
            sessions[idx].updatedAt = now
            changed = true
        }
        if changed { save() }
    }

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(
            at: Self.transcriptDirectory,
            withIntermediateDirectories: true
        )
    }

    private func transcriptURL(for sessionID: UUID) -> URL {
        Self.transcriptDirectory.appendingPathComponent("\(sessionID.uuidString).ansi", isDirectory: false)
    }

    private func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func truncateFile(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        try? handle.truncate(atOffset: 0)
        try? handle.close()
    }

    private func resolvedDirectory(_ path: String, fallback: URL) -> URL {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue ? URL(fileURLWithPath: path) : fallback
    }
}

enum TerminalTranscriptSanitizer {
    static func plainText(from data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            let scalar = text[index].unicodeScalars.first?.value ?? 0
            if scalar == 0x1B {
                skipEscape(in: text, index: &index)
                continue
            }
            let ch = text[index]
            if ch == "\r" {
                output.append("\n")
            } else if ch == "\u{08}" {
                if !output.isEmpty { output.removeLast() }
            } else if ch == "\u{07}" {
                // bell
            } else {
                output.append(ch)
            }
            index = text.index(after: index)
        }

        let lines = output
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .controlCharacters) }
        return lines.joined(separator: "\n")
    }

    private static func skipEscape(in text: String, index: inout String.Index) {
        index = text.index(after: index)
        guard index < text.endIndex else { return }

        let marker = text[index]
        if marker == "]" {
            while index < text.endIndex {
                let ch = text[index]
                if ch == "\u{07}" {
                    index = text.index(after: index)
                    return
                }
                if ch == "\u{1B}" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\\" {
                        index = text.index(after: next)
                        return
                    }
                }
                index = text.index(after: index)
            }
            return
        }

        while index < text.endIndex {
            let value = text[index].unicodeScalars.first?.value ?? 0
            index = text.index(after: index)
            if value >= 0x40 && value <= 0x7E {
                return
            }
        }
    }
}
