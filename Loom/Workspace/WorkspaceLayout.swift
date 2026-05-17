import Foundation
import Observation

enum PanelKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case terminal
    case editor
    case tasks
    case agent
    case notes
    case preview
    case commands

    var id: String { rawValue }

    var label: String {
        switch self {
        case .terminal: return "Terminal"
        case .editor:   return "Editor"
        case .tasks:    return "Tasks"
        case .agent:    return "Agent"
        case .notes:    return "Notes"
        case .preview:  return "Preview"
        case .commands: return "Commands"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal: return "terminal"
        case .editor:   return "curlybraces"
        case .tasks:    return "rectangle.split.3x1"
        case .agent:    return "sparkles"
        case .notes:    return "note.text"
        case .preview:  return "globe"
        case .commands: return "list.bullet.rectangle"
        }
    }
}

enum BlockPin: String, Hashable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }
}

/// Direction the panes inside a multi-pane terminal block are arranged when
/// the count is 2 or 3. Ignored at count 1 (no split) and 4 (always 2x2).
enum TerminalSplitAxis: String, Codable, Hashable {
    case horizontal  // panes laid out left-to-right
    case vertical    // panes stacked top-to-bottom
}

@Observable
@MainActor
final class WorkspaceBlock: Identifiable {
    let id: UUID
    let kind: PanelKind
    /// Live PTY sessions hosted by this block. For non-terminal blocks the
    /// array stays empty. For terminal blocks the array has 1 to 4 entries;
    /// each entry is its own resizable pane in the rendered layout.
    var terminalSessions: [TerminalSession]
    var terminalSplitAxis: TerminalSplitAxis
    /// Persistent WebKit controller for preview blocks. Owned by the block
    /// so the WKWebView (and its loaded page) survives workspace switches —
    /// otherwise each switch tears down and re-creates the WebView, forcing
    /// a full reload of the previewed URL.
    var webController: WebController?
    var pin: BlockPin?
    var spansFullRow: Bool
    /// Relative width within the block's row. Defaults to 1.0 (even share).
    /// Combined with siblings via `weight_i / sum_of_weights` to size each
    /// column. Clamped to `weightRange` on write.
    var widthWeight: Double
    /// Relative height of the row this block anchors. Only the first block in
    /// a row drives row height; non-anchor blocks still store the value so
    /// reordering preserves user intent.
    var heightWeight: Double
    /// Pin's share of the deck (0.2 to 0.8). When `pin != nil`, replaces the
    /// hard-coded 0.5 split between the pinned area and the free area. `nil`
    /// falls back to 0.5 for backwards compatibility.
    var pinFraction: Double?
    /// Block's share of its allotted cell along the horizontal axis. 1.0 (default)
    /// fills the cell. Values below 1.0 shrink the block toward the left, leaving
    /// deck background visible on the right. Lets stacked single-block rows expose
    /// a horizontal resize handle even when there is no sibling to share width with.
    var widthFraction: Double
    var customTitle: String?
    var autoTerminalIndex: Int?
    var autoPreviewIndex: Int?
    var previewURL: String?

    /// Compatibility shim. Most consumers (sidebar label, live-agent count,
    /// persistence) only care about the first session. Multi-pane-aware
    /// callers walk `terminalSessions` directly.
    var terminalSession: TerminalSession? {
        terminalSessions.first
    }

    /// Hard ceiling on splits. The 2x2 grid is the practical limit before
    /// the panes get too small to read on typical macOS windows.
    static let maxTerminalPanes = 4

    /// Allowed range for column/row weights. Below 0.2 the block disappears
    /// behind the minimum size clamp; above 5x the neighbouring block hits
    /// the minimum on the other side.
    static let weightRange: ClosedRange<Double> = 0.2...5.0
    /// Allowed range for `pinFraction`. Symmetrical so the unpinned side
    /// never falls below 20% of the deck.
    static let pinFractionRange: ClosedRange<Double> = 0.2...0.8
    /// Allowed range for `widthFraction`. Floor of 0.3 keeps the block
    /// readable; ceiling of 1.0 means "fill the cell" — going wider would
    /// overflow neighbouring blocks.
    static let widthFractionRange: ClosedRange<Double> = 0.3...1.0

