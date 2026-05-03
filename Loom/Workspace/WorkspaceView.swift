import SwiftUI
import SwiftData

struct WorkspaceView: View {
    @Environment(WorkspaceLayout.self) private var layout
    @Environment(UpdateService.self) private var updates
    @Environment(WorkspaceContext.self) private var workspaceContext
    @Query(sort: \Workspace.createdAt) private var workspaces: [Workspace]
    @State private var deckSize: CGSize = CGSize(width: 1400, height: 800)
    @State private var draggingBlockID: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var dragTarget: DropTarget?
    @State private var renamingBlockID: UUID?
    @State private var selectedUsageTool: CLITool? = nil

    private var deckCapacity: Int {
        let cap = WorkspaceLayout.capacity(for: deckSize)
        return cap.cols * cap.rows
    }

    private var canAddBlock: Bool {
        layout.blocks.count < deckCapacity
    }

    private var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == layout.selectedWorkspaceID }
    }

    private var currentKind: WorkspaceKind {
        selectedWorkspace?.kind ?? .code
    }

    var body: some View {
        ZStack {
            LoomTheme.background
                .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar

                HStack(alignment: .top, spacing: 12) {
                    leftRail
                        .frame(width: 240)

                    deckOrUsage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(14)
        }
        .loomAppearance()
        .onChange(of: layout.selectedWorkspaceID) { _, _ in handleWorkspaceChange() }
        .onChange(of: selectedWorkspace?.folderPath) { _, _ in syncTerminalCwd() }
        .task { handleWorkspaceChange() }
    }

    private func handleWorkspaceChange() {
        // Workspace switching swaps the deck in a single frame — animating
        // the cross-fade adds 100+ms of perceived latency for no payoff.
        // Drag/reorder mutations still animate via their own withAnimation.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            syncTerminalCwd()
            if let kind = selectedWorkspace?.kind {
                layout.bind(to: kind)
            }
            publishWorkspaceContext()
        }
    }

    private func publishWorkspaceContext() {
        let ws = selectedWorkspace
        workspaceContext.workspaceKind = ws?.kind ?? .code
        workspaceContext.workspaceID = ws?.id
        workspaceContext.workspaceName = ws?.name ?? ""
        workspaceContext.folderPath = ws?.folderPath ?? ""
        // The active tab + commit closures get republished by NotesPaneView
        // when it appears for the new workspace; clear stale state so the
        // agent doesn't think the prior workspace's tab is still focused.
        workspaceContext.activeTab = .none
        workspaceContext.appendToActiveTab = nil
        workspaceContext.createTabsForItems = nil
        workspaceContext.readActiveTabBody = nil
        workspaceContext.readSiblingTabs = nil
    }

    private func syncTerminalCwd() {
        layout.setDefaultCwd(selectedWorkspace?.folderURL)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Image("LoomBanner")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(LoomTheme.hairline, lineWidth: 1)
                }
                .accessibilityLabel("Loom")

            usageTabs

            Spacer()

            if selectedUsageTool == nil {
                addBlockStrip
            }

            if updates.available != nil {
                updatePill
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.18), value: updates.available)
    }

    private var updatePill: some View {
        Button {
            updates.applyAndRelaunch()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: updates.isApplying ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                Text(updates.isApplying ? "Restarting…" : "Update")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                if let label = updates.available?.displayLabel, !updates.isApplying {
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LoomTheme.green)
            .clipShape(Capsule())
            .shadow(color: LoomTheme.green.opacity(0.5), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(updates.isApplying)
        .help("Restart Loom with the staged build")
    }

    private var usageTabs: some View {
        HStack(spacing: 6) {
            usageTab(.claude, label: "Claude Usage")
            usageTab(.codex,  label: "Codex Usage")
            usageTab(.gemini, label: "Gemini Usage")
        }
    }

    private func usageTab(_ tool: CLITool, label: String) -> some View {
        let isSelected = selectedUsageTool == tool
        return Button {
            selectedUsageTool = isSelected ? nil : tool
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? .white : tool.brandColor)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : LoomTheme.primaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? tool.brandColor : LoomTheme.softPanel.opacity(0.7))
            .overlay(Capsule().stroke(LoomTheme.hairline, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Click a workspace to return" : "Open \(label) dashboard")
    }

    private var addBlockStrip: some View {
        HStack(spacing: 4) {
            ForEach(currentKind.availablePanels) { panel in
                addBlockButton(panel)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(LoomTheme.softPanel.opacity(0.6))
        .overlay(Capsule().stroke(LoomTheme.hairline, lineWidth: 1))
        .clipShape(Capsule())
    }

    private func addBlockButton(_ panel: PanelKind) -> some View {
        Button {
            guard canAddBlock else { return }
            layout.addBlock(panel)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Image(systemName: panel.systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(panel.label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(canAddBlock ? LoomTheme.primaryText : LoomTheme.mutedText.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LoomTheme.softPanel.opacity(canAddBlock ? 1 : 0.4))
            .overlay(Capsule().stroke(LoomTheme.hairline, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canAddBlock)
        .help(canAddBlock ? "Add \(panel.label) block" : "Block limit reached for this window size")
    }

    // MARK: - Sidebar

    private var leftRail: some View {
        @Bindable var bindable = layout
        return LoomPanel {
            WorkspaceSidebarView(
                selectedWorkspaceID: $bindable.selectedWorkspaceID,
                selectedUsageTool: $selectedUsageTool
            )
        }
    }

    // MARK: - Deck or Usage overlay

    @ViewBuilder
    private var deckOrUsage: some View {
        if let tool = selectedUsageTool {
            LoomPanel {
                UsageView(tool: tool)
            }
            .id(tool)
        } else {
            mainDeck
        }
    }

    // MARK: - Main deck (block grid)

    private var mainDeck: some View {
        Group {
            if layout.blocks.isEmpty {
                GeometryReader { geo in
                    deckEmptyState
                        .onAppear { deckSize = geo.size }
                        .onChange(of: geo.size) { _, new in deckSize = new }
                }
            } else {
                GeometryReader { geo in
                    let metrics = DeckMetrics(size: geo.size, blocks: layout.blocks)
                    ZStack(alignment: .topLeading) {
                        if draggingBlockID != nil, case let .pin(pin) = dragTarget {
                            let rect = DeckMetrics.pinFrame(pin: pin, deckSize: geo.size, gap: metrics.gap)
                            RoundedRectangle(cornerRadius: 14)
                                .fill(LoomTheme.blue.opacity(0.13))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(
                                            LoomTheme.blue.opacity(0.65),
                                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                                        )
                                }
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }

                        ForEach(layout.blocks) { block in
                            deckBlock(block, metrics: metrics)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .coordinateSpace(name: "deck")
                    .animation(.easeOut(duration: 0.12), value: dragTarget)
                    .onAppear { deckSize = geo.size }
                    .onChange(of: geo.size) { _, new in deckSize = new }
                }
            }
        }
    }

    @ViewBuilder
    private func deckBlock(_ block: WorkspaceBlock, metrics: DeckMetrics) -> some View {
        let isDragging = draggingBlockID == block.id
        let cellRect = metrics.frame(for: block.id)
        let translation = isDragging ? dragTranslation : .zero
        let isHoverTarget: Bool = {
            guard !isDragging, draggingBlockID != nil else { return false }
            if case .swap(let id) = dragTarget, id == block.id { return true }
            return false
        }()

        LoomPanel(
            title: block.displayTitle,
            systemImage: block.kind.systemImage,
            onClose: { layout.removeBlock(block.id) },
            onDragChanged: { value in
                if draggingBlockID != block.id { draggingBlockID = block.id }
                dragTranslation = value.translation
                let cursor = CGPoint(
                    x: cellRect.midX + value.translation.width,
                    y: cellRect.midY + value.translation.height
                )
                dragTarget = metrics.dropTarget(at: cursor, draggedID: block.id)
            },
            onDragEnded: { _ in
                let resolved = dragTarget
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    switch resolved {
                    case .pin(let edge):
                        layout.setPin(block.id, to: edge)
                    case .swap(let otherID):
                        if let i = layout.index(of: block.id),
                           let j = layout.index(of: otherID) {
                            layout.swapBlocks(at: i, with: j)
                        }
                    case .none:
                        break
                    }
                    dragTranslation = .zero
                    draggingBlockID = nil
                    dragTarget = nil
                }
            },
            isDragging: isDragging,
            isHoverTarget: isHoverTarget,
            isRenaming: renamingBlockID == block.id,
            onRenameStart: { renamingBlockID = block.id },
            onRenameCommit: { newName in
                layout.setTitle(block.id, to: newName)
                renamingBlockID = nil
            }
        ) {
            blockContent(for: block)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(width: cellRect.width, height: cellRect.height)
        .position(x: cellRect.midX + translation.width, y: cellRect.midY + translation.height)
        .zIndex(isDragging ? 10 : (isHoverTarget ? 1 : 0))
        .id(block.id)
        .contextMenu {
            Button("Rename") { renamingBlockID = block.id }
            Button(block.spansFullRow ? "Collapse to grid" : "Expand to full row") {
                layout.toggleSpan(block.id)
            }
            if block.pin != nil {
                Button("Unpin") { layout.setPin(block.id, to: nil) }
            }
            if block.customTitle != nil {
                Button("Reset name") { layout.setTitle(block.id, to: nil) }
            }
            Divider()
            Button("Close block", role: .destructive) {
                layout.removeBlock(block.id)
            }
        }
    }

    @ViewBuilder
    private func blockContent(for block: WorkspaceBlock) -> some View {
        switch block.kind {
        case .terminal:
            if let session = block.terminalSession {
                TerminalPaneView(session: session)
            } else {
                Color.black
            }
        case .editor:
            EditorPaneView(rootURL: selectedWorkspace?.folderURL)
        case .tasks:
            KanbanPaneView()
        case .agent:
            AgentPaneView(cwd: selectedWorkspace?.folderURL)
        case .notes:
            NotesPaneView(workspaceID: layout.selectedWorkspaceID)
        case .preview:
            PreviewPaneView(block: block)
        }
    }

    private var deckEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(LoomTheme.mutedText)
            Text("No blocks here.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LoomTheme.primaryText)
            Text("Use the buttons in the top bar to add a block to this workspace.")
                .font(.system(size: 11))
                .foregroundStyle(LoomTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(LoomTheme.panel.opacity(0.4))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(LoomTheme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

}

#Preview {
    WorkspaceView()
        .frame(width: 1400, height: 800)
}


struct LoomPanel<Content: View>: View {
    var title: String?
    var systemImage: String?
    var onClose: (() -> Void)?
    var onDragChanged: ((DragGesture.Value) -> Void)?
    var onDragEnded: ((DragGesture.Value) -> Void)?
    var isDragging: Bool = false
    var isHoverTarget: Bool = false
    var isRenaming: Bool = false
    var onRenameStart: (() -> Void)?
    var onRenameCommit: ((String) -> Void)?
    @ViewBuilder var content: Content

    @State private var renameDraft: String = ""
    @FocusState private var renameFocused: Bool

    init(
        title: String? = nil,
        systemImage: String? = nil,
        onClose: (() -> Void)? = nil,
        onDragChanged: ((DragGesture.Value) -> Void)? = nil,
        onDragEnded: ((DragGesture.Value) -> Void)? = nil,
        isDragging: Bool = false,
        isHoverTarget: Bool = false,
        isRenaming: Bool = false,
        onRenameStart: (() -> Void)? = nil,
        onRenameCommit: ((String) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.onClose = onClose
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.isDragging = isDragging
        self.isHoverTarget = isHoverTarget
        self.isRenaming = isRenaming
        self.onRenameStart = onRenameStart
        self.onRenameCommit = onRenameCommit
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let title { titleBar(title) }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LoomTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(
            color: .black.opacity(isDragging ? 0.55 : 0.28),
            radius: isDragging ? 28 : 18,
            x: 0,
            y: isDragging ? 18 : 12
        )
        .scaleEffect(isDragging ? 1.015 : 1)
        .animation(.easeOut(duration: 0.18), value: isDragging)
        .animation(.easeOut(duration: 0.18), value: isHoverTarget)
    }

    private var borderColor: Color {
        if isDragging { return LoomTheme.orange.opacity(0.6) }
        if isHoverTarget { return LoomTheme.blue.opacity(0.55) }
        return LoomTheme.hairline
    }

    private var borderWidth: CGFloat {
        isDragging || isHoverTarget ? 1.5 : 1
    }

    @ViewBuilder
    private func titleBar(_ title: String) -> some View {
        let bar = HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LoomTheme.orange)
            }
            titleText(title)
            Spacer()
            Circle().fill(LoomTheme.green).frame(width: 7, height: 7)
            if onDragChanged != nil {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LoomTheme.mutedText.opacity(0.55))
                    .help("Drag to rearrange")
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LoomTheme.mutedText)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close block")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.16))
        .overlay(Divider().overlay(LoomTheme.hairline), alignment: .bottom)
        .contentShape(Rectangle())

        // Drag is disabled while renaming so typing doesn't fight the gesture.
        if let onDragChanged, let onDragEnded, !isRenaming {
            bar
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named("deck"))
                        .onChanged(onDragChanged)
                        .onEnded(onDragEnded)
                )
                #if canImport(AppKit)
                .onHover { hovering in
                    if hovering {
                        NSCursor.openHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                #endif
        } else {
            bar
        }
    }

    @ViewBuilder
    private func titleText(_ title: String) -> some View {
        if isRenaming, onRenameCommit != nil {
            TextField("Block name", text: $renameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LoomTheme.primaryText)
                .frame(maxWidth: 220)
                .focused($renameFocused)
                .onAppear {
                    renameDraft = title
                    renameFocused = true
                }
                .onSubmit { commitRename() }
                .onExitCommand { commitRename() }
        } else {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LoomTheme.primaryText)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    onRenameStart?()
                }
        }
    }

    private func commitRename() {
        onRenameCommit?(renameDraft)
        renameFocused = false
    }
}

enum DropTarget: Equatable, Hashable {
    case pin(BlockPin)
    case swap(UUID)
}

@MainActor
struct DeckMetrics {
    let containerSize: CGSize
    let gap: CGFloat
    let frames: [UUID: CGRect]
    let pinnedID: UUID?

    init(size: CGSize, blocks: [WorkspaceBlock]) {
        let gap: CGFloat = 12
        var frames: [UUID: CGRect] = [:]
        var pinnedID: UUID?

        if blocks.count == 1 {
            // Single block always fills the deck. Pinning makes no sense when
            // there are no other blocks to take the remainder.
            frames[blocks[0].id] = CGRect(origin: .zero, size: size)
        } else if let pinned = blocks.first(where: { $0.pin != nil }), let pin = pinned.pin {
            frames[pinned.id] = Self.pinFrame(pin: pin, deckSize: size, gap: gap)
            pinnedID = pinned.id

            let freeBlocks = blocks.filter { $0.id != pinned.id }
            if pin.isCorner {
                // L-shaped free area: a small "neighbor" quadrant adjacent to the pin
                // takes the first free block; the rest fill the opposite full-width row.
                let zones = Self.cornerComplementZones(pin: pin, deckSize: size, gap: gap)
                let neighbor = zones.neighbor
                let wideRow = zones.wideRow
                if let head = freeBlocks.first {
                    frames[head.id] = neighbor
                    let tail = Array(freeBlocks.dropFirst())
                    for (id, rect) in Self.computeEvenRow(blocks: tail, area: wideRow, gap: gap) {
                        frames[id] = rect
                    }
                }
            } else {
                let freeArea = Self.complementFrame(pin: pin, deckSize: size, gap: gap)
                for (id, rect) in Self.computeEvenRow(blocks: freeBlocks, area: freeArea, gap: gap) {
                    frames[id] = rect
                }
            }
        } else {
            let area = CGRect(origin: .zero, size: size)
            for (id, rect) in Self.computeEvenRow(blocks: blocks, area: area, gap: gap) {
                frames[id] = rect
            }
        }

        self.containerSize = size
        self.gap = gap
        self.frames = frames
        self.pinnedID = pinnedID
    }

    static func pinFrame(pin: BlockPin, deckSize: CGSize, gap: CGFloat) -> CGRect {
        let halfW = (deckSize.width - gap) / 2
        let halfH = (deckSize.height - gap) / 2
        switch pin {
        case .left:
            return CGRect(x: 0, y: 0, width: halfW, height: deckSize.height)
        case .right:
            return CGRect(x: halfW + gap, y: 0, width: halfW, height: deckSize.height)
        case .top:
            return CGRect(x: 0, y: 0, width: deckSize.width, height: halfH)
        case .bottom:
            return CGRect(x: 0, y: halfH + gap, width: deckSize.width, height: halfH)
        case .topLeft:
            return CGRect(x: 0, y: 0, width: halfW, height: halfH)
        case .topRight:
            return CGRect(x: halfW + gap, y: 0, width: halfW, height: halfH)
        case .bottomLeft:
            return CGRect(x: 0, y: halfH + gap, width: halfW, height: halfH)
        case .bottomRight:
            return CGRect(x: halfW + gap, y: halfH + gap, width: halfW, height: halfH)
        }
    }

    static func complementFrame(pin: BlockPin, deckSize: CGSize, gap: CGFloat) -> CGRect {
        let halfW = (deckSize.width - gap) / 2
        let halfH = (deckSize.height - gap) / 2
        switch pin {
        case .left:
            return CGRect(x: halfW + gap, y: 0, width: halfW, height: deckSize.height)
        case .right:
            return CGRect(x: 0, y: 0, width: halfW, height: deckSize.height)
        case .top:
            return CGRect(x: 0, y: halfH + gap, width: deckSize.width, height: halfH)
        case .bottom:
            return CGRect(x: 0, y: 0, width: deckSize.width, height: halfH)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            // Corners use cornerComplementZones; this should not be called for them.
            return CGRect(origin: .zero, size: deckSize)
        }
    }

    private static func cornerComplementZones(pin: BlockPin, deckSize: CGSize, gap: CGFloat) -> (neighbor: CGRect, wideRow: CGRect) {
        let halfW = (deckSize.width - gap) / 2
        let halfH = (deckSize.height - gap) / 2
        switch pin {
        case .topLeft:
            return (
                neighbor: CGRect(x: halfW + gap, y: 0, width: halfW, height: halfH),
                wideRow:  CGRect(x: 0, y: halfH + gap, width: deckSize.width, height: halfH)
            )
        case .topRight:
            return (
                neighbor: CGRect(x: 0, y: 0, width: halfW, height: halfH),
                wideRow:  CGRect(x: 0, y: halfH + gap, width: deckSize.width, height: halfH)
            )
        case .bottomLeft:
            return (
                neighbor: CGRect(x: halfW + gap, y: halfH + gap, width: halfW, height: halfH),
                wideRow:  CGRect(x: 0, y: 0, width: deckSize.width, height: halfH)
            )
        case .bottomRight:
            return (
                neighbor: CGRect(x: 0, y: halfH + gap, width: halfW, height: halfH),
                wideRow:  CGRect(x: 0, y: 0, width: deckSize.width, height: halfH)
            )
        default:
            return (.zero, .zero)
        }
    }

    private static func computeEvenRow(blocks: [WorkspaceBlock], area: CGRect, gap: CGFloat) -> [UUID: CGRect] {
        guard !blocks.isEmpty, area.width > 0, area.height > 0 else { return [:] }
        let cap = WorkspaceLayout.capacity(for: area.size)
        let cols = balancedCols(
            count: blocks.count,
            capCols: cap.cols,
            capRows: cap.rows,
            deckSize: area.size
        )

        // Group blocks into rows. A `spansFullRow` block always sits alone
        // in its row; otherwise we pack up to `cols` blocks per row, breaking
        // early when the next block needs a row of its own.
        var rows: [[WorkspaceBlock]] = []
        var i = 0
        while i < blocks.count {
            if blocks[i].spansFullRow {
                rows.append([blocks[i]])
                i += 1
            } else {
                var chunk: [WorkspaceBlock] = []
                while i < blocks.count, chunk.count < cols, !blocks[i].spansFullRow {
                    chunk.append(blocks[i])
                    i += 1
                }
                rows.append(chunk)
            }
        }

        let totalGapY = CGFloat(max(0, rows.count - 1)) * gap
        let cellH = max(160, (area.height - totalGapY) / CGFloat(max(1, rows.count)))
        var frames: [UUID: CGRect] = [:]
        for (rowIdx, row) in rows.enumerated() {
            let blocksInRow = row.count
            let totalGapX = CGFloat(max(0, blocksInRow - 1)) * gap
            let cellW = max(140, (area.width - totalGapX) / CGFloat(max(1, blocksInRow)))
            for (posInRow, block) in row.enumerated() {
                let x = area.minX + CGFloat(posInRow) * (cellW + gap)
                let y = area.minY + CGFloat(rowIdx) * (cellH + gap)
                frames[block.id] = CGRect(x: x, y: y, width: cellW, height: cellH)
            }
        }
        return frames
    }

    private static func balancedCols(count: Int, capCols: Int, capRows: Int, deckSize: CGSize) -> Int {
        let target: CGFloat = 1.35
        let w = max(deckSize.width, 1)
        let h = max(deckSize.height, 1)
        var bestCols = 1
        var bestScore: CGFloat = .infinity
        for cols in 1...max(capCols, 1) {
            let rows = max(1, Int(ceil(Double(count) / Double(cols))))
            if rows > capRows && cols < capCols { continue }
            let cellAspect = (w / CGFloat(cols)) / (h / CGFloat(rows))
            let score = abs(log(cellAspect / target))
            if score < bestScore {
                bestScore = score
                bestCols = cols
            }
        }
        return bestCols
    }

    func frame(for id: UUID) -> CGRect {
        frames[id] ?? .zero
    }

    /// Decide what should happen if the user drops the dragged block at the
    /// given point. Corner zones beat edge zones beat swap targets — so
    /// "drag to top-right" reads as a quadrant pin, "drag to right" as a half
    /// pin, and "drag onto another block" as a swap.
    func dropTarget(at point: CGPoint, draggedID: UUID) -> DropTarget? {
        let xMargin = max(60, containerSize.width * 0.18)
        let yMargin = max(60, containerSize.height * 0.18)
        let leftDist = point.x
        let rightDist = containerSize.width - point.x
        let topDist = point.y
        let bottomDist = containerSize.height - point.y

        let nearLeft   = leftDist   < xMargin
        let nearRight  = rightDist  < xMargin
        let nearTop    = topDist    < yMargin
        let nearBottom = bottomDist < yMargin

        if nearTop && nearLeft     { return .pin(.topLeft) }
        if nearTop && nearRight    { return .pin(.topRight) }
        if nearBottom && nearLeft  { return .pin(.bottomLeft) }
        if nearBottom && nearRight { return .pin(.bottomRight) }

        if nearLeft   { return .pin(.left) }
        if nearRight  { return .pin(.right) }
        if nearTop    { return .pin(.top) }
        if nearBottom { return .pin(.bottom) }

        for (id, rect) in frames where id != draggedID && rect.contains(point) {
            return .swap(id)
        }
        return nil
    }
}
