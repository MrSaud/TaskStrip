import SwiftData
import XCTest
@testable import TaskStrips

/// A whole strip out through a backup and back in, field by field.
///
/// This is the test that has to hold when the board moves from a build made here to one installed
/// from elsewhere: a backup is the only thing that carries a board across that gap, and anything
/// it silently drops is data somebody loses without being told. Every field added since — the
/// checklist, the deferral, the sessions, the calendar event, the totals, the chase date — is
/// named here on purpose, so adding a field and forgetting the backup fails a test rather than
/// losing somebody's month.
@MainActor
final class BackupRoundTripTests: XCTestCase {
    private var context: ModelContext!
    private var credentials: CredentialStore!
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
        credentials = CredentialStore(ephemeral: true)
    }

    /// One strip carrying everything a strip can carry.
    private func fullStrip() -> TaskItem {
        let strip = TaskItem(title: "Renew the licence", orderIndex: 3, priority: .high, createdAt: when)
        strip.notes = "تجديد الرخصة قبل الموعد"
        strip.notesRtl = true
        strip.tags = ["WORK", "MOSA"]
        strip.progress = 40
        strip.dueAt = when.addingTimeInterval(10 * 86_400)
        strip.deferUntil = when.addingTimeInterval(2 * 86_400)
        strip.reminderMinutesBefore = 30
        strip.repeatIntervalDays = 365
        strip.calendarEventID = "event-123"
        strip.linkedSketchID = "sketch-2026-09-24-1"

        strip.waitingOnName = "Bassam"
        strip.waitingOnSince = when.addingTimeInterval(-12 * 86_400)
        strip.waitingOnFollowUpDays = 7
        strip.waitingOnChasedAt = when.addingTimeInterval(-86_400)

        strip.checklist = [
            TaskChecklistItem(text: "Fill the form", isDone: true, doneAt: when),
            TaskChecklistItem(text: "Pay the fee", isDone: false),
        ]
        strip.sessions = [TaskWorkSession(startedAt: when, endedAt: when.addingTimeInterval(1_800))]
        strip.links = [TaskLink(url: "message://%3Cabc@kfas.org.kw%3E", label: "The request")]
        strip.contacts = [TaskContact(name: "Bassam Alfeeli", email: "b@kfas.org.kw", phone: "+965 5000 0000")]
        strip.actionLog = [TaskActionLogEntry(text: "Chased Bassam by email", timestamp: when)]

        var cost = TaskTally(name: "Cost", unit: .money(currency: "KWD"))
        cost = StripTally.adding(150, to: cost, note: "Deposit", at: when)
        cost = StripTally.adding(2.5, to: cost, at: when, fromTimer: true)
        cost.target = 1_000
        cost.announced = [90]
        var hours = TaskTally(name: "Hours", unit: .hours)
        hours = StripTally.adding(3, to: hours, at: when)
        strip.tallies = [cost, hours]

        context.insert(strip)
        return strip
    }

    /// Out and back in, through the same code the app uses.
    private func roundTrip(_ strip: TaskItem) throws -> TaskItem {
        var passwords = 0
        let manifest = try BackupExport.manifestData(
            BackupExport.Contents(tasks: [strip]),
            credentialStore: credentials,
            passwordsIncluded: &passwords
        )
        let parsed = try BackupImport.parse(manifest: manifest)
        _ = BackupImport.apply(parsed.tasks, mode: .replace, existing: [strip], context: context)
        let restored = try context.fetch(FetchDescriptor<TaskItem>())
        return try XCTUnwrap(restored.first)
    }

    func testTheWordsAndTheDatesComeBack() throws {
        let restored = try roundTrip(fullStrip())
        XCTAssertEqual(restored.title, "Renew the licence")
        XCTAssertEqual(restored.notes, "تجديد الرخصة قبل الموعد")
        XCTAssertTrue(restored.notesRtl)
        XCTAssertEqual(restored.tags, ["WORK", "MOSA"])
        XCTAssertEqual(restored.priority, .high)
        XCTAssertEqual(restored.progress, 40)
        XCTAssertEqual(
            try XCTUnwrap(restored.dueAt).timeIntervalSince1970,
            when.addingTimeInterval(10 * 86_400).timeIntervalSince1970,
            accuracy: 60
        )
        XCTAssertEqual(
            try XCTUnwrap(restored.deferUntil).timeIntervalSince1970,
            when.addingTimeInterval(2 * 86_400).timeIntervalSince1970,
            accuracy: 60
        )
        XCTAssertEqual(restored.reminderMinutesBefore, 30)
        XCTAssertEqual(restored.repeatIntervalDays, 365)
        XCTAssertEqual(restored.calendarEventID, "event-123")
        XCTAssertEqual(restored.linkedSketchID, "sketch-2026-09-24-1")
    }

    func testWhoItIsWaitingOnAndWhenItWasChasedComeBack() throws {
        let restored = try roundTrip(fullStrip())
        XCTAssertEqual(restored.waitingOnName, "Bassam")
        XCTAssertEqual(restored.waitingOnFollowUpDays, 7)
        XCTAssertNotNil(restored.waitingOnSince)
        // Without this the strip asks to be chased again the day it's restored.
        XCTAssertEqual(
            try XCTUnwrap(restored.waitingOnChasedAt).timeIntervalSince1970,
            when.addingTimeInterval(-86_400).timeIntervalSince1970,
            accuracy: 60
        )
    }

    func testTheChecklistAndTheWorkComeBack() throws {
        let restored = try roundTrip(fullStrip())
        XCTAssertEqual(restored.checklist.map(\.text), ["Fill the form", "Pay the fee"])
        XCTAssertEqual(restored.checklist.first?.isDone, true)
        XCTAssertEqual(restored.sessions.count, 1)
        XCTAssertEqual(StripTime.total(of: restored.sessions), 1_800, accuracy: 1)
    }

    func testWhatIsOnItComesBack() throws {
        let restored = try roundTrip(fullStrip())
        XCTAssertEqual(restored.links.first?.url, "message://%3Cabc@kfas.org.kw%3E")
        XCTAssertEqual(restored.links.first?.label, "The request")
        XCTAssertEqual(restored.contacts.first?.email, "b@kfas.org.kw")
        XCTAssertEqual(restored.actionLog.first?.text, "Chased Bassam by email")
    }

    /// The totals, which are the newest thing on a strip and the easiest to forget.
    func testTheTotalsComeBackWhole() throws {
        let restored = try roundTrip(fullStrip())
        XCTAssertEqual(restored.tallies.count, 2)

        let cost = try XCTUnwrap(restored.tallies.first { $0.name == "Cost" })
        XCTAssertEqual(cost.unit, .money(currency: "KWD"))
        XCTAssertEqual(cost.total, 152.5)
        XCTAssertEqual(cost.target, 1_000)
        XCTAssertEqual(cost.entries.count, 2)
        XCTAssertEqual(cost.entries.first { $0.fromTimer }?.amount, 2.5)
        XCTAssertEqual(cost.entries.first { !$0.fromTimer }?.note, "Deposit")
        // Already announced at nine tenths, and shouldn't announce it again after a restore.
        XCTAssertEqual(cost.announced, [90])

        let hours = try XCTUnwrap(restored.tallies.first { $0.name == "Hours" })
        XCTAssertEqual(hours.unit, .hours)
        XCTAssertEqual(hours.total, 3)
    }

    /// A strip made by an older version of the app — no totals, no chase date — restores as what
    /// it is rather than failing the whole import.
    func testABackupFromBeforeTheseFieldsStillRestores() throws {
        let manifest = """
        {"version":1,"tasks":[{"title":"Old strip","orderIndex":0,"priority":"NORMAL","notes":"","createdAt":1700000000000}],
         "credentials":[],"notes":[],"reminders":[],"storageItems":[]}
        """
        let parsed = try BackupImport.parse(manifest: Data(manifest.utf8))
        _ = BackupImport.apply(parsed.tasks, mode: .replace, existing: [], context: context)
        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertEqual(restored.title, "Old strip")
        XCTAssertTrue(restored.tallies.isEmpty)
        XCTAssertNil(restored.waitingOnChasedAt)
    }
}
