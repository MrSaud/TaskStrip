import XCTest
@testable import TaskStrips

/// A message drawn as a page to mark on.
final class MailSnapshotTests: XCTestCase {
    func testAShortMessageIsShownWhole() {
        let (text, wasCut) = MailSnapshot.shown("Two lines.\nThat's all.")
        XCTAssertEqual(text, "Two lines.\nThat's all.")
        XCTAssertFalse(wasCut)
    }

    /// A page you can mark on is a page you can read: forty thousand characters scaled onto a
    /// canvas is a grey smear, so a long message is cut and says so.
    func testALongMessageIsCutAndSaysSo() {
        let long = String(repeating: "word ", count: 2000)
        let (text, wasCut) = MailSnapshot.shown(long)
        XCTAssertTrue(wasCut)
        XCTAssertLessThanOrEqual(text.count, MailSnapshot.characterLimit)
    }

    func testTheCutFallsOnALineBreakWhenOneIsNear() {
        let paragraph = String(repeating: "a", count: 40) + "\n"
        let (text, wasCut) = MailSnapshot.shown(String(repeating: paragraph, count: 10), limit: 100)
        XCTAssertTrue(wasCut)
        XCTAssertFalse(text.hasSuffix("a\n"))
        XCTAssertEqual(text.last, "a")
        // Whole lines, not a line and a half.
        XCTAssertTrue(text.split(separator: "\n").allSatisfy { $0.count == 40 }, text)
    }

    /// A line longer than the limit has no break to fall on, and still has to be cut.
    func testAMessageWithNoLineBreaksIsCutAnyway() {
        let (text, wasCut) = MailSnapshot.shown(String(repeating: "x", count: 500), limit: 100)
        XCTAssertTrue(wasCut)
        XCTAssertEqual(text.count, 100)
    }
}

/// Where a picture starts out on the page.
final class SketchImagePlacementFractionTests: XCTestCase {
    func testAPickedPictureLeavesRoomAroundIt() {
        let placement = SketchImagePlacement.initial(
            imageSize: CGSize(width: 1000, height: 1000), canvas: CGSize(width: 1000, height: 1000)
        )
        XCTAssertEqual(placement.scale, SketchImagePlacement.fillFraction, accuracy: 0.001)
    }

    /// A message being marked up is the page rather than something added to it.
    func testAPageSizedThingTakesTheWholePage() {
        let placement = SketchImagePlacement.initial(
            imageSize: CGSize(width: 1800, height: 2400),
            canvas: CGSize(width: 900, height: 1200),
            fraction: 0.95
        )
        XCTAssertEqual(placement.scale, 0.475, accuracy: 0.001)
        // Centred, so the margins are even.
        XCTAssertEqual(placement.offset.x, (900 - 1800 * 0.475) / 2, accuracy: 0.5)
        XCTAssertEqual(placement.offset.y, (1200 - 2400 * 0.475) / 2, accuracy: 0.5)
    }

    func testAPictureSmallerThanThePageIsNotBlownUp() {
        let placement = SketchImagePlacement.initial(
            imageSize: CGSize(width: 100, height: 100),
            canvas: CGSize(width: 900, height: 900),
            fraction: 0.95
        )
        XCTAssertEqual(placement.scale, 1, accuracy: 0.001)
    }
}
