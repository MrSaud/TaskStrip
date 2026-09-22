import XCTest
@testable import TaskStrips

final class StorageLibraryTests: XCTestCase {
    private func item(
        _ name: String,
        type: StorageItemType = .document,
        tag: String = "",
        emoji: String = "",
        createdAt: Date = .now
    ) -> StorageItem {
        StorageItem(
            name: name,
            path: "documents/\(name)",
            type: type,
            tag: tag,
            tagEmoji: emoji,
            createdAt: createdAt
        )
    }

    // MARK: - Quick Look

    func testSpaceOpensWhateverIsSelected() {
        let picked = item("invoice.pdf")

        XCTAssertEqual(
            StorageLibrary.quickLookAction(selection: picked.id, in: [picked], isPreviewing: false),
            .open(picked.id)
        )
    }

    /// Space is a toggle in Finder, and that's the half people rely on: look, then stop looking,
    /// without reaching for the mouse.
    func testSpaceAgainClosesIt() {
        let picked = item("invoice.pdf")

        XCTAssertEqual(
            StorageLibrary.quickLookAction(selection: picked.id, in: [picked], isPreviewing: true),
            .close
        )
    }

    func testSpaceWithNothingSelectedDoesNothing() {
        XCTAssertEqual(
            StorageLibrary.quickLookAction(selection: nil, in: [item("invoice.pdf")], isPreviewing: false),
            .nothing
        )
    }

    /// A selection outlives the row it names when the file is deleted or the tag filter moves on,
    /// and previewing something no longer on screen would be a small mystery.
    func testSpaceIgnoresASelectionThatIsNoLongerOnScreen() {
        let gone = item("deleted.pdf")
        let shown = item("invoice.pdf")

        XCTAssertEqual(
            StorageLibrary.quickLookAction(selection: gone.id, in: [shown], isPreviewing: false),
            .nothing
        )
    }

    /// Closing wins over the stale-selection check: a panel that's up has to be closable even if
    /// what it's showing has just been filtered away underneath it.
    func testAnOpenPreviewStillClosesWhenItsRowHasGone() {
        let gone = item("deleted.pdf")

        XCTAssertEqual(
            StorageLibrary.quickLookAction(selection: gone.id, in: [], isPreviewing: true),
            .close
        )
    }

    // MARK: - Which shelf a file lands on

    func testAReportedImageTypeWins() {
        XCTAssertEqual(StorageItemType.inferred(mimeType: "image/heic", name: "scan.bin"), .image)
        XCTAssertEqual(StorageItemType.inferred(mimeType: "video/quicktime", name: "clip.bin"), .video)
        XCTAssertEqual(StorageItemType.inferred(mimeType: "application/pdf", name: "invoice"), .document)
    }

    /// Share sheets report exactly these for ordinary photos, and a photo filed under Documents
    /// never turns up where the user looks for it.
    func testAUselessMimeTypeFallsBackToTheExtension() {
        for useless in ["", "   ", "*/*", "application/octet-stream", "APPLICATION/OCTET-STREAM"] {
            XCTAssertEqual(
                StorageItemType.inferred(mimeType: useless, name: "holiday.jpg"),
                .image,
                "\"\(useless)\" should not decide the category"
            )
        }
        XCTAssertEqual(StorageItemType.inferred(mimeType: nil, name: "trip.mov"), .video)
    }

    func testAnythingUnrecognisedIsADocument() {
        XCTAssertEqual(StorageItemType.inferred(mimeType: nil, name: "notes.xyz"), .document)
        XCTAssertEqual(StorageItemType.inferred(mimeType: nil, name: "no-extension"), .document)
    }

    /// The library has three shelves, not four — Android's picker files anything that isn't an
    /// image or a video as a document, audio included.
    func testAudioIsFiledAsADocument() {
        XCTAssertEqual(StorageItemType.inferred(mimeType: nil, name: "memo.m4a"), .document)
    }

    func testEachTypeKeepsTheFolderStripsUse() {
        XCTAssertEqual(StorageItemType.image.attachmentKind, .image)
        XCTAssertEqual(StorageItemType.video.attachmentKind, .video)
        XCTAssertEqual(StorageItemType.document.attachmentKind, .document)
    }

    // MARK: - Tags

    func testAvailableTagsSkipTheUntagged() {
        let items = [item("a", tag: "Receipt"), item("b"), item("c", tag: "Invoice")]
        XCTAssertEqual(StorageLibrary.availableTags(in: items), ["Invoice", "Receipt"])
    }

    /// Two items sharing a tag with different emoji shouldn't put the tag in the menu twice.
    func testATagShownTwiceKeepsTheLastEmoji() {
        let items = [item("a", tag: "Travel", emoji: "🧳"), item("b", tag: "Travel", emoji: "✈️")]
        XCTAssertEqual(StorageLibrary.availableTags(in: items), ["Travel"])
        XCTAssertEqual(StorageLibrary.tagEmojis(in: items)["Travel"], "✈️")
    }

    func testFilteringKeepsOnlyThatTag() {
        let items = [item("a", tag: "Receipt"), item("b", tag: "Invoice"), item("c")]
        XCTAssertEqual(StorageLibrary.visible(items, tag: "Receipt").map(\.name), ["a"])
    }

    /// Otherwise deleting the last Receipt leaves the library showing nothing, with no clue why.
    func testAFilterWhoseTagIsGoneStopsApplying() {
        let items = [item("a", tag: "Invoice")]
        XCTAssertNil(StorageLibrary.activeTag("Receipt", in: items))
        XCTAssertEqual(StorageLibrary.visible(items, tag: "Receipt").map(\.name), ["a"])
    }

    func testNoFilterShowsEverything() {
        let items = [item("a", tag: "Receipt"), item("b")]
        XCTAssertEqual(StorageLibrary.visible(items, tag: nil).count, 2)
    }

    func testTheTagLabelPairsTheEmojiWithTheTag() {
        XCTAssertEqual(item("a", tag: "Receipt", emoji: "💳").tagLabel, "💳 Receipt")
        // An emoji is optional; a tag without one still reads fine.
        XCTAssertEqual(item("a", tag: "Receipt").tagLabel, "Receipt")
        XCTAssertEqual(item("a").tagLabel, "")
    }

    // MARK: - Ordering and sizes

    func testNewestFileComesFirst() {
        let older = item("older", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = item("newer", createdAt: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(StorageLibrary.sorted([older, newer]).map(\.name), ["newer", "older"])
    }

    func testSectionsSplitByType() {
        let items = [item("a", type: .image), item("b", type: .document), item("c", type: .image)]
        XCTAssertEqual(StorageLibrary.items(items, ofType: .image).map(\.name), ["a", "c"])
        XCTAssertTrue(StorageLibrary.items(items, ofType: .video).isEmpty)
    }

    /// A row imported from a backup can have no size recorded, and "Zero KB" beside a file that
    /// plainly exists reads as a bug.
    func testAnUnknownSizeShowsNothingAtAll() {
        XCTAssertEqual(StorageLibrary.readableSize(0), "")
        XCTAssertFalse(StorageLibrary.readableSize(20_480).isEmpty)
    }
}
