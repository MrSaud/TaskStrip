import AVFoundation
import Foundation

/// Recording a voice note, mirroring VoiceRecorder.kt: MPEG-4/AAC, which is what the phone
/// writes, so a note recorded here plays there and the other way round.
///
/// Writes to a temporary file and hands back the URL. Putting it in the attachment store is the
/// caller's job — the same path a picked file takes, so a recording and an attachment are the
/// same thing by the time anything else sees them.
@MainActor
final class VoiceRecorder: ObservableObject {
    enum Failure: LocalizedError {
        case microphoneRefused
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .microphoneRefused:
                return "Task Strips can't use the microphone. Allow it in System Settings › "
                    + "Privacy & Security › Microphone."
            case .couldNotStart:
                return "The recording couldn't be started."
            }
        }
    }

    @Published private(set) var isRecording = false
    /// Seconds so far, for the timer on screen. A recording with no visible clock gives no sign
    /// it's working.
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var ticker: Timer?

    /// UI tests never touch the microphone: the permission dialog would sit there unanswered and
    /// take the rest of the suite with it.
    private var isEnabled: Bool {
        !ProcessInfo.processInfo.arguments.contains(TaskStripsApp.uiTestingArgument)
    }

    /// Asked for the first time Record is pressed, never at launch.
    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() async throws {
        guard isEnabled else { throw Failure.microphoneRefused }
        guard await Self.requestAccess() else { throw Failure.microphoneRefused }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "TaskStrips-recording-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        guard let recorder = try? AVAudioRecorder(url: url, settings: settings), recorder.record() else {
            throw Failure.couldNotStart
        }
        self.recorder = recorder
        startedAt = .now
        elapsed = 0
        isRecording = true

        let ticker = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date.now.timeIntervalSince(startedAt)
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    /// The finished file, or nil if nothing usable came out — a recording stopped before the
    /// encoder wrote anything leaves a file that plays as silence.
    @discardableResult
    func stop() -> URL? {
        guard let recorder else { return nil }
        let url = recorder.url
        recorder.stop()
        finish()

        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    func cancel() {
        guard let recorder else { return }
        let url = recorder.url
        recorder.stop()
        try? FileManager.default.removeItem(at: url)
        finish()
    }

    private func finish() {
        ticker?.invalidate()
        ticker = nil
        recorder = nil
        startedAt = nil
        isRecording = false
        elapsed = 0
    }
}
