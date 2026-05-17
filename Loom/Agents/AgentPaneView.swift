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
    @Environment(WorkspaceContext.self) private var workspace
    @State private var cliProvider = CLIAgentProvider()
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

    /// Persisted across panes: when on, local-HTTP providers run through
    /// `AgentOrchestrator` (multi-turn loop, tool calls, task list) instead
    /// of single-shot streaming. Off by default since plain chat is what
    /// users expect when they pick a model from the picker.
    @AppStorage("loom.agent.mode") private var agentMode: Bool = false
    @AppStorage("loom.agent.allowBash") private var allowBash: Bool = false

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

    var body: some View {
        VStack(spacing: 0) {
            header

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
                    // No animation while a stream is in flight — token-by-token
                    // animations chain and stutter. Snap on commit.
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

            Divider().overlay(Color.white.opacity(0.10))
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
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.95, green: 0.39, blue: 0.18))

            agentPicker

            Text("· \(headerSubtitle)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            if registry.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .help("Refreshing agents")
            }
            Button {
                Task { await registry.refresh(localEndpoints: endpoints.endpoints) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Refresh agent list")

            if isWaiting {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Button {
                    cancelInflight()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.32))
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

    /// "<vendor> · <agent>  (model)" — single Text so macOS Menu items render
    /// as a single tappable row. Model goes in parens since trailing-aligned
    /// secondary text isn't possible with a plain Text.
    private func pickerRowLabel(for agent: AgentDescriptor) -> String {
        var label = "\(agent.vendor.label) · \(agent.displayName)"
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
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        HStack(alignment: .bottom, spacing: 8) {
            if selectedAgent.vendor.isLocalHTTP {
                Button {
                    agentMode.toggle()
                } label: {
                    Image(systemName: agentMode ? "wand.and.stars" : "wand.and.stars.inverse")
                        .font(.system(size: 14))
                        .foregroundStyle(agentMode
                            ? Color(red: 0.62, green: 0.40, blue: 0.95)
                            : Color.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help(agentMode
                    ? "Agent Mode on — model can call tools and track tasks"
                    : "Agent Mode off — single-shot chat")
                .disabled(isWaiting)
            }

            TextField(
                "",
                text: $draft,
                prompt: Text(agentMode && selectedAgent.vendor.isLocalHTTP
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
        .background(Color.black.opacity(0.32))
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
        resolveToolApproval(false)
        isWaiting = false
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isWaiting else { return }
        draft = ""
        error = nil
        let userMsg = AgentMessage(role: .user, text: prompt)
        messages.append(userMsg)
        streaming.begin()
        pendingProposals = nil
        isWaiting = true

        if selectedAgent.vendor.isLocalHTTP {
            if agentMode {
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
            allowBash: allowBash,
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
        case .turnFinished:
            break
        case .taskListUpdated:
            break
        case .toolStarted(let name, let arguments):
            let preview = String(SecretRedactor.redact(arguments).prefix(120))
            streaming.append("\n[tool] \(name) \(preview)\n")
        case .toolFinished(let record):
            let prefix = record.succeeded ? "[ok]" : "[ERR]"
            let preview = String(SecretRedactor.redact(record.result).prefix(400))
            streaming.append("\(prefix) \(record.name): \(preview)\n")
        case .completed(let finalText):
            _ = streaming.finish()
            commitAssistantMessage(text: finalText.isEmpty ? "(done)" : finalText, toolProposals: nil)
        case .failed(let message):
            streaming.cancel()
            error = message
        case .cancelled:
            streaming.cancel()
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
        - run_bash(command) — run a shell command (\(allowBash ? "enabled" : "DISABLED — do not call"))
        - update_tasks(tasks) — replace the visible task list. Use it to plan multi-step work and reflect progress.

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
