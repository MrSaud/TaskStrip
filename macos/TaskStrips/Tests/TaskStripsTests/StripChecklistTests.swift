import SwiftData
import XCTest
@testable import TaskStrips

final class StripChecklistTests: XCTestCase {
    private func steps(_ done: Bool...) -> [TaskChecklistItem] {
        done.enumerated().map { TaskChecklistItem(text: "Step \($0.offset)", isDone: $0.element) }
    }

    func testProgressIsWhatTheTicksAddUpTo() {
        XCTAssertEqual(StripChecklist.progress(of: steps(false, false)), 0)
        XCTAssertEqual(StripChecklist.progress(of: steps(true, false)), 50)
        XCTAssertEqual(StripChecklist.progress(of: steps(true, true, true)), 100)
        // Thirds round to something a bar can show rather than 33.333…
        XCTAssertEqual(StripChecklist.progress(of: steps(true, false, false)), 33)
    }

    func testAStripWithNoStepsKeepsTheBarItAlwaysHad() {
        XCTAssertNil(StripChecklist.progress(of: []))
        XCTAssertNil(StripChecklist.summary(of: []))
    }

    func testTheSummaryCountsWhatIsDoneOutOfWhatThereIs() {
        XCTAssertEqual(StripChecklist.summary(of: steps(true, false, true)), "2/3")
    }

    func testTickingAStepStampsWhenAndUntickingForgets() throws {
        let items = steps(false)
        let id = try XCTUnwrap(items.first?.id)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let ticked = StripChecklist.toggling(id, in: items, now: now)
        XCTAssertEqual(ticked.first?.isDone, true)
        XCTAssertEqual(ticked.first?.doneAt, now)

        let unticked = StripChecklist.toggling(id, in: ticked, now: now)
        XCTAssertEqual(unticked.first?.isDone, false)
        XCTAssertNil(unticked.first?.doneAt)
    }

    func testTickingOneStepLeavesTheOthersAlone() {
        let items = steps(false, false)
        let toggled = StripChecklist.toggling(items[1].id, in: items)
        XCTAssertEqual(toggled.map(\.isDone), [false, true])
    }

    // MARK: - Typing them in

    func testAPastedListArrivesAsOneStepPerLine() {
        let items = StripChecklist.items(fromTyped: "Photos\nForm\nAppointment")
        XCTAssertEqual(items.map(\.text), ["Photos", "Form", "Appointment"])
        XCTAssertTrue(items.allSatisfy { !$0.isDone })
    }

    func testTheBulletsAndBoxesAListBringsWithItAreLeftBehind() {
        let items = StripChecklist.items(fromTyped: "- Photos\n* Form\n[ ] Appointment\n[x] Paid")
        XCTAssertEqual(items.map(\.text), ["Photos", "Form", "Appointment", "Paid"])
    }

    func testBlankLinesAreNotSteps() {
        XCTAssertTrue(StripChecklist.items(fromTyped: "\n   \n").isEmpty)
        XCTAssertEqual(StripChecklist.items(fromTyped: "One\n\n\nTwo").count, 2)
    }
}

final class StripDeferralTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)   // a fixed "today"
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func days(_ count: Int) -> Date {
        calendar.date(byAdding: .day, value: count, to: now)!
    }

    func testAStripWithNoDateIsNeverDeferred() {
        XCTAssertFalse(StripDeferral.isDeferred(nil, now: now, calendar: calendar))
        XCTAssertNil(StripDeferral.label(nil, now: now, calendar: calendar))
    }

    func testItIsDeferredUntilItsDayComes() {
        XCTAssertTrue(StripDeferral.isDeferred(days(1), now: now, calendar: calendar))
        XCTAssertFalse(StripDeferral.isDeferred(days(-1), now: now, calendar: calendar))
    }

    /// The whole day counts: deferred to today means back this morning, not at this hour.
    func testTheDayItComesBackItIsBack() {
        let laterToday = calendar.date(byAdding: .hour, value: 6, to: now)!
        XCTAssertFalse(StripDeferral.isDeferred(laterToday, now: now, calendar: calendar))
    }

    func testAWaitingStripSaysWhatItIsWaitingFor() throws {
        let label = try XCTUnwrap(StripDeferral.label(days(8), now: now, calendar: calendar))
        XCTAssertTrue(label.hasPrefix("NOT BEFORE "), label)
        XCTAssertNil(StripDeferral.label(days(-3), now: now, calendar: calendar), "it's back; nothing to say")
    }
}
