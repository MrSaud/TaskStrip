import AVFoundation
import Foundation

/// How long a voice note runs, and how to say it.
///
/// Mirrors AudioDuration.kt and formatDurationMinSec — a recording with no length shown reads as
/// a file that might be empty, which is exactly what a failed recording produces.
enum AudioDuration {
    /// Read straight from the file rather than through AVAsset's async loading: this is called
    /// while laying out a row, and a duration that arrives a frame later makes the row jump.
    static func seconds(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return nil }
        return Double(file.length) / rate
    }

    /// "0:07", "1:05", "12:30" — the same shape Android's formatDurationMinSec produces, since a
    /// voice note is a thing of seconds and minutes.
    static func formatted(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func formatted(of url: URL) -> String? {
        seconds(of: url).map(formatted)
    }
}
