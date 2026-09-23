import XCTest
@testable import TaskStrips

final class BoardPanesTests: XCTestCase {
    func testEverythingShowsAllThreeInBoardOrder() {
        XCTAssertEqual(BoardPanes.everything.showing, [.strips, .reminders, .notes])
        XCTAssertEqual(BoardPanes.everything.count, 3)
        XCTAssertNil(BoardPanes.everything.lonePane)
    }

    func testTogglingPutsAPaneAwayAndBringsItBack() {
        let withoutNotes = BoardPanes.everything.toggling(.notes)
        XCTAssertEqual(withoutNotes.showing, [.strips, .reminders])
        XCTAssertEqual(withoutNotes.toggling(.notes), .everything)
    }

    func testTheLastPaneCannotBeSwitchedOff() {
        let stripsOnly = BoardPanes.strips
        XCTAssertTrue(stripsOnly.isOnlyPane(.strips))
        XCTAssertEqual(stripsOnly.toggling(.strips), stripsOnly)
        XCTAssertEqual(stripsOnly.lonePane, .strips)
    }

    func testShowingAPaneLeavesTheOthersAlone() {
        let panes = BoardPanes.strips.showing(.reminders)
        XCTAssertEqual(panes.showing, [.strips, .reminders])
        // Asking for one that's already there changes nothing.
        XCTAssertEqual(panes.showing(.reminders), panes)
    }

    func testSingleStepsThroughThePanesAndStopsAtTheEnds() {
        XCTAssertEqual(BoardPanes.strips.single(after: .strips), .reminders)
        XCTAssertEqual(BoardPanes.reminders.single(after: .reminders), .notes)
        XCTAssertNil(BoardPanes.notes.single(after: .notes))
        XCTAssertEqual(BoardPanes.notes.single(before: .notes), .reminders)
        XCTAssertNil(BoardPanes.strips.single(before: .strips))
    }

    /// It's stored as a number in UserDefaults, so the numbers have to stay put: a build that
    /// renumbered them would open everyone's board on the wrong panes.
    func testRawValuesAreStable() {
        XCTAssertEqual(BoardPanes.strips.rawValue, 1)
        XCTAssertEqual(BoardPanes.reminders.rawValue, 2)
        XCTAssertEqual(BoardPanes.notes.rawValue, 4)
        XCTAssertEqual(BoardPanes.everything.rawValue, 7)
    }
}
