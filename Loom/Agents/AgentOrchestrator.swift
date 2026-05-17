import Foundation
import Observation
import os

private let orchestratorLog = Logger(subsystem: "com.chasesims.Loom", category: "orchestrator")

/// Provider-agnostic agent loop. Wraps any `LLMProvider` and drives a
/// multi-turn conversation that can call tools (read_file, edit_file,
/// run_bash) and maintain a visible task list. Designed for LM Studio's
/// OpenAI-compatible endpoint with local code models like Qwen3-Coder, but
/// works with any provider that emits `LLMEvent.toolUse`.
///
/// Termination follows the Claude Code pattern: the loop ends when the model
/// produces a turn with no tool calls (i.e. it answered in plain text). Hard
/// stops also kick in at `maxTurns` and on user cancel.
@Observable
@MainActor
final class AgentOrchestrator {
    /// Snapshot of one model turn in the loop, kept so the UI can show what
    /// the agent did at each step.
    struct Turn: Identifiable, Hashable {
        let id: UUID = UUID()
        let index: Int
        let assistantText: String
        let toolCalls: [ToolCallRecord]
    }

    struct ToolCallRecord: Identifiable, Hashable {
        let id: UUID = UUID()
        let name: String
        let arguments: String
        let result: String
        let succeeded: Bool
    }

    enum AgentEvent {
        case textDelta(String)
        case turnStarted(index: Int)
        case turnFinished(Turn)
        case taskListUpdated([LiveAgentTask])
        case toolStarted(name: String, arguments: String)
        case toolFinished(ToolCallRecord)
        case completed(finalText: String)
        case failed(String)
        case cancelled
    }

    enum OrchestratorError: Error, LocalizedError {
        case maxTurnsExceeded(Int)
        case noProvider

        var errorDescription: String? {
            switch self {
            case .maxTurnsExceeded(let n): return "Agent stopped after \(n) turns without finishing."
            case .noProvider:              return "No agent provider configured."
            }
        }
    }

    let sessionID: String = UUID().uuidString
    let source: AgentSource
    let modelLabel: String?

    private(set) var tasks: [LiveAgentTask] = []
    private(set) var turns: [Turn] = []
    private(set) var isRunning: Bool = false
    private(set) var currentStreamingText: String = ""
    private(set) var lastError: String?

    /// Maximum loop iterations before bailing. Read from UserDefaults so the
    /// Settings UI can change it without rebuilding the orchestrator.
    var maxTurns: Int {
        let stored = UserDefaults.standard.integer(forKey: "loom.agent.maxTurns")
        return stored > 0 ? stored : 30
    }

    private let provider: LLMProvider
    private let toolRunner: AgentToolRunner
    private var currentTask: Task<Void, Never>?
    private var transcript: [LLMMessage] = []

    init(provider: LLMProvider, toolRunner: AgentToolRunner, source: AgentSource, modelLabel: String? = nil) {
        self.provider = provider
        self.toolRunner = toolRunner
        self.source = source
        self.modelLabel = LiveAgentTaskGroup.normalizedModelLabel(modelLabel)
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
    }

    /// Drive the loop until the model answers without a tool call, or until
    /// `maxTurns` is hit. `onEvent` runs on the main actor so SwiftUI can
    /// react directly.
    func run(
        prompt: String,
        system: String?,
        onEvent: @escaping @MainActor (AgentEvent) -> Void
    ) async {
        cancel()
        isRunning = true
        lastError = nil
        turns = []
        currentStreamingText = ""
        transcript = [LLMMessage(role: .user, content: prompt)]

        let task = Task { @MainActor in
            do {
                try await loop(system: system, onEvent: onEvent)
            } catch is CancellationError {
                onEvent(.cancelled)
            } catch {
                lastError = error.localizedDescription
                onEvent(.failed(error.localizedDescription))
                orchestratorLog.error("Agent loop failed: \(error.localizedDescription, privacy: .public)")
            }
            isRunning = false
            currentTask = nil
        }
        currentTask = task
        await task.value
    }

    // MARK: - Loop

    private func loop(
        system: String?,
        onEvent: @escaping @MainActor (AgentEvent) -> Void
    ) async throws {
        let tools = AgentToolRunner.defaultTools
        var turnIndex = 0

        while turnIndex < maxTurns {
            try Task.checkCancellation()
            turnIndex += 1
            onEvent(.turnStarted(index: turnIndex))
            currentStreamingText = ""

            var assistantText = ""
            var toolCalls: [(name: String, input: Data)] = []

            let stream = provider.stream(messages: transcript, system: system, tools: tools)
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .textDelta(let chunk):
                    assistantText += chunk
                    currentStreamingText += chunk
                    onEvent(.textDelta(chunk))
                case .toolUse(let name, let input):
                    toolCalls.append((name: name, input: input))
                case .done:
                    break
                }
            }

