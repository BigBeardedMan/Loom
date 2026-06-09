import Foundation

/// Helpers for reading the CLI agents' on-disk session logs without pulling
/// whole files — or whole directory trees — into memory.
///
/// Loom polls `~/.codex/sessions` and `~/.claude/projects` on short timers
/// (2–3 s) and on every app activation. A long-time Codex user can have a
/// multi-gigabyte session tree; enumerating it file-by-file and reading each
/// rollout end-to-end ballooned resident memory by gigabytes per sweep and
/// showed up as system-wide memory pressure that grew the longer Loom ran.
/// Every poll must therefore (a) touch only the day directories that can
/// contain files inside its activity window and (b) read at most a bounded
/// tail of any file it inspects.
enum SessionLogScan {
    /// How far before the cutoff we still walk day directories. A rollout
    /// lives in the directory of the day it was *created*, so a session
    /// resumed days later has an mtime newer than its directory date. The
    /// grace keeps such sessions visible without re-walking years of history.
    static let dayDirectoryGrace: TimeInterval = 31 * 24 * 3600

    /// Codex day directories (`root/YYYY/MM/DD`) that can contain rollouts
    /// modified at or after `cutoff`, oldest first. Includes `root` itself so
    /// stray rollouts written directly to the root keep working. Only
    /// directories that exist are returned.
    static func codexDayDirectories(root: URL, cutoff: Date, now: Date = Date()) -> [URL] {
        let fm = FileManager.default
        let calendar = Calendar(identifier: .gregorian)
        var dirs: [URL] = [root]
        var day = calendar.startOfDay(for: cutoff.addingTimeInterval(-dayDirectoryGrace))
        let lastDay = calendar.startOfDay(for: now)
        // The widest caller window is days, plus the 31-day grace — cap the
        // walk defensively so a bad clock can't spin this loop unbounded.
        var steps = 0
        while day <= lastDay, steps < 400 {
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            if let year = c.year, let month = c.month, let dayOfMonth = c.day {
                dirs.append(
                    root
                        .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                        .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                        .appendingPathComponent(String(format: "%02d", dayOfMonth), isDirectory: true)
                )
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            steps += 1
        }
        return dirs.filter { fm.fileExists(atPath: $0.path) }
    }

    /// All `.jsonl` rollouts under the candidate day directories whose mtime
    /// is at or after `cutoff`. Touches directory metadata only — no file
    /// contents are read.
    static func recentCodexRollouts(
        root: URL,
        cutoff: Date,
        now: Date = Date()
    ) -> [(url: URL, mtime: Date)] {
        let fm = FileManager.default
        var out: [(url: URL, mtime: Date)] = []
        for dir in codexDayDirectories(root: root, cutoff: cutoff, now: now) {
            let entries = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in entries where url.pathExtension == "jsonl" {
                guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate, mtime >= cutoff else { continue }
                out.append((url: url, mtime: mtime))
            }
        }
        return out
    }

    /// Reads at most the trailing `maxBytes` of a file as UTF-8. When the
    /// read is truncated, the partial first line is dropped so callers only
    /// ever see whole lines. Returns nil when the file can't be opened or is
    /// empty.
    static func tailText(of url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        guard size > 0 else { return nil }
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if offset > 0 {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            } else {
                return nil
            }
        }
        return text
    }

    /// mtime + size stamp for cheap "has this file changed since the last
    /// poll" checks.
    static func stamp(of url: URL) -> FileStamp? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let mtime = values.contentModificationDate else { return nil }
        return FileStamp(mtime: mtime, size: Int64(values.fileSize ?? 0))
    }
}

struct FileStamp: Equatable, Sendable {
    let mtime: Date
    let size: Int64
}

/// Lock-guarded parse-result cache keyed by file path + `FileStamp`. The
/// 2-second task poll re-visits the same session logs on every tick; most
/// ticks the files haven't changed, so caching the parse result (including
/// nil results) avoids re-reading multi-megabyte JSONL bodies each time.
final class StampedParseCache<Value>: @unchecked Sendable {
    private struct Entry {
        let stamp: FileStamp
        let value: Value
    }

    private var entries: [String: Entry] = [:]
    private let lock = NSLock()
    private let maxEntries: Int

    init(maxEntries: Int = 256) {
        self.maxEntries = maxEntries
    }

    func value(for path: String, stamp: FileStamp) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path], entry.stamp == stamp else { return nil }
        return entry.value
    }

    func store(_ value: Value, for path: String, stamp: FileStamp) {
        lock.lock()
        defer { lock.unlock() }
        if entries.count >= maxEntries, entries[path] == nil {
            // Simple pressure valve: drop everything and let the next polls
            // repopulate. Keeps the cache itself from becoming a leak.
            entries.removeAll(keepingCapacity: true)
        }
        entries[path] = Entry(stamp: stamp, value: value)
    }
}
