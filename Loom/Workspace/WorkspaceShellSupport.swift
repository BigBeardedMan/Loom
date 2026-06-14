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

enum WorkspaceRightRailAvailability {
    static func tabs(
        workspace: Workspace?,
        selectedBlock: WorkspaceBlock? = nil,
        blocks: [WorkspaceBlock],
        memoryFiles: [WorkspaceMemoryFile] = [],
        runSummaries: [AgentGraphRunSummary] = []
    ) -> [WorkspaceRightRailTab] {
        var tabs: [WorkspaceRightRailTab] = []
        if workspace?.folderPath.isEmpty == false { tabs.append(.files) }
        if blocks.contains(where: { $0.kind == .preview }) || selectedBlock?.kind == .preview {
            tabs.append(.preview)
        }
        tabs.append(.timeline)
        tabs.append(.tools)
        if workspace?.kind == .review
            || workspace?.kind == .runs
            || runSummaries.contains(where: hasReviewEvidence) {
            tabs.append(.diff)
        }
        if workspace?.folderPath.isEmpty == false
            || workspace?.kind == .runs
            || workspace?.kind == .review
            || !memoryFiles.isEmpty
            || !runSummaries.isEmpty {
            tabs.append(.memory)
        }
        tabs.append(.details)
        return tabs
    }

    static func scopedRunSummaries(
        _ summaries: [AgentGraphRunSummary],
        workspace: Workspace?
    ) -> [AgentGraphRunSummary] {
        guard let folderPath = workspace?.folderPath, !folderPath.isEmpty else {
            return summaries
        }
        let root = normalizedPath(folderPath)
        return summaries.filter { summary in
            guard let workspacePath = summary.workspacePath, !workspacePath.isEmpty else { return false }
            let candidate = normalizedPath(workspacePath)
            return candidate == root || candidate.hasPrefix(root + "/")
        }
    }

    static func hasReviewEvidence(_ summary: AgentGraphRunSummary) -> Bool {
        summary.gitBranch != nil
        || summary.gitDirty != nil
        || summary.gitHead != nil
        || summary.toolEventCount > 0
        || summary.taskCount > 0
        || !summary.toolNames.isEmpty
        || !summary.parentRunIDs.isEmpty
        || summary.childRunCount > 0
        || summary.lineageEventCount > 0
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
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
        WorkspaceRightRailAvailability.tabs(
            workspace: workspace,
            selectedBlock: selectedBlock,
            blocks: blocks,
            memoryFiles: memoryFiles,
            runSummaries: scopedRunSummaries
        )
    }

