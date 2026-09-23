import XCTest
@testable import TaskStrips

/// Values that add up on a strip: hours attended, money spent, anything else.
final class StripTallyTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private func tally(_ amounts: [Double], unit: TallyUnit = .hours, target: Double? = nil) -> TaskTally {
        var tally = TaskTally(name: "Training", unit: unit)
        for amount in amounts { tally = StripTally.adding(amount, to: tally) }
        tally.target = target
        return tally
    }

    /// The example that started this: two hours today, one tomorrow, three altogether.
    func testTwoHoursAndThenOneMakesThree() {
        let counted = tally([2, 1])
        XCTAssertEqual(counted.total, 3)
        XCTAssertEqual(StripTally.formatted(counted.total, unit: .hours), "3h")
    }

    func testEachAdditionIsKeptSoTheTotalCanBeTakenApart() {
        let counted = tally([2, 1])
        XCTAssertEqual(counted.entries.count, 2)
        // Newest first, so the list reads as a history.
        XCTAssertEqual(counted.entries.first?.amount, 1)
    }

    func testHoursAndMinutesRatherThanADecimal() {
        XCTAssertEqual(StripTally.formatted(3.5, unit: .hours), "3h 30m")
        XCTAssertEqual(StripTally.formatted(0.25, unit: .hours), "15m")
        XCTAssertEqual(StripTally.formatted(90, unit: .minutes), "1h 30m")
        XCTAssertEqual(StripTally.formatted(45, unit: .minutes), "45m")
        XCTAssertEqual(StripTally.formatted(2, unit: .hours), "2h")
    }

    func testMoneyIsShownInItsOwnCurrency() {
        let kuwait = StripTally.formatted(412.5, unit: .money(currency: "KWD"), locale: locale)
        XCTAssertTrue(kuwait.contains("412.500"), kuwait)
        let dollars = StripTally.formatted(412.5, unit: .money(currency: "USD"), locale: locale)
        XCTAssertTrue(dollars.contains("412.50"), dollars)
    }

    func testCountsAndAnythingElse() {
        XCTAssertEqual(StripTally.formatted(12, unit: .count), "12")
        XCTAssertEqual(StripTally.formatted(12.5, unit: .custom("km")), "12.50 km")
    }

    // MARK: - Targets

    func testATargetSaysHowFarAlongAndWhatIsLeft() throws {
        let counted = tally([2, 1], target: 10)
        XCTAssertEqual(try XCTUnwrap(counted.progress), 0.3, accuracy: 0.001)
        XCTAssertEqual(counted.remaining, 7)
        XCTAssertFalse(counted.isOverTarget)
    }

    func testGoingOverATargetIsSaidPlainly() {
        let counted = tally([8, 5], target: 10)
        XCTAssertTrue(counted.isOverTarget)
        XCTAssertEqual(counted.remaining, -3)
    }

    func testNoTargetMeansNoProgressToShow() {
        XCTAssertNil(tally([2]).progress)
        XCTAssertNil(tally([2]).remaining)
        XCTAssertFalse(tally([2]).isOverTarget)
    }

    // MARK: - The clock feeding it

    func testStoppingTheClockAddsTheHoursItCounted() throws {
        let counted = StripTally.recording(seconds: 5_400, in: [], at: .now)   // an hour and a half
        let tally = try XCTUnwrap(counted.first)
        XCTAssertEqual(tally.name, TaskTally.timeName)
        XCTAssertEqual(tally.unit, .hours)
        XCTAssertEqual(tally.total, 1.5, accuracy: 0.0001)
        XCTAssertEqual(tally.entries.first?.fromTimer, true)
    }

    /// The second stretch goes into the same total, not into a second one.
    func testTheClockAddsToTheTallyThatIsAlreadyThere() {
        var counted = StripTally.recording(seconds: 3_600, in: [])
        counted = StripTally.recording(seconds: 1_800, in: counted)
        XCTAssertEqual(counted.count, 1)
        XCTAssertEqual(counted.first?.total ?? 0, 1.5, accuracy: 0.0001)
    }

    func testAClockKeptInMinutesIsFedInMinutes() throws {
        let existing = [TaskTally(name: "Attendance", unit: .minutes)]
        let counted = StripTally.recording(seconds: 5_400, in: existing)
        XCTAssertEqual(try XCTUnwrap(counted.first).total, 90, accuracy: 0.0001)
    }

    /// A clock started and stopped by accident shouldn't leave a line behind.
    func testAStretchTooShortToKeepIsNotAnEntry() {
        XCTAssertTrue(StripTally.recording(seconds: 4, in: []).isEmpty)
    }

    /// Money isn't time: a stretch of work doesn't land in the cost.
    func testTheClockDoesNotFeedATallyThatCountsMoney() {
        let money = [TaskTally(name: "Cost", unit: .money(currency: "KWD"))]
        let counted = StripTally.recording(seconds: 3_600, in: money)
        XCTAssertEqual(counted.count, 2)
        XCTAssertEqual(counted.first?.total, 0)
        XCTAssertEqual(counted.last?.unit, .hours)
    }

    // MARK: - On the row

    func testTheRowShowsEveryTotalItHas() {
        let summary = StripTally.summary(
            [tally([2, 1]), tally([150], unit: .money(currency: "KWD"))],
            locale: locale
        )
        XCTAssertTrue(summary.contains("3h"), summary)
        XCTAssertTrue(summary.contains("150"), summary)
        XCTAssertTrue(summary.contains("·"), summary)
    }

    func testATallyWithNothingInItIsNotShownOnTheRow() {
        XCTAssertEqual(StripTally.summary([TaskTally(name: "Cost", unit: .count)]), "")
    }
}