            // Always record the assistant turn in the transcript so the model
            // can reason about what it just said next iteration.
            transcript.append(LLMMessage(role: .assistant, content: assistantText))

            if toolCalls.isEmpty {
                let turn = Turn(index: turnIndex, assistantText: assistantText, toolCalls: [])
                turns.append(turn)
                onEvent(.turnFinished(turn))
                onEvent(.completed(finalText: assistantText))
                markRemainingTasksComplete()
                return
            }

            var records: [ToolCallRecord] = []
            for call in toolCalls {
                try Task.checkCancellation()
                let argsString = String(decoding: call.input, as: UTF8.self)
                onEvent(.toolStarted(name: call.name, arguments: argsString))
                let record: ToolCallRecord
                if call.name == "update_tasks" {
                    do {
                        let count = try applyTaskUpdate(call.input)
                        let summary = "Task list updated. \(count) task\(count == 1 ? "" : "s")."
                        record = ToolCallRecord(
                            name: call.name,
                            arguments: argsString,
                            result: summary,
                            succeeded: true
                        )
                        onEvent(.taskListUpdated(tasks))
                    } catch {
                        record = ToolCallRecord(
                            name: call.name,
                            arguments: argsString,
                            result: "Error: \(error.localizedDescription)",
                            succeeded: false
                        )
                    }
                } else {
                    do {
                        let result = try await toolRunner.execute(name: call.name, input: call.input)
                        record = ToolCallRecord(
                            name: call.name,
                            arguments: argsString,
                            result: result,
                            succeeded: true
                        )
                    } catch {
                        record = ToolCallRecord(
                            name: call.name,
                            arguments: argsString,
                            result: "Error: \(error.localizedDescription)",
                            succeeded: false
                        )
                    }
                }
                records.append(record)
                onEvent(.toolFinished(record))
            }

            // Feed tool results back to the model as a synthetic user turn.
            // Using user-role keeps every provider happy (some don't support
            // the "tool" role, especially older OpenAI-compat shims).
            let toolReport = records.map { record in
                "Tool \(record.name) \(record.succeeded ? "succeeded" : "FAILED"):\n\(record.result)"
            }.joined(separator: "\n\n")
            transcript.append(LLMMessage(role: .user, content: toolReport))

            let turn = Turn(index: turnIndex, assistantText: assistantText, toolCalls: records)
            turns.append(turn)
            onEvent(.turnFinished(turn))
        }

        throw OrchestratorError.maxTurnsExceeded(maxTurns)
    }

    // MARK: - Task list management

    private struct TaskUpdatePayload: Decodable {
        let tasks: [Item]
        struct Item: Decodable {
            let subject: String
            let activeForm: String?
            let status: String
        }
    }

    @discardableResult
    private func applyTaskUpdate(_ input: Data) throws -> Int {
        let payload = try JSONDecoder().decode(TaskUpdatePayload.self, from: input)
        let now = Date()
        let next: [LiveAgentTask] = payload.tasks.enumerated().map { index, item in
            let status = LiveAgentTaskStatus(rawValue: item.status) ?? .pending
            return LiveAgentTask(
                id: "\(source.rawValue):\(sessionID):\(index)",
                source: source,
                modelLabel: modelLabel,
                sessionID: sessionID,
                taskID: String(index),
                subject: item.subject,
                description: "",
                activeForm: item.activeForm ?? item.subject,
                status: status,
                updatedAt: now
            )
        }
        tasks = next
        return next.count
    }

    /// When the model wraps up cleanly, flip any leftover in-progress/pending
    /// tasks to completed so the UI doesn't look mid-stream forever. Doesn't
    /// touch tasks the model explicitly cancelled.
    private func markRemainingTasksComplete() {
        let now = Date()
        tasks = tasks.map { task in
            switch task.status {
            case .pending, .inProgress:
                return LiveAgentTask(
                    id: task.id,
                    source: task.source,
                    modelLabel: task.modelLabel,
                    sessionID: task.sessionID,
                    taskID: task.taskID,
                    subject: task.subject,
                    description: task.description,
                    activeForm: task.activeForm,
                    status: .completed,
                    updatedAt: now
                )
            default:
                return task
            }
        }
    }
}
