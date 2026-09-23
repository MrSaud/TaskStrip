import XCTest
@testable import TaskStrips

final class SketchPaperTests: XCTestCase {
    func testPlainPapersAreRuledByNothing() {
        for paper in [SketchPaper.clean, .mint, .sky] {
            XCTAssertEqual(paper.ruling, .none, "\(paper)")
            XCTAssertTrue(paper.lineOffsets(forHeight: 1000).isEmpty, "\(paper)")
            let grid = paper.gridOffsets(forSize: CGSize(width: 800, height: 1000))
            XCTAssertTrue(grid.columns.isEmpty && grid.rows.isEmpty, "\(paper)")
        }
    }

    func testLinedPaperRulesEverySpacingAndNeverOnTheEdge() {
        let offsets = SketchPaper.lined.lineOffsets(forHeight: 100)
        XCTAssertEqual(offsets, [30, 60, 90])
        XCTAssertFalse(offsets.contains(0))
        XCTAssertFalse(offsets.contains(100))
    }

    func testGridAndDotsRuleBothWays() {
        let squares = SketchPaper.grid.gridOffsets(forSize: CGSize(width: 100, height: 60))
        XCTAssertEqual(squares.columns, [24, 48, 72, 96])
        XCTAssertEqual(squares.rows, [24, 48])

        let dots = SketchPaper.dots.gridOffsets(forSize: CGSize(width: 50, height: 50))
        XCTAssertEqual(dots.columns, [22, 44])
        XCTAssertEqual(dots.rows, [22, 44])
    }

    func testAPageWithNoSizeIsRuledByNothing() {
        XCTAssertTrue(SketchPaper.lined.lineOffsets(forHeight: 0).isEmpty)
        let grid = SketchPaper.grid.gridOffsets(forSize: .zero)
        XCTAssertTrue(grid.columns.isEmpty && grid.rows.isEmpty)
    }

    func testTintedPapersAreTintedAndPlainOnesAreNot() {
        XCTAssertNil(SketchPaper.lined.tint)
        XCTAssertNotNil(SketchPaper.legal.tint)
    }

    /// The tint multiplies over a page that already has ink on it, so a dark one would take the
    /// strokes with it. Every tint has to stay light enough to leave them readable.
    func testEveryTintIsLightEnoughToLeaveTheInkReadable() {
        for paper in SketchPaper.allCases {
            guard let tint = paper.tint else { continue }
            let darkest = min(tint.red, tint.green, tint.blue)
            XCTAssertGreaterThan(darkest, 0.5, "\(paper) would swallow the ink")
        }
    }

    /// The name is what's written beside the pages and sent to iCloud, so it has to stay put.
    func testNamesAreStable() {
        XCTAssertEqual(
            SketchPaper.allCases.map(\.rawValue),
            ["clean", "lined", "grid", "dots", "legal", "mint", "sky", "graph"]
        )
    }
}

final class SketchPaperStoreTests: XCTestCase {
    private var store: SketchStore!
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "paper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = SketchStore(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeNote(_ id: String) throws {
        let png = SketchRenderer.png(
            size: CGSize(width: 10, height: 10),
            strokes: [SketchStroke(points: [.zero, CGPoint(x: 5, y: 5)], ink: .ink, width: 2)]
        )
        try store.write(XCTUnwrap(png), to: store.nextPageURL(of: id))
    }

    func testANoteRemembersItsPaperAndGivesItBackWithTheNote() throws {
        try makeNote("n1")
        XCTAssertEqual(store.paper(of: "n1"), .clean)

        store.setPaper(.legal, of: "n1")
        XCTAssertEqual(store.paper(of: "n1"), .legal)
        XCTAssertEqual(store.note("n1")?.paper, .legal)

        // Back to plain, and the file goes with it.
        store.setPaper(.clean, of: "n1")
        XCTAssertEqual(store.paper(of: "n1"), .clean)
    }

    /// Picking paper for a note that was never drawn on must not conjure a folder for it.
    func testPaperForANoteThatDoesNotExistYetLeavesNothingBehind() {
        store.setPaper(.grid, of: "ghost")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(of: "ghost").path))
        XCTAssertEqual(store.paper(of: "ghost"), .clean)
    }

    /// The hidden file sits beside the pages, so nothing that counts pages may see it.
    func testThePaperFileIsNotAPage() throws {
        try makeNote("n2")
        store.setPaper(.dots, of: "n2")
        XCTAssertEqual(store.pages(of: "n2").count, 1)
        XCTAssertEqual(store.note("n2")?.pageCount, 1)
    }
}
