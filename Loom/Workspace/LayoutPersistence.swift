import Foundation

/// On-disk store for the per-kind block list. We persist enough to restore
/// the same blocks (kinds, names, terminal slots, pin/span state) but
/// deliberately *not* the live `TerminalSession` — PTYs aren't checkpointable,
/// so a restored terminal block gets a fresh shell that respawns from the
/// saved cwd on first mount. The user gets back their layout, not their
/// scrollback.
@MainActor
enum LayoutPersistence {
    private static let storeURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Loom", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layout.json")
    }()

    fileprivate struct StoredBlock: Codable, Sendable {
        let kind: String
        var customTitle: String?
        var autoTerminalIndex: Int?
        var autoPreviewIndex: Int?
        var previewURL: String?
        var pin: String?
        var spansFullRow: Bool
        /// Persisted only for terminal blocks so a restored session reopens
        /// in the same directory the user had it in.
        var cwdPath: String?
    }

    fileprivate struct StoredLayout: Codable, Sendable {
        var blocksByKind: [String: [StoredBlock]]
    }

    /// In-memory mirror of the on-disk store. Loaded once per session;
    /// subsequent reads/writes go through the cache rather than touching the
    /// file on the main thread. Disk writes are coalesced through a single
    /// in-flight task so two rapid `save()` calls can't race each other to
    /// the file (the previous fire-and-forget detached pattern would let the
    /// second-finishing task silently overwrite the most recent state).
    private static var cachedStore: StoredLayout?
    private static var cacheLoaded: Bool = false
    private static var flushTask: Task<Void, Never>?
    private static var pendingFlush: StoredLayout?

    static func save(kind: WorkspaceKind, blocks: [WorkspaceBlock]) {
        ensureCacheLoaded()
        var store = cachedStore ?? StoredLayout(blocksByKind: [:])
        store.blocksByKind[kind.rawValue] = blocks.map(StoredBlock.init(from:))
        cachedStore = store
        scheduleFlush(store)
    }

    static func load(kind: WorkspaceKind, cwd: URL) -> [WorkspaceBlock]? {
        ensureCacheLoaded()
        guard let store = cachedStore,
              let stored = store.blocksByKind[kind.rawValue],
              !stored.isEmpty
        else { return nil }
        let blocks = stored.compactMap { $0.materialize(defaultCwd: cwd) }
        return blocks.isEmpty ? nil : blocks
    }

    private static func ensureCacheLoaded() {
        if cacheLoaded { return }
        cacheLoaded = true
        guard let data = try? Data(contentsOf: storeURL),
              let store = try? JSONDecoder().decode(StoredLayout.self, from: data)
        else { return }
        cachedStore = store
    }

    /// Coalesces flushes: if a write is already in flight, the new state is
    /// queued and the in-flight task picks it up after the current write
    /// finishes. The chain always ends with the most-recent in-memory state
    /// on disk.
    private static func scheduleFlush(_ store: StoredLayout) {
        pendingFlush = store
        guard flushTask == nil else { return }
        flushTask = Task {
            await drainFlushQueue()
        }
    }

    private static func drainFlushQueue() async {
        let url = storeURL
        while let next = pendingFlush {
            pendingFlush = nil
            // Encode + write off the main actor; only the queue check above
            // and below runs under MainActor isolation.
            let snapshot = next
            await Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: url, options: [.atomic])
            }.value
        }
        flushTask = nil
    }
}

@MainActor
private extension LayoutPersistence.StoredBlock {
    init(from block: WorkspaceBlock) {
        self.kind = block.kind.rawValue
        self.customTitle = block.customTitle
        self.autoTerminalIndex = block.autoTerminalIndex
        self.autoPreviewIndex = block.autoPreviewIndex
        self.previewURL = block.previewURL
        self.pin = block.pin?.rawValue
        self.spansFullRow = block.spansFullRow
        self.cwdPath = block.kind == .terminal ? block.terminalSession?.cwd.path : nil
    }

    func materialize(defaultCwd: URL) -> WorkspaceBlock? {
        // Skip stored blocks whose kind no longer exists in this Loom build —
        // e.g. the short-lived `.usage` panel that 0.11.0 shipped before
        // moving Usage to a top-bar overlay.
        guard let kind = PanelKind(rawValue: self.kind) else { return nil }
        let resolvedCwd: URL = {
            guard let path = cwdPath, !path.isEmpty else { return defaultCwd }
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return exists && isDir.boolValue ? URL(fileURLWithPath: path) : defaultCwd
        }()
        let block = WorkspaceBlock(kind: kind, cwd: resolvedCwd)
        block.customTitle = customTitle
        block.autoTerminalIndex = autoTerminalIndex
        block.autoPreviewIndex = autoPreviewIndex
        block.previewURL = previewURL
        block.pin = pin.flatMap(BlockPin.init(rawValue:))
        block.spansFullRow = spansFullRow
        return block
    }
}