/// A total has to survive a backup and a sync, or it isn't a record of anything.
final class StripTallyRoundTripTests: XCTestCase {
    private var tally: TaskTally {
        var tally = TaskTally(name: "Project cost", unit: .money(currency: "KWD"))
        tally = StripTally.adding(150, to: tally, note: "Deposit", at: Date(timeIntervalSince1970: 1_700_000_000))
        tally = StripTally.adding(2.5, to: tally, fromTimer: true)
        tally.target = 1_000
        return tally
    }

    func testAUnitSurvivesBeingWrittenToABackupAndRead() {
        for unit: TallyUnit in [.hours, .minutes, .count, .money(currency: "KWD"), .custom("km")] {
            let written = BackupExport.unitText(unit)
            XCTAssertEqual(BackupImport.unit(from: written), unit, written)
        }
    }

    /// An unknown unit in somebody else's backup mustn't lose the entries underneath it.
    func testAnUnrecognisedUnitFallsBackRatherThanFailing() {
        XCTAssertEqual(BackupImport.unit(from: "furlongs"), .hours)
        XCTAssertEqual(BackupImport.unit(from: ""), .hours)
    }

    func testATallySurvivesBeingEncodedAndDecoded() throws {
        // Held once: the property makes fresh ids every time it's read.
        let original = tally
        let encoded = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([TaskTally].self, from: encoded)
        XCTAssertEqual(decoded, [original])
        XCTAssertEqual(decoded.first?.total, 152.5)
        XCTAssertEqual(decoded.first?.target, 1_000)
    }

    /// A strip saved before totals existed comes back with none rather than failing to decode.
    func testAnOlderStripHasNoTotals() throws {
        let decoded = try JSONDecoder().decode([TaskTally].self, from: Data("[]".utf8))
        XCTAssertTrue(decoded.isEmpty)
    }

    /// The bug this test exists for: `announced` was added to a tally after tallies had already
    /// been stored, and a default written beside a property does nothing for a decoder. Every
    /// strip carrying a total stopped loading — the store itself crashed on the way in.
    func testATallyStoredBeforeAFieldExistedStillDecodes() throws {
        let old = """
        [{"id":"7EB6EE98-6EAF-41DE-B5A7-3A7AC385591F","name":"Cost","unit":{"money":{"currency":"KWD"}},
          "entries":[{"id":"B7DDB300-E8B2-4D1B-AE20-478E4F3FA5D3","amount":150,"at":721000000,"note":"Deposit","fromTimer":false}]}]
        """
        let decoded = try JSONDecoder().decode([TaskTally].self, from: Data(old.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.name, "Cost")
        XCTAssertEqual(decoded.first?.total, 150)
        XCTAssertEqual(decoded.first?.announced, [])
        XCTAssertNil(decoded.first?.target)
    }

    /// The same for an entry, which is the shape most likely to gain a field next.
    func testAnEntryMissingItsNewerFieldsStillDecodes() throws {
        let old = """
        [{"id":"B7DDB300-E8B2-4D1B-AE20-478E4F3FA5D3","amount":2,"at":721000000}]
        """
        let decoded = try JSONDecoder().decode([TaskTallyEntry].self, from: Data(old.utf8))
        XCTAssertEqual(decoded.first?.amount, 2)
        XCTAssertEqual(decoded.first?.note, "")
        XCTAssertEqual(decoded.first?.fromTimer, false)
    }
}
