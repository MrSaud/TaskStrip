import SwiftData
import XCTest
@testable import TaskStrips

final class BoardFilterTests: XCTestCase {
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)   // a fixed "today"

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    @discardableResult
    private func strip(
        _ title: String, order: Int = 0, priority: Priority = .normal, notes: String = "",
        tags: [String] = [], due: Date? = nil, done: Bool = false, progress: Int = 0
    ) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: order, priority: priority)
        task.notes = notes
        task.tags = tags
        task.dueAt = due
        task.isDone = done
        task.progress = progress
        context.insert(task)
        return task
    }

    private func titles(_ filter: BoardFilter, _ tasks: [TaskItem]) -> [String] {
        filter.apply(to: tasks, now: now).map(\.title)
    }

    func testSearchLooksAtTitlesNotesAndTags() {
        let tasks = [
            strip("Renew passport", order: 0),
            strip("Call bank", order: 1, notes: "ask about the passport fee"),
            strip("Book dentist", order: 2, tags: ["passport"]),
            strip("Fix bike", order: 3),
        ]
        XCTAssertEqual(titles(BoardFilter(search: "passport"), tasks), ["Renew passport", "Call bank", "Book dentist"])
        XCTAssertEqual(titles(BoardFilter(search: "  "), tasks).count, 4, "a blank search hides nothing")
    }

    func testOneTagAtATimeIgnoringCase() {
        let tasks = [strip("A", tags: ["Home"]), strip("B", tags: ["work"]), strip("C")]
        XCTAssertEqual(titles(BoardFilter(tag: "home"), tasks), ["A"])
    }

    func testPrioritiesNarrowAndEmptyMeansAll() {
        let tasks = [strip("A", priority: .urgent), strip("B", priority: .low), strip("C", priority: .high)]
        XCTAssertEqual(titles(BoardFilter(priorities: [.urgent, .high]), tasks), ["A", "C"])
        XCTAssertEqual(titles(BoardFilter(priorities: []), tasks).count, 3)
    }

    /// Today and overdue, as Android reads it — and a finished strip stays put, so completing
    /// something doesn't make it disappear from under the finger that completed it.
    func testTodayOnlyKeepsDueTodayOverdueAndDoneStrips() {
        let yesterday = now.addingTimeInterval(-86_400)
        let laterToday = now.addingTimeInterval(3_600)
        let tomorrow = now.addingTimeInterval(86_400 * 2)
        let tasks = [
            strip("Overdue", due: yesterday),
            strip("Today", due: laterToday),
            strip("Tomorrow", due: tomorrow),
            strip("No date"),
            strip("Finished", due: tomorrow, done: true),
        ]
        XCTAssertEqual(titles(BoardFilter(todayOnly: true), tasks), ["Overdue", "Today", "Finished"])
    }

    func testADueRangeKeepsOnlyStripsInside() {
        let tasks = [
            strip("Before", due: now.addingTimeInterval(-86_400 * 3)),
            strip("Inside", due: now),
            strip("After", due: now.addingTimeInterval(86_400 * 3)),
            strip("No date"),
        ]
        let filter = BoardFilter(dueFrom: now.addingTimeInterval(-86_400), dueTo: now.addingTimeInterval(86_400))
        XCTAssertEqual(titles(filter, tasks), ["Inside"])
    }

    func testSortingByProgressBothWays() {
        let tasks = [strip("Half", progress: 50), strip("None", progress: 0), strip("Most", progress: 90)]
        XCTAssertEqual(titles(BoardFilter(sort: .progressAscending), tasks), ["None", "Half", "Most"])
        XCTAssertEqual(titles(BoardFilter(sort: .progressDescending), tasks), ["Most", "Half", "None"])
        XCTAssertEqual(titles(BoardFilter(sort: .manual), tasks), ["Half", "None", "Most"], "manual keeps the board's own order")
    }

    /// Dragging only means something when the board is whole and in its own order.
    func testReorderingIsOnlyAllowedWithNothingNarrowingAndManualOrder() {
        XCTAssertTrue(BoardFilter().allowsReordering)
        XCTAssertFalse(BoardFilter(search: "a").allowsReordering)
        XCTAssertFalse(BoardFilter(tag: "home").allowsReordering)
        XCTAssertFalse(BoardFilter(priorities: [.low]).allowsReordering)
        XCTAssertFalse(BoardFilter(todayOnly: true).allowsReordering)
        XCTAssertFalse(BoardFilter(sort: .progressAscending).allowsReordering)
    }

    func testClearingLeavesTheSearchAndSortAlone() {
        var filter = BoardFilter(search: "keep", tag: "home", priorities: [.low], todayOnly: true, sort: .progressAscending)
        XCTAssertEqual(filter.narrowingCount, 4)
        filter.clear()
        XCTAssertEqual(filter, BoardFilter(search: "keep", sort: .progressAscending))
        XCTAssertEqual(filter.narrowingCount, 1, "the search still narrows the board")
    }
}
