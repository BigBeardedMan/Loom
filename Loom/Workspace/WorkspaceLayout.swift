import Foundation
import Observation

enum PanelKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case terminal
    case editor
    case tasks
    case agent
    case notes
    case preview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .terminal: return "Terminal"
        case .editor:   return "Editor"
        case .tasks:    return "Tasks"
        case .agent:    return "Agent"
        case .notes:    return "Notes"
        case .preview:  return "Preview"
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

@Observable
@MainActor
final class WorkspaceBlock: Identifiable {
    let id: UUID
    let kind: PanelKind
    var terminalSession: TerminalSession?
    /// Persistent WebKit controller for preview blocks. Owned by the block
    /// so the WKWebView (and its loaded page) survives workspace switches —
    /// otherwise each switch tears down and re-creates the WebView, forcing
    /// a full reload of the previewed URL.
    var webController: WebController?
    var pin: BlockPin?
    var spansFullRow: Bool
    var customTitle: String?
    var autoTerminalIndex: Int?
    var autoPreviewIndex: Int?
    var previewURL: String?

    init(kind: PanelKind, cwd: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.id = UUID()
        self.kind = kind
        self.pin = nil
        self.spansFullRow = false
        self.customTitle = nil
        self.autoTerminalIndex = nil
        self.autoPreviewIndex = nil
        self.previewURL = nil
        if kind == .terminal {
            self.terminalSession = TerminalSession(cwd: cwd)
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
        terminalSession?.cleanup()
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
                block.pin = pin
            } else if pin != nil {
                block.pin = nil
            }
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
                if block.terminalSession?.isRunningCLIAgent == true {
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
