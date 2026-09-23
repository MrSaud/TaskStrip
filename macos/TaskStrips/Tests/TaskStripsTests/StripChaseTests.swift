import SwiftData
import XCTest
@testable import TaskStrips

/// Going after the thing somebody else owes you, which is what actually slips in a project.
@MainActor
final class StripChaseTests: XCTestCase {
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)   // 21 Sep 2026

    override func setUpWithError() throws {
        try super.setUpWithError()
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func strip(
        _ title: String = "Tender 4471 documents",
        waitingOn: String = "Bassam Alfeeli",
        daysAgo: Int = 12,
        contacts: [TaskContact] = [TaskContact(name: "Bassam Alfeeli", email: "balfeeli@kfas.org.kw")]
    ) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0)
        task.waitingOnName = waitingOn
        task.waitingOnSince = now.addingTimeInterval(Double(-daysAgo) * 86_400)
        task.waitingOnFollowUpDays = 7
        task.contacts = contacts
        context.insert(task)
        return task
    }

    private var account: IMAPAccount {
        var account = IMAPAccount(email: "me@kfas.org.kw", host: "imap.kfas.org.kw")
        account.senderName = "Saud Alenezi"
        return account
    }

    func testTheChaseIsAddressedToThePersonBeingWaitedOn() {
        let draft = StripChase.draft(for: strip(), from: account, now: now)
        XCTAssertEqual(draft.to, "balfeeli@kfas.org.kw")
        XCTAssertEqual(draft.subject, "Following up: Tender 4471 documents")
    }

    /// Specific about what and since when — the two things that make a reminder answerable.
    func testItSaysWhatItIsAboutAndHowLongItHasBeen() {
        let draft = StripChase.draft(for: strip(), from: account, now: now)
        XCTAssertTrue(draft.body.contains("Hello Bassam,"), draft.body)
        XCTAssertTrue(draft.body.contains("Tender 4471 documents"), draft.body)
        XCTAssertTrue(draft.body.contains("12 days"), draft.body)
        XCTAssertTrue(draft.body.contains("Saud Alenezi"), draft.body)
    }

    func testADayIsADayRatherThanOneDays() {
        let draft = StripChase.draft(for: strip(daysAgo: 1), from: account, now: now)
        XCTAssertTrue(draft.body.contains("a day"), draft.body)
        XCTAssertFalse(draft.body.contains("1 days"), draft.body)
    }

    func testTheRightContactIsPickedOutOfSeveral() {
        let task = strip(contacts: [
            TaskContact(name: "Mona Salmeen", email: "msalmeen@kfas.org.kw"),
            TaskContact(name: "Bassam Alfeeli", email: "balfeeli@kfas.org.kw"),
        ])
        XCTAssertEqual(StripChase.recipient(of: task)?.email, "balfeeli@kfas.org.kw")
    }

    /// One contact on a strip waiting for somebody: it's them, whatever the name was typed as.
    func testASingleContactIsUsedEvenIfTheNameDoesNotMatch() {
        let task = strip(waitingOn: "the ministry", contacts: [TaskContact(name: "Help Desk", email: "desk@mosa.gov.kw")])
        XCTAssertEqual(StripChase.recipient(of: task)?.email, "desk@mosa.gov.kw")
    }

    func testWithNobodyToWriteToTheAddressIsLeftForThePersonToFill() {
        let draft = StripChase.draft(for: strip(contacts: []), from: account, now: now)
        XCTAssertEqual(draft.to, "")
        XCTAssertFalse(draft.isSendable)
    }

    /// A chase belongs under the conversation it came from.
    func testAChaseThreadsUnderTheOriginalEmail() {
        let task = strip()
        task.links.append(TaskLink(url: "message://%3Cabc123@kfas.org.kw%3E", label: "Tender 4471"))
        XCTAssertEqual(StripChase.originalMessageID(of: task), "abc123@kfas.org.kw")
        XCTAssertEqual(StripChase.draft(for: task, from: account, now: now).inReplyTo, "abc123@kfas.org.kw")
    }

    func testAStripWithNoEmailBehindItStartsANewConversation() {
        let task = strip()
        task.links.append(TaskLink(url: "https://example.com/tender", label: "Portal"))
        XCTAssertNil(StripChase.originalMessageID(of: task))
    }

    // MARK: - What a chase does to the next nudge

    /// Without this the strip asks to be chased every single day once the follow-up is passed.
    func testChasingBuysAnotherRoundOfDays() {
        let task = strip(daysAgo: 12)   // follow-up is 7 days, so a chase is overdue
        XCTAssertTrue(DayPlan.isChaseDue(task, now: now))

        task.waitingOnChasedAt = now
        XCTAssertFalse(DayPlan.isChaseDue(task, now: now))
        // And it comes back when the next round is up.
        XCTAssertTrue(DayPlan.isChaseDue(task, now: now.addingTimeInterval(8 * 86_400)))
    }

    func testTheNotificationCountsFromTheChaseToo() throws {
        let task = strip(daysAgo: 12)
        task.waitingOnChasedAt = now
        let fireAt = try XCTUnwrap(ReminderPlan.followUpDate(for: task, now: now))
        XCTAssertEqual(fireAt.timeIntervalSince(now) / 86_400, 7, accuracy: 0.01)
    }

    func testTheLogSaysWhoWasChased() {
        XCTAssertEqual(StripChase.logLine(to: "Bassam Alfeeli"), "Chased Bassam Alfeeli by email")
        XCTAssertEqual(StripChase.logLine(to: ""), "Chased by email")
    }

    /// A strip saved before chasing existed has no chase date, and behaves as it always did.
    func testAStripThatHasNeverBeenChasedIsUnchanged() {
        let task = strip(daysAgo: 12)
        XCTAssertNil(task.waitingOnChasedAt)
        XCTAssertTrue(DayPlan.isChaseDue(task, now: now))
    }
}
