import AVFoundation
import Foundation

/// Reading a strip's notes or a reminder out loud, mirroring TextToSpeechHelper.kt.
///
/// One shared synthesiser rather than one per row, and starting a new utterance stops whatever
/// was reading before — so `speakingID` is only ever one thing at a time.
///
/// Android has to offset a reminder's id to keep it from colliding with a strip's, since both are
/// auto-increment integers in the same shared engine. Here they're uuids, so there is nothing to
/// collide.
@MainActor
final class SpeechReader: NSObject, ObservableObject {
    static let shared = SpeechReader()

    /// What's being read right now, so a row can offer Stop instead of Read.
    @Published private(set) var speakingID: UUID?

    private let synthesizer = AVSpeechSynthesizer()
    /// UI tests would otherwise talk through the runner for the length of the suite.
    private let isEnabled: Bool

    private override init() {
        isEnabled = !ProcessInfo.processInfo.arguments.contains(TaskStripsApp.uiTestingArgument)
        super.init()
        synthesizer.delegate = self
    }

    /// What a strip reads out: its notes, which is what Android speaks — the title is already on
    /// screen, and reading it back adds nothing.
    ///
    /// Nonisolated, like the reminder one below: both are pure functions of their argument, and
    /// inheriting the class's main-actor isolation only made them unusable from a test.
    nonisolated static func speech(for task: TaskItem) -> String? {
        task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : task.notes
    }

    nonisolated static func speech(for reminder: Reminder) -> String {
        reminder.details.isEmpty ? reminder.text : "\(reminder.text). \(reminder.details)"
    }

    func isSpeaking(_ id: UUID) -> Bool { speakingID == id }

    /// Pressing Read on the row that's already reading stops it, which is the only thing that
    /// button can usefully mean at that point.
    func toggle(_ text: String, id: UUID) {
        if speakingID == id {
            stop()
        } else {
            speak(text, id: id)
        }
    }

    func speak(_ text: String, id: UUID) {
        guard isEnabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Immediate, not word-boundary: starting a new one is meant to interrupt the last.
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = id
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = nil
    }
}

extension SpeechReader: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in speakingID = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in speakingID = nil }
    }
}
