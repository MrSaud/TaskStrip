import SwiftData
import XCTest
@testable import TaskStrips

final class StripMailTests: XCTestCase {
    private func strip(
        _ title: String = "Renew the passport",
        notes: String = "",
        due: Date? = nil,
        priority: Priority = .high,
        progress: Int = 0,
        tags: [String] = [],
        links: [TaskLink] = [],
        contacts: [TaskContact] = []
    ) -> TaskItem {
        let task = TaskItem(title: title, orderIndex: 0, priority: priority)
        task.notes = notes
        task.dueAt = due
        task.progress = progress
        task.tags = tags
        task.links = links
        task.contacts = contacts
        return task
    }

    // MARK: - An email linked to a strip

    /// The exact shape Mail puts on the pasteboard when a message is dragged out of it: one
    /// colon, no slashes, and the angle brackets already escaped.
    func testTheLinkMailActuallyHandsOverIsRecognised() {
        let dragged = "message:%3C1372329598.91023@mail.example.com%3E"
        XCTAssertTrue(EmailLink.isMessage(dragged))
        XCTAssertEqual(EmailLink.label(for: dragged), "Email message")
        XCTAssertNotNil(URL(string: dragged), "it has to survive being made into a URL")
    }

    func testAMessageLinkIsToldApartFromAWebPage() {
        XCTAssertTrue(EmailLink.isMessage("message://%3C123@mail.example%3E"))
        XCTAssertTrue(EmailLink.isMessage("mailto:someone@example.com"))
        XCTAssertTrue(EmailLink.isMessage("MESSAGE://%3C9%3E"), "the scheme's case doesn't matter")
        XCTAssertFalse(EmailLink.isMessage("https://example.com"))
        XCTAssertFalse(EmailLink.isMessage("not a url at all"))
        XCTAssertFalse(EmailLink.isMessage(""))
    }

    func testALinkedMessageIsCalledSomethingReadable() {
        XCTAssertEqual(EmailLink.label(for: "message://%3C123@mail.example%3E"), "Email message")
        XCTAssertEqual(EmailLink.label(for: "mailto:boss@example.com"), "Email boss@example.com")
        // A web link is its own label.
        XCTAssertEqual(EmailLink.label(for: "https://example.com"), "https://example.com")
    }

    // MARK: - A strip sent as an email

    func testTheSubjectIsTheStripAndAStripWithNoTitleStillHasOne() {
        XCTAssertEqual(StripMail.subject(for: strip()), "Renew the passport")
        XCTAssertEqual(StripMail.subject(for: strip("")), "Task Strips")
    }

    func testTheBodyCarriesWhatTheStripSays() {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let task = strip(notes: "Booked for Tuesday.", due: due, progress: 40, tags: ["HOME"])
        let body = StripMail.body(for: task)

        XCTAssertTrue(body.contains("Priority: High"), body)
        XCTAssertTrue(body.contains("Progress: 40%"), body)
        XCTAssertTrue(body.contains("Tags: HOME"), body)
        XCTAssertTrue(body.contains("Booked for Tuesday."), body)
        XCTAssertTrue(body.hasSuffix("— Sent from Task Strips"), body)
    }

    func testAnEmptyStripSendsNoEmptyHeadings() {
        let body = StripMail.body(for: strip(priority: .normal))
        XCTAssertFalse(body.contains("Tags:"), body)
        XCTAssertFalse(body.contains("Links:"), body)
        XCTAssertFalse(body.contains("People:"), body)
        XCTAssertFalse(body.contains("Progress:"), body)
    }

    /// A message: link is an id inside one person's mail app. Sending it to someone else would be
    /// sending them a link that can only ever fail.
    func testALinkedEmailIsNotPassedOnToSomeoneElse() {
        let task = strip(links: [
            TaskLink(url: "https://example.com/form", label: "The form"),
            TaskLink(url: "message://%3C123@mail.example%3E", label: ""),
        ])
        let body = StripMail.body(for: task)
        XCTAssertTrue(body.contains("The form — https://example.com/form"), body)
        XCTAssertFalse(body.contains("message://"), body)
    }

