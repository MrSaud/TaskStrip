import SwiftData
import XCTest
@testable import TaskStrips

/// What the board's hours and money add up to — asked of the board, never kept on it.
@MainActor
final class ValueReportTests: XCTestCase {
    private var context: ModelContext!
    /// 21 September 2026.
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    @discardableResult
    private func strip(
        _ title: String,
        tags: [String] = [],
        hours: [(Double, Date)] = [],
        money: [(Double, Date)] = []
    ) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0)
        task.tags = tags
        var tallies: [TaskTally] = []
        if !hours.isEmpty {
            var tally = TaskTally(name: "Hours", unit: .hours)
            for (amount, at) in hours { tally = StripTally.adding(amount, to: tally, at: at) }
            tallies.append(tally)
        }
        if !money.isEmpty {
            var tally = TaskTally(name: "Cost", unit: .money(currency: "KWD"))
            for (amount, at) in money { tally = StripTally.adding(amount, to: tally, at: at) }
            tallies.append(tally)
        }
        task.tallies = tallies
        context.insert(task)
        return task
    }

    private func fetch() -> [TaskItem] { (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [] }
    private func yesterday() -> Date { now.addingTimeInterval(-86_400) }
    private func lastMonth() -> Date { now.addingTimeInterval(-35 * 86_400) }

    func testHoursAndMoneyAreCountedSeparately() throws {
        strip("Fit-out", tags: ["WORK"], hours: [(3, yesterday())], money: [(150, yesterday())])
        let group = try XCTUnwrap(ValueReport.byTag(fetch(), range: .thisMonth, now: now).first)
        XCTAssertEqual(group.name, "WORK")
        XCTAssertEqual(group.amounts.count, 2, "hours and dinars never share a line")
        XCTAssertEqual(group.amounts.first { $0.unit == .hours }?.amount, 3)
        XCTAssertEqual(group.amounts.first { $0.unit == .money(currency: "KWD") }?.amount, 150)
    }

    func testEntriesOutsideThePeriodAreLeftOut() {
        strip("Fit-out", tags: ["WORK"], hours: [(3, yesterday()), (10, lastMonth())])
        XCTAssertEqual(
            ValueReport.byTag(fetch(), range: .thisMonth, now: now).first?.amounts.first?.amount, 3
        )
        XCTAssertEqual(
            ValueReport.byTag(fetch(), range: .lastMonth, now: now).first?.amounts.first?.amount, 10
        )
        XCTAssertEqual(
            ValueReport.byTag(fetch(), range: .everything, now: now).first?.amounts.first?.amount, 13
        )
    }

    /// A report is a way of looking: work done under two tags belongs in both answers.
    func testAStripWithTwoTagsCountsUnderBoth() {
        strip("Survey", tags: ["WORK", "MOSA"], hours: [(4, yesterday())])
        let groups = ValueReport.byTag(fetch(), range: .thisMonth, now: now)
        XCTAssertEqual(groups.map(\.name), ["MOSA", "WORK"])
        XCTAssertTrue(groups.allSatisfy { $0.amounts.first?.amount == 4 })
    }

    func testStripsWithNoTagAreStillCountedSomewhere() {
        strip("Loose end", hours: [(2, yesterday())])
        XCTAssertEqual(ValueReport.byTag(fetch(), range: .thisMonth, now: now).map(\.name), [ValueReport.untagged])
    }

    func testTheStripsBehindATotalCanBeSeen() {
        strip("One", tags: ["WORK"], hours: [(2, yesterday())])
        strip("Two", tags: ["WORK"], hours: [(3, yesterday())])
        XCTAssertEqual(ValueReport.byTag(fetch(), range: .thisMonth, now: now).first?.amounts.first?.amount, 5)
        XCTAssertEqual(
            ValueReport.byStrip(fetch(), range: .thisMonth, tag: "WORK", now: now).map(\.name),
            ["One", "Two"]
        )
    }

    func testADeletedStripIsNotCounted() {
        let task = strip("Gone", tags: ["WORK"], hours: [(5, yesterday())])
        task.isTombstoned = true
        XCTAssertTrue(ValueReport.byTag(fetch(), range: .thisMonth, now: now).isEmpty)
    }

    // MARK: - The export

    func testEveryEntryGetsALineTheSpreadsheetCanRead() {
        strip("Fit-out", tags: ["WORK", "MOSA"], hours: [(3, yesterday())], money: [(150, yesterday())])
        let csv = ValueReport.csv(fetch(), range: .thisMonth, now: now)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "Date,Strip,Tags,Total,Unit,Amount,Note,Source")
        XCTAssertEqual(lines.count, 3, "a header and one line per entry")
        XCTAssertTrue(csv.contains("\"Fit-out\",\"WORK MOSA\",\"Hours\",\"hours\",3"), csv)
        XCTAssertTrue(csv.contains("\"Cost\",\"KWD\",150"), csv)
    }

    /// A title with a comma in it would otherwise become two columns.
    func testCommasAndQuotesInATitleDoNotBreakTheColumns() {
        strip("Alenezi, Ahmad \"the boss\"", hours: [(1, yesterday())])
        let csv = ValueReport.csv(fetch(), range: .thisMonth, now: now)
        XCTAssertTrue(csv.contains("\"Alenezi, Ahmad \"\"the boss\"\"\""), csv)
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
    }

    func testAnEntryFromTheClockSaysSoInTheExport() {
        let task = strip("Timed")
        task.tallies = StripTally.recording(seconds: 3_600, in: [], at: yesterday())
        XCTAssertTrue(ValueReport.csv(fetch(), range: .thisMonth, now: now).hasSuffix("timer"))
    }

    func testTheFileIsNamedForWhatIsInIt() {
        XCTAssertTrue(ValueReport.fileName(for: .lastMonth, now: now).hasPrefix("TaskStrips-lastMonth-"))
        XCTAssertTrue(ValueReport.fileName(for: .lastMonth, now: now).hasSuffix(".csv"))
    }

    // MARK: - The periods themselves

    func testWhatEachPeriodCovers() {
        XCTAssertTrue(ValueRange.thisMonth.contains(yesterday(), now: now))
        XCTAssertFalse(ValueRange.thisMonth.contains(lastMonth(), now: now))
        XCTAssertTrue(ValueRange.lastMonth.contains(lastMonth(), now: now))
        XCTAssertTrue(ValueRange.thisYear.contains(lastMonth(), now: now))
        XCTAssertFalse(ValueRange.thisYear.contains(now.addingTimeInterval(-400 * 86_400), now: now))
        XCTAssertTrue(ValueRange.everything.contains(now.addingTimeInterval(-4_000 * 86_400), now: now))
    }
}
