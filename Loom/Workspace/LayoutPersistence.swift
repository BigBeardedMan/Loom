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
        /// Single-pane terminal cwd. Kept for backward compatibility with
        /// pre-1.9.0 stores; new writes also populate `terminalCwds`.
        var cwdPath: String?
        /// One cwd per pane in a terminal block. When unset on read, the
        /// stored block is treated as single-pane and falls back to
        /// `cwdPath`.
        var terminalCwds: [String]?
        /// Layout direction for 2- or 3-pane terminal blocks. Ignored at
        /// 1 pane and at 4 panes (always rendered 2x2).
        var terminalSplitAxis: String?
        /// Relative column width within the block's row. `nil` on read
        /// means a pre-3.1.0 store; hydrate at default 1.0.
        var widthWeight: Double?
        /// Relative height of the row this block anchors.
        var heightWeight: Double?
        /// Pin fraction (0.2-0.8). `nil` means an unpinned block or a
        /// pre-3.1.0 store with default 50% split.
        var pinFraction: Double?
        /// Horizontal cell-fill fraction (0.3-1.0). `nil` means default 1.0
        /// (block fills its cell). Drives the trailing-edge resize handle.
        var widthFraction: Double?
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
        // Only serialize weights when they diverge from the default so the
        // on-disk store stays compact and predictable.
        self.widthWeight = block.widthWeight == 1.0 ? nil : block.widthWeight
        self.heightWeight = block.heightWeight == 1.0 ? nil : block.heightWeight
        self.pinFraction = block.pinFraction
        self.widthFraction = block.widthFraction == 1.0 ? nil : block.widthFraction
        if block.kind == .terminal {
            self.cwdPath = block.terminalSessions.first?.cwd.path
            self.terminalCwds = block.terminalSessions.map { $0.cwd.path }
            self.terminalSplitAxis = block.terminalSplitAxis.rawValue
        } else {
            self.cwdPath = nil
            self.terminalCwds = nil
            self.terminalSplitAxis = nil
        }
    }

    func materialize(defaultCwd: URL) -> WorkspaceBlock? {
        // Skip stored blocks whose kind no longer exists in this Loom build,
        // e.g. the short-lived `.usage` panel that 0.11.0 shipped before
        // moving Usage to a top-bar overlay.
        guard let kind = PanelKind(rawValue: self.kind) else { return nil }
        let resolvedCwd: URL = Self.resolveDir(cwdPath, fallback: defaultCwd)
        let block = WorkspaceBlock(kind: kind, cwd: resolvedCwd)
        block.customTitle = customTitle
        block.autoTerminalIndex = autoTerminalIndex
        block.autoPreviewIndex = autoPreviewIndex
        block.previewURL = previewURL
        block.pin = pin.flatMap(BlockPin.init(rawValue:))
        block.spansFullRow = spansFullRow
        if let w = widthWeight {
            block.widthWeight = min(max(w, WorkspaceBlock.weightRange.lowerBound),
                                    WorkspaceBlock.weightRange.upperBound)
        }
        if let h = heightWeight {
            block.heightWeight = min(max(h, WorkspaceBlock.weightRange.lowerBound),
                                     WorkspaceBlock.weightRange.upperBound)
        }
        if let pf = pinFraction {
            block.pinFraction = min(max(pf, WorkspaceBlock.pinFractionRange.lowerBound),
                                    WorkspaceBlock.pinFractionRange.upperBound)
        }
        if let wf = widthFraction {
            block.widthFraction = min(max(wf, WorkspaceBlock.widthFractionRange.lowerBound),
                                      WorkspaceBlock.widthFractionRange.upperBound)
        }

        if kind == .terminal {
            // Migrate forward: when terminalCwds is present, recreate the
            // exact pane layout. Older stores (pre-1.9.0) only have
            // `cwdPath` and the constructor already created the single
            // session that maps to it, so no extra work is needed.
            if let extras = terminalCwds, extras.count > 1 {
                let trimmed = Array(extras.prefix(WorkspaceBlock.maxTerminalPanes))
                // The block's init already created the first session at
                // resolvedCwd. Replace it so each restored pane gets its
                // own saved cwd.
                let firstCwd = Self.resolveDir(trimmed.first, fallback: resolvedCwd)
                let firstSession = TerminalSession(cwd: firstCwd)
                block.terminalSessions = [firstSession]
                for path in trimmed.dropFirst() {
                    let cwd = Self.resolveDir(path, fallback: resolvedCwd)
                    block.terminalSessions.append(TerminalSession(cwd: cwd))
                }
            }
            if let raw = terminalSplitAxis,
               let axis = TerminalSplitAxis(rawValue: raw) {
                block.terminalSplitAxis = axis
            }
        }
        return block
    }

    /// Validate a saved directory string and fall back when it's missing
    /// or no longer a directory on disk.
    private static func resolveDir(_ path: String?, fallback: URL) -> URL {
        guard let path, !path.isEmpty else { return fallback }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue ? URL(fileURLWithPath: path) : fallback
    }
}
