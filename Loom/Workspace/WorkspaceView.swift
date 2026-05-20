import SwiftUI
import SwiftData

struct WorkspaceView: View {
    @Environment(WorkspaceLayout.self) private var layout
    @Environment(UpdateService.self) private var updates
    @Environment(UsageService.self) private var usage
    @Environment(DictationService.self) private var dictation
    @Environment(WorkspaceContext.self) private var workspaceContext
    @Environment(TerminalTranscriptStore.self) private var terminalHistory
    @Environment(\.openURL) private var openURL
    @Query(sort: \Workspace.createdAt) private var workspaces: [Workspace]
    @State private var showCommandPalette: Bool = false
    @State private var deckSize: CGSize = CGSize(width: 1400, height: 800)
    @State private var draggingBlockID: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var dragTarget: DropTarget?
    @State private var renamingBlockID: UUID?
    @State private var selectedUsageTool: CLITool? = nil
    @State private var transcriptPreview: TerminalTranscriptSession?

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

            VStack(spacing: 10) {
                topBar

                HStack(alignment: .top, spacing: 12) {
                    leftRail
                        .frame(width: 268)

                    deckOrUsage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(12)

            if let session = transcriptPreview {
                transcriptPreviewOverlay(session)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(10)
            }
        }
        .loomAppearance()
        .onChange(of: layout.selectedWorkspaceID) { _, _ in handleWorkspaceChange() }
        .onChange(of: selectedWorkspace?.folderPath) { _, _ in syncTerminalCwd() }
        .animation(.easeOut(duration: 0.16), value: transcriptPreview?.id)
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
        HStack(spacing: 10) {
            brandButton
            verticalHairline
            workspaceIdentity
            commandPaletteButton

            Spacer()

            if let tool = selectedUsageTool {
                selectedUsageStatus(tool)
            } else {
                addBlockStrip
            }

            dictationButton

            if updates.available != nil {
                updatePill
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(LoomTheme.chrome)
        .overlay(
            RoundedRectangle(cornerRadius: LoomTheme.panelRadius)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LoomTheme.panelRadius))
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 5)
        .animation(.easeInOut(duration: 0.18), value: updates.available)
        .sheet(isPresented: $showCommandPalette) {
            CommandPalette(isPresented: $showCommandPalette)
        }
        .onReceive(NotificationCenter.default.publisher(for: .loomOpenPalette)) { _ in
            showCommandPalette = true
        }
    }