    func testTheMailtoEscapesEverythingThatWouldBreakIt() throws {
        let url = try XCTUnwrap(StripMail.mailtoURL(subject: "Tea & biscuits", body: "One\nTwo & three"))
        let text = url.absoluteString
        XCTAssertTrue(text.hasPrefix("mailto:?"), text)
        XCTAssertFalse(text.contains("Tea & biscuits"), "an unescaped ampersand ends the subject")
        XCTAssertTrue(text.contains("%26"), text)
        XCTAssertTrue(text.contains("%0A") || text.contains("%0D"), "the line break survives")
    }

    // MARK: - The files that go with it

    func testTheFilesThatFitGoAndTheRestStayBehind() {
        let plan = StripMail.attachmentsThatFit([5_000_000, 30_000_000, 1_000], limit: 20 * 1024 * 1024)
        XCTAssertEqual(plan.sent, [0, 2])
        XCTAssertEqual(plan.left, [1])
    }

    func testFilesAreTakenInOrderUntilTheLimitIsReached() {
        let plan = StripMail.attachmentsThatFit([8, 8, 8], limit: 20)
        XCTAssertEqual(plan.sent, [0, 1])
        XCTAssertEqual(plan.left, [2])
    }

    func testAFileWithNoSizeIsNotSent() {
        let plan = StripMail.attachmentsThatFit([0, 10], limit: 100)
        XCTAssertEqual(plan.sent, [1])
        XCTAssertEqual(plan.left, [0])
    }

    func testTheBodySaysWhichFilesWereLeftBehind() {
        XCTAssertNil(StripMail.note(forFilesLeftBehind: []))
        XCTAssertEqual(
            StripMail.note(forFilesLeftBehind: ["video.mov"]),
            "\n(video.mov was too large to attach.)"
        )
        XCTAssertEqual(
            StripMail.note(forFilesLeftBehind: ["a.mov", "b.zip"]),
            "\n(a.mov, b.zip were too large to attach.)"
        )
    }

    // MARK: - An email dropped as a file

    private let sample = """
    From: someone@example.com
    To: me@example.com
    Subject: The quote
    Message-ID: <CAF123abc@mail.example.com>
    Date: Mon, 1 Sep 2026 10:00:00 +0300

    Message-ID: <not-this-one@example.com>
    The body of the email.
    """

    func testTheLinkBackToAMessageIsReadOutOfTheFile() throws {
        let link = try XCTUnwrap(EmailLink.fromEmail(sample))
        XCTAssertTrue(link.hasPrefix("message://"), link)
        XCTAssertTrue(link.contains("CAF123abc"), link)
        // The angle brackets have to be escaped or the URL ends at the first one.
        XCTAssertFalse(link.contains("<"), link)
        XCTAssertTrue(EmailLink.isMessage(link))
    }

    /// Only the headers count. A message quoting another message's id in its body would otherwise
    /// link to the wrong email entirely.
    func testOnlyTheHeaderIsRead() throws {
        let link = try XCTUnwrap(EmailLink.fromEmail(sample))
        XCTAssertFalse(link.contains("not-this-one"), link)
    }

    func testAFileWithNoMessageIdLinksToNothing() {
        XCTAssertNil(EmailLink.fromEmail("Subject: no id here\n\nbody"))
        XCTAssertNil(EmailLink.fromEmail(""))
        // A malformed one is no id at all.
        XCTAssertNil(EmailLink.fromEmail("Message-ID: 123\n\nbody"))
    }

    func testAnEmailFileIsToldApartFromAnyOtherFile() {
        XCTAssertTrue(EmailLink.isEmailFile(URL(fileURLWithPath: "/tmp/The quote.eml")))
        XCTAssertTrue(EmailLink.isEmailFile(URL(fileURLWithPath: "/tmp/x.EML")))
        XCTAssertFalse(EmailLink.isEmailFile(URL(fileURLWithPath: "/tmp/report.pdf")))
    }

    // MARK: - A shared email becomes a strip that points back at it

    @MainActor
    func testAnEmailSharedInBecomesAStripWithALinkOnIt() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)

        let root = FileManager.default.temporaryDirectory.appending(path: "share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try ShareInbox.add(
            SharedEntry(
                kind: .strip,
                title: "The quote",
                notes: "",
                links: ["message:%3Cshared-1@mail.example.com%3E"]
            ),
            files: [],
            root: root
        )

        let filed = ShareInboxDrain.run(
            context: context, tasks: [], defaultPriority: .normal, root: root
        )
        XCTAssertEqual(filed.strips, 1)

        let strip = try XCTUnwrap(try context.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertEqual(strip.links.count, 1)
        XCTAssertEqual(strip.links.first?.url, "message:%3Cshared-1@mail.example.com%3E")
        // The subject is what a link to a message should be called.
        XCTAssertEqual(strip.links.first?.label, "The quote")
    }
}

