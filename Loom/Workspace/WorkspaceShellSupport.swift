import SwiftUI

enum WorkspaceRightRailTab: String, CaseIterable, Identifiable {
    case timeline
    case files
    case preview
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
        return Button {
            selectedUsageTool = nil
            selectedWorkspaceID = workspace.id
        } label: {
            VStack(spacing: 4) {
                Image(systemName: workspace.kind.systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(selected ? .white : workspace.color.color)
                    .frame(width: 34, height: 28)
                    .background(selected ? workspace.color.color : workspace.color.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .help("Open \(workspace.kind.label)")
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
    }

    private var refreshKey: String {
        "\(workspace?.id.uuidString ?? "none"):\(refreshNonce)"
    }

    private var effectiveTab: WorkspaceRightRailTab {
        availableTabs.contains(selectedTab) ? selectedTab : availableTabs.first ?? .details
    }

    private var availableTabs: [WorkspaceRightRailTab] {
        var tabs: [WorkspaceRightRailTab] = [.timeline]
        if workspace?.folderPath.isEmpty == false { tabs.append(.files) }
        if blocks.contains(where: { $0.kind == .preview }) || selectedBlock?.kind == .preview { tabs.append(.preview) }
        tabs.append(.tools)
        if workspace?.kind == .review || workspace?.kind == .runs || scopedRunSummaries.contains(where: { $0.gitBranch != nil || $0.gitDirty != nil || $0.toolEventCount > 0 }) {
            tabs.append(.diff)
        }
        if workspace?.folderPath.isEmpty == false || !memoryFiles.isEmpty { tabs.append(.memory) }
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
            if liveAgentTasks.groups.isEmpty {
                railMuted("No live agent task groups are active.")
            } else {
                ForEach(liveAgentTasks.groups.prefix(5)) { group in
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
                ForEach(scopedRunSummaries.prefix(6)) { summary in
                    railRow(
                        icon: statusIcon(summary.status),
                        tint: statusTint(summary.status),
                        title: summary.title,
                        detail: summaryChips(summary).joined(separator: " · ")
                    )
                }
            }
        }
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
            railSectionTitle("Ship Decision")
            railRow(
                icon: decision.icon,
                tint: decision.tint,
                title: decision.title,
                detail: decision.detail
            )

            railSectionTitle("Review Signals")
            let reviewable = scopedRunSummaries.filter { $0.gitBranch != nil || $0.gitDirty != nil || $0.toolEventCount > 0 }
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
        let hasActiveAgents = !liveAgentTasks.groups.isEmpty || hasRunningRun
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
                title: "\(liveAgentTasks.groups.count) live runs",
                detail: liveRunDetail,
                tint: liveAgentTasks.groups.isEmpty ? LoomTheme.mutedText : LoomTheme.green
            )

            statusSegment(
                icon: "server.rack",
                title: agentRegistry.selectedAgent.vendor.label,
                detail: modelDetail,
                tint: endpointStore.endpoints.isEmpty ? LoomTheme.mutedText : LoomTheme.purple
            )

            Spacer()

            statusSegment(
                icon: rightRailTab.systemImage,
                title: rightRailTab.label,
                detail: "Inspector",
                tint: LoomTheme.blue
            )

            if updates.available != nil {
                statusSegment(icon: "arrow.down.circle.fill", title: "Update available", detail: updates.available?.displayLabel, tint: LoomTheme.green)
            }

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
        guard let group = liveAgentTasks.groups.first else { return nil }
        if let headline = group.headline, !headline.isEmpty {
            return "\(group.displayName) · \(headline)"
        }
        return group.displayName
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
