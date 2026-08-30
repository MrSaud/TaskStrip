import XCTest
@testable import TaskStrips

/// The counting behind the progress bar. The bar itself is a view; what's worth pinning is that
/// the numbers reaching it are the ones a person would expect.
final class BackupProgressTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
    }

    private func makeStore() -> AttachmentStore {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "progress-\(UUID().uuidString)", directoryHint: .isDirectory)
        roots.append(root)
        return AttachmentStore(root: root)
    }

    // MARK: - The value on screen

    func testAFractionOnlyExistsOnceThereIsSomethingToCount() {
        XCTAssertNil(BackupProgress(title: "t", step: "s").fraction)
        XCTAssertNil(BackupProgress(title: "t", step: "s", completed: 0, total: 0).fraction)
        XCTAssertEqual(BackupProgress(title: "t", step: "s", completed: 1, total: 4).fraction, 0.25)
        XCTAssertEqual(BackupProgress(title: "t", step: "s", completed: 4, total: 4).fraction, 1)
    }

    // MARK: - Export

    func testPackingReportsEveryFileAndStartsAtZero() throws {
        let store = makeStore()
        try store.write(Data("a".utf8), toRelativePath: "images/a.jpg")
        try store.write(Data("b".utf8), toRelativePath: "images/b.jpg")

        var reports: [(Int, Int)] = []
        _ = BackupExport.archive(
            manifest: Data(#"{"tasks":[]}"#.utf8),
            mediaPaths: ["images/a.jpg", "images/b.jpg"],
            store: store,
            progress: { reports.append(($0, $1)) }
        )

        // Zero first, so the bar appears before the first file rather than after it.
        XCTAssertEqual(reports.first?.0, 0)
        XCTAssertEqual(reports.map(\.0), [0, 1, 2])
        XCTAssertTrue(reports.allSatisfy { $0.1 == 2 })
    }

    /// A file the store can't produce still counts as dealt with — otherwise the bar stalls short
    /// of the end and the export looks stuck at the moment it finishes.
    func testAMissingFileStillAdvancesTheCount() {
        var reports: [(Int, Int)] = []
        let result = BackupExport.archive(
            manifest: Data(#"{"tasks":[]}"#.utf8),
            mediaPaths: ["images/gone.jpg"],
            store: makeStore(),
            progress: { reports.append(($0, $1)) }
        )

        XCTAssertEqual(result.filesMissing, 1)
        XCTAssertEqual(reports.last?.0, 1)
        XCTAssertEqual(reports.last?.1, 1)
    }

    func testAnExportWithNoFilesReportsNothingToDoRatherThanNothingAtAll() {
        var reports: [(Int, Int)] = []
        _ = BackupExport.archive(
            manifest: Data(#"{"tasks":[]}"#.utf8),
            mediaPaths: [],
            store: makeStore(),
            progress: { reports.append(($0, $1)) }
        )
        XCTAssertEqual(reports.map(\.1), [0])
    }

    /// Splitting the manifest from the packing is what lets the slow half run off the main
    /// thread; both halves together still have to produce what the one-call version does.
    func testTheSplitBuildMatchesTheWholeOne() throws {
        let store = makeStore()
        try store.write(Data("a".utf8), toRelativePath: "images/a.jpg")

        var contents = BackupExport.Contents()
        let strip = TaskItem(title: "With a file", orderIndex: 0)
        strip.attachments = [TaskAttachment(kind: .image, path: "images/a.jpg", name: "a.jpg")]
        contents.tasks = [strip]

        let credentials = CredentialStore(ephemeral: true)
        var included = 0
        let manifest = try BackupExport.manifestData(contents, credentialStore: credentials, passwordsIncluded: &included)
        let split = BackupExport.archive(manifest: manifest, mediaPaths: BackupExport.mediaPaths(contents), store: store)
        let whole = try BackupExport.archive(contents, store: store, credentialStore: credentials)

        XCTAssertEqual(split.fileCount, whole.fileCount)
        XCTAssertEqual(split.filesMissing, whole.filesMissing)
        XCTAssertEqual(split.archive, whole.archive)
    }

    // MARK: - Import

    func testRestoringReportsAgainstWhatTheBackupClaims() throws {
        let source = try XCTUnwrap(
            Bundle(for: BackupArchiveTests.self).url(forResource: "android_backup", withExtension: "zip")
        )
        var reports: [(Int, Int)] = []
        let restored = try BackupImport.restoreMedia(
            fromArchiveAt: source,
            // Two of these are in the archive; documents/checklist.pdf is deliberately not.
            paths: ["images/passport.jpg", "images/form.jpg", "documents/checklist.pdf"],
            into: makeStore(),
            progress: { reports.append(($0, $1)) }
        )

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(reports.first?.0, 0)
        // Counted against what was asked for, not what turned up, so the total doesn't move
        // halfway through.
        XCTAssertTrue(reports.allSatisfy { $0.1 == 3 })
        XCTAssertEqual(reports.last?.0, 2)
    }

    func testRestoringNothingReportsNothing() throws {
        let source = try XCTUnwrap(
            Bundle(for: BackupArchiveTests.self).url(forResource: "android_backup", withExtension: "zip")
        )
        var reports: [(Int, Int)] = []
        _ = try BackupImport.restoreMedia(fromArchiveAt: source, paths: [], into: makeStore(),
                                          progress: { reports.append(($0, $1)) })
        XCTAssertTrue(reports.isEmpty)
    }
}