    private var brandButton: some View {
        Button {
            openURL(URL(string: "https://github.com/BigBeardedMan/Loom")!)
        } label: {
            HStack(spacing: 8) {
                LoomLogoMark(size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Loom")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LoomTheme.primaryText)
                    Text("Testing Edition")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LoomTheme.orange)
                        .tracking(0.45)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(LoomTheme.softPanel.opacity(0.58))
            .overlay(
                RoundedRectangle(cornerRadius: LoomTheme.rowRadius)
                    .stroke(LoomTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LoomTheme.rowRadius))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("Open Loom on GitHub")
        .accessibilityLabel("Loom Testing Edition, open on GitHub")
    }

    private var verticalHairline: some View {
        Rectangle()
            .fill(LoomTheme.hairline)
            .frame(width: 1, height: 28)
    }

    @ViewBuilder
    private var workspaceIdentity: some View {
        if let selectedWorkspace {
            HStack(spacing: 8) {
                Circle()
                    .fill(selectedWorkspace.color.color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(selectedWorkspace.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LoomTheme.primaryText)
                            .lineLimit(1)
                        Image(systemName: selectedWorkspace.kind.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LoomTheme.mutedText)
                    }
                    Text(selectedWorkspace.displayFolderPath.isEmpty ? selectedWorkspace.kind.label : selectedWorkspace.displayFolderPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(LoomTheme.mutedText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: 150, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LoomTheme.mutedText)
                Text("No workspace")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LoomTheme.primaryText)
            }
        }
    }

    private var commandPaletteButton: some View {
        Button {
            showCommandPalette = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                Text("Command")
                    .font(.system(size: 11, weight: .semibold))
                Text("⌘K")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LoomTheme.tertiaryText)
            }
            .foregroundStyle(LoomTheme.mutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(LoomTheme.softPanel.opacity(0.54))
            .overlay(
                RoundedRectangle(cornerRadius: LoomTheme.controlRadius)
                    .stroke(LoomTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LoomTheme.controlRadius))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("Open command palette")
    }

    private func selectedUsageStatus(_ tool: CLITool) -> some View {
        Button {
            selectedUsageTool = nil
        } label: {
            HStack(spacing: 7) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tool.brandColor)
                Text("\(tool.label) dashboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LoomTheme.primaryText)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LoomTheme.mutedText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tool.brandColor.opacity(0.12))
            .overlay(Capsule().stroke(tool.brandColor.opacity(0.32), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("Return to workspace")
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
            .shadow(color: LoomTheme.green.opacity(0.34), radius: 7, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(updates.isApplying)
        .help("Restart Loom with the staged build")
    }

    private var dictationButton: some View {
        Button {
            dictation.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: dictation.state.isActive ? "mic.fill" : "mic")
                    .font(.system(size: 11, weight: .bold))
                Text(dictation.state.isActive ? dictation.state.label : "Dictate")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(dictation.state.isActive ? .white : LoomTheme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(dictation.state.isActive ? LoomTheme.purple : LoomTheme.softPanel.opacity(0.66))
            .overlay(Capsule().stroke(dictation.state.isActive ? LoomTheme.purple.opacity(0.5) : LoomTheme.hairline, lineWidth: 1))
            .clipShape(Capsule())
            .overlay(alignment: .topTrailing) {
                if dictation.state.isActive {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 1, y: -1)
                }
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(dictationHelpText)
        .accessibilityLabel(dictation.state.isActive ? "Stop dictation" : "Start dictation")
    }

    private var dictationHelpText: String {
        switch dictation.state {
        case .idle:
            return "Start dictation (F5)"
        case .requestingPermission:
            return "Requesting microphone and speech access"
        case .listening:
            return dictation.liveTranscript.isEmpty ? "Listening… press F5 to insert or Esc to cancel" : dictation.liveTranscript
        case .transcribing:
            return "Transcribing…"
        case .error(let message):
            return message
        }
    }

    private var addBlockStrip: some View {
        HStack(spacing: 4) {
            ForEach(currentKind.availablePanels) { panel in
                addBlockButton(panel)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(LoomTheme.softPanel.opacity(0.56))
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
            .background(canAddBlock ? LoomTheme.panel.opacity(0.7) : LoomTheme.softPanel.opacity(0.34))
            .overlay(Capsule().stroke(LoomTheme.hairline, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(!canAddBlock)
        .help(canAddBlock ? "Add \(panel.label) block" : "Block limit reached for this window size")
    }

    // MARK: - Sidebar

    private var leftRail: some View {
        @Bindable var bindable = layout
        return LoomPanel {
            WorkspaceSidebarView(
                selectedWorkspaceID: $bindable.selectedWorkspaceID,
                selectedUsageTool: $selectedUsageTool,
                transcriptPreview: $transcriptPreview
            )
        }
    }

    private func transcriptPreviewOverlay(_ session: TerminalTranscriptSession) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.46)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        transcriptPreview = nil
                    }

                TerminalTranscriptDetailView(
                    session: session,
                    onStartFreshShell: {
                        let cwd = URL(fileURLWithPath: session.cwd)
                        layout.addTerminalBlock(cwd: cwd)
                        transcriptPreview = nil
                    },
                    onDismiss: {
                        transcriptPreview = nil
                    }
                )
                .environment(terminalHistory)
                .frame(
                    width: transcriptPreviewWidth(in: geo.size),
                    height: transcriptPreviewHeight(in: geo.size)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(LoomTheme.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.38), radius: 28, x: 0, y: 18)
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onExitCommand {
            transcriptPreview = nil
        }
    }

    private func transcriptPreviewWidth(in size: CGSize) -> CGFloat {
        let available = max(320, size.width - 48)
        let preferred = max(620, size.width * 0.74)
        return min(980, min(preferred, available))
    }

    private func transcriptPreviewHeight(in size: CGSize) -> CGFloat {
        let available = max(320, size.height - 48)
        let preferred = max(440, size.height * 0.76)
        return min(760, min(preferred, available))
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
                            RoundedRectangle(cornerRadius: LoomTheme.panelRadius)
                                .fill(LoomTheme.blue.opacity(0.13))
                                .overlay {
                                    RoundedRectangle(cornerRadius: LoomTheme.panelRadius)
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

                        // Divider grips overlay the gaps between blocks.
                        // Hidden until hover so the deck stays visually quiet.
                        // Identity is keyed on `kind` (stable across weight
                        // changes) so an in-flight drag isn't torn down each
                        // time the seam's rect shifts.
                        //
                        // Hit zone is padded `dividerHitPad` past the visible
                        // 12pt gap on each side of the seam. The block shadow
                        // (y:12, radius:18) bleeds well past the 12pt gap, so
                        // users aim for what *looks* like the seam and miss
                        // the tighter rect. The hairline indicator stays
                        // centered on the actual gap.
                        if draggingBlockID == nil {
                            ForEach(metrics.dividers, id: \.kind) { divider in
                                let pad = DeckMetrics.dividerHitPad
                                DividerGripView(divider: divider, metrics: metrics, deckSize: geo.size)
                                    .frame(
                                        width: divider.isVertical
                                            ? divider.rect.width + pad * 2
                                            : divider.rect.width,
                                        height: divider.isVertical
                                            ? divider.rect.height
                                            : divider.rect.height + pad * 2
                                    )
                                    .position(x: divider.rect.midX, y: divider.rect.midY)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .coordinateSpace(name: "deck")
                    .animation(.easeOut(duration: 0.12), value: dragTarget)
                    .contextMenu {
                        Button("Reset Grid Layout") { layout.resetAllWeights() }
                    }
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
            if !block.terminalSessions.isEmpty {
                TerminalPaneView(
                    block: block,
                    workspaceID: selectedWorkspace?.id,
                    workspaceName: selectedWorkspace?.name
                )
            } else {
                Color.black
            }
        case .editor:
            EditorPaneView(rootURL: selectedWorkspace?.folderURL)
        case .tasks:
            KanbanPaneView()
        case .agent:
            AgentPaneView(
                cwd: selectedWorkspace?.folderURL,
                handlesExternalRuns: block.id == layout.blocks.first(where: { $0.kind == .agent })?.id
            )
        case .notes:
            NotesPaneView(workspaceID: layout.selectedWorkspaceID)
        case .preview:
            PreviewPaneView(block: block)
        case .commands:
            CommandHistoryPaneView()
        }
    }

    private var deckEmptyState: some View {
        LoomEmptyState(
            systemImage: "rectangle.dashed",
            title: "Empty deck",
            detail: "Add Terminal, Editor, Tasks, Agent, or Commands from the command bar.",
            tint: selectedWorkspace?.color.color ?? LoomTheme.blue
        )
    }

}

#Preview {
    WorkspaceView()
        .frame(width: 1400, height: 800)
}

/// Captured at drag start so weight math is stable across the gesture even
/// as SwiftUI re-renders the view with updated metrics.
private enum DividerDragStart {
    case column(leftWeight: Double, rightWeight: Double, leftPx: CGFloat, rowWidthPx: CGFloat)
    case row(topWeight: Double, bottomWeight: Double, topPx: CGFloat, colHeightPx: CGFloat)
    case pin(fraction: Double, extentPx: CGFloat, sign: CGFloat)
    case trailing(fraction: Double, cellWidthPx: CGFloat)
}

/// Invisible 12pt-thick grip living in a gap between blocks. Renders a thin
/// hairline on hover, switches the cursor, and on drag updates the relevant
/// widthWeight/heightWeight/pinFraction live. Double-click resets to even.
@MainActor
struct DividerGripView: View {
    let divider: DeckDivider
    let metrics: DeckMetrics
    let deckSize: CGSize
    @Environment(WorkspaceLayout.self) private var layout
    @State private var isHovering: Bool = false
    @State private var isDragging: Bool = false
    @State private var dragStart: DividerDragStart? = nil

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .overlay(gripIndicator.opacity(isDragging ? 0.45 : (isHovering ? 0.25 : 0)))
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                #if canImport(AppKit)
                if hovering {
                    (divider.isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
                } else if !isDragging {
                    NSCursor.arrow.set()
                }
                #endif
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("deck"))
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStart = captureStart()
                        }
                        applyDrag(translation: value.translation)
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragStart = nil
                    }
            )
            .onTapGesture(count: 2) { resetSeam() }
    }

    @ViewBuilder
    private var gripIndicator: some View {
        if divider.isVertical {
            HStack(spacing: 0) {
                Spacer()
                Rectangle().fill(LoomTheme.hairline).frame(width: 2)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                Spacer()
                Rectangle().fill(LoomTheme.hairline).frame(height: 2)
                Spacer()
            }
        }
    }

    private func captureStart() -> DividerDragStart? {
        switch divider.kind {
        case .columnGap(let leftID, let rightID):
            guard let l = layout.blocks.first(where: { $0.id == leftID }),
                  let r = layout.blocks.first(where: { $0.id == rightID }) else { return nil }
            let leftRect = metrics.frame(for: leftID)
            let rightRect = metrics.frame(for: rightID)
            let rowWidth = leftRect.width + rightRect.width + metrics.gap
            return .column(leftWeight: l.widthWeight, rightWeight: r.widthWeight,
                           leftPx: leftRect.width, rowWidthPx: rowWidth)
        case .rowGap(let topID, let bottomID):
            guard let t = layout.blocks.first(where: { $0.id == topID }),
                  let b = layout.blocks.first(where: { $0.id == bottomID }) else { return nil }
            let topRect = metrics.frame(for: topID)
            let bottomRect = metrics.frame(for: bottomID)
            let colHeight = topRect.height + bottomRect.height + metrics.gap
            return .row(topWeight: t.heightWeight, bottomWeight: b.heightWeight,
                        topPx: topRect.height, colHeightPx: colHeight)
        case .pinSplit(let pinnedID, let axis):
            guard let p = layout.blocks.first(where: { $0.id == pinnedID }), let pin = p.pin else { return nil }
            let f0 = p.pinFraction ?? 0.5
            let extent: CGFloat = axis == .horizontal
                ? (deckSize.width - metrics.gap)
                : (deckSize.height - metrics.gap)
            return .pin(fraction: f0, extentPx: extent, sign: pinSign(for: pin, axis: axis))
        case .trailingEdge(let blockID):
            guard let b = layout.blocks.first(where: { $0.id == blockID }) else { return nil }
            let f0 = b.widthFraction
            let cellW = metrics.cellWidths[blockID] ?? metrics.frame(for: blockID).width
            return .trailing(fraction: f0, cellWidthPx: cellW)
        }
    }

    private func applyDrag(translation: CGSize) {
        guard let start = dragStart else { return }
        switch (divider.kind, start) {
        case (.columnGap(let leftID, let rightID),
              .column(let w0L, let w0R, let leftPx0, let rowWidthPx)):
            let totalW = max(0.0001, w0L + w0R)
            let usable = rowWidthPx - metrics.gap
            let minLeftPx: CGFloat = 140
            let minRightPx: CGFloat = 140
            let newLeftPx = min(max(leftPx0 + translation.width, minLeftPx),
                                max(minLeftPx, usable - minRightPx))
            let leftFrac = max(0.001, min(0.999, newLeftPx / max(1, usable)))
            let newWL = totalW * Double(leftFrac)
            let newWR = totalW - newWL
            layout.applyWeights([
                (id: leftID,  width: newWL, height: nil),
                (id: rightID, width: newWR, height: nil)
            ])

        case (.rowGap(let topID, let bottomID),
              .row(let h0T, let h0B, let topPx0, let colHeightPx)):
            let totalH = max(0.0001, h0T + h0B)
            let usable = colHeightPx - metrics.gap
            let minTopPx: CGFloat = 160
            let minBottomPx: CGFloat = 160
            let newTopPx = min(max(topPx0 + translation.height, minTopPx),
                               max(minTopPx, usable - minBottomPx))
            let topFrac = max(0.001, min(0.999, newTopPx / max(1, usable)))
            let newHT = totalH * Double(topFrac)
            let newHB = totalH - newHT
            layout.applyWeights([
                (id: topID,    width: nil, height: newHT),
                (id: bottomID, width: nil, height: newHB)
            ])

        case (.pinSplit(let pinnedID, let axis),
              .pin(let f0, let extentPx, let sign)):
            let delta: CGFloat = axis == .horizontal ? translation.width : translation.height
            let normalized = (sign * delta) / max(1, extentPx)
            let target = f0 + Double(normalized)
            layout.setPinFraction(pinnedID, to: target)

        case (.trailingEdge(let blockID),
              .trailing(let f0, let cellWidthPx)):
            // translation.width > 0 grows the block back toward the right;
            // < 0 shrinks it. Convert pixel delta to fraction-of-cell.
            let normalized = translation.width / max(1, cellWidthPx)
            let target = f0 + Double(normalized)
            layout.setWidthFraction(blockID, to: target)

        default:
            break
        }
    }

    private func resetSeam() {
        switch divider.kind {
        case .columnGap(let leftID, let rightID), .rowGap(let leftID, let rightID):
            layout.resetWeights(for: [leftID, rightID])
        case .pinSplit(let pinnedID, _):
            // Reset just this seam by clearing the pin fraction back to 50%.
            layout.setPinFraction(pinnedID, to: 0.5)
        case .trailingEdge(let blockID):
            // Restore the block to full-cell width.
            layout.setWidthFraction(blockID, to: 1.0)
        }
    }

    /// Sign convention for pin drags. +1 means dragging the gesture's positive
    /// axis direction (right or down) increases the pin's fraction. -1 means
    /// it decreases the fraction.
    private func pinSign(for pin: BlockPin, axis: Axis) -> CGFloat {
        switch (pin, axis) {
        case (.left, .horizontal), (.bottomLeft, .horizontal), (.topLeft, .horizontal):
            return 1
        case (.right, .horizontal), (.topRight, .horizontal), (.bottomRight, .horizontal):
            return -1
        case (.top, .vertical), (.topLeft, .vertical), (.topRight, .vertical):
            return 1
        case (.bottom, .vertical), (.bottomLeft, .vertical), (.bottomRight, .vertical):
            return -1
        default:
            return 1
        }
    }
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
            RoundedRectangle(cornerRadius: LoomTheme.panelRadius)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: LoomTheme.panelRadius))
        .shadow(
            color: LoomTheme.panelShadow(active: isDragging),
            radius: isDragging ? 24 : 10,
            x: 0,
            y: isDragging ? 16 : 5
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
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LoomTheme.orange.opacity(0.14))
                        .frame(width: 22, height: 20)
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LoomTheme.orange)
                }
            }
            titleText(title)
            Spacer()
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
                        .frame(width: 22, height: 20)
                        .background(LoomTheme.softPanel.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Close block")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LoomTheme.inset)
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

/// Identifies one draggable seam in the deck. The kind tells the gesture
/// handler whose weights or pin fraction to update; the rect is the
/// 12pt-thick hit area centered in the gap.
enum DeckDividerKind: Hashable {
    /// Vertical seam between two row-mates. Drag redistributes their
    /// `widthWeight`.
    case columnGap(leftID: UUID, rightID: UUID)
    /// Horizontal seam between two rows. Drag redistributes the row anchors'
    /// `heightWeight`.
    case rowGap(topAnchorID: UUID, bottomAnchorID: UUID)
    /// Boundary of a pinned block. `axis = .horizontal` for a vertical seam
    /// (drag left/right adjusts width-side fraction); `axis = .vertical` for
    /// a horizontal seam (drag up/down adjusts height-side fraction).
    case pinSplit(pinnedID: UUID, axis: Axis)
    /// Right edge of the last block in a row. Drag adjusts the block's
    /// `widthFraction`, shrinking it toward the left and exposing deck
    /// background on the right. The only horizontal control in a
    /// single-block (stacked) row.
    case trailingEdge(blockID: UUID)
}

struct DeckDivider: Hashable {
    let kind: DeckDividerKind
    let rect: CGRect
    let isVertical: Bool
}

@MainActor
struct DeckMetrics {
    /// Extra padding added to each side of a divider's visible rect when
    /// building its hit zone. Matches the perceptual gap, which the block
    /// shadow widens past the literal 12pt gap.
    static let dividerHitPad: CGFloat = 6
    let containerSize: CGSize
    let gap: CGFloat
    let frames: [UUID: CGRect]
    let pinnedID: UUID?
    /// Pre-`widthFraction` cell width for each block. Equal to `frame.width`
    /// when the block fills its cell; larger when the block has been shrunk
    /// via the trailing-edge handle. Used by the trailing-edge drag handler
    /// to recover what the cell *could* be at full width.
    let cellWidths: [UUID: CGFloat]
    /// Draggable divider hit zones. Always centered in the 12pt gap so the
    /// grip never overlaps a block's visible content.
    let dividers: [DeckDivider]

    init(size: CGSize, blocks: [WorkspaceBlock]) {
        let gap: CGFloat = 12
        var frames: [UUID: CGRect] = [:]
        var cellWidths: [UUID: CGFloat] = [:]
        var pinnedID: UUID?
        var dividers: [DeckDivider] = []

        if blocks.count == 1 {
            // Single block fills the deck along the row but still gets a
            // trailing-edge handle so the user can carve out empty space on
            // the right via widthFraction. Pinning makes no sense when
            // there are no other blocks to take the remainder.
            let only = blocks[0]
            let cellW = size.width
            let frac = CGFloat(min(max(only.widthFraction, WorkspaceBlock.widthFractionRange.lowerBound),
                                   WorkspaceBlock.widthFractionRange.upperBound))
            let blockW = max(140, cellW * frac)
            frames[only.id] = CGRect(x: 0, y: 0, width: blockW, height: size.height)
            cellWidths[only.id] = cellW
            let trailingRect = CGRect(x: blockW, y: 0, width: gap, height: size.height)
            dividers.append(DeckDivider(
                kind: .trailingEdge(blockID: only.id),
                rect: trailingRect,
                isVertical: true
            ))
        } else if let pinned = blocks.first(where: { $0.pin != nil }), let pin = pinned.pin {
            let fraction = CGFloat(pinned.pinFraction ?? 0.5)
            frames[pinned.id] = Self.pinFrame(pin: pin, deckSize: size, gap: gap, fraction: fraction)
            cellWidths[pinned.id] = frames[pinned.id]!.width
            pinnedID = pinned.id

            let freeBlocks = blocks.filter { $0.id != pinned.id }
            if pin.isCorner {
                // L-shaped free area: a small "neighbor" quadrant adjacent to the pin
                // takes the first free block; the rest fill the opposite full-width row.
                let zones = Self.cornerComplementZones(pin: pin, deckSize: size, gap: gap, fraction: fraction)
                let neighbor = zones.neighbor
                let wideRow = zones.wideRow
                if let head = freeBlocks.first {
                    frames[head.id] = neighbor
                    cellWidths[head.id] = neighbor.width
                    let tail = Array(freeBlocks.dropFirst())
                    let rowResult = Self.computeEvenRow(blocks: tail, area: wideRow, gap: gap)
                    for (id, rect) in rowResult.frames {
                        frames[id] = rect
                    }
                    for (id, w) in rowResult.cellWidths {
                        cellWidths[id] = w
                    }
                    dividers.append(contentsOf: rowResult.dividers)
                }
            } else {
                let freeArea = Self.complementFrame(pin: pin, deckSize: size, gap: gap, fraction: fraction)
                let rowResult = Self.computeEvenRow(blocks: freeBlocks, area: freeArea, gap: gap)
                for (id, rect) in rowResult.frames {
                    frames[id] = rect
                }
                for (id, w) in rowResult.cellWidths {
                    cellWidths[id] = w
                }
                dividers.append(contentsOf: rowResult.dividers)
            }

            // Pin boundary draggable. Edge pins yield one divider (axis depends
            // on the edge); corner pins yield two (one per shared edge).
            dividers.append(contentsOf: Self.pinDividers(
                pin: pin,
                deckSize: size,
                gap: gap,
                fraction: fraction,
                pinnedID: pinned.id
            ))
        } else {
            let area = CGRect(origin: .zero, size: size)
            let rowResult = Self.computeEvenRow(blocks: blocks, area: area, gap: gap)
            for (id, rect) in rowResult.frames {
                frames[id] = rect
            }
            for (id, w) in rowResult.cellWidths {
                cellWidths[id] = w
            }
            dividers.append(contentsOf: rowResult.dividers)
        }

        self.containerSize = size
        self.gap = gap
        self.frames = frames
        self.cellWidths = cellWidths
        self.pinnedID = pinnedID
        self.dividers = dividers
    }

    static func pinFrame(pin: BlockPin, deckSize: CGSize, gap: CGFloat, fraction: CGFloat = 0.5) -> CGRect {
        let leftW  = (deckSize.width  - gap) * fraction
        let rightW = (deckSize.width  - gap) - leftW
        let topH   = (deckSize.height - gap) * fraction
        let bottomH = (deckSize.height - gap) - topH
        switch pin {
        case .left:
            return CGRect(x: 0, y: 0, width: leftW, height: deckSize.height)
        case .right:
            return CGRect(x: leftW + gap, y: 0, width: rightW, height: deckSize.height)
        case .top:
            return CGRect(x: 0, y: 0, width: deckSize.width, height: topH)
        case .bottom:
            return CGRect(x: 0, y: topH + gap, width: deckSize.width, height: bottomH)
        case .topLeft:
            return CGRect(x: 0, y: 0, width: leftW, height: topH)
        case .topRight:
            return CGRect(x: leftW + gap, y: 0, width: rightW, height: topH)
        case .bottomLeft:
            return CGRect(x: 0, y: topH + gap, width: leftW, height: bottomH)
        case .bottomRight:
            return CGRect(x: leftW + gap, y: topH + gap, width: rightW, height: bottomH)
        }
    }

    static func complementFrame(pin: BlockPin, deckSize: CGSize, gap: CGFloat, fraction: CGFloat = 0.5) -> CGRect {
        let leftW  = (deckSize.width  - gap) * fraction
        let rightW = (deckSize.width  - gap) - leftW
        let topH   = (deckSize.height - gap) * fraction
        let bottomH = (deckSize.height - gap) - topH
        switch pin {
        case .left:
            return CGRect(x: leftW + gap, y: 0, width: rightW, height: deckSize.height)
        case .right:
            return CGRect(x: 0, y: 0, width: leftW, height: deckSize.height)
        case .top:
            return CGRect(x: 0, y: topH + gap, width: deckSize.width, height: bottomH)
        case .bottom:
            return CGRect(x: 0, y: 0, width: deckSize.width, height: topH)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            // Corners use cornerComplementZones; this should not be called for them.
            return CGRect(origin: .zero, size: deckSize)
        }
    }

    private static func cornerComplementZones(pin: BlockPin, deckSize: CGSize, gap: CGFloat, fraction: CGFloat = 0.5) -> (neighbor: CGRect, wideRow: CGRect) {
        let leftW  = (deckSize.width  - gap) * fraction
        let rightW = (deckSize.width  - gap) - leftW
        let topH   = (deckSize.height - gap) * fraction
        let bottomH = (deckSize.height - gap) - topH
        switch pin {
        case .topLeft:
            return (
                neighbor: CGRect(x: leftW + gap, y: 0, width: rightW, height: topH),
                wideRow:  CGRect(x: 0, y: topH + gap, width: deckSize.width, height: bottomH)
            )
        case .topRight:
            return (
                neighbor: CGRect(x: 0, y: 0, width: leftW, height: topH),
                wideRow:  CGRect(x: 0, y: topH + gap, width: deckSize.width, height: bottomH)
            )
        case .bottomLeft:
            return (
                neighbor: CGRect(x: leftW + gap, y: topH + gap, width: rightW, height: bottomH),
                wideRow:  CGRect(x: 0, y: 0, width: deckSize.width, height: topH)
            )
        case .bottomRight:
            return (
                neighbor: CGRect(x: 0, y: topH + gap, width: leftW, height: bottomH),
                wideRow:  CGRect(x: 0, y: 0, width: deckSize.width, height: topH)
            )
        default:
            return (.zero, .zero)
        }
    }

    private static func computeEvenRow(
        blocks: [WorkspaceBlock],
        area: CGRect,
        gap: CGFloat
    ) -> (frames: [UUID: CGRect], cellWidths: [UUID: CGFloat], dividers: [DeckDivider]) {
        guard !blocks.isEmpty, area.width > 0, area.height > 0 else { return ([:], [:], []) }
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

        // Row heights come from each row's anchor block (the first one). A
        // weight of 1.0 everywhere preserves the legacy even-row behaviour.
        let totalGapY = CGFloat(max(0, rows.count - 1)) * gap
        let usableH = max(0, area.height - totalGapY)
        let rowWeights: [CGFloat] = rows.map { row in
            CGFloat(row.first?.heightWeight ?? 1.0)
        }
        let rowWeightSum = max(rowWeights.reduce(0, +), 0.0001)
        let rawRowHeights: [CGFloat] = rowWeights.map { w in
            usableH * w / rowWeightSum
        }
        let rowHeights: [CGFloat] = rawRowHeights.map { max(160, $0) }

        var frames: [UUID: CGRect] = [:]
        var cellWidths: [UUID: CGFloat] = [:]
        var dividers: [DeckDivider] = []
        var cursorY = area.minY
        for (rowIdx, row) in rows.enumerated() {
            let blocksInRow = row.count
            let totalGapX = CGFloat(max(0, blocksInRow - 1)) * gap
            let usableW = max(0, area.width - totalGapX)
            let rowH = rowHeights[rowIdx]

            // Column widths from per-block widthWeight. Full-row blocks ignore
            // weights entirely; everyone else shares usableW proportionally.
            let weights: [CGFloat] = row.map { CGFloat($0.widthWeight) }
            let weightSum = max(weights.reduce(0, +), 0.0001)
            let rawWidths: [CGFloat] = weights.map { w in usableW * w / weightSum }
            let widths: [CGFloat] = rawWidths.map { max(140, $0) }

            var cursorX = area.minX
            for (posInRow, block) in row.enumerated() {
                let isLast = (posInRow == row.count - 1)
                let cellW = widths[posInRow]
                // widthFraction only applies to the LAST block in a row. For
                // earlier blocks the columnGap to their right is the resize
                // control; introducing a second handle there would overlap
                // it. The last block has no columnGap, so its widthFraction
                // shrinks it toward the left, exposing deck background on
                // the right where a trailing-edge handle lives.
                let frac: CGFloat = isLast
                    ? CGFloat(min(max(block.widthFraction, WorkspaceBlock.widthFractionRange.lowerBound),
                                  WorkspaceBlock.widthFractionRange.upperBound))
                    : 1.0
                let blockW = max(140, cellW * frac)
                frames[block.id] = CGRect(x: cursorX, y: cursorY, width: blockW, height: rowH)
                cellWidths[block.id] = cellW
                // Vertical divider between this block and the next in the row.
                if !isLast {
                    let dividerX = cursorX + cellW
                    let rightID = row[posInRow + 1].id
                    let rect = CGRect(x: dividerX, y: cursorY, width: gap, height: rowH)
                    dividers.append(DeckDivider(
                        kind: .columnGap(leftID: block.id, rightID: rightID),
                        rect: rect,
                        isVertical: true
                    ))
                } else {
                    // Trailing-edge handle for the last block in the row.
                    // Always sits flush against the block's right edge (12pt
                    // wide), so the grip moves with the block as it shrinks
                    // or grows. The exposed deck background to the right is
                    // visual feedback for the new widthFraction.
                    let trailingRect = CGRect(
                        x: cursorX + blockW,
                        y: cursorY,
                        width: gap,
                        height: rowH
                    )
                    dividers.append(DeckDivider(
                        kind: .trailingEdge(blockID: block.id),
                        rect: trailingRect,
                        isVertical: true
                    ))
                }
                cursorX += cellW + gap
            }

            // Horizontal divider between this row and the next.
            if rowIdx < rows.count - 1 {
                let dividerY = cursorY + rowH
                let topAnchorID = row.first!.id
                let bottomAnchorID = rows[rowIdx + 1].first!.id
                let rect = CGRect(x: area.minX, y: dividerY, width: area.width, height: gap)
                dividers.append(DeckDivider(
                    kind: .rowGap(topAnchorID: topAnchorID, bottomAnchorID: bottomAnchorID),
                    rect: rect,
                    isVertical: false
                ))
            }
            cursorY += rowH + gap
        }
        return (frames, cellWidths, dividers)
    }

    /// Build the draggable boundary divider(s) for a pinned block. Edge pins
    /// yield one divider whose axis matches the edge; corner pins yield two,
    /// one along each shared edge of the corner quadrant.
    private static func pinDividers(
        pin: BlockPin,
        deckSize: CGSize,
        gap: CGFloat,
        fraction: CGFloat,
        pinnedID: UUID
    ) -> [DeckDivider] {
        let leftW  = (deckSize.width  - gap) * fraction
        let topH   = (deckSize.height - gap) * fraction
        switch pin {
        case .left, .right:
            // Vertical divider at the seam. Position is just past the pinned
            // block's right edge (or just before its left edge for .right).
            let x: CGFloat = (pin == .left) ? leftW : ((deckSize.width - gap) - leftW)
            let rect = CGRect(x: x, y: 0, width: gap, height: deckSize.height)
            return [DeckDivider(
                kind: .pinSplit(pinnedID: pinnedID, axis: .horizontal),
                rect: rect,
                isVertical: true
            )]
        case .top, .bottom:
            let y: CGFloat = (pin == .top) ? topH : ((deckSize.height - gap) - topH)
            let rect = CGRect(x: 0, y: y, width: deckSize.width, height: gap)
            return [DeckDivider(
                kind: .pinSplit(pinnedID: pinnedID, axis: .vertical),
                rect: rect,
                isVertical: false
            )]
        case .topLeft:
            let vRect = CGRect(x: leftW, y: 0, width: gap, height: topH)
            let hRect = CGRect(x: 0, y: topH, width: deckSize.width, height: gap)
            return [
                DeckDivider(kind: .pinSplit(pinnedID: pinnedID, axis: .horizontal), rect: vRect, isVertical: true),
                DeckDivider(kind: .pinSplit(pinnedID: pinnedID, axis: .vertical),   rect: hRect, isVertical: false)
            ]
        case .topRight:
            let vRect = CGRect(x: (deckSize.width - gap) - leftW, y: 0, width: gap, height: topH)
            let hRect = CGRect(x: 0, y: topH, width: deckSize.width, height: gap)
            return [
                DeckDivider(kind: .pinSplit(pinnedID: pinnedID, axis: .horizontal), rect: vRect, isVertical: true),
                DeckDivider(kind: .pinSplit(pinnedID: pinnedID, axis: .vertical),   rect: hRect, isVertical: false)
            ]
        case .bottomLeft:
            let vRect = CGRect(x: leftW, y: topH + gap, width: gap, height: (deckSize.height - gap) - topH)
            let hRect = CGRect(x: 0, y: topH, width: deckSize.width, height: gap)
            return [
                DeckDivider(kind: .pinSplit(pinnedID: pinnedID, axis: .horizontal), rect: vRect, isVertical: true),
                DeckDivider(kind: .pinSplit(pinnedID: pinnedID, axis: .vertical),   rect: hRect, isVertical: false)
            ]
        case .bottomRight:
            let vRect = CGRect(x: (deckSize.width - gap) - leftW, y: topH + gap, width: gap, height: (deckSize.height - gap) - topH)
            let hRect = CGRect(x: 0, y: topH, width: deckSize.width, height: gap)
            return [
                DeckDivider(kind: .pinSplit(pinnedID: pinnedID, axis: .horizontal), rect: vRect, isVertical: true),
                DeckDivider(kind: .pinSplit(pinnedID: pinnedID, axis: .vertical),   rect: hRect, isVertical: false)
            ]
        }
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
