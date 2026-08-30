import SwiftData
import XCTest
@testable import TaskStrips

/// The Mac has no canvas, so a sketch is something it carries rather than something it uses. That
/// makes this easy to get wrong quietly: everything looks right on the Mac while a round trip
/// through it strips the phone's sketches out.
final class SketchPassThroughTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
    }

    private func makeStore() -> AttachmentStore {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "sketch-\(UUID().uuidString)", directoryHint: .isDirectory)
        roots.append(root)
        return AttachmentStore(root: root)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, Note.self, StorageItem.self, Reminder.self, Credential.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func fixtureURL() throws -> URL {
        try XCTUnwrap(
            Bundle(for: BackupArchiveTests.self).url(forResource: "android_backup", withExtension: "zip")
        )
    }

    private func fixtureSummary() throws -> BackupImportSummary {
        try BackupImport.parse(
            manifest: try BackupArchive.manifestData(inArchive: Data(contentsOf: try fixtureURL()))
        )
    }

    // MARK: - The link

    func testAStripsSketchLinkSurvivesTheImport() throws {
        let context = try makeContext()
        BackupImport.apply(try fixtureSummary().tasks, mode: .add, existing: [], context: context)

        let strips = try context.fetch(FetchDescriptor<TaskItem>())
        let passport = try XCTUnwrap(strips.first { $0.title == "Renew passport" })
        XCTAssertEqual(passport.linkedSketchID, "note_1787000000000")
    }

    func testAStripWithNoSketchHasNoLink() throws {
        let summary = try fixtureSummary()
        let flights = try XCTUnwrap(summary.tasks.first { $0.title == "Book flights" })
        XCTAssertNil(flights.linkedSketchID)
    }

    /// The round trip that was quietly broken: the link has to come back out again.
    func testTheLinkIsWrittenBackOut() throws {
        var contents = BackupExport.Contents()
        let strip = TaskItem(title: "Renew passport", orderIndex: 0)
        strip.linkedSketchID = "note_1787000000000"
        contents.tasks = [strip, TaskItem(title: "No sketch", orderIndex: 1)]

        var included = 0
        let data = try BackupExport.manifestData(
            contents, credentialStore: CredentialStore(ephemeral: true), passwordsIncluded: &included
        )
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tasks = try XCTUnwrap(root["tasks"] as? [[String: Any]])

        XCTAssertEqual(tasks[0]["linkedSketchId"] as? String, "note_1787000000000")
        // Absent rather than null: Android reads it with a has/isNull check either way, and an
        // absent key is the honest way to say "this strip has no sketch".
        XCTAssertNil(tasks[1]["linkedSketchId"])
    }

    // MARK: - The files

    /// Sketch pages belong to no strip and are named by no manifest, so they're taken by where
    /// they sit. Nothing else in the import works that way.
    func testSketchFilesAreRestoredEvenThoughNothingAsksForThem() throws {
        let store = makeStore()
        let restored = try BackupImport.restoreMedia(
            fromArchiveAt: try fixtureURL(),
            paths: try fixtureSummary().referencedMediaPaths,
            into: store
        )
        XCTAssertTrue(restored.contains("sketches/note_1787000000000/page1.png"))
        XCTAssertTrue(store.relativePaths(under: "sketches/").contains("sketches/note_1787000000000/page1.png"))
    }

    func testCarryingCanBeTurnedOff() throws {
        let store = makeStore()
        let restored = try BackupImport.restoreMedia(
            fromArchiveAt: try fixtureURL(),
            paths: try fixtureSummary().referencedMediaPaths,
            into: store,
            carrying: []
        )
        XCTAssertFalse(restored.contains("sketches/note_1787000000000/page1.png"))
    }

    /// Nothing in the model mentions a sketch file, so the export has to go and look for them.
    func testTheExportFindsSketchFilesOnDiskRatherThanInTheModel() throws {
        let store = makeStore()
        try store.write(Data("page one".utf8), toRelativePath: "sketches/note_1/page1.png")
        try store.write(Data("page two".utf8), toRelativePath: "sketches/note_1/page2.png")
        try store.write(Data("elsewhere".utf8), toRelativePath: "images/unrelated.jpg")

        let paths = BackupExport.mediaPaths(BackupExport.Contents(), store: store)
        XCTAssertEqual(paths, ["sketches/note_1/page1.png", "sketches/note_1/page2.png"])
        // Without a store there's nowhere to look, and the model alone knows of no sketches.
        XCTAssertTrue(BackupExport.mediaPaths(BackupExport.Contents()).isEmpty)
    }

    /// The name the user gave a sketch and the day it was started live in dotfiles beside the
    /// pages. BackupHelper.kt takes every file inside a note folder without filtering, so an
    /// export that skipped hidden files would hand the phone back a sketch called "07 Mar 2026".
    func testTheNameAndTheCreatedStampGoWithTheSketch() throws {
        let store = makeStore()
        try store.write(Data("page one".utf8), toRelativePath: "sketches/note_1/page1.png")
        try store.write(Data("Kitchen plan".utf8), toRelativePath: "sketches/note_1/.name")
        try store.write(Data("1787000000000".utf8), toRelativePath: "sketches/note_1/.created")

        let paths = BackupExport.mediaPaths(BackupExport.Contents(), store: store)

        XCTAssertTrue(paths.contains("sketches/note_1/.name"), "got \(paths)")
        XCTAssertTrue(paths.contains("sketches/note_1/.created"), "got \(paths)")
    }

    /// A carried file is one the manifest never counted, so it must not push the progress bar
    /// past its own total — a bar that reads "4 of 3" is worse than no bar.
    func testCarriedFilesDoNotPushTheCountPastItsTotal() throws {
        var reports: [(Int, Int)] = []
        _ = try BackupImport.restoreMedia(
            fromArchiveAt: try fixtureURL(),
            paths: ["images/passport.jpg", "images/form.jpg"],
            into: makeStore(),
            progress: { reports.append(($0, $1)) }
        )

        XCTAssertTrue(reports.allSatisfy { $0.0 <= $0.1 }, "got \(reports)")
        XCTAssertEqual(reports.last?.1, 2)
    }

    /// The whole point, end to end: what a phone's backup carried has to still be there in one
    /// written on the Mac.
    func testASketchSurvivesAWholeRoundTrip() throws {
        let store = makeStore()
        let context = try makeContext()
        let summary = try fixtureSummary()

        try BackupImport.restoreMedia(
            fromArchiveAt: try fixtureURL(),
            paths: summary.referencedMediaPaths,
            into: store
        )
        BackupImport.apply(summary.tasks, mode: .add, existing: [], context: context)

        var contents = BackupExport.Contents()
        contents.tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let result = try BackupExport.archive(
            contents, store: store, credentialStore: CredentialStore(ephemeral: true)
        )

        let names = try BackupArchive.entries(inArchive: result.archive).map(\.name)
        XCTAssertTrue(
            names.contains("media/sketches/note_1787000000000/page1.png"),
            "the sketch page never made it back out: \(names)"
        )

        let reread = try BackupImport.parse(manifest: try BackupArchive.manifestData(inArchive: result.archive))
        let passport = try XCTUnwrap(reread.tasks.first { $0.title == "Renew passport" })
        XCTAssertEqual(passport.linkedSketchID, "note_1787000000000")
    }
}
