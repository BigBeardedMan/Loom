import AppKit
import SwiftData
import SwiftUI

enum WorkspaceRightRailTab: String, CaseIterable, Identifiable {
    case files
    case preview
    case timeline
    case tools
    case diff
    case memory
    case details

    var id: String { rawValue }

    var label: String {
        switch self {
        case .timeline: return "Timeline"
        case .files:    return "Files"
        case .preview:  return "Preview"
        case .tools:    return "Tools"
        case .diff:     return "Diff"
        case .memory:   return "Memory"
        case .details:  return "Details"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: return "point.3.connected.trianglepath.dotted"
        case .files:    return "folder"
        case .preview:  return "globe"
        case .tools:    return "wrench.and.screwdriver"
        case .diff:     return "plusminus"
        case .memory:   return "brain.head.profile"
        case .details:  return "sidebar.right"
        }
    }
}

struct WorkspaceRoomRailView: View {
    @Environment(\.modelContext) private var modelContext
    let workspaces: [Workspace]
    @Binding var selectedWorkspaceID: UUID?
    @Binding var selectedUsageTool: CLITool?
    let isRightRailVisible: Bool
    let activeInspectorTab: WorkspaceRightRailTab
    let toggleRightRail: () -> Void
    let openInspector: (WorkspaceRightRailTab) -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(workspaces) { workspace in
                roomButton(workspace)
            }

            Spacer(minLength: 12)

            Divider()
                .overlay(LoomTheme.hairline)
                .padding(.horizontal, 10)

            railUtilityButton(
                systemImage: "chart.line.uptrend.xyaxis",
                help: "Usage dashboards",
                isActive: selectedUsageTool != nil,
                action: { selectedUsageTool = selectedUsageTool == nil ? .claude : nil }
            )

            railUtilityButton(
                systemImage: "wrench.and.screwdriver",
                help: "Open tools and models",
                isActive: isRightRailVisible && activeInspectorTab == .tools,
                action: { openInspector(.tools) }
            )

            railUtilityButton(
                systemImage: "sidebar.right",
                help: isRightRailVisible ? "Hide inspector" : "Show inspector",
                isActive: isRightRailVisible,
                action: toggleRightRail
            )

