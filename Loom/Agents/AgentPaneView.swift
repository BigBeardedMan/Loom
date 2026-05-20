import SwiftUI

struct AgentMessage: Identifiable, Hashable {
    let id = UUID()
    var role: Role
    var text: String
    var proposals: [ItemProposal]?
    var proposalMode: ProposalMode = .createNewTabs
    var proposalCommittedSummary: String?
    var proposalDismissed: Bool = false
    enum Role { case user, assistant, system }
}

/// Chat-style Agent pane. Two provider paths share the UI:
///   - Claude / Codex / Gemini: `CLIAgentProvider` subprocess. Auth piggybacks
///     on the user's existing CLI OAuth login. Argv shape varies per vendor
///     (claude session-resume; codex/gemini stateless).
///   - Ollama / OpenAI-compatible: `LLMProvider` HTTP streaming against the
///     user's configured local endpoint, tokens land live in the bubble.
///
/// Streaming text is held in `StreamingState` (own `@Observable`) so token
/// deltas only re-render the streaming bubble, not the whole message list.
/// On stream finalize, the buffered text is committed to `messages` along
/// with any proposal items the agent emitted via the `propose_items` tool
/// (Anthropic) or that the fallback parser detected (other providers).
struct AgentPaneView: View {
    @Environment(AgentRegistry.self) private var registry
    @Environment(LocalEndpointStore.self) private var endpoints
    @Environment(LMStudioRuntimeService.self) private var lmStudioRuntime
    @Environment(WorkspaceContext.self) private var workspace
    @Environment(WorkspaceLayout.self) private var layout
    @State private var cliProvider = CLIAgentProvider()
    @State private var sessionStore = AgentSessionStore()
    @State private var messages: [AgentMessage] = []
    @State private var streaming = StreamingState()
    @State private var draft: String = ""
    @State private var isWaiting: Bool = false
    @State private var error: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var pendingProposals: [ItemProposal]?
    @State private var orchestrator: AgentOrchestrator?
    @State private var orchestratorTask: Task<Void, Never>?
    @State private var pendingURLRun: PendingURLRun?
    @State private var pendingToolApproval: PendingToolApproval?
    @State private var pendingRunReview: String?
    @State private var compactionCount: Int = 0
    @State private var showRenameSession: Bool = false
    @State private var showSessionBrowser: Bool = false
    @State private var renameDraft: String = ""
    @State private var workbenchEvents: [AgentWorkbenchEvent] = []
    @State private var workbenchTasks: [LiveAgentTask] = []
    @State private var changedFiles: [String] = []
    @State private var verificationResults: [AgentVerificationResult] = []
    @State private var isRunningVerification: Bool = false

    /// Persisted across panes: when on, local-HTTP providers run through
    /// `AgentOrchestrator` (multi-turn loop, tool calls, task list) instead
    /// of single-shot streaming. Off by default since plain chat is what
    /// users expect when they pick a model from the picker.
    @AppStorage("loom.agent.mode") private var agentMode: Bool = false
    @AppStorage("loom.agent.lmstudioMode") private var lmStudioAgentMode: Bool = true
    @AppStorage("loom.agent.allowBash") private var allowBash: Bool = false
    @AppStorage("loom.agent.permissionMode") private var permissionModeRaw: String = AgentPermissionMode.confirm.rawValue
    @AppStorage("loom.lmstudio.routingEnabled") private var lmStudioRoutingEnabled: Bool = false
    @AppStorage("loom.lmstudio.plannerModel") private var lmStudioPlannerModel: String = ""
    @AppStorage("loom.lmstudio.coderModel") private var lmStudioCoderModel: String = ""
    @AppStorage("loom.lmstudio.autoScale") private var lmStudioAutoScale: Bool = true
    @AppStorage("loom.lmstudio.maxContext") private var lmStudioMaxContext: Int = 65_536
    @AppStorage("loom.lmstudio.workbenchEnabled") private var lmStudioWorkbenchEnabled: Bool = true
    @AppStorage("loom.lmstudio.autoPrepare") private var lmStudioAutoPrepare: Bool = true
    @AppStorage("loom.agent.autoVerify") private var autoVerifyAgentRuns: Bool = true
    @AppStorage("loom.agent.previewSnapshots") private var previewSnapshots: Bool = false

    private let cwd: URL?
    private let handlesExternalRuns: Bool

    init(cwd: URL? = nil, handlesExternalRuns: Bool = true) {
        self.cwd = cwd
        self.handlesExternalRuns = handlesExternalRuns
    }

    private struct PendingURLRun: Identifiable {
        let id = UUID()
        let prompt: String
        let agentID: String?
    }

    private struct PendingToolApproval: Identifiable {
        let request: AgentToolApprovalRequest
        let continuation: CheckedContinuation<Bool, Never>
        var id: UUID { request.id }
    }

    private var selectedAgent: AgentDescriptor {
        registry.selectedAgent
    }

    private var effectiveAgentMode: Bool {
        selectedAgent.vendor == .lmstudio ? lmStudioAgentMode : agentMode
    }

    private var permissionMode: AgentPermissionMode {
        get { AgentPermissionMode(rawValue: permissionModeRaw) ?? .confirm }
        nonmutating set { permissionModeRaw = newValue.rawValue }
    }

    private var agentRunBashEnabled: Bool {
        permissionMode != .plan && (allowBash || permissionMode == .bypassPermissions)
    }

    private var sessionWorkspaceKey: String {
        AgentSessionStore.workspaceKey(
            workspaceID: workspace.workspaceID,
            folderPath: sessionWorkspacePath ?? workspace.folderPath,
            workspaceName: workspace.workspaceName
        )
    }

