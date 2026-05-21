import AppKit
import AVFoundation
import Foundation
import Observation
import OSLog
import Speech

extension Notification.Name {
    static let loomDictationInsertText = Notification.Name("loomDictationInsertText")
}

private let dictationLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.chasesims.Loom",
    category: "Dictation"
)

@Observable
@MainActor
final class DictationService {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case transcribing
        case error(String)

        var isActive: Bool {
            switch self {
            case .requestingPermission, .listening, .transcribing:
                return true
            case .idle, .error:
                return false
            }
        }

        var isError: Bool {
            if case .error = self {
                return true
            }
            return false
        }

        var label: String {
            switch self {
            case .idle:
                return "Dictation"
            case .requestingPermission:
                return "Requesting Access"
            case .listening:
                return "Listening"
            case .transcribing:
                return "Transcribing"
            case .error:
                return "Dictation Error"
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var liveTranscript: String = ""

    private let audioEngine = AVAudioEngine()
    private let captureMonitor = DictationCaptureMonitor()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var captureWatchdogTask: Task<Void, Never>?
    private var finalResultWatchdogTask: Task<Void, Never>?
    private var isFinishingRecognition = false
    private var hasInsertedTranscript = false
    private var insertionTarget: DictationInsertionTarget?

    func toggle() {
        if state.isActive {
            stopAndInsert()
        } else {
            Task { await start() }
        }
    }

    func cancel() {
        guard state.isActive else { return }
        finishAudio(cancelTask: true)
        liveTranscript = ""
        state = .idle
    }

    private func start() async {
        guard !state.isActive else { return }
        let target = FocusedTextInserter.captureTarget()
        finishAudio(cancelTask: true)
        insertionTarget = target

        state = .requestingPermission
        liveTranscript = ""
        hasInsertedTranscript = false
        captureMonitor.reset()

        let allowed = await requestPermissions()
        guard allowed else {
            state = .error("Enable Microphone and Speech Recognition access in System Settings.")
            return
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            state = .error("Speech recognition is not available right now.")
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            state = .error("Could not start a dictation request.")
            return
        }
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            state = .error("No microphone input format is available. Check the selected Mac input device.")
            recognitionRequest = nil
            return
        }

        recognitionTask = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeRecognitionHandler(for: self)
        )
        isFinishingRecognition = false

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: Self.makeAudioTapHandler(request: request, monitor: captureMonitor)
        )

        audioEngine.prepare()
        do {
            try audioEngine.start()
            startCaptureWatchdog()
            dictationLogger.debug(
                "Started dictation capture, sampleRate=\(format.sampleRate, privacy: .public), channels=\(format.channelCount, privacy: .public)"
            )
        } catch {
            inputNode.removeTap(onBus: 0)
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            state = .error("Could not start microphone capture: \(error.localizedDescription)")
            return
        }

        state = .listening
    }

    private func requestPermissions() async -> Bool {
        let micAllowed = await requestMicrophonePermission()
        guard micAllowed else { return false }
        let speechStatus = await requestSpeechPermission()
        return speechStatus == .authorized
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func requestSpeechPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus)
            }
        }
    }

    private func handleRecognition(transcript: String?, isFinal: Bool, errorMessage: String?) {
        if let transcript {
            liveTranscript = transcript
            state = isFinal ? .transcribing : .listening
            if isFinal {
                insertTranscriptIfNeeded()
                completeRecognition()
                state = .idle
            }
        }

        if let errorMessage,
           !hasInsertedTranscript,
           state.isActive {
            completeRecognition()
            state = .error(errorMessage)
        }
    }

    private func stopAndInsert() {
        let insertedImmediately = insertTranscriptIfNeeded()
        finishAudio(cancelTask: false)
        if insertedImmediately {
            state = .idle
            startFinalResultWatchdog(showNoSpeechError: false)
        } else {
            state = .transcribing
            startFinalResultWatchdog(showNoSpeechError: true)
        }
    }

    @discardableResult
    private func insertTranscriptIfNeeded() -> Bool {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !hasInsertedTranscript else { return false }
        hasInsertedTranscript = true
        if !(insertionTarget?.insert(text) ?? false),
           !FocusedTextInserter.insert(text) {
            NotificationCenter.default.post(
                name: .loomDictationInsertText,
                object: nil,
                userInfo: ["text": text]
            )
        }
        return true
    }

    private func finishAudio(cancelTask: Bool) {
        stopAudioCapture()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if cancelTask {
            finalResultWatchdogTask?.cancel()
            finalResultWatchdogTask = nil
            recognitionTask?.cancel()
            recognitionTask = nil
            isFinishingRecognition = false
            insertionTarget = nil
        } else if !isFinishingRecognition {
            recognitionTask?.finish()
            isFinishingRecognition = recognitionTask != nil
        }
    }

    private func stopAudioCapture() {
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func completeRecognition() {
        finalResultWatchdogTask?.cancel()
        finalResultWatchdogTask = nil
        stopAudioCapture()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        isFinishingRecognition = false
        insertionTarget = nil
    }

    private func startCaptureWatchdog() {
        captureWatchdogTask?.cancel()
        let monitor = captureMonitor
        captureWatchdogTask = Task { [weak self, monitor] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            let snapshot = monitor.snapshot()
            guard snapshot.bufferCount == 0 else { return }

            await MainActor.run {
                guard let self, self.state.isActive else { return }
                dictationLogger.error("Dictation audio tap started but delivered no buffers")
                self.finishAudio(cancelTask: true)
                self.state = .error("Microphone started, but no audio arrived. Check the Mac input device and try again.")
            }
        }
    }

    private func startFinalResultWatchdog(showNoSpeechError: Bool) {
        finalResultWatchdogTask?.cancel()
        finalResultWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.recognitionTask != nil else { return }
                dictationLogger.error("Speech recognizer did not deliver a final result before timeout")
                self.recognitionTask?.cancel()
                self.recognitionTask = nil
                self.isFinishingRecognition = false
                self.finalResultWatchdogTask = nil
                self.insertionTarget = nil

                if showNoSpeechError, !self.hasInsertedTranscript {
                    self.state = .error("No speech was transcribed. Check the selected Mac input device and try again.")
                } else if self.state.isActive {
                    self.state = .idle
                }
            }
        }
    }

    nonisolated private static func makeAudioTapHandler(
        request: SFSpeechAudioBufferRecognitionRequest,
        monitor: DictationCaptureMonitor
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            monitor.markBuffer(frameLength: buffer.frameLength)
            request.append(buffer)
        }
    }

    nonisolated private static func makeRecognitionHandler(
        for service: DictationService
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak service] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorMessage = error?.localizedDescription
            if let errorMessage {
                dictationLogger.error("Speech recognizer error: \(errorMessage, privacy: .public)")
            }

            Task { @MainActor in
                service?.handleRecognition(
                    transcript: transcript,
                    isFinal: isFinal,
                    errorMessage: errorMessage
                )
            }
        }
    }
}

