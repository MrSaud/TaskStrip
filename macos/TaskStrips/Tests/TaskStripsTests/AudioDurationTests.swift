import XCTest
@testable import TaskStrips

/// The recorder itself needs a microphone, so what's checked is the part that doesn't: how a
/// length is written out. It's on screen twice — ticking while recording, and on the row
/// afterwards — so a wrong format is visible constantly.
final class AudioDurationTests: XCTestCase {
    func testSecondsReadAsMinutesAndSeconds() {
        XCTAssertEqual(AudioDuration.formatted(0), "0:00")
        XCTAssertEqual(AudioDuration.formatted(7), "0:07")
        XCTAssertEqual(AudioDuration.formatted(65), "1:05")
        XCTAssertEqual(AudioDuration.formatted(750), "12:30")
    }

    /// Zero-padded seconds, never "1:5" — the same shape Android's formatDurationMinSec writes.
    func testSecondsAreAlwaysTwoDigits() {
        XCTAssertEqual(AudioDuration.formatted(61), "1:01")
        XCTAssertEqual(AudioDuration.formatted(3600), "60:00")
    }

    /// The clock ticks in fractions while recording; a row that flickered between 0:07 and 0:08
    /// on every frame would be worse than one that rounds.
    func testAPartSecondRounds() {
        XCTAssertEqual(AudioDuration.formatted(7.4), "0:07")
        XCTAssertEqual(AudioDuration.formatted(7.6), "0:08")
    }

    /// Nothing produces a negative length, but a clock read across a system time change could.
    func testANegativeLengthReadsAsZero() {
        XCTAssertEqual(AudioDuration.formatted(-5), "0:00")
    }

    func testAFileThatIsNotAudioHasNoDuration() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "not-audio-\(UUID().uuidString).m4a")
        try Data("this is not a recording".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNil(AudioDuration.seconds(of: url))
        XCTAssertNil(AudioDuration.formatted(of: url))
    }

    func testAMissingFileHasNoDuration() {
        let url = FileManager.default.temporaryDirectory.appending(path: "gone-\(UUID().uuidString).m4a")
        XCTAssertNil(AudioDuration.seconds(of: url))
    }
}