/// The list of strips the share sheet offers, and what happens when something is filed onto one.
final class StripIndexTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var file: URL { root.appending(path: "strips.json") }

    private func entry(_ title: String, tags: [String] = [], done: Bool = false, order: Int = 0) -> StripIndexEntry {
        StripIndexEntry(id: UUID(), title: title, tags: tags, isDone: done, orderIndex: order)
    }

    func testTheListSurvivesTheTripThroughTheAppGroup() {
        let strips = [entry("Renew the passport", tags: ["HOME"], order: 1), entry("Quarterly report", order: 2)]
        StripIndex.write(strips, to: file)
        XCTAssertEqual(StripIndex.read(from: file), strips)
    }

    func testNoListAtAllIsAnEmptyList() {
        XCTAssertTrue(StripIndex.read(from: root.appending(path: "nothing.json")).isEmpty)
    }

    func testStripsAreFoundByNameOrTagAndKeepTheBoardsOrder() {
        let strips = [
            entry("Quarterly report", tags: ["WORK"], order: 2),
            entry("Renew the passport", tags: ["HOME"], order: 1),
            entry("Book the dentist", tags: ["HEALTH"], done: true, order: 0),
        ]
        XCTAssertEqual(StripIndex.matching("", in: strips).map(\.title),
                       ["Renew the passport", "Quarterly report", "Book the dentist"],
                       "board order, and anything finished last")
        XCTAssertEqual(StripIndex.matching("passport", in: strips).map(\.title), ["Renew the passport"])
        XCTAssertEqual(StripIndex.matching("work", in: strips).map(\.title), ["Quarterly report"], "by tag")
        XCTAssertTrue(StripIndex.matching("aubergine", in: strips).isEmpty)
    }

    func testOnlyTheStripsWorthFilingOntoAreOffered() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let live = TaskItem(title: "Live", orderIndex: 0)
        let archived = TaskItem(title: "Archived", orderIndex: 1)
        archived.isArchived = true
        context.insert(live)
        context.insert(archived)

        let offered = StripIndexEntry.board([live, archived])
        XCTAssertEqual(offered.map(\.title), ["Live"])
    }
}

final class ShareOntoAStripTests: XCTestCase {
    @MainActor
    func testAnEmailSharedOntoAStripJoinsItRatherThanMakingANewOne() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let strip = TaskItem(title: "Renew the passport", orderIndex: 0)
        context.insert(strip)

        let root = FileManager.default.temporaryDirectory.appending(path: "share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try ShareInbox.add(
            SharedEntry(
                kind: .strip,
                title: "Your appointment is confirmed",
                links: ["message:%3Cappt-9@mail.example.com%3E"],
                targetStripID: strip.id
            ),
            files: [],
            root: root
        )

        let filed = ShareInboxDrain.run(context: context, tasks: [strip], defaultPriority: .normal, root: root)
        XCTAssertEqual(filed.strips, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).count, 1, "no second strip")
        XCTAssertEqual(strip.links.first?.url, "message:%3Cappt-9@mail.example.com%3E")
        XCTAssertEqual(strip.links.first?.label, "Your appointment is confirmed")
        XCTAssertEqual(strip.actionLog.last?.text, "Linked an email")
    }

    /// The strip could have been deleted between sharing and opening the app. Nothing is lost:
    /// it becomes a strip of its own.
    @MainActor
    func testAStripThatHasGoneFallsBackToANewOne() throws {
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)

        let root = FileManager.default.temporaryDirectory.appending(path: "share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try ShareInbox.add(
            SharedEntry(
                kind: .strip, title: "Orphan",
                links: ["message:%3Cgone@mail.example.com%3E"], targetStripID: UUID()
            ),
            files: [], root: root
        )

        _ = ShareInboxDrain.run(context: context, tasks: [], defaultPriority: .normal, root: root)
        let strips = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(strips.map(\.title), ["Orphan"])
        XCTAssertEqual(strips.first?.links.count, 1)
    }
}
