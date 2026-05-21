import AppKit
import AVFoundation
import Foundation
import Observation
import Speech

extension Notification.Name {
    static let loomDictationInsertText = Notification.Name("loomDictationInsertText")
}

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
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInsertedTranscript = false

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
        state = .requestingPermission
        liveTranscript = ""
        hasInsertedTranscript = false

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
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: Self.makeAudioTapHandler(request: request)
        )

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            state = .error("Could not start microphone capture: \(error.localizedDescription)")
            return
        }

        state = .listening
        recognitionTask = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeRecognitionHandler(for: self)
        )
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
                finishAudio(cancelTask: false)
                state = .idle
            }
        }

        if let errorMessage,
           !hasInsertedTranscript,
           state.isActive {
            finishAudio(cancelTask: true)
            state = .error(errorMessage)
        }
    }

    private func stopAndInsert() {
        insertTranscriptIfNeeded()
        finishAudio(cancelTask: false)
        state = .idle
    }

    private func insertTranscriptIfNeeded() {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !hasInsertedTranscript else { return }
        hasInsertedTranscript = true
        if !FocusedTextInserter.insert(text) {
            NotificationCenter.default.post(
                name: .loomDictationInsertText,
                object: nil,
                userInfo: ["text": text]
            )
        }
    }

    private func finishAudio(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if cancelTask {
            recognitionTask?.cancel()
        } else {
            recognitionTask?.finish()
        }
        recognitionTask = nil
    }

    nonisolated private static func makeAudioTapHandler(
        request: SFSpeechAudioBufferRecognitionRequest
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
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

private enum FocusedTextInserter {
    @MainActor
    static func insert(_ text: String) -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            textView.insertText(text, replacementRange: textView.selectedRange())
            return true
        }
        return responder.tryToPerform(#selector(NSResponder.insertText(_:)), with: text)
    }
}