    init(kind: PanelKind, cwd: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.id = UUID()
        self.kind = kind
        self.pin = nil
        self.spansFullRow = false
        self.widthWeight = 1.0
        self.heightWeight = 1.0
        self.pinFraction = nil
        self.widthFraction = 1.0
        self.customTitle = nil
        self.autoTerminalIndex = nil
        self.autoPreviewIndex = nil
        self.previewURL = nil
        self.terminalSessions = []
        self.terminalSplitAxis = .horizontal
        if kind == .terminal {
            self.terminalSessions = [TerminalSession(cwd: cwd)]
        }
        if kind == .preview {
            self.webController = WebController()
        }
    }

    var defaultPreviewURL: String {
        let port = 3000 + max(0, (autoPreviewIndex ?? 1) - 1)
        return "http://localhost:\(port)"
    }

    var effectivePreviewURL: String {
        if let override = previewURL?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        return defaultPreviewURL
    }

    var displayTitle: String {
        if let trimmed = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }
        if kind == .terminal, let idx = autoTerminalIndex {
            return idx == 1 ? "Terminal" : "Terminal \(idx)"
        }
        return kind.label
    }

    func cleanup() {
        for session in terminalSessions {
            session.cleanup()
        }
    }

    /// Add a new pane to a terminal block, capped at `maxTerminalPanes`.
    /// The new session inherits the block's most recent pane's cwd so the
    /// split feels like a fork from where the user just was.
    func addTerminalPane(defaultCwd: URL) {
        guard kind == .terminal,
              terminalSessions.count < Self.maxTerminalPanes else { return }
        let cwd = terminalSessions.last?.cwd ?? defaultCwd
        terminalSessions.append(TerminalSession(cwd: cwd))
    }

    /// Remove a specific pane by id and clean up its PTY. No-op when the
    /// block is already a single pane (we don't allow zero panes).
    func removeTerminalPane(id sessionID: UUID) {
        guard kind == .terminal,
              terminalSessions.count > 1,
              let idx = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let removed = terminalSessions.remove(at: idx)
        removed.cleanup()
    }

    /// Toggle the layout direction for 2- or 3-pane blocks. No effect at 1
    /// pane (axis is moot) or 4 panes (always rendered as 2x2 quad).
    func toggleTerminalSplitAxis() {
        guard kind == .terminal else { return }
        terminalSplitAxis = (terminalSplitAxis == .horizontal) ? .vertical : .horizontal
    }
}

@Observable
@MainActor
final class WorkspaceLayout {
    private var blocksByKind: [WorkspaceKind: [WorkspaceBlock]] = [:]
    var currentKind: WorkspaceKind = .code
    var defaultCwd: URL = FileManager.default.homeDirectoryForCurrentUser

    /// Currently-active workspace, hoisted onto the layout so top-level
    /// commands (⌘⇧O quick-flip, layout shortcuts) can drive selection
    /// without threading bindings through every consumer.
    var selectedWorkspaceID: UUID? {
        didSet {
            if let oldValue, oldValue != selectedWorkspaceID {
                previousWorkspaceID = oldValue
            }
        }
    }

    /// Most-recent prior selection. Drives ⌘⇧O quick-flip back to where the
    /// user just was.
    private(set) var previousWorkspaceID: UUID?

    var liveAgentTerminalCount: Int = 0

    /// True once at least one kind has been hydrated. Suppresses the auto-save
    /// during initial load so prefetch doesn't write back over kinds that are
    /// still loading.
    private var hasHydrated: Bool = false

    private var liveAgentTimer: Timer?
    private let liveAgentPollInterval: TimeInterval = 2.0

    var blocks: [WorkspaceBlock] {
        blocksByKind[currentKind] ?? []
    }

    /// First block on the active deck. Layout shortcuts (⌥⌘ pin / toggle full
    /// row) act on this so the user always has a deterministic target without
    /// needing per-block focus tracking.
    var commandTargetBlock: WorkspaceBlock? {
        blocks.first
    }

