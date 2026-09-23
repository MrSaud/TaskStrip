import SwiftData
import XCTest
@testable import TaskStrips

final class StripTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(from: TimeInterval, to: TimeInterval?) -> TaskWorkSession {
        TaskWorkSession(
            startedAt: now.addingTimeInterval(from),
            endedAt: to.map { now.addingTimeInterval($0) }
        )
    }

    func testAStretchWithNoEndIsTheOneRunning() {
        let sessions = [session(from: -3600, to: -1800), session(from: -600, to: nil)]
        XCTAssertTrue(StripTime.isRunning(sessions))
        XCTAssertEqual(StripTime.running(in: sessions)?.startedAt, now.addingTimeInterval(-600))
        XCTAssertFalse(StripTime.isRunning([session(from: -60, to: -30)]))
        XCTAssertFalse(StripTime.isRunning([]))
    }

    func testTheTotalCountsTheRunningStretchUpToNow() {
        let sessions = [session(from: -3600, to: -1800), session(from: -600, to: nil)]
        XCTAssertEqual(StripTime.total(of: sessions, now: now), 1800 + 600, accuracy: 0.1)
    }

    func testStartingTwiceDoesNotStartTwice() {
        let started = StripTime.start([], now: now)
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(StripTime.start(started, now: now).count, 1, "it was already running")
    }

    func testStoppingClosesTheStretch() {
        let started = StripTime.start([], now: now.addingTimeInterval(-900))
        let stopped = StripTime.stop(started, now: now)
        XCTAssertFalse(StripTime.isRunning(stopped))
        XCTAssertEqual(StripTime.total(of: stopped, now: now), 900, accuracy: 0.1)
    }

    /// Started and stopped in the same breath is a misclick, not work.
    func testATinyStretchIsThrownAwayRatherThanKept() {
        let started = StripTime.start([], now: now.addingTimeInterval(-2))
        XCTAssertTrue(StripTime.stop(started, now: now).isEmpty)
        XCTAssertNil(StripTime.logEntry(for: 2))
    }

    func testStoppingWhenNothingIsRunningChangesNothing() {
        let sessions = [session(from: -600, to: -300)]
        XCTAssertEqual(StripTime.stop(sessions, now: now), sessions)
    }

    // MARK: - The week

    func testTheWeekCountsOnlyWhatFellInsideIt() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let week = try? XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: now))
        guard let week else { return XCTFail("no week") }

        // An hour last week, an hour that straddles the boundary, an hour this week.
        let lastWeek = TaskWorkSession(
            startedAt: week.start.addingTimeInterval(-7200), endedAt: week.start.addingTimeInterval(-3600)
        )
        let straddling = TaskWorkSession(
            startedAt: week.start.addingTimeInterval(-1800), endedAt: week.start.addingTimeInterval(1800)
        )
        let inside = TaskWorkSession(startedAt: now.addingTimeInterval(-600), endedAt: now)

        let total = StripTime.thisWeek([lastWeek, straddling, inside], now: now, calendar: calendar)
        XCTAssertEqual(total, 1800 + 600, accuracy: 0.1, "only the half that fell inside the week")
    }

    // MARK: - How it reads

    func testTimeReadsTheWayAPersonWouldSayIt() {
        XCTAssertEqual(StripTime.label(30), "30s")
        XCTAssertEqual(StripTime.label(45 * 60), "45m")
        XCTAssertEqual(StripTime.label(65 * 60), "1h 05m")
        XCTAssertEqual(StripTime.label(3 * 3600), "3h 00m")
        XCTAssertEqual(StripTime.label(0), "0s")
    }

    func testTheLogSaysWhatWasSpent() {
        XCTAssertEqual(StripTime.logEntry(for: 25 * 60), "Worked 25m")
    }
}

final class StripTimerActionTests: XCTestCase {
    private var context: ModelContext!

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func strip(_ title: String) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0)
        context.insert(task)
        return task
    }

    func testStartingOneStripStopsTheOther() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = strip("First")
        let second = strip("Second")

        StripActions.startTimer(on: first, in: [first, second], now: now.addingTimeInterval(-1800))
        let stopped = StripActions.startTimer(on: second, in: [first, second], now: now)

        XCTAssertEqual(stopped?.title, "First")
        XCTAssertFalse(StripTime.isRunning(first.sessions))
        XCTAssertTrue(StripTime.isRunning(second.sessions))
        XCTAssertEqual(StripTime.total(of: first.sessions, now: now), 1800, accuracy: 1)
        XCTAssertEqual(first.actionLog.last?.text, "Worked 30m")
    }

    func testFinishingAStripStopsItsClock() {
        let task = strip("Something")
        StripActions.startTimer(on: task, in: [task], now: Date().addingTimeInterval(-600))
        _ = StripActions.toggleDone(task, in: [task], context: context)
        XCTAssertFalse(StripTime.isRunning(task.sessions))
    }

    func testTheTimerTogglesBothWays() {
        let task = strip("Something")
        StripActions.toggleTimer(on: task, in: [task], now: Date().addingTimeInterval(-600))
        XCTAssertTrue(StripTime.isRunning(task.sessions))
        StripActions.toggleTimer(on: task, in: [task])
        XCTAssertFalse(StripTime.isRunning(task.sessions))
    }
}
