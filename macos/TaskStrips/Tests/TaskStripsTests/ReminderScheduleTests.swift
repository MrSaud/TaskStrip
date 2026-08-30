import XCTest
@testable import TaskStrips

final class ReminderScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func reminder(
        _ text: String = "Renew the registration",
        at triggerAt: Date,
        lead: Int? = nil,
        amount: Int? = nil,
        unit: ReminderRepeatUnit? = nil,
        done: Bool = false,
        tag: String = "",
        emoji: String = ""
    ) -> Reminder {
        Reminder(
            text: text,
            triggerAt: triggerAt,
            leadMinutesBefore: lead,
            repeatAmount: amount,
            repeatUnit: unit,
            tag: tag,
            tagEmoji: emoji,
            isDone: done
        )
    }

    // MARK: - When it fires

    func testFiresAtTheMomentItIsSetFor() {
        let now = date(2026, 6, 15)
        let item = reminder(at: date(2026, 6, 20))
        XCTAssertEqual(ReminderSchedule.fireDate(for: item, now: now), date(2026, 6, 20))
    }

    /// The lead time replaces the alarm rather than adding a second one, exactly as a strip's
    /// due-date reminder does.
    func testALeadTimeMovesTheOnlyAlarmEarlier() {
        let now = date(2026, 6, 15)
        let item = reminder(at: date(2026, 6, 20), lead: 1440)
        XCTAssertEqual(ReminderSchedule.fireDate(for: item, now: now), date(2026, 6, 19))
    }

    func testAFinishedReminderDoesNotFire() {
        let now = date(2026, 6, 15)
        XCTAssertNil(ReminderSchedule.fireDate(for: reminder(at: date(2026, 6, 20), done: true), now: now))
    }

    /// A backup is full of reminders whose moment has passed, and none of them should announce
    /// themselves on arrival.
    func testAMomentAlreadyPastDoesNotFire() {
        let now = date(2026, 6, 15)
        XCTAssertNil(ReminderSchedule.fireDate(for: reminder(at: date(2026, 6, 1)), now: now))
    }

    /// The lead can push a reminder that is still ahead into the past.
    func testALeadTimeThatHasAlreadyElapsedDoesNotFire() {
        let now = date(2026, 6, 15, 12)
        let item = reminder(at: date(2026, 6, 15, 18), lead: 1440)
        XCTAssertNil(ReminderSchedule.fireDate(for: item, now: now))
    }

    // MARK: - Repeats

    func testTheNextOccurrenceUsesCalendarArithmetic() {
        let start = date(2026, 1, 31)
        XCTAssertEqual(
            ReminderSchedule.nextOccurrence(after: start, amount: 1, unit: .monthly, calendar: calendar),
            date(2026, 2, 28),
            "adding a month to the 31st has to land on a real date"
        )
        XCTAssertEqual(
            ReminderSchedule.nextOccurrence(after: start, amount: 1, unit: .yearly, calendar: calendar),
            date(2027, 1, 31),
            "a year later is the same date, not 365 days"
        )
        XCTAssertEqual(
            ReminderSchedule.nextOccurrence(after: date(2026, 6, 1), amount: 2, unit: .weekly, calendar: calendar),
            date(2026, 6, 15)
        )
    }

    func testAnAmountOfZeroHasNoNextOccurrence() {
        XCTAssertNil(
            ReminderSchedule.nextOccurrence(after: date(2026, 6, 1), amount: 0, unit: .daily, calendar: calendar)
        )
    }

    // MARK: - Rolling forward

    /// Android advances one step inside the receiver that fires it; the Mac has no such hook, so
    /// a reminder catches up the next time the app sees it.
    func testARepeatingReminderCatchesUpPastEveryMissedOccurrence() {
        let item = reminder(at: date(2026, 1, 10), amount: 1, unit: .monthly)
        let next = ReminderSchedule.rolledForward(item, now: date(2026, 6, 15), calendar: calendar)
        XCTAssertEqual(next, date(2026, 7, 10), "the next one due, not the first one missed")
    }

    func testARepeatingReminderStillAheadIsLeftAlone() {
        let item = reminder(at: date(2026, 8, 1), amount: 1, unit: .monthly)
        XCTAssertNil(ReminderSchedule.rolledForward(item, now: date(2026, 6, 15), calendar: calendar))
    }

    func testAOneShotReminderIsNeverRolledForward() {
        let item = reminder(at: date(2026, 1, 10))
        XCTAssertNil(ReminderSchedule.rolledForward(item, now: date(2026, 6, 15), calendar: calendar))
    }

    /// Finishing a repeating reminder ends the series rather than quietly starting it again.
    func testAFinishedRepeatingReminderIsNotRolledForward() {
        let item = reminder(at: date(2026, 1, 10), amount: 1, unit: .monthly, done: true)
        XCTAssertNil(ReminderSchedule.rolledForward(item, now: date(2026, 6, 15), calendar: calendar))
    }

    func testARepeatMissingOneOfItsHalvesIsNotARepeat() {
        XCTAssertFalse(reminder(at: date(2026, 1, 1), amount: 2, unit: nil).repeats)
        XCTAssertFalse(reminder(at: date(2026, 1, 1), amount: nil, unit: .daily).repeats)
        XCTAssertFalse(reminder(at: date(2026, 1, 1), amount: 0, unit: .daily).repeats)
        XCTAssertTrue(reminder(at: date(2026, 1, 1), amount: 2, unit: .daily).repeats)
    }

    // MARK: - The list

    func testTheListIsSoonestFirstUnlessAskedOtherwise() {
        let later = reminder("Later", at: date(2026, 7, 1))
        let sooner = reminder("Sooner", at: date(2026, 6, 1))
        XCTAssertEqual(ReminderSchedule.visible([later, sooner]).map(\.text), ["Sooner", "Later"])
        XCTAssertEqual(
            ReminderSchedule.visible([later, sooner], newestFirst: true).map(\.text),
            ["Later", "Sooner"]
        )
    }

    /// Android searches the title only, which is worth keeping: a description is where the long
    /// text goes, and matching it would make the search feel indiscriminate.
    func testSearchMatchesTheTitleAndIgnoresCase() {
        let item = Reminder(text: "Dentist", triggerAt: date(2026, 6, 1), details: "bring the referral")
        XCTAssertEqual(ReminderSchedule.visible([item], search: "DENT").count, 1)
        XCTAssertEqual(ReminderSchedule.visible([item], search: "referral").count, 0)
        XCTAssertEqual(ReminderSchedule.visible([item], search: "   ").count, 1)
    }

    func testTheTagFilterNarrowsTheListAndForgetsItselfWhenTheTagIsGone() {
        let tagged = reminder("Registration", at: date(2026, 6, 1), tag: "Documents", emoji: "📄")
        let untagged = reminder("Dentist", at: date(2026, 6, 2))

        XCTAssertEqual(ReminderSchedule.visible([tagged, untagged], tag: "Documents").map(\.text), ["Registration"])
        XCTAssertEqual(ReminderSchedule.visible([tagged, untagged], tag: "Birthday").count, 2)
        XCTAssertEqual(tagged.tagLabel, "📄 Documents")
    }

    // MARK: - What a row says

    func testTheSummaryReadsBackWhatWasSet() {
        let item = reminder(at: date(2026, 6, 20), lead: 1440, amount: 1, unit: .yearly)
        let summary = ReminderSchedule.summary(for: item, now: date(2026, 6, 1))

        XCTAssertTrue(summary.contains("1440 min before"))
        XCTAssertTrue(summary.contains("every year"))
        XCTAssertFalse(summary.contains("overdue"))
    }

    func testSomethingStillOpenAndPastSaysSo() {
        let item = reminder(at: date(2026, 6, 1))
        XCTAssertTrue(ReminderSchedule.summary(for: item, now: date(2026, 6, 15)).contains("overdue"))
        // Finishing it takes the word away rather than leaving it accusing.
        let done = reminder(at: date(2026, 6, 1), done: true)
        XCTAssertFalse(ReminderSchedule.summary(for: done, now: date(2026, 6, 15)).contains("overdue"))
    }

    func testARepeatOfOneReadsAsEveryUnit() {
        XCTAssertEqual(reminder(at: date(2026, 6, 1), amount: 1, unit: .monthly).repeatLabel, "Every month")
        XCTAssertEqual(reminder(at: date(2026, 6, 1), amount: 3, unit: .weekly).repeatLabel, "Every 3 weeks")
        XCTAssertNil(reminder(at: date(2026, 6, 1)).repeatLabel)
    }
}