    func bind(to kind: WorkspaceKind) {
        currentKind = kind
        if blocksByKind[kind] == nil {
            if let restored = LayoutPersistence.load(kind: kind, cwd: defaultCwd) {
                blocksByKind[kind] = restored
            } else {
                blocksByKind[kind] = makeDefaults(for: kind)
            }
        }
        hasHydrated = true
    }

    /// Eagerly hydrate every kind's blocks at app launch so the first switch
    /// into each kind doesn't pay the load + first-render cost (PTY spawn,
    /// JSON decode) on the user's click. Prefetching shifts that work into
    /// the launch task where it's invisible.
    func prefetchAllKinds() {
        for kind in WorkspaceKind.allCases {
            if blocksByKind[kind] == nil {
                if let restored = LayoutPersistence.load(kind: kind, cwd: defaultCwd) {
                    blocksByKind[kind] = restored
                } else {
                    blocksByKind[kind] = makeDefaults(for: kind)
                }
            }
        }
        hasHydrated = true
    }

    func setDefaultCwd(_ url: URL?) {
        defaultCwd = url ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func addBlock(_ kind: PanelKind) {
        var current = blocks
        let block = WorkspaceBlock(kind: kind, cwd: defaultCwd)
        if kind == .terminal {
            block.autoTerminalIndex = Self.nextTerminalIndex(in: current)
        }
        if kind == .preview {
            block.autoPreviewIndex = nextPreviewIndex(considering: current)
        }
        current.append(block)
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    func addTerminalBlock(cwd: URL, title: String? = nil) {
        var current = blocks
        let block = WorkspaceBlock(kind: .terminal, cwd: cwd)
        block.autoTerminalIndex = Self.nextTerminalIndex(in: current)
        block.customTitle = title
        current.append(block)
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    private static func nextTerminalIndex(in blocks: [WorkspaceBlock]) -> Int {
        let used = Set(blocks.compactMap { $0.kind == .terminal ? $0.autoTerminalIndex : nil })
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }

    private func nextPreviewIndex(considering pendingBlocks: [WorkspaceBlock]) -> Int {
        var used: Set<Int> = []
        for blocks in blocksByKind.values {
            for block in blocks where block.kind == .preview {
                if let idx = block.autoPreviewIndex { used.insert(idx) }
            }
        }
        for block in pendingBlocks where block.kind == .preview {
            if let idx = block.autoPreviewIndex { used.insert(idx) }
        }
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }

    func removeBlock(_ id: UUID) {
        var current = blocks
        guard let idx = current.firstIndex(where: { $0.id == id }) else { return }
        current[idx].cleanup()
        current.remove(at: idx)
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    func swapBlocks(at a: Int, with b: Int) {
        var current = blocks
        guard a != b, current.indices.contains(a), current.indices.contains(b) else { return }
        current[a].pin = nil
        current[b].pin = nil
        current.swapAt(a, b)
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    func setPin(_ id: UUID, to pin: BlockPin?) {
        let current = blocks
        for block in current {
            if block.id == id {
                // Re-pinning to a different edge clears any prior pin
                // fraction so the new edge starts at the default 50% split.
                // Re-pinning to the same edge keeps the user's drag.
                if block.pin != pin {
                    block.pinFraction = nil
                }
                block.pin = pin
            } else if pin != nil {
                block.pin = nil
                block.pinFraction = nil
            }
        }
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    /// Apply new width/height weights to a pair of adjacent blocks (a single
    /// drag of a divider). Both ends are clamped to `WorkspaceBlock.weightRange`.
    func applyWeights(_ updates: [(id: UUID, width: Double?, height: Double?)]) {
        let current = blocks
        for update in updates {
            guard let block = current.first(where: { $0.id == update.id }) else { continue }
            if let w = update.width {
                block.widthWeight = min(max(w, WorkspaceBlock.weightRange.lowerBound),
                                        WorkspaceBlock.weightRange.upperBound)
            }
            if let h = update.height {
                block.heightWeight = min(max(h, WorkspaceBlock.weightRange.lowerBound),
                                         WorkspaceBlock.weightRange.upperBound)
            }
        }
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    /// Update the pin/free split for a pinned block. No-op when the block
    /// isn't pinned. Clamped to `WorkspaceBlock.pinFractionRange`.
    func setPinFraction(_ id: UUID, to fraction: Double) {
        let current = blocks
        guard let block = current.first(where: { $0.id == id }), block.pin != nil else { return }
        block.pinFraction = min(max(fraction, WorkspaceBlock.pinFractionRange.lowerBound),
                                WorkspaceBlock.pinFractionRange.upperBound)
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    /// Update the horizontal cell-fill fraction for a single block. Drives
    /// the trailing-edge resize handle, which is the only horizontal control
    /// in a stacked single-block row.
    func setWidthFraction(_ id: UUID, to fraction: Double) {
        let current = blocks
        guard let block = current.first(where: { $0.id == id }) else { return }
        block.widthFraction = min(max(fraction, WorkspaceBlock.widthFractionRange.lowerBound),
                                  WorkspaceBlock.widthFractionRange.upperBound)
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    /// Reset weights for a specific pair (the two sides of one divider).
    func resetWeights(for ids: [UUID]) {
        let current = blocks
        for block in current where ids.contains(block.id) {
            block.widthWeight = 1.0
            block.heightWeight = 1.0
            block.widthFraction = 1.0
        }
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    /// Reset all weights and pin fractions on the current deck. Pin
    /// assignments themselves are preserved; only the fractions revert.
    func resetAllWeights() {
        let current = blocks
        for block in current {
            block.widthWeight = 1.0
            block.heightWeight = 1.0
            block.pinFraction = nil
            block.widthFraction = 1.0
        }
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    func toggleSpan(_ id: UUID) {
        let current = blocks
        for block in current where block.id == id {
            block.spansFullRow.toggle()
        }
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    func setTitle(_ id: UUID, to title: String?) {
        let current = blocks
        for block in current where block.id == id {
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                block.customTitle = trimmed
            } else {
                block.customTitle = nil
            }
        }
        blocksByKind[currentKind] = current
        persistCurrent()
    }

    private func persistCurrent() {
        guard hasHydrated else { return }
        LayoutPersistence.save(kind: currentKind, blocks: blocks)
    }

    func index(of id: UUID) -> Int? {
        blocks.firstIndex(where: { $0.id == id })
    }

    nonisolated static func capacity(for size: CGSize) -> (cols: Int, rows: Int) {
        let w = size.width
        let h = size.height
        if w >= 1800 && h >= 900 { return (4, 3) }
        if w >= 1300 { return (4, 2) }
        if w >= 900  { return (3, 2) }
        return (2, 2)
    }

    func firstTerminalSession() -> TerminalSession? {
        blocks.first(where: { $0.kind == .terminal })?.terminalSession
    }

    func ensureTerminalBlock() {
        if firstTerminalSession() == nil {
            addBlock(.terminal)
        }
    }

    func startLiveAgentPolling() {
        guard liveAgentTimer == nil else { return }
        recomputeLiveAgentCount()
        liveAgentTimer = Timer.scheduledTimer(
            withTimeInterval: liveAgentPollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.recomputeLiveAgentCount() }
        }
    }

    private func recomputeLiveAgentCount() {
        var count = 0
        for blocks in blocksByKind.values {
            for block in blocks where block.kind == .terminal {
                for session in block.terminalSessions where session.isRunningCLIAgent {
                    count += 1
                }
            }
        }
        if liveAgentTerminalCount != count {
            liveAgentTerminalCount = count
        }
    }

    private func makeDefaults(for kind: WorkspaceKind) -> [WorkspaceBlock] {
        switch kind {
        case .code:
            let terminal = WorkspaceBlock(kind: .terminal, cwd: defaultCwd)
            terminal.autoTerminalIndex = 1
            return [
                terminal,
                WorkspaceBlock(kind: .tasks),
                WorkspaceBlock(kind: .agent)
            ]
        case .ideas:
            return [
                WorkspaceBlock(kind: .notes),
                WorkspaceBlock(kind: .agent)
            ]
        case .review:
            let preview = WorkspaceBlock(kind: .preview, cwd: defaultCwd)
            preview.autoPreviewIndex = nextPreviewIndex(considering: [])
            return [
                preview,
                WorkspaceBlock(kind: .agent)
            ]
        }
    }
}
