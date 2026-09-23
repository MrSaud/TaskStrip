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
        XCTAssertEqual(BoardPanes.today.single(after: .today), .strips)
        XCTAssertEqual(BoardPanes.strips.single(after: .strips), .reminders)
        XCTAssertEqual(BoardPanes.reminders.single(after: .reminders), .notes)
        XCTAssertEqual(BoardPanes.notes.single(after: .notes), .inbox, "the Mac's inbox comes last")
        XCTAssertNil(BoardPanes.inbox.single(after: .inbox), "the last pane is the last")
        XCTAssertEqual(BoardPanes.notes.single(before: .notes), .reminders)
        XCTAssertEqual(BoardPanes.strips.single(before: .strips), .today)
        XCTAssertNil(BoardPanes.today.single(before: .today), "the first pane is the first")
    }

    /// It's stored as a number in UserDefaults, so the numbers have to stay put: a build that
    /// renumbered them would open everyone's board on the wrong panes.
    func testRawValuesAreStable() {
        XCTAssertEqual(BoardPanes.strips.rawValue, 1)
        XCTAssertEqual(BoardPanes.reminders.rawValue, 2)
        XCTAssertEqual(BoardPanes.notes.rawValue, 4)
        XCTAssertEqual(BoardPanes.today.rawValue, 8, "the day pane arrived after the other three")
        XCTAssertEqual(BoardPanes.everything.rawValue, 7)
    }

    /// The day pane is opt-in: a board someone already arranged shouldn't rearrange itself.
    func testTheDayPaneIsNotOnUntilItIsAskedFor() {
        XCTAssertFalse(BoardPanes.everything.shows(.today))
        XCTAssertTrue(BoardPanes.everything.toggling(.today).shows(.today))
        XCTAssertEqual(BoardPanes.everything.toggling(.today).showing.first, .today, "it leads the board")
    }
}
