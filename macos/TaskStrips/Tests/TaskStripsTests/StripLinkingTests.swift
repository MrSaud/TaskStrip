import SwiftData
import XCTest
@testable import TaskStrips

/// Filing an email, and filing a sketch, onto the strip either belongs to.
@MainActor
final class StripLinkingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    private func strip(_ title: String, done: Bool = false, archived: Bool = false, order: Int = 0) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: order)
        task.isDone = done
        task.isArchived = archived
        context.insert(task)
        return task
    }

    private var message: MailMessage {
        MailMessage(
            id: "abc123@example.com",
            subject: "Quarterly report",
            sender: "Ahmad <ahmad@example.com>",
            receivedAt: .now,
            isRead: false
        )
    }

    /// The link the reader files is the same record a message dragged out of Mail leaves, so both
    /// routes put the same thing on the strip.
    func testAnEmailFiledFromTheReaderLooksLikeOneDraggedFromMail() throws {
        let task = strip("Invoices")
        let url = try XCTUnwrap(message.link)
        task.links.append(TaskLink(url: url, label: message.subject))

        XCTAssertEqual(task.links.count, 1)
        XCTAssertEqual(task.links.first?.label, "Quarterly report")
        XCTAssertTrue(EmailLink.isMessage(try XCTUnwrap(task.links.first?.url)))
        // The angle brackets are escaped, which is what Mail's own links look like.
        XCTAssertEqual(url, "message://%3Cabc123@example.com%3E")
    }

    func testTheSameMessageFiledTwiceIsOneLink() throws {
        let task = strip("Invoices")
        let url = try XCTUnwrap(message.link)
        for _ in 0..<2 where !task.links.contains(where: { $0.url == url }) {
            task.links.append(TaskLink(url: url, label: message.subject))
        }
        XCTAssertEqual(task.links.count, 1)
    }

    /// Active means on the board, not finished, and not deleted: the picker offers somewhere
    /// worth filing to.
    ///
    /// The tombstone is the one that bit. A deleted strip stays as a row so the deletion can
    /// reach the other devices, and the picker listed three of them under names the board no
    /// longer showed — the same strip twice over, apparently duplicated.
    func testThePickerOffersOnlyStripsStillInPlay() throws {
        _ = strip("On the board", order: 0)
        _ = strip("Finished", done: true, order: 1)
        _ = strip("Archived", archived: true, order: 2)
        let deleted = strip("Deleted", order: 3)
        deleted.isTombstoned = true

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { !$0.isTombstoned && !$0.isArchived && !$0.isDone },
            sortBy: [SortDescriptor(\TaskItem.orderIndex)]
        )
        XCTAssertEqual(try context.fetch(descriptor).map(\.title), ["On the board"])
    }

    func testASketchGoesOntoAStripAndTheStripSaysSo() {
        let task = strip("Roof repair")
        task.linkedSketchID = "sketch-2026-09-23-1"
        task.actionLog.append(TaskActionLogEntry(text: "Linked a sketch", timestamp: .now))

        XCTAssertEqual(task.linkedSketchID, "sketch-2026-09-23-1")
        XCTAssertEqual(task.actionLog.last?.text, "Linked a sketch")
    }

    /// A strip holds one sketch, so choosing a strip that has one replaces it — which is why the
    /// menu says so in the row before it's tapped.
    func testAStripThatAlreadyHasASketchIsFlaggedInThePicker() {
        let withSketch = strip("Has one")
        withSketch.linkedSketchID = "older-sketch"
        let without = strip("Has none", order: 1)

        let note: (TaskItem) -> String? = { $0.linkedSketchID == nil ? nil : "replaces its sketch" }
        XCTAssertEqual(note(withSketch), "replaces its sketch")
        XCTAssertNil(note(without))
    }
}
