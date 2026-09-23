import XCTest
@testable import TaskStrips

/// Saying so when a total gets where it was going.
final class StripTallyAlertTests: XCTestCase {
    private func tally(_ total: Double, target: Double?, announced: [Int] = []) -> TaskTally {
        var tally = TaskTally(name: "Cost", unit: .money(currency: "KWD"))
        tally.target = target
        tally.announced = announced
        if total != 0 { tally = StripTally.adding(total, to: tally) }
        return tally
    }

    func testNothingIsSaidBeforeNineTenths() {
        let (_, alerts) = StripTallyAlerts.check([tally(500, target: 1_000)], stripTitle: "Fit-out")
        XCTAssertTrue(alerts.isEmpty)
    }

    func testNineTenthsIsWorthSaying() throws {
        let (edited, alerts) = StripTallyAlerts.check([tally(900, target: 1_000)], stripTitle: "Fit-out")
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.threshold, 90)
        XCTAssertEqual(alerts.first?.title, "Fit-out")
        XCTAssertTrue(try XCTUnwrap(alerts.first?.body).contains("left"), alerts.first?.body ?? "")
        // And marked, so it isn't said again.
        XCTAssertEqual(edited.first?.announced, [90])
    }

    func testReachingTheTargetIsSaidOnceMore() {
        let (edited, alerts) = StripTallyAlerts.check(
            [tally(1_000, target: 1_000, announced: [90])], stripTitle: "Fit-out"
        )
        XCTAssertEqual(alerts.map(\.threshold), [100])
        XCTAssertEqual(edited.first?.announced, [90, 100])
    }

    /// The whole point of marking: an entry a day for a month shouldn't be a notification a day.
    func testTheSameThresholdIsNotSaidTwice() {
        let (edited, alerts) = StripTallyAlerts.check(
            [tally(1_200, target: 1_000, announced: [90, 100])], stripTitle: "Fit-out"
        )
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertEqual(edited.first?.announced, [90, 100])
    }

    /// A total that jumps past both in one entry has both to say.
    func testATotalThatPassesBothAtOnceSaysBoth() {
        let (_, alerts) = StripTallyAlerts.check([tally(1_500, target: 1_000)], stripTitle: "Fit-out")
        XCTAssertEqual(alerts.map(\.threshold), [90, 100])
    }

    /// Entries get corrected, and a total that falls back under the line should speak again when
    /// it next crosses it.
    func testCorrectingATotalBackUnderTheLineResetsIt() {
        let (edited, alerts) = StripTallyAlerts.check(
            [tally(400, target: 1_000, announced: [90, 100])], stripTitle: "Fit-out"
        )
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertEqual(edited.first?.announced, [])
    }

    func testATotalWithNoTargetSaysNothingEver() {
        let (edited, alerts) = StripTallyAlerts.check([tally(9_999, target: nil)], stripTitle: "Fit-out")
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertEqual(edited.first?.announced, [])
    }

    func testWhatItActuallySays() {
        let nearly = tally(900, target: 1_000)
        let ninety = StripTallyAlerts.message(for: nearly, threshold: 90, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(ninety.contains("Cost"), ninety)
        XCTAssertTrue(ninety.contains("900"), ninety)
        XCTAssertTrue(ninety.contains("1,000"), ninety)

        let over = tally(1_200, target: 1_000)
        let full = StripTallyAlerts.message(for: over, threshold: 100, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(full.contains("over its target"), full)

        let exact = tally(1_000, target: 1_000)
        XCTAssertTrue(
            StripTallyAlerts.message(for: exact, threshold: 100, locale: Locale(identifier: "en_US"))
                .contains("reached its target"),
            "an exact hit isn't 'over'"
        )
    }

    /// The ninety and the hundred are different notifications, not one overwriting the other.
    func testEachThresholdHasItsOwnIdentifier() {
        let strip = UUID()
        let tallyID = UUID()
        let ninety = StripTallyAlerts.Alert(tallyID: tallyID, threshold: 90, title: "", body: "")
        let full = StripTallyAlerts.Alert(tallyID: tallyID, threshold: 100, title: "", body: "")
        XCTAssertNotEqual(
            StripTallyAlerts.identifier(stripID: strip, alert: ninety),
            StripTallyAlerts.identifier(stripID: strip, alert: full)
        )
    }

    // MARK: - A note and a date on every entry

    func testAnEntryKeepsWhatItWasForAndWhenItHappened() throws {
        let yesterday = Date(timeIntervalSince1970: 1_700_000_000)
        var tally = TaskTally(name: "Training", unit: .hours)
        tally = StripTally.adding(2, to: tally, note: "Safety course", at: yesterday)
        let entry = try XCTUnwrap(tally.entries.first)
        XCTAssertEqual(entry.note, "Safety course")
        XCTAssertEqual(entry.at, yesterday)
        XCTAssertFalse(entry.fromTimer)
    }

    /// Hours are written up the morning after as often as on the day, so the date is the entry's,
    /// not the moment it was typed.
    func testTheDateIsTheOneChosenRatherThanTheMomentItWasTyped() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let tally = StripTally.adding(2, to: TaskTally(name: "Training", unit: .hours), at: day)
        XCTAssertEqual(tally.entries.first?.at, day)
        XCTAssertNotEqual(tally.entries.first?.at, Date.now)
    }

    func testAnEntryFromTheClockSaysWhereItCameFrom() throws {
        let counted = StripTally.recording(seconds: 3_600, in: [])
        let entry = try XCTUnwrap(counted.first?.entries.first)
        XCTAssertTrue(entry.fromTimer)
        XCTAssertEqual(entry.note, "From the timer")
    }
}