    private var scopedRunSummaries: [AgentGraphRunSummary] {
        WorkspaceRightRailAvailability.scopedRunSummaries(runSummaries, workspace: workspace)
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
        let ids = reviewableRunSummaries.prefix(8).map(\.id).joined(separator: ",")
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
                NotificationCenter.default.post(name: .loomRefreshInspectorContext, object: nil)
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
        let metrics = workflowMetrics
        let focus = workflowFocus
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
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                alignment: .leading,
                spacing: 6
            ) {
                workflowMetricChip("Active", value: metrics.activeCount, tint: LoomTheme.blue)
                workflowMetricChip("Ready", value: metrics.readyCount, tint: LoomTheme.green)
                workflowMetricChip("Attention", value: metrics.attentionCount, tint: LoomTheme.orange)
                workflowMetricChip("Checks", value: metrics.checkCount, tint: LoomTheme.purple)
            }
            Button {
                selectedTab = focus.targetTab
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: focus.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(focus.tint)
                        .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(focus.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LoomTheme.primaryText)
                            .lineLimit(1)
                        Text(focus.detail)
                            .font(.system(size: 9))
                            .foregroundStyle(LoomTheme.mutedText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(LoomTheme.tertiaryText)
                }
                .padding(8)
                .background(LoomTheme.softPanel.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Open \(focus.targetTab.label)")
        }
        .padding(10)
        .background(LoomTheme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func workflowMetricChip(_ label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .frame(minWidth: 14, alignment: .leading)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(value > 0 ? LoomTheme.primaryText : LoomTheme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LoomTheme.softPanel.opacity(0.44))
        .clipShape(RoundedRectangle(cornerRadius: 7))
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
                    ledgerActions(for: summary)
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
                folderActions(path: workspace.folderPath, label: workspace.kind.label)
                if memoryFiles.isEmpty {
                    railMuted("No agent memory files found in this folder.")
                } else {
                    ForEach(memoryFiles) { file in
                        VStack(alignment: .leading, spacing: 6) {
                            railRow(
                                icon: "doc.text",
                                tint: LoomTheme.blue,
                                title: file.name,
                                detail: "\(file.characterCount) bytes"
                            )
                            memoryFileActions(for: file)
                        }
                        .padding(9)
                        .background(LoomTheme.inset)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    previewRailCard(for: block)
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
                    changedFileCard(for: path)
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
                    previewRailCard(for: block)
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
                        memoryFileActions(for: file)
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
                        ledgerActions(for: summary)
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
        for summary in reviewableRunSummaries.prefix(8) where eventsByRunID[summary.id] == nil {
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
        let parentRunCount = Set(runs.flatMap(\.parentRunIDs)).count
        let childRunCount = runs.reduce(0) { $0 + $1.childRunCount }
        let lineageEventCount = runs.reduce(0) { $0 + $1.lineageEventCount }

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

        if parentRunCount > 0 || childRunCount > 0 || lineageEventCount > 0 {
            rows.append(LedgerEvidence(
                id: "lineage",
                icon: "point.3.connected.trianglepath.dotted",
                tint: LoomTheme.purple,
                title: "Lineage",
                detail: lineageSummary(
                    parentRunCount: parentRunCount,
                    childRunCount: childRunCount,
                    eventCount: lineageEventCount
                )
            ))
        }

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
            let payloadFileTexts = [
                event.payload["changedFiles"],
                event.payload["changed_files"],
                event.payload["filesChanged"],
                event.payload["modifiedFiles"],
                event.payload["changedPaths"]
            ].compactMap { $0 }
            for text in payloadFileTexts {
                for path in changedFilePaths(fromInlineBody: text) where seen.insert(path).inserted {
                    files.append(path)
                }
            }
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
            let inlinePaths = inlineChangedFiles(in: line)
            if !inlinePaths.isEmpty {
                paths.append(contentsOf: inlinePaths)
                continue
            }
            if isChangedFilesHeader(line) {
                inChangedFiles = true
                continue
            }
            guard inChangedFiles else { continue }
            if line.isEmpty { break }
            if line.hasPrefix("```") { break }
            if line.hasSuffix(":") && !line.hasPrefix("- ") && !line.hasPrefix("* ") { break }
            guard let path = changedFilePath(from: line) else { break }
            paths.append(path)
        }
        return paths
    }

    private func isChangedFilesHeader(_ line: String) -> Bool {
        let stripped = line
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*_` "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            .lowercased()
        let withoutCount = stripped.replacingOccurrences(
            of: #"\s*\(\d+\)$"#,
            with: "",
            options: .regularExpression
        )
        return [
            "changed files",
            "files changed",
            "modified files",
            "changed paths",
            "touched files"
        ].contains(withoutCount)
    }

    private func inlineChangedFiles(in line: String) -> [String] {
        guard let colon = line.firstIndex(of: ":") else { return [] }
        let header = String(line[..<colon])
        guard isChangedFilesHeader(header) else { return [] }
        return changedFilePaths(fromInlineBody: String(line[line.index(after: colon)...]))
    }

    private func changedFilePaths(fromInlineBody body: String) -> [String] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        if ["none", "n/a", "no changes"].contains(lower) { return [] }
        let spans = codeSpans(in: trimmed)
        if !spans.isEmpty { return spans }
        return trimmed
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .compactMap { changedFilePath(from: String($0)) }
    }

    private func changedFilePath(from line: String) -> String? {
        let body = changedFileLineBody(line)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        if body.hasPrefix("…and") || body.hasPrefix("...and") { return nil }
        if let codePath = firstCodeSpan(in: body) {
            return codePath
        }
        let cleaned = stripReviewFileStatus(body)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`\"' "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.hasPrefix("…and"), !cleaned.hasPrefix("...and") else {
            return nil
        }
        return cleaned
    }

    private func changedFileLineBody(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst(2))
        }
        if let dot = trimmed.firstIndex(of: ".") {
            let prefix = trimmed[..<dot]
            let afterDot = trimmed.index(after: dot)
            if !prefix.isEmpty,
               prefix.allSatisfy(\.isNumber),
               afterDot < trimmed.endIndex,
               trimmed[afterDot].isWhitespace {
                return String(trimmed[trimmed.index(after: afterDot)...])
            }
        }
        return trimmed
    }

    private func firstCodeSpan(in text: String) -> String? {
        codeSpans(in: text).first
    }

    private func codeSpans(in text: String) -> [String] {
        var spans: [String] = []
        var cursor = text.startIndex
        while let start = text[cursor...].firstIndex(of: "`") {
            let restStart = text.index(after: start)
            guard let end = text[restStart...].firstIndex(of: "`") else { break }
            let value = text[restStart..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { spans.append(String(value)) }
            cursor = text.index(after: end)
        }
        return spans
    }

    private func stripReviewFileStatus(_ text: String) -> String {
        let statusPrefixes = ["modified:", "added:", "removed:", "deleted:", "renamed:", "created:"]
        let lower = text.lowercased()
        for prefix in statusPrefixes where lower.hasPrefix(prefix) {
            return reviewFilePathCandidate(String(text.dropFirst(prefix.count)))
        }
        let parts = text.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        if parts.count == 2,
           isGitReviewStatusToken(parts[0]) {
            return reviewFilePathCandidate(String(parts[1]))
        }
        return text
    }

    private func isGitReviewStatusToken(_ token: Substring) -> Bool {
        if token.hasPrefix("R"), token.dropFirst().allSatisfy(\.isNumber) {
            return true
        }
        let allowed = CharacterSet(charactersIn: "MADRCU?!")
        return token.count <= 2 && token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func reviewFilePathCandidate(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let arrowRange = trimmed.range(of: " -> ") {
            return String(trimmed[arrowRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
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

    private func ledgerActions(for summary: AgentGraphRunSummary) -> some View {
        HStack(spacing: 6) {
            railActionButton(title: "Copy", systemImage: "doc.on.doc", help: "Copy ledger path") {
                copyLedgerPath(summary.ledgerPath)
            }
            railActionButton(title: "Reveal", systemImage: "folder", help: "Reveal ledger in Finder") {
                revealLedger(summary.ledgerPath)
            }
        }
    }

    private func memoryFileActions(for file: WorkspaceMemoryFile) -> some View {
        HStack(spacing: 6) {
            railActionButton(title: "Copy", systemImage: "doc.on.doc", help: "Copy memory file path") {
                copyPath(file.path)
            }
            railActionButton(title: "Open", systemImage: "doc.text", help: "Open \(file.name)") {
                openPath(file.path)
            }
            railActionButton(title: "Reveal", systemImage: "folder", help: "Reveal \(file.name) in Finder") {
                revealPath(file.path)
            }
        }
    }

    private func folderActions(path: String, label: String) -> some View {
        HStack(spacing: 6) {
            railActionButton(title: "Copy", systemImage: "doc.on.doc", help: "Copy \(label) folder path") {
                copyPath(path)
            }
            railActionButton(title: "Reveal", systemImage: "folder", help: "Reveal \(label) folder in Finder") {
                revealPath(path)
            }
        }
    }

    private func previewRailCard(for block: WorkspaceBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            railRow(
                icon: "globe",
                tint: LoomTheme.pink,
                title: block.displayTitle,
                detail: block.effectivePreviewURL
            )
            previewActions(url: block.effectivePreviewURL, label: block.displayTitle)
        }
        .padding(9)
        .background(LoomTheme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func changedFileCard(for path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            railRow(
                icon: "doc.text",
                tint: LoomTheme.blue,
                title: reviewPathBaseName(path),
                detail: path
            )
            changedFileActions(path: path)
        }
        .padding(9)
        .background(LoomTheme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func changedFileActions(path: String) -> some View {
        let url = reviewFileURL(for: path)
        let label = reviewPathBaseName(path)
        return HStack(spacing: 6) {
            railActionButton(title: "Copy", systemImage: "doc.on.doc", help: "Copy \(label) path") {
                copyPath(url.path)
            }
            railActionButton(title: "Open", systemImage: "doc.text", help: "Open \(label)") {
                openPath(url.path)
            }
            railActionButton(title: "Reveal", systemImage: "folder", help: "Reveal \(label) in Finder") {
                revealReviewFile(url)
            }
        }
    }

    private func previewActions(url: String, label: String) -> some View {
        HStack(spacing: 6) {
            railActionButton(title: "Copy", systemImage: "doc.on.doc", help: "Copy \(label) preview URL") {
                copyPath(url)
            }
            railActionButton(title: "Open", systemImage: "arrow.up.forward.app", help: "Open \(label) preview") {
                openURLString(url)
            }
        }
    }

    private func railActionButton(
        title: String,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(LoomTheme.mutedText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(LoomTheme.softPanel.opacity(0.58))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(LoomTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
    }

    private func copyLedgerPath(_ path: String) {
        copyPath(path)
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    private func revealLedger(_ path: String) {
        revealPath(path)
    }

    private func revealPath(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func openPath(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func revealReviewFile(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        let parent = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) {
            NSWorkspace.shared.open(parent)
        }
    }

    private func openURLString(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func reviewFileURL(for path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        if let folderPath = workspace?.folderPath, !folderPath.isEmpty {
            return URL(fileURLWithPath: folderPath, isDirectory: true).appendingPathComponent(expanded)
        }
        return URL(fileURLWithPath: expanded)
    }

    private func reviewPathBaseName(_ path: String) -> String {
        let trimmed = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        let parts = trimmed.split { character in
            character == "/" || character == "\\"
        }
        return parts.last.map(String.init) ?? trimmed
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
        WorkspaceRightRailAvailability.hasReviewEvidence(summary)
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
            summary.taskCount > 0 ? "\(summary.taskCount) tasks" : nil,
            summary.childRunCount > 0 ? "\(summary.childRunCount) child runs" : nil,
            summary.parentRunIDs.isEmpty ? nil : "\(summary.parentRunIDs.count) parents"
        ].compactMap { $0 }
    }

    private func lineageSummary(parentRunCount: Int, childRunCount: Int, eventCount: Int) -> String {
        let parts = [
            childRunCount > 0 ? "\(childRunCount) child run\(childRunCount == 1 ? "" : "s")" : nil,
            parentRunCount > 0 ? "\(parentRunCount) parent\(parentRunCount == 1 ? "" : "s")" : nil,
            eventCount > 0 ? "\(eventCount) lineage event\(eventCount == 1 ? "" : "s")" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "No lineage edges recorded." : parts.joined(separator: " · ")
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
            && WorkspaceRightRailAvailability.hasReviewEvidence(summary)
        }
        return WorkspaceWorkflowSignals(
            hasActiveAgents: hasActiveAgents,
            hasCheckSignals: hasCheckSignals,
            hasAttention: hasAttention,
            hasReviewSignals: hasAttention || hasCompletedEvidence || hasCheckSignals,
            shipReady: hasCompletedEvidence && !hasAttention && !hasActiveAgents
        )
    }

    private var workflowMetrics: WorkspaceWorkflowMetrics {
        let runs = scopedRunSummaries
        let runningCount = runs.filter { isRunningStatus($0.status) }.count
        let attentionCount = runs.filter { summary in
            isAttentionStatus(summary.status) || summary.gitDirty == true
        }.count
        let readyCount = runs.filter { summary in
            isCompletedStatus(summary.status)
            && summary.gitDirty != true
            && WorkspaceRightRailAvailability.hasReviewEvidence(summary)
        }.count
        let reviewableCount = runs.filter(isReviewable).count
        let checkCount = runs.reduce(0) { partial, summary in
            partial + summary.toolEventCount + summary.taskCount
        }

        return WorkspaceWorkflowMetrics(
            activeCount: scopedLiveAgentGroups.count + runningCount,
            readyCount: readyCount,
            attentionCount: attentionCount,
            reviewableCount: reviewableCount,
            checkCount: checkCount
        )
    }

    private var workflowFocus: (
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        targetTab: WorkspaceRightRailTab
    ) {
        let metrics = workflowMetrics
        if metrics.attentionCount > 0 {
            return (
                "exclamationmark.triangle.fill",
                LoomTheme.orange,
                "\(metrics.attentionCount) attention signal\(metrics.attentionCount == 1 ? "" : "s")",
                "Review failed, cancelled, or dirty runs",
                .diff
            )
        }
        if metrics.activeCount > 0 {
            return (
                "point.3.connected.trianglepath.dotted",
                LoomTheme.blue,
                "\(metrics.activeCount) active stream\(metrics.activeCount == 1 ? "" : "s")",
                "Watch the live timeline",
                .timeline
            )
        }
        if metrics.readyCount > 0 {
            return (
                "checkmark.seal.fill",
                LoomTheme.green,
                "\(metrics.readyCount) ready for review",
                "Open the review packet",
                .diff
            )
        }
        if metrics.checkCount > 0 || metrics.reviewableCount > 0 {
            return (
                "doc.text.magnifyingglass",
                LoomTheme.purple,
                "\(max(metrics.checkCount, metrics.reviewableCount)) review signal\(max(metrics.checkCount, metrics.reviewableCount) == 1 ? "" : "s")",
                "Inspect recorded evidence",
                .diff
            )
        }
        if !memoryFiles.isEmpty {
            return (
                "brain.head.profile",
                LoomTheme.purple,
                "\(memoryFiles.count) memory file\(memoryFiles.count == 1 ? "" : "s")",
                "Review project context",
                .memory
            )
        }
        return (
            "sidebar.right",
            LoomTheme.mutedText,
            "No review queue yet",
            "Inspect the current room",
            .details
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

private struct WorkspaceWorkflowMetrics {
    let activeCount: Int
    let readyCount: Int
    let attentionCount: Int
    let reviewableCount: Int
    let checkCount: Int
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
    @Environment(UsageService.self) private var usage
    @Environment(DictationService.self) private var dictation
    @AppStorage("loom.agent.allowBash") private var allowBash: Bool = false
    @AppStorage("loom.agent.permissionMode") private var permissionModeRaw: String = AgentPermissionMode.confirm.rawValue
    let workspace: Workspace?
    let blocks: [WorkspaceBlock]
    let selectedBlock: WorkspaceBlock?
    let runSummaries: [AgentGraphRunSummary]
    let rightRailTab: WorkspaceRightRailTab
    let openInspector: (WorkspaceRightRailTab) -> Void
    let showUsageTool: (CLITool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            statusSegment(
                icon: workspace?.kind.systemImage ?? "rectangle.stack",
                title: workspace?.name ?? "No workspace",
                detail: workspace?.displayFolderPath.isEmpty == false ? workspace?.displayFolderPath : workspace?.kind.label,
                tint: workspace?.color.color ?? LoomTheme.blue,
                action: { openInspector(.details) }
            )

            statusSegment(
                icon: "rectangle.split.3x1",
                title: "\(blocks.count) panes",
                detail: selectedBlock?.displayTitle ?? "No selection",
                tint: LoomTheme.mutedText,
                action: { openInspector(.details) }
            )

            statusSegment(
                icon: "point.3.connected.trianglepath.dotted",
                title: "\(scopedLiveAgentGroups.count) live runs",
                detail: liveRunDetail,
                tint: scopedLiveAgentGroups.isEmpty ? LoomTheme.mutedText : LoomTheme.green,
                action: { openInspector(.timeline) }
            )

            let runs = runHistoryStatus
            statusSegment(
                icon: runs.icon,
                title: runs.title,
                detail: runs.detail,
                tint: runs.tint,
                action: { openInspector(runs.targetTab) }
            )

            statusSegment(
                icon: "server.rack",
                title: agentRegistry.selectedAgent.vendor.label,
                detail: modelDetail,
                tint: endpointStore.endpoints.isEmpty ? LoomTheme.mutedText : LoomTheme.purple,
                action: { openInspector(.tools) }
            )

            let permission = permissionStatus
            statusSegment(
                icon: permission.icon,
                title: permission.title,
                detail: permission.detail,
                tint: permission.tint,
                action: { openInspector(.tools) }
            )

            if let warning = usageWarningStatus {
                statusSegment(
                    icon: "exclamationmark.triangle.fill",
                    title: warning.title,
                    detail: warning.detail,
                    tint: LoomTheme.orange,
                    action: {
                        showUsageTool(warning.tool)
                        usage.requestLimitWarningRefresh()
                    }
                )
            }

            Spacer()

            let update = updateStatus
            statusSegment(
                icon: update.icon,
                title: update.title,
                detail: update.detail,
                tint: update.tint,
                action: runUpdateAction
            )

            statusSegment(
                icon: rightRailTab.systemImage,
                title: rightRailTab.label,
                detail: "Inspector",
                tint: LoomTheme.blue,
                action: { openInspector(rightRailTab) }
            )

            if dictation.state.isActive {
                statusSegment(
                    icon: "mic.fill",
                    title: dictation.state.label,
                    detail: dictation.liveTranscript,
                    tint: LoomTheme.purple,
                    action: { dictation.toggle() }
                )
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

    private var runHistoryStatus: (
        icon: String,
        title: String,
        detail: String?,
        tint: Color,
        targetTab: WorkspaceRightRailTab
    ) {
        guard !runSummaries.isEmpty else {
            return (
                "clock.arrow.circlepath",
                "No Run History",
                nil,
                LoomTheme.mutedText,
                .timeline
            )
        }

        let attention = runSummaries.filter { summary in
            isAttentionStatus(summary.status) || summary.gitDirty == true
        }.count
        let running = runSummaries.filter { isRunningStatus($0.status) }.count
        let ready = runSummaries.filter { summary in
            isCompletedStatus(summary.status)
            && summary.gitDirty != true
            && WorkspaceRightRailAvailability.hasReviewEvidence(summary)
        }.count
        let reviewable = runSummaries.filter(WorkspaceRightRailAvailability.hasReviewEvidence).count
        let checkCount = runSummaries.reduce(0) { partial, summary in
            partial + summary.toolEventCount + summary.taskCount
        }
        let detail = runQueueDetail(
            total: runSummaries.count,
            ready: ready,
            reviewable: reviewable,
            checks: checkCount
        )

        if attention > 0 {
            return (
                "exclamationmark.triangle.fill",
                "\(attention) Attention",
                detail,
                LoomTheme.orange,
                .diff
            )
        }
        if running > 0 {
            return (
                "point.3.connected.trianglepath.dotted",
                "\(running) Running",
                detail,
                LoomTheme.blue,
                .timeline
            )
        }
        if ready > 0 {
            return (
                "checkmark.seal.fill",
                "\(ready) Ready",
                detail,
                LoomTheme.green,
                .diff
            )
        }
        return (
            "clock.arrow.circlepath",
            "\(runSummaries.count) Recent",
            "run history",
            LoomTheme.mutedText,
            .timeline
        )
    }

    private func runQueueDetail(total: Int, ready: Int, reviewable: Int, checks: Int) -> String {
        let parts = [
            ready > 0 ? "\(ready) ready" : nil,
            checks > 0 ? "\(checks) checks" : nil,
            reviewable > 0 ? "\(reviewable) reviewable" : nil,
            "\(total) recent"
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
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

    private var permissionMode: AgentPermissionMode {
        AgentPermissionMode(rawValue: permissionModeRaw) ?? .confirm
    }

    private var permissionStatus: (icon: String, title: String, detail: String, tint: Color) {
        let mode = permissionMode
        let bashEnabled = allowBash || mode == .bypassPermissions
        let tint: Color
        switch mode {
        case .bypassPermissions:
            tint = LoomTheme.orange
        case .plan:
            tint = LoomTheme.mutedText
        default:
            tint = LoomTheme.purple
        }
        return (
            mode.systemImage,
            mode.label,
            bashEnabled ? "Bash on" : "Bash off",
            tint
        )
    }

    private var usageWarningStatus: (tool: CLITool, title: String, detail: String)? {
        let warnings = CLITool.allCases.compactMap { tool -> UsageLimitWarning? in
            guard tool.supportsLimitSignals,
                  usage.hasUnacknowledgedLimitWarning(for: tool) else { return nil }
            return usage.limitWarnings[tool]
        }
        guard !warnings.isEmpty else { return nil }
        let sorted = warnings.sorted {
            ($0.observedAt ?? .distantPast) > ($1.observedAt ?? .distantPast)
        }
        guard let warning = sorted.first else { return nil }
        let title = warnings.count == 1
            ? "\(warning.tool.label) Limit"
            : "\(warnings.count) Usage Warnings"
        let percent = warning.peakUsedPercent.map { "\(Int($0.rounded()))%" }
        let detail = [
            warning.tool.label,
            warning.reachedType,
            percent
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return (
            warning.tool,
            title,
            detail.isEmpty ? "Limit signal" : detail
        )
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

    private func runUpdateAction() {
        if updates.available != nil {
            updates.applyAndRelaunch()
            return
        }
        Task {
            await updates.checkRemoteAndAnnounce()
        }
    }

    @ViewBuilder
    private func statusSegment(
        icon: String,
        title: String,
        detail: String?,
        tint: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        if let action {
            Button(action: action) {
                statusSegmentContent(icon: icon, title: title, detail: detail, tint: tint)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(detail?.isEmpty == false ? "\(title) · \(detail ?? "")" : title)
        } else {
            statusSegmentContent(icon: icon, title: title, detail: detail, tint: tint)
        }
    }

    private func statusSegmentContent(icon: String, title: String, detail: String?, tint: Color) -> some View {
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