            railUtilityButton(
                systemImage: "gearshape",
                help: "Open Settings",
                isActive: false,
                action: openSettings
            )
        }
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity)
        .background(LoomTheme.shellRail)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func roomButton(_ workspace: Workspace) -> some View {
        let selected = workspace.id == selectedWorkspaceID && selectedUsageTool == nil
        let hasFolder = !workspace.folderPath.isEmpty
        return Button {
            selectRoom(workspace)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: workspace.kind.systemImage)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(selected ? .white : workspace.color.color)
                        .frame(width: 34, height: 28)
                        .background(selected ? workspace.color.color : workspace.color.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    if hasFolder {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(selected ? workspace.color.color : LoomTheme.primaryText)
                            .frame(width: 13, height: 13)
                            .background(selected ? .white : workspace.color.color)
                            .clipShape(Circle())
                            .offset(x: 5, y: -5)
                    }
                }
                Text(workspace.kind.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? LoomTheme.primaryText : LoomTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 52)
            .padding(.vertical, 5)
            .background(selected ? LoomTheme.softPanel.opacity(0.75) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(roomHelp(for: workspace))
        .accessibilityLabel(roomHelp(for: workspace))
        .contextMenu {
            roomContextMenu(for: workspace)
        }
    }

    private func selectRoom(_ workspace: Workspace) {
        selectedUsageTool = nil
        selectedWorkspaceID = workspace.id
    }

    @ViewBuilder
    private func roomContextMenu(for workspace: Workspace) -> some View {
        let hasFolder = !workspace.folderPath.isEmpty
        Button(hasFolder ? "Change Folder..." : "Set Folder...") {
            chooseFolder(for: workspace)
        }
        if hasFolder {
            Button("Reveal in Finder") {
                revealInFinder(workspace)
            }
            Button("Clear Folder", role: .destructive) {
                clearFolder(for: workspace)
            }
        }
    }

    private func chooseFolder(for workspace: Workspace) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for \(workspace.kind.label)"
        if !workspace.folderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: workspace.folderPath)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectRoom(workspace)
        workspace.folderPath = url.path
        try? modelContext.save()
    }

    private func clearFolder(for workspace: Workspace) {
        selectRoom(workspace)
        workspace.folderPath = ""
        try? modelContext.save()
    }

    private func revealInFinder(_ workspace: Workspace) {
        guard let url = workspace.folderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func roomHelp(for workspace: Workspace) -> String {
        if workspace.folderPath.isEmpty {
            return "Open \(workspace.kind.label). Right-click to set a folder."
        }
        return "Open \(workspace.kind.label): \(workspace.displayFolderPath)"
    }

    private func railUtilityButton(
        systemImage: String,
        help: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? .white : LoomTheme.mutedText)
                .frame(width: 34, height: 30)
                .background(isActive ? LoomTheme.blue : LoomTheme.softPanel.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

struct WorkspaceRightRailView: View {
    @Environment(LiveAgentTasksService.self) private var liveAgentTasks
    @Environment(AgentRegistry.self) private var agentRegistry
    @Environment(LocalEndpointStore.self) private var endpointStore
    @Binding var selectedTab: WorkspaceRightRailTab
    let refreshNonce: Int
    let workspace: Workspace?
    let selectedBlock: WorkspaceBlock?
    let blocks: [WorkspaceBlock]

    @State private var runSummaries: [AgentGraphRunSummary] = []
    @State private var expandedRunID: String?
    @State private var loadingRunID: String?
    @State private var eventsByRunID: [String: [AgentGraphEvent]] = [:]
    @State private var memoryFiles: [WorkspaceMemoryFile] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            tabStrip
            Divider().overlay(LoomTheme.hairline)
            content
        }
        .background(LoomTheme.shellInspector)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: refreshKey) {
            await refreshRailData()
        }
        .task(id: reviewEvidenceTaskKey) {
            await prefetchReviewEvidenceIfNeeded()
        }
    }

    private var refreshKey: String {
        "\(workspace?.id.uuidString ?? "none"):\(refreshNonce)"
    }

    private var effectiveTab: WorkspaceRightRailTab {
        availableTabs.contains(selectedTab) ? selectedTab : availableTabs.first ?? .details
    }

    private var availableTabs: [WorkspaceRightRailTab] {
        var tabs: [WorkspaceRightRailTab] = []
        if workspace?.folderPath.isEmpty == false { tabs.append(.files) }
        if blocks.contains(where: { $0.kind == .preview }) || selectedBlock?.kind == .preview { tabs.append(.preview) }
        tabs.append(.timeline)
        tabs.append(.tools)
        if workspace?.kind == .review || workspace?.kind == .runs || scopedRunSummaries.contains(where: { $0.gitBranch != nil || $0.gitDirty != nil || $0.toolEventCount > 0 }) {
            tabs.append(.diff)
        }
        if workspace?.folderPath.isEmpty == false || !memoryFiles.isEmpty || !scopedRunSummaries.isEmpty {
            tabs.append(.memory)
        }
        tabs.append(.details)
        return tabs
    }

    private var scopedRunSummaries: [AgentGraphRunSummary] {
        guard let folderPath = workspace?.folderPath, !folderPath.isEmpty else {
            return runSummaries
        }
        let root = normalizedPath(folderPath)
        return runSummaries.filter { summary in
            guard let workspacePath = summary.workspacePath, !workspacePath.isEmpty else { return false }
            let candidate = normalizedPath(workspacePath)
            return candidate == root || candidate.hasPrefix(root + "/")
        }
    }

    private var scopedLiveAgentGroups: [LiveAgentTaskGroup] {
        guard let folderPath = workspace?.folderPath, !folderPath.isEmpty else {
            return liveAgentTasks.groups
        }
        let root = normalizedPath(folderPath)
        return liveAgentTasks.groups.filter { group in
            guard let workspacePath = group.workspacePath,
                  !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return true
            }
            let candidate = normalizedPath(workspacePath)
            return candidate == root || candidate.hasPrefix(root + "/")
        }
    }

    private var reviewableRunSummaries: [AgentGraphRunSummary] {
        scopedRunSummaries.filter(isReviewable)
    }

    private var reviewEvidenceTaskKey: String {
        let ids = reviewableRunSummaries.prefix(6).map(\.id).joined(separator: ",")
        return "\(effectiveTab.rawValue):\(ids)"
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "rectangle.3.group.bubble.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(workspace?.color.color ?? LoomTheme.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(workspace?.kind.label ?? "Inspector")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LoomTheme.primaryText)
                Text(selectedBlock?.displayTitle ?? "Adaptive context")
                    .font(.system(size: 10))
                    .foregroundStyle(LoomTheme.mutedText)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await refreshRailData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LoomTheme.mutedText)
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Refresh rail data")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(availableTabs) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(effectiveTab == tab ? .white : LoomTheme.mutedText)
                            .frame(width: 26, height: 24)
                            .background(effectiveTab == tab ? LoomTheme.blue : LoomTheme.softPanel.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help(tab.label)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                workflowMap
                switch effectiveTab {
                case .timeline: timelineContent
                case .files: filesContent
                case .preview: previewContent
                case .tools: toolsContent
                case .diff: diffContent
                case .memory: memoryContent
                case .details: detailsContent
                }
            }
            .padding(12)
        }
    }

    private var workflowMap: some View {
        let signals = workflowSignals
        let phases = [
            ("Scope", workspace != nil, workspace?.color.color ?? LoomTheme.blue),
            ("Workspace", workspace?.folderPath.isEmpty == false, LoomTheme.blue),
            ("Agents", signals.hasActiveAgents, LoomTheme.purple),
            ("Checks", signals.hasCheckSignals, LoomTheme.green),
            ("Review", signals.hasReviewSignals, signals.hasAttention ? LoomTheme.orange : LoomTheme.green),
            ("Ship", signals.shipReady, LoomTheme.green)
        ]
        return VStack(alignment: .leading, spacing: 7) {
            railSectionTitle("Workflow")
            HStack(spacing: 5) {
                ForEach(Array(phases.enumerated()), id: \.offset) { _, phase in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(phase.1 ? phase.2 : LoomTheme.hairline)
                            .frame(width: 7, height: 7)
                        Text(phase.0)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(phase.1 ? LoomTheme.primaryText : LoomTheme.tertiaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .background(LoomTheme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            railSectionTitle("Live Runs")
            if scopedLiveAgentGroups.isEmpty {
                railMuted("No live agent task groups are active.")
            } else {
                ForEach(scopedLiveAgentGroups.prefix(5)) { group in
                    railRow(
                        icon: group.source.systemImage,
                        tint: group.source.brandColor,
                        title: group.displayName,
                        detail: group.headline ?? "\(group.tasks.count) tasks"
                    )
                }
            }

            railSectionTitle("Recent History")
            if scopedRunSummaries.isEmpty {
                railMuted("No graph ledgers found under ~/.loom/agent-runs.")
            } else {
                ForEach(scopedRunSummaries.prefix(8)) { summary in
                    runHistoryCard(summary)
                }
            }
        }
    }

    private func runHistoryCard(_ summary: AgentGraphRunSummary) -> some View {
        let expanded = expandedRunID == summary.id
        let events = eventsByRunID[summary.id] ?? []
        let recentEvents = Array(events.suffix(5).reversed())
        let evidence = ledgerEvidence(from: events)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleRunExpansion(summary)
            } label: {
                HStack(alignment: .center, spacing: 6) {
                    railRow(
                        icon: statusIcon(summary.status),
                        tint: statusTint(summary.status),
                        title: summary.title,
                        detail: summaryChips(summary).joined(separator: " · ")
                    )
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LoomTheme.tertiaryText)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(expanded ? "Collapse run ledger" : "Inspect run ledger")

            if expanded {
                Divider()
                    .overlay(LoomTheme.hairline)
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 7) {
                    if loadingRunID == summary.id {
                        railMuted("Loading ledger events...")
                    } else if recentEvents.isEmpty {
                        railMuted("No ledger events found.")
                    } else {
                        ForEach(recentEvents, id: \.eventID) { event in
                            railRow(
                                icon: eventIcon(event.type),
                                tint: eventTint(event.type),
                                title: event.type.rawValue,
                                detail: eventDetail(event)
                            )
                        }
                    }

                    if !evidence.isEmpty {
                        railSectionTitle("Evidence")
                        ForEach(evidence) { item in
                            railRow(
                                icon: item.icon,
                                tint: item.tint,
                                title: item.title,
                                detail: item.detail
                            )
                        }
                    }

                    railCode(displayPath(summary.ledgerPath))
                }
            }
        }
        .padding(10)
        .background(LoomTheme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var filesContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            railSectionTitle("Project Folder")
            if let workspace, !workspace.folderPath.isEmpty {
                railCode(workspace.displayFolderPath)
                if memoryFiles.isEmpty {
                    railMuted("No agent memory files found in this folder.")
                } else {
                    ForEach(memoryFiles) { file in
                        railRow(
                            icon: "doc.text",
                            tint: LoomTheme.blue,
                            title: file.name,
                            detail: "\(file.characterCount) bytes"
                        )
                    }
                }
            } else {
                railMuted("Bind this workspace to a folder to show project context.")
            }
        }
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            railSectionTitle("Previews")
            let previewBlocks = blocks.filter { $0.kind == .preview }
            if previewBlocks.isEmpty {
                railMuted("No Preview panes in this room.")
            } else {
                ForEach(previewBlocks) { block in
                    railRow(
                        icon: "globe",
                        tint: LoomTheme.pink,
                        title: block.displayTitle,
                        detail: block.effectivePreviewURL
                    )
                }
            }
        }
    }

    private var toolsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            railSectionTitle("Block Tools")
            ForEach(panelCounts, id: \.kind) { entry in
                railRow(
                    icon: entry.kind.systemImage,
                    tint: panelTint(entry.kind),
                    title: entry.kind.label,
                    detail: "\(entry.count) open"
                )
            }

            railSectionTitle("Selected Model")
            railRow(
                icon: providerIcon(agentRegistry.selectedAgent.vendor),
                tint: providerTint(agentRegistry.selectedAgent.vendor),
                title: agentRegistry.selectedAgent.vendor.label,
                detail: selectedAgentDetail
            )

            railSectionTitle("Local Endpoints")
            if endpointStore.endpoints.isEmpty {
                railMuted("No local providers configured. Add Ollama, LM Studio, or OpenAI-compatible endpoints in Settings.")
            } else {
                ForEach(endpointStore.endpoints) { endpoint in
                    railRow(
                        icon: "server.rack",
                        tint: endpointTint(endpoint.kind),
                        title: endpoint.displayName,
                        detail: "\(endpoint.kind.label) · \(endpoint.defaultModel.isEmpty ? endpoint.baseURL : endpoint.defaultModel)"
                    )
                }
            }

            railSectionTitle("Available Agents")
            ForEach(agentRegistry.agents.prefix(6)) { agent in
                railRow(
                    icon: providerIcon(agent.vendor),
                    tint: providerTint(agent.vendor),
                    title: agent.displayName,
                    detail: agent.group ?? agent.model ?? agent.vendor.label
                )
            }
        }
    }

    private var diffContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            let decision = shipDecision
            let packetRows = reviewPacketRows
            railSectionTitle("Review Packet")
            if packetRows.isEmpty {
                railMuted("No run, check, worktree, or handoff evidence has been recorded yet.")
            } else {
                ForEach(packetRows) { row in
                    railRow(
                        icon: row.icon,
                        tint: row.tint,
                        title: row.title,
                        detail: row.detail
                    )
                }
            }

            railSectionTitle("Ship Decision")
            railRow(
                icon: decision.icon,
                tint: decision.tint,
                title: decision.title,
                detail: decision.detail
            )

            railSectionTitle("Changed Files")
            let changedFiles = reviewChangedFiles
            if changedFiles.isEmpty {
                railMuted("No changed-file list has been recorded yet.")
            } else {
                ForEach(changedFiles.prefix(8), id: \.self) { path in
                    railRow(
                        icon: "doc.text",
                        tint: LoomTheme.blue,
                        title: URL(fileURLWithPath: path).lastPathComponent,
                        detail: path
                    )
                }
            }

            railSectionTitle("Review Signals")
            let reviewable = reviewableRunSummaries
            if reviewable.isEmpty {
                railMuted("No changed-file or check signals have been recorded yet.")
            } else {
                ForEach(reviewable.prefix(6)) { summary in
                    railRow(
                        icon: "plusminus",
                        tint: summary.gitDirty == true ? LoomTheme.orange : LoomTheme.green,
                        title: summary.gitBranch ?? summary.title,
                        detail: summary.gitHead ?? "\(summary.toolEventCount) tool events"
                    )
                }
            }

            railSectionTitle("Preview Status")
            let previewBlocks = blocks.filter { $0.kind == .preview }
            if previewBlocks.isEmpty {
                railMuted("No Preview panes are open in this room.")
            } else {
                ForEach(previewBlocks.prefix(3)) { block in
                    railRow(
                        icon: "globe",
                        tint: LoomTheme.pink,
                        title: block.displayTitle,
                        detail: block.effectivePreviewURL
                    )
                }
            }
        }
    }

    private var memoryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            railSectionTitle("Read-only Memory")
            if memoryFiles.isEmpty {
                railMuted("No CLAUDE.md, AGENTS.md, GUIDE.md, or README.md found for this workspace.")
            } else {
                ForEach(memoryFiles) { file in
                    VStack(alignment: .leading, spacing: 5) {
                        railRow(icon: "brain.head.profile", tint: LoomTheme.purple, title: file.name, detail: file.path)
                        Text(file.excerpt)
                            .font(.system(size: 10))
                            .foregroundStyle(LoomTheme.mutedText)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(9)
                    .background(LoomTheme.inset)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            railSectionTitle("Run Ledger Summaries")
            if scopedRunSummaries.isEmpty {
                railMuted("No graph ledger summaries found under ~/.loom/agent-runs.")
            } else {
                ForEach(scopedRunSummaries.prefix(5)) { summary in
                    VStack(alignment: .leading, spacing: 5) {
                        railRow(
                            icon: statusIcon(summary.status),
                            tint: statusTint(summary.status),
                            title: summary.title,
                            detail: summaryChips(summary).joined(separator: " · ")
                        )
                        railCode(displayPath(summary.ledgerPath))
                    }
                    .padding(9)
                    .background(LoomTheme.inset)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            railSectionTitle("Selected Pane")
            if let selectedBlock {
                railRow(icon: selectedBlock.kind.systemImage, tint: panelTint(selectedBlock.kind), title: selectedBlock.displayTitle, detail: selectedBlock.kind.label)
                if selectedBlock.kind == .terminal {
                    railMuted("\(selectedBlock.terminalSessions.count) terminal pane(s), split \(selectedBlock.terminalSplitAxis.rawValue).")
                }
                if let pin = selectedBlock.pin {
                    railCode("Pinned: \(pin)")
                }
            } else {
                railMuted("Select a pane to inspect it.")
            }

            railSectionTitle("Room")
            if let workspace {
                railRow(icon: workspace.kind.systemImage, tint: workspace.color.color, title: workspace.name, detail: workspace.kind.label)
            }
            railMuted("\(blocks.count) pane(s) open in this room.")
        }
    }

    private var panelCounts: [(kind: PanelKind, count: Int)] {
        let grouped = Dictionary(grouping: blocks, by: \.kind)
        return PanelKind.allCases.compactMap { kind in
            guard let count = grouped[kind]?.count, count > 0 else { return nil }
            return (kind, count)
        }
    }

    private func refreshRailData() async {
        runSummaries = (try? await AgentGraphLedger.shared.summaries()) ?? []
        memoryFiles = WorkspaceMemoryFile.load(from: workspace?.folderPath)
    }

    private func prefetchReviewEvidenceIfNeeded() async {
        guard effectiveTab == .diff else { return }
        for summary in reviewableRunSummaries.prefix(6) where eventsByRunID[summary.id] == nil {
            let events = (try? await AgentGraphLedger.shared.events(rootRunID: summary.id)) ?? []
            eventsByRunID[summary.id] = events.sorted { $0.occurredAt < $1.occurredAt }
        }
    }

    private func toggleRunExpansion(_ summary: AgentGraphRunSummary) {
        if expandedRunID == summary.id {
            expandedRunID = nil
            return
        }

        expandedRunID = summary.id
        guard eventsByRunID[summary.id] == nil else { return }
        loadingRunID = summary.id
        Task { await loadEvents(for: summary) }
    }

    private func loadEvents(for summary: AgentGraphRunSummary) async {
        let events = (try? await AgentGraphLedger.shared.events(rootRunID: summary.id)) ?? []
        eventsByRunID[summary.id] = events.sorted { $0.occurredAt < $1.occurredAt }
        if loadingRunID == summary.id {
            loadingRunID = nil
        }
    }

    private var reviewPacketRows: [LedgerEvidence] {
        let runs = reviewableRunSummaries
        guard !runs.isEmpty else { return [] }

        let loadedEvents = loadedReviewEvents
        let failedEvents = loadedEvents.filter { event in
            event.type == .runFailed
            || event.type == .spawnFailed
            || event.type == .handoffRejected
            || event.type == .attentionRequested
            || event.type == .andonPaused
            || (event.type == .toolCompleted && event.payload["status"] == "failed")
        }
        let handoffEvents = loadedEvents.filter { isHandoffEvent($0.type) }
        let previewEvents = loadedEvents.filter { ($0.payload["tool"] ?? $0.title) == "preview_snapshot" }
        let toolNames = Array(Set(runs.flatMap(\.toolNames) + loadedEvents.compactMap { $0.payload["tool"] })).sorted()
        let toolEventCount = runs.reduce(0) { $0 + $1.toolEventCount }
        let completed = runs.filter { $0.status == "completed" }.count
        let failed = runs.filter { $0.status == "failed" || $0.status == "cancelled" }.count
        let running = runs.count - completed - failed
        let branches = Array(Set(runs.compactMap(\.gitBranch))).sorted()
        let dirtyCount = runs.filter { $0.gitDirty == true }.count

        var rows: [LedgerEvidence] = [
            LedgerEvidence(
                id: "coverage",
                icon: "rectangle.stack",
                tint: failed > 0 ? LoomTheme.orange : LoomTheme.green,
                title: "Run coverage",
                detail: "\(runs.count) runs · \(completed) complete · \(running) running · \(failed) blocked"
            ),
            LedgerEvidence(
                id: "checks",
                icon: "checklist",
                tint: failedEvents.isEmpty ? LoomTheme.green : LoomTheme.orange,
                title: "Checks",
                detail: toolEventCount > 0
                    ? "\(toolEventCount) tool events · \(limitedList(toolNames, empty: "tools recorded"))"
                    : "No tool checks recorded yet."
            )
        ]

        if let failedEvent = failedEvents.first {
            rows.append(LedgerEvidence(
                id: "failed-evidence",
                icon: "exclamationmark.triangle.fill",
                tint: LoomTheme.orange,
                title: "\(failedEvents.count) attention signal\(failedEvents.count == 1 ? "" : "s")",
                detail: compact(failedEvent.summary ?? failedEvent.title ?? failedEvent.payload["tool"] ?? failedEvent.type.rawValue)
            ))
        }

        if !branches.isEmpty || runs.contains(where: { $0.gitDirty != nil }) {
            let cleanliness = dirtyCount > 0 ? "\(dirtyCount) dirty" : "clean"
            rows.append(LedgerEvidence(
                id: "worktrees",
                icon: "arrow.triangle.branch",
                tint: dirtyCount > 0 ? LoomTheme.orange : LoomTheme.green,
                title: "Worktrees",
                detail: "\(limitedList(branches, empty: "no branch")) · \(cleanliness)"
            ))
        }

        if let handoff = handoffEvents.first {
            rows.append(LedgerEvidence(
                id: "handoffs",
                icon: "arrowshape.turn.up.right",
                tint: eventTint(handoff.type),
                title: "\(handoffEvents.count) handoff\(handoffEvents.count == 1 ? "" : "s")",
                detail: compact(handoff.summary ?? handoff.payload["reviewSummary"] ?? handoff.title ?? handoffTitle(handoff.type))
            ))
        }

        if let preview = previewEvents.first {
            rows.append(LedgerEvidence(
                id: "preview-evidence",
                icon: "globe",
                tint: LoomTheme.pink,
                title: "Preview evidence",
                detail: compact(preview.summary ?? preview.payload["status"] ?? "Preview snapshot recorded.")
            ))
        } else {
            let previewCount = blocks.filter { $0.kind == .preview }.count
            if previewCount > 0 {
                rows.append(LedgerEvidence(
                    id: "preview-panes",
                    icon: "globe",
                    tint: LoomTheme.pink,
                    title: "Preview evidence",
                    detail: "\(previewCount) Preview pane\(previewCount == 1 ? "" : "s") open for manual checks."
                ))
            }
        }

        return Array(rows.prefix(6))
    }

    private var loadedReviewEvents: [AgentGraphEvent] {
        reviewableRunSummaries
            .flatMap { eventsByRunID[$0.id] ?? [] }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private var reviewChangedFiles: [String] {
        var files: [String] = []
        var seen: Set<String> = []
        for event in loadedReviewEvents {
            let texts = [
                event.payload["reviewSummary"],
                event.payload["review"],
                event.summary
            ].compactMap { $0 }
            for text in texts {
                for path in changedFiles(in: text) where seen.insert(path).inserted {
                    files.append(path)
                }
            }
        }
        return files
    }

    private func changedFiles(in reviewText: String) -> [String] {
        var paths: [String] = []
        var inChangedFiles = false
        for rawLine in reviewText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "Changed files:" {
                inChangedFiles = true
                continue
            }
            guard inChangedFiles else { continue }
            if line.isEmpty { break }
            guard line.hasPrefix("- ") else { break }
            let path = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty || path.hasPrefix("…and") { continue }
            paths.append(path)
        }
        return paths
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func railSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(LoomTheme.tertiaryText)
    }

    private func railMuted(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(LoomTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func railCode(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(LoomTheme.mutedText)
            .lineLimit(2)
            .truncationMode(.middle)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoomTheme.inset)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func railRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LoomTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(LoomTheme.mutedText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func panelTint(_ kind: PanelKind) -> Color {
        switch kind {
        case .terminal: return LoomTheme.green
        case .editor: return LoomTheme.blue
        case .tasks: return LoomTheme.orange
        case .chat: return LoomTheme.blue
        case .agent: return LoomTheme.purple
        case .notes: return LoomTheme.yellow
        case .preview: return LoomTheme.pink
        case .commands: return LoomTheme.blue
        }
    }

    private var selectedAgentDetail: String {
        let agent = agentRegistry.selectedAgent
        if let model = agent.model, !model.isEmpty {
            return model
        }
        if let group = agent.group, !group.isEmpty {
            return group
        }
        return agent.displayName
    }

    private func providerIcon(_ vendor: AgentDescriptor.Vendor) -> String {
        switch vendor {
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .gemini: return "diamond"
        case .ollama: return "shippingbox"
        case .openAICompatible: return "server.rack"
        case .lmstudio: return "cpu"
        }
    }

    private func providerTint(_ vendor: AgentDescriptor.Vendor) -> Color {
        switch vendor {
        case .claude: return LoomTheme.orange
        case .codex: return LoomTheme.green
        case .gemini: return LoomTheme.blue
        case .ollama: return LoomTheme.mutedText
        case .openAICompatible: return LoomTheme.blue
        case .lmstudio: return LoomTheme.purple
        }
    }

    private func endpointTint(_ kind: LocalEndpoint.Kind) -> Color {
        switch kind {
        case .ollama: return LoomTheme.mutedText
        case .lmstudio: return LoomTheme.purple
        case .openAICompatible: return LoomTheme.blue
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "completed": return "checkmark.circle.fill"
        case "failed", "cancelled": return "xmark.circle.fill"
        default: return "circle.dashed"
        }
    }

    private func statusTint(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed": return LoomTheme.green
        case "failed", "cancelled": return LoomTheme.orange
        default: return LoomTheme.blue
        }
    }

    private func eventIcon(_ type: AgentGraphEventType) -> String {
        switch type {
        case .runCompleted, .spawnCompleted:
            return "checkmark.circle.fill"
        case .runFailed, .runCancelled, .spawnFailed:
            return "xmark.circle.fill"
        case .toolStarted, .toolCompleted:
            return "terminal"
        case .handoffWritten, .handoffAccepted, .handoffRejected:
            return "arrowshape.turn.up.right"
        case .attentionRequested, .andonPaused:
            return "exclamationmark.triangle.fill"
        case .graphCreated, .runStarted, .runHeartbeat, .runStatusChanged, .spawnRequested, .spawnStarted, .andonResumed:
            return "point.3.connected.trianglepath.dotted"
        case .taskCreated, .taskUpdated, .taskStatusChanged, .edgeCreated:
            return "list.bullet.rectangle"
        }
    }

    private func eventTint(_ type: AgentGraphEventType) -> Color {
        switch type {
        case .runCompleted, .spawnCompleted, .toolCompleted, .handoffAccepted, .andonResumed:
            return LoomTheme.green
        case .runFailed, .runCancelled, .spawnFailed, .handoffRejected, .attentionRequested, .andonPaused:
            return LoomTheme.orange
        case .toolStarted:
            return LoomTheme.purple
        default:
            return LoomTheme.blue
        }
    }

    private func eventDetail(_ event: AgentGraphEvent) -> String {
        let candidates = [
            event.summary,
            event.title,
            event.payload["tool"],
            event.payload["status"],
            event.payload["subject"],
            event.payload["taskID"],
            event.payload["path"],
            event.source
        ]
        let detail = candidates.compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }.first
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relativeTime = formatter.localizedString(for: event.occurredAt, relativeTo: .now)
        guard let detail else { return relativeTime }
        return "\(detail) · \(relativeTime)"
    }

    private func ledgerEvidence(from events: [AgentGraphEvent]) -> [LedgerEvidence] {
        let newest = events.sorted { $0.occurredAt > $1.occurredAt }
        var evidence: [LedgerEvidence] = []

        if let event = newest.first(where: { compactPayload($0, keys: ["reviewSummary", "review"]) != nil }),
           let detail = compactPayload(event, keys: ["reviewSummary", "review"]) {
            evidence.append(LedgerEvidence(
                id: "review",
                icon: "doc.text.magnifyingglass",
                tint: LoomTheme.purple,
                title: "Review ready",
                detail: detail
            ))
        }

        if let event = newest.first(where: { $0.type == .toolCompleted && $0.payload["status"] == "failed" }) {
            let tool = event.payload["tool"] ?? event.title ?? "Tool"
            evidence.append(LedgerEvidence(
                id: "failed-tool",
                icon: "exclamationmark.triangle.fill",
                tint: LoomTheme.orange,
                title: "\(tool) failed",
                detail: compact(event.summary ?? event.payload["status"] ?? "Tool needs attention.")
            ))
        }

        if let event = newest.first(where: { ($0.payload["tool"] ?? $0.title) == "preview_snapshot" }) {
            evidence.append(LedgerEvidence(
                id: "preview",
                icon: "globe",
                tint: LoomTheme.pink,
                title: "Preview check",
                detail: compact(event.summary ?? event.payload["status"] ?? "Preview snapshot recorded.")
            ))
        }

        if let event = newest.first(where: { isHandoffEvent($0.type) }) {
            evidence.append(LedgerEvidence(
                id: "handoff",
                icon: "arrowshape.turn.up.right",
                tint: eventTint(event.type),
                title: handoffTitle(event.type),
                detail: compact(event.summary ?? event.payload["reviewSummary"] ?? event.title ?? "Handoff signal recorded.")
            ))
        }

        if let event = newest.first(where: { hasGitEvidence($0) }) {
            let gitParts = [
                event.payload["gitBranch"],
                event.payload["gitHead"],
                event.payload["gitDirty"].map { $0 == "true" ? "dirty" : "clean" }
            ].compactMap { $0 }
            evidence.append(LedgerEvidence(
                id: "git",
                icon: "arrow.triangle.branch",
                tint: event.payload["gitDirty"] == "true" ? LoomTheme.orange : LoomTheme.green,
                title: "Git state",
                detail: gitParts.joined(separator: " · ")
            ))
        }

        if let event = newest.first(where: { $0.type == .attentionRequested || $0.type == .andonPaused || $0.type == .runFailed }) {
            evidence.append(LedgerEvidence(
                id: "attention",
                icon: "exclamationmark.triangle.fill",
                tint: LoomTheme.orange,
                title: "Attention needed",
                detail: compact(event.summary ?? event.title ?? event.payload["status"] ?? event.type.rawValue)
            ))
        }

        return Array(evidence.prefix(5))
    }

    private func compactPayload(_ event: AgentGraphEvent, keys: [String]) -> String? {
        for key in keys {
            if let value = event.payload[key] {
                let compacted = compact(value)
                if !compacted.isEmpty { return compacted }
            }
        }
        return nil
    }

    private func compact(_ text: String, limit: Int = 180) -> String {
        let normalized = text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<end]) + "..."
    }

    private func isHandoffEvent(_ type: AgentGraphEventType) -> Bool {
        switch type {
        case .handoffWritten, .handoffAccepted, .handoffRejected:
            return true
        default:
            return false
        }
    }

    private func handoffTitle(_ type: AgentGraphEventType) -> String {
        switch type {
        case .handoffAccepted: return "Handoff accepted"
        case .handoffRejected: return "Handoff rejected"
        default:               return "Handoff written"
        }
    }

    private func hasGitEvidence(_ event: AgentGraphEvent) -> Bool {
        event.payload["gitBranch"] != nil
        || event.payload["gitHead"] != nil
        || event.payload["gitDirty"] != nil
    }

    private func isReviewable(_ summary: AgentGraphRunSummary) -> Bool {
        summary.gitBranch != nil
        || summary.gitDirty != nil
        || summary.gitHead != nil
        || summary.toolEventCount > 0
        || summary.taskCount > 0
        || !summary.toolNames.isEmpty
    }

    private func limitedList(_ values: [String], empty: String, limit: Int = 3) -> String {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return empty }
        let visible = cleaned.prefix(limit).joined(separator: ", ")
        let remaining = cleaned.count - min(cleaned.count, limit)
        return remaining > 0 ? "\(visible) +\(remaining)" : visible
    }

    private func summaryChips(_ summary: AgentGraphRunSummary) -> [String] {
        [
            summary.status.capitalized,
            summary.modelLabel,
            summary.gitBranch,
            summary.toolEventCount > 0 ? "\(summary.toolEventCount) tools" : nil,
            summary.taskCount > 0 ? "\(summary.taskCount) tasks" : nil
        ].compactMap { $0 }
    }

    private var workflowSignals: WorkspaceWorkflowSignals {
        let runs = scopedRunSummaries
        let hasRunningRun = runs.contains { isRunningStatus($0.status) }
        let hasActiveAgents = !scopedLiveAgentGroups.isEmpty || hasRunningRun
        let hasCheckSignals = runs.contains { $0.toolEventCount > 0 || !$0.toolNames.isEmpty }
        let hasAttention = runs.contains { summary in
            isAttentionStatus(summary.status) || summary.gitDirty == true
        }
        let hasCompletedEvidence = runs.contains { summary in
            isCompletedStatus(summary.status)
            && summary.gitDirty != true
            && (summary.toolEventCount > 0 || summary.taskCount > 0 || summary.gitHead != nil || summary.gitBranch != nil)
        }
        return WorkspaceWorkflowSignals(
            hasActiveAgents: hasActiveAgents,
            hasCheckSignals: hasCheckSignals,
            hasAttention: hasAttention,
            hasReviewSignals: hasAttention || hasCompletedEvidence || hasCheckSignals,
            shipReady: hasCompletedEvidence && !hasAttention && !hasActiveAgents
        )
    }

    private var shipDecision: (icon: String, tint: Color, title: String, detail: String) {
        let signals = workflowSignals
        if signals.shipReady {
            return (
                "checkmark.seal.fill",
                LoomTheme.green,
                "Ready for review",
                "Completed run with clean ledger signals."
            )
        }
        if signals.hasAttention {
            return (
                "exclamationmark.triangle.fill",
                LoomTheme.orange,
                "Attention needed",
                "Failed, cancelled, or dirty run signals are present."
            )
        }
        if signals.hasActiveAgents {
            return (
                "clock.arrow.circlepath",
                LoomTheme.blue,
                "In progress",
                "Live or running agents are still producing context."
            )
        }
        if signals.hasCheckSignals {
            return (
                "doc.text.magnifyingglass",
                LoomTheme.purple,
                "Review pending",
                "Tool and check signals are ready to inspect."
            )
        }
        return (
            "circle.dashed",
            LoomTheme.mutedText,
            "No ship signal",
            "Runs will promote this once checks and review evidence land."
        )
    }

    private func isCompletedStatus(_ status: String) -> Bool {
        status.lowercased() == "completed"
    }

    private func isAttentionStatus(_ status: String) -> Bool {
        switch status.lowercased() {
        case "failed", "cancelled":
            return true
        default:
            return false
        }
    }

    private func isRunningStatus(_ status: String) -> Bool {
        switch status.lowercased() {
        case "running", "pending", "in_progress", "in-progress":
            return true
        default:
            return false
        }
    }
}