    private var sessionWorkspacePath: String? {
        if let cwd {
            return cwd.standardizedFileURL.path
        }
        let trimmed = workspace.folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    private var sessionScopeKey: String {
        "\(sessionWorkspaceKey)|\(selectedAgent.id)"
    }

    private var showsLMStudioWorkbench: Bool {
        selectedAgent.vendor == .lmstudio && effectiveAgentMode && lmStudioWorkbenchEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            conversationArea

            Divider().overlay(Color.white.opacity(0.10))
            if selectedAgent.vendor == .lmstudio {
                lmStudioStatusLine
            }
            inputBar
        }
        .background(Color(red: 0.018, green: 0.022, blue: 0.026))
        .onReceive(NotificationCenter.default.publisher(for: .loomURLAgentRun)) { note in
            handleAgentRunNotification(note)
        }
        .sheet(item: $pendingURLRun) { request in
            URLRunConfirmationSheet(
                prompt: request.prompt,
                agentLabel: agentLabel(for: request.agentID),
                onCancel: { pendingURLRun = nil },
                onRun: { confirmURLRun(request) }
            )
        }
        .sheet(item: $pendingToolApproval) { pending in
            ToolApprovalSheet(
                request: pending.request,
                onDecision: { approve in resolveToolApproval(approve) }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showRenameSession) {
            RenameSessionSheet(
                title: $renameDraft,
                onCancel: { showRenameSession = false },
                onSave: {
                    sessionStore.renameCurrent(
                        to: renameDraft,
                        workspaceKey: sessionWorkspaceKey,
                        workspacePath: sessionWorkspacePath
                    )
                    showRenameSession = false
                }
            )
        }
        .sheet(isPresented: $showSessionBrowser) {
            LMStudioSessionBrowserSheet(
                loomSessions: sessionStore.summaries,
                cliSessions: sessionStore.cliSessions,
                onResumeLoom: { summary in
                    resumeLMStudioSession(summary)
                    showSessionBrowser = false
                },
                onResumeCLI: { summary in
                    resumeLMStudioCLISession(summary)
                    showSessionBrowser = false
                },
                onDeleteLoom: { summary in
                    sessionStore.delete(
                        summary,
                        workspaceKey: sessionWorkspaceKey,
                        workspacePath: sessionWorkspacePath
                    )
                },
                onClose: { showSessionBrowser = false }
            )
        }
        .task(id: sessionScopeKey) {
            sessionStore.load(workspaceKey: sessionWorkspaceKey, workspacePath: sessionWorkspacePath)
            await refreshLMStudioRuntimeIfNeeded()
            if selectedAgent.vendor == .lmstudio,
               lmStudioAutoPrepare,
               lmStudioRuntime.serverState == .stopped {
                await prepareLMStudioForAgentWork()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loomDictationInsertText)) { notification in
            guard let text = notification.userInfo?["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft = text
            } else {
                draft += " " + text
            }
        }
    }

    private var conversationArea: some View {
        HStack(spacing: 0) {
            transcriptScroll
            if showsLMStudioWorkbench {
                Divider().overlay(Color.white.opacity(0.10))
                lmStudioWorkbenchPanel
                    .frame(width: 340)
            }
        }
    }

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty && !isWaiting {
                        placeholder
                            .padding(.top, 40)
                    }
                    ForEach($messages) { $msg in
                        messageBubble($msg)
                            .id(msg.id)
                    }
                    StreamingBubble(state: streaming, label: assistantLabel)
                        .id("__streaming__")
                    if let error {
                        errorBanner(error).id("err")
                    }
                }
                .padding(12)
            }
            .onChange(of: messages.last?.id) { _, last in
                guard let last else { return }
                if isWaiting {
                    proxy.scrollTo(last, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .onChange(of: streaming.isActive) { _, active in
                if active {
                    proxy.scrollTo("__streaming__", anchor: .bottom)
                }
            }
        }
    }

    /// Triggered by `loom://run?...` URLs forwarded through `URLSchemeHandler`.
    /// Captures a pending request and asks the user before sending. Multiple
    /// agent panes may exist, so WorkspaceView marks one visible pane as the
    /// external-run handler for the active workspace.
    private func handleAgentRunNotification(_ note: Notification) {
        guard handlesExternalRuns else { return }
        guard let info = note.userInfo,
              let prompt = info["prompt"] as? String,
              !prompt.isEmpty,
              !isWaiting else { return }

        let agentID = (info["agent"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        pendingURLRun = PendingURLRun(
            prompt: prompt,
            agentID: (agentID?.isEmpty ?? true) ? nil : agentID
        )
    }

    private func confirmURLRun(_ request: PendingURLRun) {
        if let agentID = request.agentID,
           registry.agents.contains(where: { $0.id == agentID }) {
            registry.selectedAgentID = agentID
        }

        pendingURLRun = nil
        draft = request.prompt
        send()
    }

    private func agentLabel(for id: String?) -> String {
        guard let id,
              let agent = registry.agents.first(where: { $0.id == id }) else {
            return pickerRowLabel(for: selectedAgent)
        }
        return pickerRowLabel(for: agent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LoomTheme.orange.opacity(0.16))
                    .frame(width: 28, height: 26)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LoomTheme.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                agentPicker

                if !headerSubtitle.isEmpty {
                    Text(headerSubtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(LoomTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if effectiveAgentMode {
                LoomStatusPill(
                    title: selectedAgent.vendor == .lmstudio ? permissionMode.label : "Agent Mode",
                    systemImage: "wand.and.stars",
                    tint: selectedAgent.vendor == .lmstudio && permissionMode == .bypassPermissions ? LoomTheme.orange : LoomTheme.purple
                )
            }

            if selectedAgent.vendor == .lmstudio {
                lmStudioSessionMenu
                Button {
                    openInLMStudioCLI()
                } label: {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                        .foregroundStyle(LoomTheme.mutedText)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Open this workspace in the lmstudio CLI")
            }
            if registry.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .help("Refreshing agents")
            }
            LoomIconButton(
                systemName: "arrow.clockwise",
                help: "Refresh agent list",
                tint: LoomTheme.orange,
                action: { Task { await registry.refresh(localEndpoints: endpoints.endpoints) } }
            )

            if isWaiting {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                LoomIconButton(
                    systemName: "stop.circle",
                    help: "Cancel",
                    tint: LoomTheme.orange,
                    action: { cancelInflight() }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.26))
        .overlay(Divider().overlay(Color.white.opacity(0.10)), alignment: .bottom)
    }

    /// Right-hand subtitle next to the picker. Claude shows its session id
    /// (so the user can see when a new conversation has started). Codex /
    /// Gemini have no resumable session today, so show "stateless" instead of
    /// a misleading id. Local-HTTP providers show the endpoint host so it's
    /// obvious which box is going to answer.
    private var headerSubtitle: String {
        if selectedAgent.vendor.isLocalHTTP,
           let id = selectedAgent.endpointID,
           let endpoint = endpoints.endpoints.first(where: { $0.id == id }),
           let url = endpoint.resolvedBaseURL,
           let host = url.host {
            if let port = url.port {
                return "\(host):\(port)"
            }
            return host
        }
        switch selectedAgent.vendor {
        case .claude:
            return String(cliProvider.sessionID.prefix(8))
        case .codex, .gemini:
            return "stateless"
        case .ollama, .openAICompatible, .lmstudio:
            return ""
        }
    }

    /// Real `Picker` rather than a `Menu` of custom-labeled buttons. The
    /// previous Menu implementation built each item as a Button whose label was
    /// an HStack with a trailing model-name; macOS's NSMenu bridge swallowed
    /// clicks on those compound labels so the selection never updated. A
    /// Picker bound to `registry.selectedAgentID` uses plain `Text` rows and
    /// gets a free checkmark on the active row, so clicks actually take.
    private var agentPicker: some View {
        @Bindable var registryBinding = registry
        return Picker("Agent", selection: $registryBinding.selectedAgentID) {
            ForEach(groupedAgents, id: \.0) { (groupKey, agents) in
                Section(groupKey) {
                    ForEach(agents) { agent in
                        Text(pickerRowLabel(for: agent))
                            .tag(agent.id)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .font(.system(size: 11))
    }

    private var lmStudioSessionMenu: some View {
        Menu {
            Button {
                startNewLMStudioSession()
            } label: {
                Label("New Session", systemImage: "plus")
            }
            Button {
                showSessionBrowser = true
            } label: {
                Label("Browse Sessions", systemImage: "rectangle.stack")
            }

            if !messages.isEmpty {
                Button {
                    renameDraft = sessionStore.summaries.first(where: { $0.id == sessionStore.currentSessionID })?.title
                        ?? messages.first(where: { $0.role == .user })?.text
                        ?? "LM Studio Session"
                    showRenameSession = true
                } label: {
                    Label("Rename Current Session", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    sessionStore.deleteCurrent(
                        workspaceKey: sessionWorkspaceKey,
                        workspacePath: sessionWorkspacePath
                    )
                    messages = []
                    compactionCount = 0
                } label: {
                    Label("Delete Current Session", systemImage: "trash")
                }
            }

            Section("Saved in Loom") {
                if sessionStore.summaries.isEmpty {
                    Text("No saved sessions")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessionStore.summaries.prefix(8)) { summary in
                        Menu(summary.title) {
                            Button {
                                resumeLMStudioSession(summary)
                            } label: {
                                Label("Resume in Agent Pane", systemImage: "arrow.uturn.forward")
                            }
                            Button(role: .destructive) {
                                sessionStore.delete(
                                    summary,
                                    workspaceKey: sessionWorkspaceKey,
                                    workspacePath: sessionWorkspacePath
                                )
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Saved by lmstudio CLI") {
                if sessionStore.cliSessions.isEmpty {
                    Text("No CLI sessions for this workspace")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessionStore.cliSessions.prefix(8)) { summary in
                        Button {
                            resumeLMStudioCLISession(summary)
                        } label: {
                            Label(summary.title, systemImage: "terminal")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(LoomTheme.mutedText)
        }
        .menuStyle(.borderlessButton)
        .help("LM Studio sessions")
    }

    /// "<vendor> · <agent>  (model)" — single Text so macOS Menu items render
    /// as a single tappable row. Model goes in parens since trailing-aligned
    /// secondary text isn't possible with a plain Text.
    private func pickerRowLabel(for agent: AgentDescriptor) -> String {
        var label = "\(agent.vendor.label) · \(agent.displayName)"
        if agent.vendor == .lmstudio {
            return label
        }
        if let model = agent.model {
            label += "  (\(model))"
        }
        return label
    }

    /// Group agents by section ("Plugin", "Built-in", endpoint name, or
    /// "Default") so the menu reads cleanly when the registry has many
    /// entries.
    private var groupedAgents: [(String, [AgentDescriptor])] {
        var buckets: [(String, [AgentDescriptor])] = []
        var seen: [String: Int] = [:]
        for agent in registry.agents {
            let key = agent.group ?? "Default"
            if let idx = seen[key] {
                buckets[idx].1.append(agent)
            } else {
                seen[key] = buckets.count
                buckets.append((key, [agent]))
            }
        }
        return buckets
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(red: 0.95, green: 0.39, blue: 0.18).opacity(0.7))
            Text(placeholderText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholderText: String {
        if workspace.supportsProposals && workspace.hasActiveTab {
            return "Ask for ideas — I can drop them straight into \u{201C}\(workspace.activeTabName)\u{201D}."
        }
        if !workspace.workspaceName.isEmpty {
            return "Ask the agent anything about \u{201C}\(workspace.workspaceName)\u{201D}."
        }
        return "Ask the agent anything about this workspace."
    }

    private func messageBubble(_ msg: Binding<AgentMessage>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            roleIcon(msg.wrappedValue.role)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(roleLabel(msg.wrappedValue.role))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.4)
                Text(msg.wrappedValue.text)
                    .font(.system(size: 12))
                    .foregroundStyle(msg.wrappedValue.role == .system ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                proposalCardIfNeeded(for: msg)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(bubbleBackground(msg.wrappedValue.role))
        .overlay {
            RoundedRectangle(cornerRadius: LoomTheme.rowRadius)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: LoomTheme.rowRadius))
    }

    @ViewBuilder
    private func proposalCardIfNeeded(for msg: Binding<AgentMessage>) -> some View {
        if msg.wrappedValue.role == .assistant,
           let proposals = msg.wrappedValue.proposals,
           !proposals.isEmpty,
           !msg.wrappedValue.proposalDismissed,
           workspace.supportsProposals {
            ProposalCard(
                messageID: msg.wrappedValue.id,
                proposals: Binding(
                    get: { msg.wrappedValue.proposals ?? [] },
                    set: { msg.wrappedValue.proposals = $0 }
                ),
                mode: msg.proposalMode,
                committedSummary: msg.proposalCommittedSummary,
                workspace: workspace,
                onDismiss: {
                    msg.wrappedValue.proposalDismissed = true
                }
            )
        }
    }

    @ViewBuilder
    private func roleIcon(_ role: AgentMessage.Role) -> some View {
        switch role {
        case .user:
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.18, green: 0.50, blue: 0.96))
        case .assistant:
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.95, green: 0.39, blue: 0.18))
        case .system:
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func roleLabel(_ role: AgentMessage.Role) -> String {
        switch role {
        case .user:      return "YOU"
        case .assistant: return assistantLabel
        case .system:    return "SYSTEM"
        }
    }

    private var assistantLabel: String {
        switch selectedAgent.vendor {
        case .claude, .codex, .gemini:    return "AGENT"
        case .ollama, .openAICompatible:  return "LOCAL"
        case .lmstudio:                   return "LM STUDIO"
        }
    }

    private func bubbleBackground(_ role: AgentMessage.Role) -> Color {
        switch role {
        case .user:      return Color.white.opacity(0.05)
        case .assistant: return Color.white.opacity(0.03)
        case .system:    return Color.orange.opacity(0.08)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
            Button {
                error = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if selectedAgent.vendor.isLocalHTTP {
                Button {
                    toggleAgentMode()
                } label: {
                    Image(systemName: effectiveAgentMode ? "wand.and.stars" : "wand.and.stars.inverse")
                        .font(.system(size: 14))
                        .foregroundStyle(effectiveAgentMode
                            ? Color(red: 0.62, green: 0.40, blue: 0.95)
                            : Color.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help(effectiveAgentMode
                    ? "Agent Mode on — model can call tools and track tasks"
                    : "Agent Mode off — single-shot chat")
                .disabled(isWaiting)
            }

            if selectedAgent.vendor == .lmstudio && effectiveAgentMode {
                permissionModePicker
            }

            TextField(
                "",
                text: $draft,
                prompt: Text(effectiveAgentMode && selectedAgent.vendor.isLocalHTTP
                    ? "Tell the agent what to do…"
                    : "Ask the agent…").foregroundColor(.white.opacity(0.4)),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(1...6)
            .disabled(isWaiting)
            .onSubmit { send() }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: LoomTheme.rowRadius)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LoomTheme.rowRadius))

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(canSend ? Color(red: 0.95, green: 0.39, blue: 0.18) : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.30))
    }

    private var lmStudioStatusLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 0.62, green: 0.40, blue: 0.95))
            Text(lmStudioStatusText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(effectiveAgentMode ? "Agent Mode" : "Chat")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(effectiveAgentMode ? Color.purple : Color.secondary)
            if effectiveAgentMode {
                Text(permissionMode.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(permissionMode == .bypassPermissions ? Color.orange : Color.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.22))
    }

    private var lmStudioStatusText: String {
        guard selectedAgent.vendor == .lmstudio else { return "" }
        let endpointText: String
        if let id = selectedAgent.endpointID,
           let endpoint = endpoints.endpoints.first(where: { $0.id == id }),
           let url = endpoint.resolvedBaseURL,
           let host = url.host {
            endpointText = url.port.map { "\(host):\($0)" } ?? host
        } else {
            endpointText = "no endpoint"
        }
        let modelText = selectedAgent.displayName.isEmpty ? "no model" : selectedAgent.displayName
        var bits = ["\(endpointText) · \(modelText)"]
        let context = lmStudioContextFilesSummary()
        if !context.isEmpty {
            bits.append("ctx \(context)")
        }
        if compactionCount > 0 {
            bits.append("compacted x\(compactionCount)")
        }
        if lmStudioRoutingEnabled {
            bits.append("routing")
        }
        return bits.joined(separator: " · ")
    }

    private var lmStudioWorkbenchPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                runtimeCard
                if !workbenchTasks.isEmpty {
                    workbenchSection("Plan", systemImage: "checklist") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(workbenchTasks) { task in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: taskIcon(task.status))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(taskColor(task.status))
                                        .frame(width: 14)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(task.subject)
                                            .font(.system(size: 11, weight: .semibold))
                                            .lineLimit(2)
                                        if !task.activeForm.isEmpty, task.activeForm != task.subject {
                                            Text(task.activeForm)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if !changedFiles.isEmpty {
                    workbenchSection("Changed Files", systemImage: "doc.badge.gearshape") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(changedFiles.prefix(12), id: \.self) { path in
                                Text(path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }

                workbenchSection("Verification", systemImage: "checkmark.seal") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                Task { await runVerificationFromWorkbench(force: true) }
                            } label: {
                                Label(isRunningVerification ? "Running" : "Run", systemImage: "play.fill")
                            }
                            .controlSize(.small)
                            .disabled(isRunningVerification || changedFiles.isEmpty)
                            Spacer()
                            Text(autoVerifyAgentRuns ? "Auto" : "Manual")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(autoVerifyAgentRuns ? .green : .secondary)
                        }

                        if verificationResults.isEmpty {
                            Text(changedFiles.isEmpty ? "No edits to verify yet." : "Verification has not run yet.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(verificationResults) { result in
                                verificationRow(result)
                            }
                        }
                    }
                }

                workbenchSection("Timeline", systemImage: "list.bullet.rectangle") {
                    VStack(alignment: .leading, spacing: 8) {
                        if workbenchEvents.isEmpty {
                            Text("Agent activity appears here during the run.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(workbenchEvents.prefix(24)) { event in
                                workbenchEventRow(event)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color.black.opacity(0.18))
    }

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .foregroundStyle(Color(red: 0.62, green: 0.40, blue: 0.95))
                Text("LM Studio")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Label(lmStudioRuntime.serverState.label, systemImage: runtimeStatusIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(runtimeStatusColor)
            }

            if let model = lmStudioRuntime.recommendedModel {
                Text(model.id)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !model.detail.isEmpty {
                    Text(model.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                Text(runtimeEmptyStateText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let error = lmStudioRuntime.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await refreshLMStudioRuntimeIfNeeded() }
                } label: {
                    Label(lmStudioRuntime.isRefreshing ? "Checking" : "Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(lmStudioRuntime.isRefreshing || lmStudioRuntime.isPreparing)

                Button {
                    Task { await prepareLMStudioForAgentWork() }
                } label: {
                    Label(lmStudioRuntime.isPreparing ? "Preparing" : "Prepare", systemImage: "wand.and.stars")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(lmStudioRuntime.isPreparing)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func workbenchSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            content()
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func workbenchEventRow(_ event: AgentWorkbenchEvent) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: event.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(eventColor(event.status))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Text(event.status.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(eventColor(event.status))
                }
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }

    private func verificationRow(_ result: AgentVerificationResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(result.succeeded ? .green : .red)
                Text(result.title)
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text(String(format: "%.1fs", result.duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if let command = result.command {
                Text(command)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(result.output.isEmpty ? "(no output)" : result.output)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .textSelection(.enabled)
        }
    }

    private var permissionModePicker: some View {
        Menu {
            ForEach(AgentPermissionMode.allCases) { mode in
                Button {
                    permissionMode = mode
                } label: {
                    Label(mode.label, systemImage: mode.systemImage)
                }
            }
        } label: {
            Image(systemName: permissionMode.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(permissionMode == .bypassPermissions ? Color.orange : Color.white.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help(permissionMode.help)
        .disabled(isWaiting)
    }

    private func toggleAgentMode() {
        if selectedAgent.vendor == .lmstudio {
            lmStudioAgentMode.toggle()
        } else {
            agentMode.toggle()
        }
    }

    private func persistLMStudioSession() {
        guard selectedAgent.vendor == .lmstudio else { return }
        sessionStore.save(
            messages: messages,
            workspaceKey: sessionWorkspaceKey,
            workspaceName: workspace.workspaceName.isEmpty ? "Workspace" : workspace.workspaceName,
            workspacePath: sessionWorkspacePath,
            modelLabel: selectedAgent.model ?? selectedAgent.displayName,
            compactedCount: compactionCount,
            finalStatus: latestRunStatus,
            changedFiles: changedFiles,
            verificationSummary: verificationResults.isEmpty ? nil : verificationSummary(verificationResults)
        )
    }

    private func startNewLMStudioSession() {
        guard !isWaiting else { return }
        sessionStore.startNew()
        messages = []
        error = nil
        compactionCount = 0
        pendingRunReview = nil
        streaming.cancel()
    }

    private func resumeLMStudioSession(_ summary: AgentSessionStore.SessionSummary) {
        guard !isWaiting else { return }
        messages = sessionStore.resume(summary)
        error = nil
        compactionCount = summary.compactedCount
        pendingRunReview = nil
        streaming.cancel()
    }

    private func resumeLMStudioCLISession(_ summary: AgentSessionStore.CLISessionSummary) {
        guard !isWaiting else { return }
        messages = sessionStore.resumeCLI(summary)
        error = nil
        compactionCount = 0
        pendingRunReview = nil
        streaming.cancel()
        persistLMStudioSession()
    }

    private func openInLMStudioCLI() {
        guard selectedAgent.vendor == .lmstudio else { return }
        var parts: [String] = ["lmstudio"]
        if let workspacePath = sessionWorkspacePath {
            parts += ["--workspace", shellQuote(workspacePath)]
        }
        if let url = selectedLMStudioEndpointURL() {
            parts += ["--base-url", shellQuote(url.absoluteString)]
        }
        if let model = selectedAgent.model, !model.isEmpty {
            parts += ["--model", shellQuote(model)]
        }
        if !lmStudioAutoScale {
            parts.append("--no-autoscale")
        } else {
            parts += ["--autoscale-max", "\(lmStudioMaxContext)"]
        }
        if lmStudioRoutingEnabled {
            if !lmStudioPlannerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts += ["--planner-model", shellQuote(lmStudioPlannerModel)]
            }
            if !lmStudioCoderModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts += ["--coder-model", shellQuote(lmStudioCoderModel)]
            }
        }
        if permissionMode == .bypassPermissions {
            parts.append("--bypass-permissions")
        } else if agentRunBashEnabled {
            parts.append("--allow-bash")
        }

        layout.ensureTerminalBlock()
        guard let terminal = layout.firstTerminalSession() else {
            error = "Could not open a terminal block for lmstudio."
            return
        }
        terminal.submit(parts.joined(separator: " "))
    }

    private func selectedLMStudioEndpointURL() -> URL? {
        guard let id = selectedAgent.endpointID,
              let endpoint = endpoints.endpoints.first(where: { $0.id == id }) else {
            return nil
        }
        return endpoint.resolvedBaseURL
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func lmStudioContextFilesSummary() -> String {
        guard let workspacePath = sessionWorkspacePath else { return "" }
        let folder = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let candidates = ["CLAUDE.md", "AGENTS.md", "GUIDE.md", "README.md", ".loom/project.json"]
        let found = candidates.filter {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        guard !found.isEmpty else { return "" }
        if found.count <= 3 {
            return found.joined(separator: ", ")
        }
        return found.prefix(3).joined(separator: ", ") + " +\(found.count - 3)"
    }

    private var runtimeStatusIcon: String {
        switch lmStudioRuntime.serverState {
        case .unknown:    return "circle.dotted"
        case .missingCLI: return "exclamationmark.triangle"
        case .stopped:    return "circle"
        case .running:    return "circle.fill"
        }
    }

    private var runtimeStatusColor: Color {
        switch lmStudioRuntime.serverState {
        case .running:    return .green
        case .missingCLI: return .orange
        case .stopped:    return .secondary
        case .unknown:    return .secondary
        }
    }

    private var runtimeEmptyStateText: String {
        switch lmStudioRuntime.serverState {
        case .missingCLI:
            return "`lms` is missing. Open LM Studio once and enable the CLI."
        case .stopped:
            return "Server is stopped. Prepare can start the daemon and load a model."
        case .running:
            return "Server is running, but no models were found."
        case .unknown:
            return "Runtime has not been checked yet."
        }
    }

    private var latestRunStatus: String? {
        if isWaiting { return "running" }
        if verificationResults.contains(where: { !$0.succeeded }) { return "needs_attention" }
        if !verificationResults.isEmpty { return "verified" }
        if !changedFiles.isEmpty { return "edited" }
        return nil
    }

    private func taskIcon(_ status: LiveAgentTaskStatus) -> String {
        switch status {
        case .pending:    return "circle"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .completed:  return "checkmark.circle.fill"
        case .cancelled:  return "minus.circle"
        case .deleted:    return "trash"
        }
    }

    private func taskColor(_ status: LiveAgentTaskStatus) -> Color {
        switch status {
        case .pending:    return .secondary
        case .inProgress: return .blue
        case .completed:  return .green
        case .cancelled:  return .orange
        case .deleted:    return .red
        }
    }

    private func eventColor(_ status: AgentWorkbenchEvent.Status) -> Color {
        switch status {
        case .running:   return .blue
        case .succeeded: return .green
        case .failed:    return .red
        case .info:      return .secondary
        }
    }

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "read_file":        return "doc.text"
        case "write_file":       return "square.and.pencil"
        case "edit_file":        return "pencil.line"
        case "list_dir":         return "folder"
        case "run_bash", "run_test": return "terminal"
        case "git_status", "git_diff": return "arrow.triangle.branch"
        case "preview_snapshot": return "globe"
        case "update_tasks":     return "checklist"
        default:                 return "wrench.adjustable"
        }
    }

    private func refreshLMStudioRuntimeIfNeeded() async {
        guard selectedAgent.vendor == .lmstudio else { return }
        await lmStudioRuntime.refresh(
            baseURL: selectedLMStudioEndpointURL(),
            selectedModel: selectedAgent.model
        )
    }

    private func prepareLMStudioForAgentWork() async {
        guard selectedAgent.vendor == .lmstudio else { return }
        let model = await lmStudioRuntime.prepareForAgentWork(
            baseURL: selectedLMStudioEndpointURL(),
            preferredModel: selectedAgent.model,
            contextTarget: lmStudioMaxContext,
            autoScale: lmStudioAutoScale
        )
        appendWorkbenchEvent(
            title: model == nil ? "Prepare failed" : "Prepared LM Studio",
            detail: model ?? (lmStudioRuntime.lastError ?? "Unknown error"),
            status: model == nil ? .failed : .succeeded,
            systemImage: model == nil ? "exclamationmark.triangle" : "wand.and.stars"
        )
        await registry.refresh(localEndpoints: endpoints.endpoints)
        if let model,
           let endpointID = selectedAgent.endpointID {
            let targetID = "lmstudio:\(endpointID.uuidString):\(model)"
            if registry.agents.contains(where: { $0.id == targetID }) {
                registry.selectedAgentID = targetID
            }
        }
    }

    private func resetWorkbenchForRun() {
        workbenchEvents = []
        workbenchTasks = []
        changedFiles = []
        verificationResults = []
        isRunningVerification = false
    }

    private func appendWorkbenchEvent(
        title: String,
        detail: String,
        status: AgentWorkbenchEvent.Status,
        systemImage: String
    ) {
        workbenchEvents.insert(AgentWorkbenchEvent(
            title: title,
            detail: detail,
            status: status,
            systemImage: systemImage
        ), at: 0)
    }

    private func recordChangedFile(from record: AgentOrchestrator.ToolCallRecord) {
        guard record.succeeded,
              record.name == "write_file" || record.name == "edit_file",
              let data = record.arguments.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = dict["path"] as? String,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !changedFiles.contains(path) else {
            return
        }
        changedFiles.append(path)
    }

    private func runVerificationFromWorkbench(force: Bool) async {
        guard force || autoVerifyAgentRuns else { return }
        guard !isRunningVerification, !changedFiles.isEmpty else { return }
        isRunningVerification = true
        appendWorkbenchEvent(
            title: "Verification started",
            detail: "\(changedFiles.count) changed file\(changedFiles.count == 1 ? "" : "s")",
            status: .running,
            systemImage: "checkmark.seal"
        )
        let workspaceURL = cwd ?? (workspace.folderPath.isEmpty ? nil : URL(fileURLWithPath: workspace.folderPath, isDirectory: true))
        let results = await AgentVerificationService.run(
            workspaceRoot: workspaceURL,
            changedFiles: changedFiles,
            previewURL: previewSnapshots ? activePreviewURL() : nil
        )
        verificationResults = results
        isRunningVerification = false
        let failed = results.filter { !$0.succeeded }
        appendWorkbenchEvent(
            title: failed.isEmpty ? "Verification passed" : "Verification needs attention",
            detail: results.isEmpty ? "No verification jobs were available." : "\(results.count) job\(results.count == 1 ? "" : "s"), \(failed.count) failed",
            status: failed.isEmpty ? .succeeded : .failed,
            systemImage: failed.isEmpty ? "checkmark.seal.fill" : "xmark.seal"
        )
        if !results.isEmpty {
            let summary = verificationSummary(results)
            messages.append(AgentMessage(role: .system, text: summary))
            persistLMStudioSession()
        }
    }

    private func verificationSummary(_ results: [AgentVerificationResult]) -> String {
        var lines = ["### Verification results"]
        for result in results {
            lines.append("- \(result.succeeded ? "PASS" : "FAIL") \(result.title)\(result.command.map { " (`\($0)`)" } ?? "")")
        }
        return lines.joined(separator: "\n")
    }

    private func activePreviewURL() -> URL? {
        guard let raw = layout.blocks.first(where: { $0.kind == .preview })?.effectivePreviewURL else {
            return nil
        }
        return URL(string: raw)
    }

    private var canSend: Bool {
        !isWaiting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func requestToolApproval(_ request: AgentToolApprovalRequest) async -> Bool {
        guard pendingToolApproval == nil else { return false }
        return await withCheckedContinuation { continuation in
            pendingToolApproval = PendingToolApproval(
                request: request,
                continuation: continuation
            )
        }
    }

    private func resolveToolApproval(_ approved: Bool) {
        guard let pending = pendingToolApproval else { return }
        pendingToolApproval = nil
        pending.continuation.resume(returning: approved)
    }

    private func cancelInflight() {
        cliProvider.cancel()
        streamTask?.cancel()
        streamTask = nil
        orchestratorTask?.cancel()
        orchestratorTask = nil
        orchestrator?.cancel()
        streaming.cancel()
        pendingProposals = nil
        pendingRunReview = nil
        resolveToolApproval(false)
        isWaiting = false
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isWaiting else { return }
        draft = ""
        error = nil
        if selectedAgent.vendor == .lmstudio {
            resetWorkbenchForRun()
        }
        let userMsg = AgentMessage(role: .user, text: prompt)
        messages.append(userMsg)
        streaming.begin()
        pendingProposals = nil
        pendingRunReview = nil
        isWaiting = true
        persistLMStudioSession()

        if selectedAgent.vendor.isLocalHTTP {
            if effectiveAgentMode {
                sendViaOrchestrator(prompt: prompt)
            } else {
                sendViaLocalHTTP(prompt: prompt)
            }
        } else {
            sendViaCLI(prompt: prompt)
        }
    }

    private func sendViaOrchestrator(prompt: String) {
        guard let endpointID = selectedAgent.endpointID,
              let endpoint = endpoints.endpoints.first(where: { $0.id == endpointID }),
              let url = endpoint.resolvedBaseURL,
              let model = selectedAgent.model else {
            error = "Local endpoint is no longer configured. Open Settings → Providers."
            streaming.cancel()
            isWaiting = false
            return
        }

        let provider: LLMProvider
        let agentSource: AgentSource
        switch endpoint.kind {
        case .lmstudio:
            provider = LMStudioProvider(baseURL: url, model: model)
            agentSource = .lmstudio
        case .openAICompatible:
            // OpenAI-compat providers don't emit tool-use events today, so
            // Agent Mode falls back to a single-turn loop. Show a soft hint.
            provider = OpenAICompatibleProvider(baseURL: url, model: model, apiKey: endpoints.authToken(for: endpoint))
            agentSource = .openAICompatible
        case .ollama:
            provider = OllamaProvider(baseURL: url, model: model)
            agentSource = .ollama
        }

        let workspaceURL = cwd ?? URL(fileURLWithPath: workspace.folderPath, isDirectory: true)
        let runner = AgentToolRunner(
            workspaceRoot: workspace.folderPath.isEmpty ? nil : workspaceURL,
            allowBash: agentRunBashEnabled,
            permissionMode: permissionMode,
            approvalHandler: { request in
                await requestToolApproval(request)
            }
        )
        let runtime = AgentOrchestrator(provider: provider, toolRunner: runner, source: agentSource, modelLabel: model)
        orchestrator = runtime

        orchestratorTask = Task { @MainActor in
            await runtime.run(
                prompt: prompt,
                system: agentSystemPrompt
            ) { event in
                handleOrchestratorEvent(event)
            }
            orchestratorTask = nil
            isWaiting = false
        }
    }

    private func handleOrchestratorEvent(_ event: AgentOrchestrator.AgentEvent) {
        switch event {
        case .textDelta(let chunk):
            streaming.append(chunk)
        case .turnStarted(let index):
            if index > 1 {
                streaming.append("\n\n— turn \(index) —\n")
            }
            appendWorkbenchEvent(
                title: "Turn \(index)",
                detail: index == 1 ? "Agent run started." : "Continuing with tool results.",
                status: .running,
                systemImage: "arrow.triangle.2.circlepath"
            )
        case .turnFinished:
            break
        case .taskListUpdated(let tasks):
            workbenchTasks = tasks
            appendWorkbenchEvent(
                title: "Plan updated",
                detail: "\(tasks.count) task\(tasks.count == 1 ? "" : "s")",
                status: .info,
                systemImage: "checklist"
            )
        case .toolStarted(let name, let arguments):
            let preview = String(SecretRedactor.redact(arguments).prefix(120))
            streaming.append("\n[tool] \(name) \(preview)\n")
            appendWorkbenchEvent(
                title: name,
                detail: preview,
                status: .running,
                systemImage: toolIcon(name)
            )
        case .toolFinished(let record):
            let prefix = record.succeeded ? "[ok]" : "[ERR]"
            let preview = String(SecretRedactor.redact(record.result).prefix(400))
            streaming.append("\(prefix) \(record.name): \(preview)\n")
            recordChangedFile(from: record)
            appendWorkbenchEvent(
                title: record.name,
                detail: preview,
                status: record.succeeded ? .succeeded : .failed,
                systemImage: toolIcon(record.name)
            )
        case .compacted(let count, let summary):
            compactionCount = count
            streaming.append("\n[context] \(summary)\n")
            appendWorkbenchEvent(
                title: "Context compacted",
                detail: summary,
                status: .info,
                systemImage: "rectangle.compress.vertical"
            )
        case .reviewReady(let review):
            pendingRunReview = review
            streaming.append("\n\(review)\n")
            appendWorkbenchEvent(
                title: "Review ready",
                detail: "Changed files and tool issues summarized.",
                status: .succeeded,
                systemImage: "doc.text.magnifyingglass"
            )
        case .completed(let finalText):
            _ = streaming.finish()
            var committed = finalText.isEmpty ? "(done)" : finalText
            if let pendingRunReview, !pendingRunReview.isEmpty {
                committed += "\n\n" + pendingRunReview
            }
            commitAssistantMessage(text: committed, toolProposals: nil)
            pendingRunReview = nil
            appendWorkbenchEvent(
                title: "Run completed",
                detail: changedFiles.isEmpty ? "No file edits recorded." : "\(changedFiles.count) changed file\(changedFiles.count == 1 ? "" : "s").",
                status: .succeeded,
                systemImage: "checkmark.circle.fill"
            )
            Task { await runVerificationFromWorkbench(force: false) }
        case .failed(let message):
            streaming.cancel()
            error = message
            appendWorkbenchEvent(
                title: "Run failed",
                detail: message,
                status: .failed,
                systemImage: "xmark.octagon"
            )
        case .cancelled:
            streaming.cancel()
            appendWorkbenchEvent(
                title: "Run cancelled",
                detail: "",
                status: .failed,
                systemImage: "stop.circle"
            )
        }
    }

    /// System prompt specialized for agent-mode runs. Reuses the workspace
    /// context block but adds tool-calling guidance so local code models
    /// understand when to invoke read_file / edit_file / run_bash and when
    /// to update the task list.
    private var agentSystemPrompt: String? {
        let base = workspaceSystemPrompt ?? ""
        let agentInstructions = """
        You are an autonomous coding agent running locally inside Loom.

        Tools available:
        - read_file(path) — read a file inside the workspace
        - list_dir(path) — list a directory inside the workspace
        - edit_file(path, old_string, new_string) — surgical text edit
        - write_file(path, content) — create or overwrite a file
        - run_bash(command) — run a shell command (\(agentRunBashEnabled ? "enabled" : "DISABLED — do not call"))
        - git_status() / git_diff(summary, path) — inspect local git changes
        - run_test(command) — run a verification command (\(agentRunBashEnabled ? "enabled" : "DISABLED — do not call"))
        - preview_snapshot(url) — check a localhost preview URL
        - update_tasks(tasks) — replace the visible task list. Use it to plan multi-step work and reflect progress.

        Permission mode: \(permissionMode.label). \(permissionMode.help)

        Workflow:
        1. For non-trivial requests, first call update_tasks with a plan.
        2. As you work, call update_tasks again to mark tasks in_progress / completed.
        3. When the user's request is done, answer in plain text with no tool calls. That ends the loop.
        """
        return base.isEmpty ? agentInstructions : "\(base)\n\n\(agentInstructions)"
    }

    private func sendViaCLI(prompt: String) {
        let vendor = selectedAgent.vendor
        let agentName = selectedAgent.cliName
        let decorated = decoratedPrompt(prompt)
        streamTask = Task {
            defer {
                streamTask = nil
                isWaiting = false
            }
            do {
                let response = try await cliProvider.send(
                    prompt: decorated,
                    cwd: cwd,
                    vendor: vendor,
                    agentName: agentName.isEmpty ? nil : agentName
                )
                guard !Task.isCancelled else { return }
                let finalText = response.isEmpty ? "(no response)" : response
                _ = streaming.finish()
                let proposals = workspace.supportsProposals
                    ? ListResponseParser.parse(finalText)
                    : nil
                commitAssistantMessage(text: finalText, toolProposals: proposals)
            } catch is CancellationError {
                streaming.cancel()
            } catch let error as CLIAgentProvider.ProviderError {
                streaming.cancel()
                if case .cancelled = error { return }
                self.error = error.localizedDescription
            } catch {
                streaming.cancel()
                self.error = error.localizedDescription
            }
        }
    }

    private func sendViaLocalHTTP(prompt: String) {
        guard let endpointID = selectedAgent.endpointID,
              let endpoint = endpoints.endpoints.first(where: { $0.id == endpointID }),
              let url = endpoint.resolvedBaseURL,
              let model = selectedAgent.model else {
            error = "Local endpoint is no longer configured. Open Settings → Providers."
            streaming.cancel()
            isWaiting = false
            return
        }

        let history = chatHistory(throughPrompt: prompt)
        let token = endpoints.authToken(for: endpoint)
        let stream: AsyncThrowingStream<LLMEvent, Error>

        switch endpoint.kind {
        case .ollama:
            let provider = OllamaProvider(baseURL: url, model: model)
            stream = provider.stream(messages: history, system: workspaceSystemPrompt)
        case .openAICompatible:
            let provider = OpenAICompatibleProvider(baseURL: url, model: model, apiKey: token)
            stream = provider.stream(messages: history, system: workspaceSystemPrompt)
        case .lmstudio:
            let provider = LMStudioProvider(baseURL: url, model: model)
            stream = provider.stream(messages: history, system: workspaceSystemPrompt)
        }

        streamTask = Task {
            do {
                for try await event in stream {
                    switch event {
                    case .textDelta(let chunk):
                        streaming.append(chunk)
                    case .toolUse:
                        // Local providers never emit tool-use today; ignore.
                        break
                    case .done:
                        finalizeStreamWithFallbackParser()
                    }
                }
            } catch {
                streaming.cancel()
                self.error = error.localizedDescription
            }
            streamTask = nil
            isWaiting = false
        }
    }

    /// On stream end: finalize streaming buffer into a real assistant
    /// message. For non-tool-use providers, run the heuristic list parser
    /// to extract proposals from the text.
    private func finalizeStreamWithFallbackParser() {
        let raw = streaming.finish()
        let committedText = raw.isEmpty ? "(no response)" : raw
        var proposals: [ItemProposal]? = nil
        if workspace.supportsProposals {
            proposals = ListResponseParser.parse(committedText)
        }
        commitAssistantMessage(text: committedText, toolProposals: proposals)
    }

    private func commitAssistantMessage(text: String, toolProposals: [ItemProposal]?) {
        var msg = AgentMessage(role: .assistant, text: text)
        msg.proposals = toolProposals
        msg.proposalMode = workspace.hasActiveTab ? .createNewTabs : .createNewTabs
        messages.append(msg)
        persistLMStudioSession()
    }

    /// System prompt for HTTP-based providers (Anthropic, Ollama, OpenAI-
    /// compatible). Combines a short role instruction with the live
    /// workspace snapshot so the model can ground its answer in what the
    /// user is looking at — folder, project memory, active tab, sibling tabs.
    private var workspaceSystemPrompt: String? {
        let snapshot = workspace.snapshot()
        let context = formatContextBlock(snapshot)
        let role = roleInstruction(for: snapshot)
        if context.isEmpty { return role }
        return role + "\n\n" + context
    }

    /// Prepended to every CLI agent prompt. Claude Code, Codex, and Gemini
    /// don't take a separate system message in our subprocess invocation, so
    /// the workspace context rides at the top of the user prompt with a
    /// clear "## User request" header before the actual question.
    private func decoratedPrompt(_ userPrompt: String) -> String {
        let snapshot = workspace.snapshot()
        let context = formatContextBlock(snapshot)
        let role = roleInstruction(for: snapshot)
        if context.isEmpty { return userPrompt }
        return [role, context, "## User request", userPrompt]
            .joined(separator: "\n\n")
    }

    /// Short instruction telling the model what kind of response Loom expects.
    /// Ideas workspaces ask for clean lists (Loom turns those into proposal
    /// cards); other workspaces get a more general "use the context" hint.
    private func roleInstruction(for snapshot: WorkspaceContext.Snapshot) -> String {
        if workspace.supportsProposals {
            return """
            You are inside Loom, a native macOS workspace. The user is on the \
            "\(snapshot.workspaceKind.label)" workspace with the \
            "\(snapshot.activeTabName)" idea tab focused. When the user asks for \
            ideas, items, tasks, or a brainstorm, reply with a clean numbered \
            or bulleted list — one short phrase per item, no extra prose \
            between items. Loom will offer to add the items to the user's \
            active tab. Use the workspace context below to ground your \
            suggestions in this specific project — pull from the project name, \
            folder, project memory, the active tab's existing notes, and the \
            other idea tabs already in the workspace. Do not repeat ideas that \
            are already captured in those tabs.
            """
        }
        return """
        You are inside Loom, a native macOS workspace. Use the workspace \
        context below to answer the user with awareness of the project they \
        are working in — its folder, project memory, and any notes they have \
        captured.
        """
    }

    /// Render the snapshot as a markdown block. Empty when the snapshot has
    /// nothing useful to say — the caller short-circuits in that case so we
    /// never paste a blank "Loom workspace context" header.
    private func formatContextBlock(_ snapshot: WorkspaceContext.Snapshot) -> String {
        guard snapshot.hasAnyContext else { return "" }
        var lines: [String] = ["## Loom workspace context"]
        if !snapshot.workspaceName.isEmpty {
            lines.append("- Workspace: \(snapshot.workspaceName) (\(snapshot.workspaceKind.label))")
        } else {
            lines.append("- Workspace kind: \(snapshot.workspaceKind.label)")
        }
        if let folder = snapshot.folderPath, !folder.isEmpty {
            lines.append("- Project folder: \(folder)")
        }
        if snapshot.workspaceKind == .ideas {
            lines.append("- Active idea tab: \"\(snapshot.activeTabName)\"")
            let body = snapshot.activeTabBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                lines.append("")
                lines.append("### Active tab contents")
                lines.append(truncate(body, max: 2000))
            }
            if !snapshot.siblingTabs.isEmpty {
                lines.append("")
                lines.append("### Other idea tabs in this workspace")
                for tab in snapshot.siblingTabs.prefix(8) {
                    let excerpt = tab.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if excerpt.isEmpty {
                        lines.append("- \"\(tab.title)\"")
                    } else {
                        lines.append("- \"\(tab.title)\": \(excerpt)")
                    }
                }
            }
        }
        if let memory = snapshot.projectMemory, !memory.isEmpty {
            lines.append("")
            lines.append("### Project memory")
            lines.append(memory)
        }
        return lines.joined(separator: "\n")
    }

    private func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        let cap = text.index(text.startIndex, offsetBy: max)
        return String(text[..<cap]) + "…"
    }

    /// Build the running chat history that local HTTP providers expect.
    /// Excludes any in-flight assistant placeholder; the latest user message
    /// is what we're answering.
    private func chatHistory(throughPrompt prompt: String) -> [LLMMessage] {
        var history: [LLMMessage] = []
        for msg in messages {
            switch msg.role {
            case .user:
                history.append(LLMMessage(role: .user, content: msg.text))
            case .assistant where !msg.text.isEmpty:
                history.append(LLMMessage(role: .assistant, content: msg.text))
            default:
                continue
            }
        }
        return history
    }
}

private struct RenameSessionSheet: View {
    @Binding var title: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Session")
                .font(.system(size: 15, weight: .semibold))
            TextField("Session title", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

private struct LMStudioSessionBrowserSheet: View {
    let loomSessions: [AgentSessionStore.SessionSummary]
    let cliSessions: [AgentSessionStore.CLISessionSummary]
    let onResumeLoom: (AgentSessionStore.SessionSummary) -> Void
    let onResumeCLI: (AgentSessionStore.CLISessionSummary) -> Void
    let onDeleteLoom: (AgentSessionStore.SessionSummary) -> Void
    let onClose: () -> Void

    @State private var query: String = ""
    @State private var showCLI: Bool = true

    private var filteredLoom: [AgentSessionStore.SessionSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return loomSessions }
        return loomSessions.filter { summary in
            [
                summary.title,
                summary.workspaceName,
                summary.modelLabel ?? "",
                summary.finalStatus ?? "",
                summary.changedFiles?.joined(separator: " ") ?? "",
                summary.lastPreview
            ].joined(separator: " ").lowercased().contains(trimmed)
        }
    }

    private var filteredCLI: [AgentSessionStore.CLISessionSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return cliSessions }
        return cliSessions.filter { summary in
            [
                summary.title,
                summary.workspacePath,
                summary.modelLabel ?? "",
                summary.preview
            ].joined(separator: " ").lowercased().contains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LM Studio Sessions")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search sessions, models, files", text: $query)
                    .textFieldStyle(.plain)
                Toggle("CLI", isOn: $showCLI)
                    .toggleStyle(.checkbox)
            }
            .padding(8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sessionHeader("Saved in Loom", count: filteredLoom.count)
                    if filteredLoom.isEmpty {
                        emptyRow("No Loom sessions match.")
                    } else {
                        ForEach(filteredLoom) { summary in
                            loomSessionRow(summary)
                        }
                    }

                    if showCLI {
                        sessionHeader("Saved by lmstudio CLI", count: filteredCLI.count)
                            .padding(.top, 8)
                        if filteredCLI.isEmpty {
                            emptyRow("No CLI sessions match.")
                        } else {
                            ForEach(filteredCLI) { summary in
                                cliSessionRow(summary)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
    }

    private func sessionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func loomSessionRow(_ summary: AgentSessionStore.SessionSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIcon(summary.finalStatus))
                .foregroundStyle(statusColor(summary.finalStatus))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(rowDetail(
                    date: summary.updatedAt,
                    model: summary.modelLabel,
                    count: summary.messageCount,
                    extra: summary.changedFiles?.isEmpty == false ? "\(summary.changedFiles?.count ?? 0) files" : nil
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if !summary.lastPreview.isEmpty {
                    Text(summary.lastPreview)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Resume") { onResumeLoom(summary) }
                .controlSize(.small)
            Button(role: .destructive) {
                onDeleteLoom(summary)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cliSessionRow(_ summary: AgentSessionStore.CLISessionSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(rowDetail(date: summary.savedAt, model: summary.modelLabel, count: summary.messageCount, extra: "CLI"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !summary.preview.isEmpty {
                    Text(summary.preview)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Resume") { onResumeCLI(summary) }
                .controlSize(.small)
        }
        .padding(10)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func rowDetail(date: Date, model: String?, count: Int, extra: String?) -> String {
        [date.formatted(date: .abbreviated, time: .shortened), model, "\(count) messages", extra]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func statusIcon(_ status: String?) -> String {
        switch status {
        case "verified":        return "checkmark.seal.fill"
        case "needs_attention": return "exclamationmark.triangle.fill"
        case "edited":          return "doc.badge.gearshape"
        case "running":         return "arrow.triangle.2.circlepath"
        default:                return "clock"
        }
    }

    private func statusColor(_ status: String?) -> Color {
        switch status {
        case "verified":        return .green
        case "needs_attention": return .orange
        case "edited":          return .blue
        case "running":         return .purple
        default:                return .secondary
        }
    }
}

private struct URLRunConfirmationSheet: View {
    let prompt: String
    let agentLabel: String
    let onCancel: () -> Void
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(Color(red: 0.95, green: 0.39, blue: 0.18))
                Text("Confirm Agent Run")
                    .font(.system(size: 15, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Agent")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(agentLabel)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(prompt)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 120, maxHeight: 220)
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Run", action: onRun)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct ToolApprovalSheet: View {
    let request: AgentToolApprovalRequest
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(.orange)
                Text("Approve Tool Call")
                    .font(.system(size: 15, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(request.action.label)
                    .font(.system(size: 12, weight: .semibold))
                Text(request.target)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !request.preview.isEmpty {
                ScrollView {
                    Text(request.preview)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 80, maxHeight: 180)
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Deny") { onDecision(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Allow Once") { onDecision(true) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var iconName: String {
        switch request.action {
        case .writeFile, .editFile:
            return "doc.badge.gearshape"
        case .runBash:
            return "terminal"
        }
    }
}

/// Live-streaming bubble. Observes `StreamingState` directly so token
/// appends only re-render this view, not the whole `LazyVStack(messages)`
/// in `AgentPaneView`. Disappears when the stream finalizes.
struct StreamingBubble: View {
    let state: StreamingState
    let label: String

    var body: some View {
        if state.isActive {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.39, blue: 0.18))
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.4)
                    Text(state.buffer.isEmpty ? "…" : state.buffer)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.white.opacity(0.03))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
