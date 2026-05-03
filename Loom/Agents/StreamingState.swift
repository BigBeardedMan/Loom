import Foundation
import Observation

/// In-flight streaming text for the agent pane. Held in its own `@Observable`
/// so the live token append only re-renders the streaming bubble, not the
/// entire chat history. The committed assistant message is appended to
/// `messages` only when the stream finalizes.
@Observable
@MainActor
final class StreamingState {
    var buffer: String = ""
    var isActive: Bool = false

    func begin() {
        buffer = ""
        isActive = true
    }

    func append(_ chunk: String) {
        buffer.append(chunk)
    }

    func finish() -> String {
        let final = buffer
        buffer = ""
        isActive = false
        return final
    }

    func cancel() {
        buffer = ""
        isActive = false
    }
}