private struct WorkspaceWorkflowSignals {
    let hasActiveAgents: Bool
    let hasCheckSignals: Bool
    let hasAttention: Bool
    let hasReviewSignals: Bool
    let shipReady: Bool
}

private struct LedgerEvidence: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let title: String
    let detail: String
}

struct WorkspaceStatusBar: View {
    @Environment(LiveAgentTasksService.self) private var liveAgentTasks
    @Environment(AgentRegistry.self) private var agentRegistry
    @Environment(LocalEndpointStore.self) private var endpointStore
    @Environment(UpdateService.self) private var updates
    @Environment(DictationService.self) private var dictation
    let workspace: Workspace?
    let blocks: [WorkspaceBlock]
    let selectedBlock: WorkspaceBlock?
    let rightRailTab: WorkspaceRightRailTab

    var body: some View {
        HStack(spacing: 10) {
            statusSegment(
                icon: workspace?.kind.systemImage ?? "rectangle.stack",
                title: workspace?.name ?? "No workspace",
                detail: workspace?.displayFolderPath.isEmpty == false ? workspace?.displayFolderPath : workspace?.kind.label,
                tint: workspace?.color.color ?? LoomTheme.blue
            )

            statusSegment(
                icon: "rectangle.split.3x1",
                title: "\(blocks.count) panes",
                detail: selectedBlock?.displayTitle ?? "No selection",
                tint: LoomTheme.mutedText
            )

            statusSegment(
                icon: "point.3.connected.trianglepath.dotted",
                title: "\(scopedLiveAgentGroups.count) live runs",
                detail: liveRunDetail,
                tint: scopedLiveAgentGroups.isEmpty ? LoomTheme.mutedText : LoomTheme.green
            )

            statusSegment(
                icon: "server.rack",
                title: agentRegistry.selectedAgent.vendor.label,
                detail: modelDetail,
                tint: endpointStore.endpoints.isEmpty ? LoomTheme.mutedText : LoomTheme.purple
            )

            Spacer()

            let update = updateStatus
            statusSegment(
                icon: update.icon,
                title: update.title,
                detail: update.detail,
                tint: update.tint
            )

            statusSegment(
                icon: rightRailTab.systemImage,
                title: rightRailTab.label,
                detail: "Inspector",
                tint: LoomTheme.blue
            )

            if dictation.state.isActive {
                statusSegment(icon: "mic.fill", title: dictation.state.label, detail: dictation.liveTranscript, tint: LoomTheme.purple)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(LoomTheme.shellStatus)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var liveRunDetail: String? {
        guard let group = scopedLiveAgentGroups.first else { return nil }
        if let headline = group.headline, !headline.isEmpty {
            return "\(group.displayName) · \(headline)"
        }
        return group.displayName
    }

    private var scopedLiveAgentGroups: [LiveAgentTaskGroup] {
        guard let folderPath = workspace?.folderPath, !folderPath.isEmpty else {
            return liveAgentTasks.groups
        }
        let root = normalizedPath(folderPath)
        return liveAgentTasks.groups.filter { group in
            guard let workspacePath = group.workspacePath,
                  !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return true
            }
            let candidate = normalizedPath(workspacePath)
            return candidate == root || candidate.hasPrefix(root + "/")
        }
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private var modelDetail: String? {
        let agent = agentRegistry.selectedAgent
        if let model = agent.model, !model.isEmpty {
            return model
        }
        if !agent.displayName.isEmpty {
            return agent.displayName
        }
        if endpointStore.endpoints.isEmpty {
            return "No local endpoints"
        }
        return "\(endpointStore.endpoints.count) local endpoints"
    }

    private var updateStatus: (icon: String, title: String, detail: String?, tint: Color) {
        if updates.isApplying {
            return ("arrow.triangle.2.circlepath.circle.fill", "Applying Update", "Relaunching", LoomTheme.green)
        }
        if let staged = updates.available {
            return ("arrow.down.circle.fill", "Update Available", staged.displayLabel, LoomTheme.green)
        }
        if updates.isFetchingRemote {
            let running = UpdateService.runningVersionTriple()
            return ("arrow.clockwise.circle", "Checking Updates", "\(running.version) (\(running.build))", LoomTheme.blue)
        }
        if updates.lastRemoteError != nil {
            return ("exclamationmark.triangle.fill", "Update Check Failed", "Help > Check", LoomTheme.orange)
        }
        let running = UpdateService.runningVersionTriple()
        return ("checkmark.seal.fill", "Up To Date", "\(running.version) (\(running.build))", LoomTheme.mutedText)
    }

    private func statusSegment(icon: String, title: String, detail: String?, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LoomTheme.primaryText)
                .lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(LoomTheme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minWidth: 0)
    }
}

struct WorkspaceMemoryFile: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let excerpt: String
    let characterCount: Int

    static func load(from folderPath: String?) -> [WorkspaceMemoryFile] {
        guard let folderPath, !folderPath.isEmpty else { return [] }
        let root = URL(fileURLWithPath: folderPath)
        let names = ["CLAUDE.md", "AGENTS.md", "GUIDE.md", "README.md"]
        return names.compactMap { name in
            let url = root.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path),
                  let handle = try? FileHandle(forReadingFrom: url) else {
                return nil
            }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: 2048)) ?? Data()
            let raw = String(decoding: data, as: UTF8.self)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let excerpt: String
            if trimmed.count > 420 {
                let end = trimmed.index(trimmed.startIndex, offsetBy: 420)
                excerpt = String(trimmed[..<end]) + "..."
            } else {
                excerpt = trimmed
            }
            let fileSize = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue
            return WorkspaceMemoryFile(
                id: url.path,
                name: name,
                path: url.path,
                excerpt: excerpt,
                characterCount: fileSize ?? trimmed.count
            )
        }
    }
}
