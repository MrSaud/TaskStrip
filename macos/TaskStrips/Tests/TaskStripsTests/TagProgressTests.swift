import XCTest
@testable import TaskStrips

final class TagProgressTests: XCTestCase {
    private func strip(_ title: String, tags: [String], done: Bool = false) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0)
        task.tags = tags
        task.isDone = done
        return task
    }

    func testCountsDoneAgainstTotalPerTag() {
        let stats = TagProgress.stats(for: [
            strip("A", tags: ["travel"], done: true),
            strip("B", tags: ["travel"]),
            strip("C", tags: ["home"], done: true),
        ])

        XCTAssertEqual(stats.map(\.tag), ["travel", "home"])
        XCTAssertEqual(stats.map(\.done), [1, 1])
        XCTAssertEqual(stats.map(\.total), [2, 1])
        XCTAssertEqual(stats.first?.fraction, 0.5)
    }

    func testAStripCountsTowardsEveryTagItCarries() {
        let stats = TagProgress.stats(for: [strip("A", tags: ["travel", "urgent"], done: true)])
        XCTAssertEqual(stats.map(\.total), [1, 1])
        XCTAssertEqual(stats.map(\.done), [1, 1])
    }

    /// Tags are typed by hand, so the same tag in two spellings is still one tag.
    func testTagsGroupWithoutRegardToCase() {
        let stats = TagProgress.stats(for: [
            strip("A", tags: ["Travel"], done: true),
            strip("B", tags: ["travel"]),
            strip("C", tags: ["TRAVEL"]),
        ])

        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.first?.total, 3)
        // Shown in the spelling that appears first on the board.
        XCTAssertEqual(stats.first?.tag, "Travel")
    }

    func testBusiestTagComesFirst() {
        let stats = TagProgress.stats(for: [
            strip("A", tags: ["small"]),
            strip("B", tags: ["big"]),
            strip("C", tags: ["big"]),
            strip("D", tags: ["big"]),
        ])
        XCTAssertEqual(stats.map(\.tag), ["big", "small"])
    }

    /// Otherwise the list would reshuffle itself every time a strip is completed.
    func testTagsWithTheSameCountKeepTheOrderTheyWereFirstSeenIn() {
        let stats = TagProgress.stats(for: [
            strip("A", tags: ["first"]),
            strip("B", tags: ["second"]),
            strip("C", tags: ["third"]),
        ])
        XCTAssertEqual(stats.map(\.tag), ["first", "second", "third"])
    }

    func testAnUntaggedBoardHasNoStats() {
        XCTAssertTrue(TagProgress.stats(for: [strip("A", tags: [])]).isEmpty)
    }

    func testATagWithNothingDoneReadsAsZero() {
        let stats = TagProgress.stats(for: [strip("A", tags: ["later"])])
        XCTAssertEqual(stats.first?.fraction, 0)
    }
}
