import SwiftData
import XCTest
@testable import TaskStrips

/// Searching what's inside the files, not only what somebody typed in a title.
final class DocumentIndexTests: XCTestCase {
    private func document(_ text: String, name: String = "invoice.pdf", path: String = "documents/1/invoice.pdf") -> IndexedDocument {
        IndexedDocument(path: path, name: name, text: DocumentIndex.folded(text), readAt: .now)
    }

    func testTheWordsAreSqueezedSoALineBreakCannotHideThem() {
        let folded = DocumentIndex.folded("Invoice\n  4471\tKFAS\n\nAmount")
        XCTAssertEqual(folded, "invoice 4471 kfas amount")
    }

    func testAReferenceNumberFindsItsDocument() {
        let invoice = document("ACME Trading\nInvoice 4471\nAmount due: KD 412.500")
        XCTAssertTrue(DocumentIndex.matches(invoice, query: "4471"))
        XCTAssertTrue(DocumentIndex.matches(invoice, query: "412.500"))
        XCTAssertFalse(DocumentIndex.matches(invoice, query: "9999"))
    }

    /// Every word has to appear, in any order — that's what makes two words a narrower search
    /// rather than a broader one.
    func testEveryWordOfTheSearchHasToBeThere() {
        let invoice = document("ACME Trading\nInvoice 4471 for KFAS")
        XCTAssertTrue(DocumentIndex.matches(invoice, query: "invoice kfas"))
        XCTAssertTrue(DocumentIndex.matches(invoice, query: "kfas invoice"))
        XCTAssertFalse(DocumentIndex.matches(invoice, query: "invoice mosa"))
    }

    func testCapitalsDoNotMatter() {
        XCTAssertTrue(DocumentIndex.matches(document("Tender Documents"), query: "TENDER"))
    }

    func testArabicIsSearchedTheSameWay() {
        let letter = document("تجديد رخصة النشاط\nرقم الطلب 4471")
        XCTAssertTrue(DocumentIndex.matches(letter, query: "تجديد"))
        XCTAssertTrue(DocumentIndex.matches(letter, query: "رخصة 4471"))
    }

    /// Two letters would return the whole board, which is not a search.
    func testAVeryShortSearchIsNotWorthRunning() {
        XCTAssertFalse(DocumentIndex.isWorthSearching("ab"))
        XCTAssertFalse(DocumentIndex.isWorthSearching("  "))
        XCTAssertTrue(DocumentIndex.isWorthSearching("4471"))
    }

    func testTheFileThatMatchedIsNamedSoTheBoardCanSayWhy() {
        let index = [
            "documents/1/invoice.pdf": document("Invoice 4471", name: "invoice.pdf"),
            "documents/2/notes.pdf": document("Minutes of the meeting", name: "notes.pdf", path: "documents/2/notes.pdf"),
        ]
        let found = DocumentIndex.matching(
            paths: ["documents/1/invoice.pdf", "documents/2/notes.pdf"], query: "4471", in: index
        )
        XCTAssertEqual(found.map(\.name), ["invoice.pdf"])
    }

    func testOnlyTheFirstPagesAreKept() {
        let huge = String(repeating: "word ", count: 20_000)
        XCTAssertLessThanOrEqual(DocumentIndex.folded(huge).count, DocumentIndex.charactersPerDocument)
    }

    // MARK: - Where it's kept

    func testTheIndexSurvivesBeingWrittenAndReadBack() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DocumentIndexStore(url: url)

        let invoice = document("Invoice 4471")
        store.write([invoice.path: invoice])
        XCTAssertEqual(store.read()[invoice.path], invoice)
    }

    func testAnIndexThatIsNotThereYetIsSimplyEmpty() {
        let store = DocumentIndexStore(url: FileManager.default.temporaryDirectory.appending(path: "no-such.json"))
        XCTAssertTrue(store.read().isEmpty)
    }

    /// Files that leave the board take their words with them.
    func testWordsOfDeletedFilesArePruned() {
        let store = DocumentIndexStore(url: FileManager.default.temporaryDirectory.appending(path: "x.json"))
        let kept = document("Invoice 4471")
        let gone = document("Old thing", name: "old.pdf", path: "documents/9/old.pdf")
        let pruned = store.pruned([kept.path: kept, gone.path: gone], keeping: [kept.path])
        XCTAssertEqual(Array(pruned.keys), [kept.path])
    }
}

/// The search itself, once a strip's files have been read.
@MainActor
final class DocumentSearchTests: XCTestCase {
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let container = try ModelContainer(
            for: Schema(BoardSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        context = ModelContext(container)
    }

    func testAStripIsFoundByWhatIsInsideItsFile() {
        let strip = TaskItem(title: "PaymentGateway", orderIndex: 0)
        context.insert(strip)
        let other = TaskItem(title: "Something else", orderIndex: 1)
        context.insert(other)

        var filter = BoardFilter()
        filter.search = "4471"
        // Nothing in the titles, notes or tags says 4471.
        XCTAssertTrue(filter.apply(to: [strip, other]).isEmpty)
        // With the file's words behind it, the strip turns up.
        XCTAssertEqual(
            filter.apply(to: [strip, other], foundInFiles: [strip.id]).map(\.title),
            ["PaymentGateway"]
        )
    }

    /// A search that matches a title still works when nothing was found in any file.
    func testTheOrdinarySearchIsUnchanged() {
        let strip = TaskItem(title: "Tender documents", orderIndex: 0)
        context.insert(strip)
        var filter = BoardFilter()
        filter.search = "tender"
        XCTAssertEqual(filter.apply(to: [strip]).count, 1)
    }
}