@MainActor
final class DictationTerminalTargetRegistry {
    static let shared = DictationTerminalTargetRegistry()

    private weak var terminalView: LoomTerminalView?
    private var activatedAt: Date?

    private init() {}

    func noteActiveTerminal(_ terminalView: LoomTerminalView) {
        self.terminalView = terminalView
        activatedAt = Date()
    }

    func recentTerminal(maxAge: TimeInterval = 120) -> LoomTerminalView? {
        guard let terminalView,
              terminalView.window != nil,
              let activatedAt,
              Date().timeIntervalSince(activatedAt) <= maxAge else {
            return nil
        }
        return terminalView
    }
}

@MainActor
private final class DictationInsertionTarget {
    private weak var terminalView: LoomTerminalView?
    private weak var textView: NSTextView?
    private weak var responder: NSResponder?

    init(terminalView: LoomTerminalView) {
        self.terminalView = terminalView
    }

    init(textView: NSTextView) {
        self.textView = textView
    }

    init(responder: NSResponder) {
        self.responder = responder
    }

    func insert(_ text: String) -> Bool {
        if let terminalView {
            return terminalView.insertDictationText(text)
        }
        if let textView {
            textView.insertText(text, replacementRange: textView.selectedRange())
            return true
        }
        if let responder {
            return responder.tryToPerform(#selector(NSResponder.insertText(_:)), with: text)
        }
        return false
    }
}

private final class DictationCaptureMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var bufferCount = 0
    private var lastFrameLength: AVAudioFrameCount = 0

    func reset() {
        lock.withLock {
            bufferCount = 0
            lastFrameLength = 0
        }
    }

    func markBuffer(frameLength: AVAudioFrameCount) {
        lock.withLock {
            bufferCount += 1
            lastFrameLength = frameLength
        }
    }

    func snapshot() -> (bufferCount: Int, lastFrameLength: AVAudioFrameCount) {
        lock.withLock {
            (bufferCount, lastFrameLength)
        }
    }
}

private enum FocusedTextInserter {
    @MainActor
    static func captureTarget() -> DictationInsertionTarget? {
        let responder = NSApp.keyWindow?.firstResponder
        if let responder {
            if let terminalView = terminalView(from: responder) {
                return DictationInsertionTarget(terminalView: terminalView)
            }
            if let textView = responder as? NSTextView {
                return DictationInsertionTarget(textView: textView)
            }
        }
        if let terminalView = DictationTerminalTargetRegistry.shared.recentTerminal() {
            return DictationInsertionTarget(terminalView: terminalView)
        }
        if let responder {
            return DictationInsertionTarget(responder: responder)
        }
        return nil
    }

    @MainActor
    static func insert(_ text: String) -> Bool {
        captureTarget()?.insert(text) ?? false
    }

    @MainActor
    private static func terminalView(from responder: NSResponder) -> LoomTerminalView? {
        if let terminalView = responder as? LoomTerminalView {
            return terminalView
        }
        var view = responder as? NSView
        while let current = view {
            if let terminalView = current as? LoomTerminalView {
                return terminalView
            }
            view = current.superview
        }
        return nil
    }
}
