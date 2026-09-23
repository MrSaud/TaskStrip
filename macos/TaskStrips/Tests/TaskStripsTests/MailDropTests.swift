import AppKit
import XCTest
@testable import TaskStrips

/// The destination side of dragging an email out of Mail, driven by the pasteboard Mail actually
/// produces: a `message:` URL with one colon and no slashes, the subject beside it as
/// `public.url-name`, the same text as plain text, and a promise of the .eml on a second item.
final class MailDropTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("TaskStripsMailDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDownWithError() throws {
        pasteboard.releaseGlobally()
    }

    private func mailDrag(
        link: String = "message:%3C1372329598.91023@mail.example.com%3E",
        subject: String = "Your Yahoo verification code is 267388"
    ) {
        let message = NSPasteboardItem()
        message.setString(link, forType: .URL)
        message.setString(subject, forType: NSPasteboard.PasteboardType("public.url-name"))
        message.setString(subject, forType: .string)

        // Mail's second item: the promise of the .eml, which carries no usable value here.
        let promise = NSPasteboardItem()
        promise.setString("\(subject).eml", forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-suggested-file-name"))

        pasteboard.writeObjects([message, promise])
    }

    func testAMessageDraggedFromMailIsLinkedWithItsSubject() throws {
        mailDrag()
        var linked: (url: URL, subject: String)?
        let view = MailDropCatcher.DropView(frame: .zero)
        view.onEmail = { linked = ($0, $1) }
        view.onFiles = { _ in XCTFail("a message is not a file") }

        let info = StubDraggingInfo(pasteboard: pasteboard)
        XCTAssertEqual(view.draggingEntered(info), .copy, "the row has to say it will take it")
        XCTAssertTrue(view.performDragOperation(info))

        let result = try XCTUnwrap(linked)
        XCTAssertEqual(result.url.absoluteString, "message:%3C1372329598.91023@mail.example.com%3E")
        XCTAssertEqual(result.subject, "Your Yahoo verification code is 267388")
    }

    func testAFileIsStillAFile() throws {
        let file = URL(fileURLWithPath: "/tmp/report.pdf")
        pasteboard.writeObjects([file as NSURL])

        var dropped: [URL] = []
        let view = MailDropCatcher.DropView(frame: .zero)
        view.onEmail = { _, _ in XCTFail("a file is not a message") }
        view.onFiles = { dropped = $0 }

        let info = StubDraggingInfo(pasteboard: pasteboard)
        XCTAssertEqual(view.draggingEntered(info), .copy)
        XCTAssertTrue(view.performDragOperation(info))
        XCTAssertEqual(dropped.map(\.lastPathComponent), ["report.pdf"])
    }

    func testSomethingThatIsNeitherIsRefused() {
        pasteboard.clearContents()
        pasteboard.setString("just some words", forType: .string)

        let view = MailDropCatcher.DropView(frame: .zero)
        view.onEmail = { _, _ in XCTFail("nothing to link") }
        view.onFiles = { _ in XCTFail("nothing to attach") }

        let info = StubDraggingInfo(pasteboard: pasteboard)
        XCTAssertEqual(view.draggingEntered(info), [])
        XCTAssertFalse(view.performDragOperation(info))
    }
}

/// Enough of NSDraggingInfo to hand a pasteboard to a drop.
private final class StubDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    init(pasteboard: NSPasteboard) { self.draggingPasteboard = pasteboard }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation {
        get { .default }
        set {}
    }
    var animatesToDestination: Bool {
        get { false }
        set {}
    }
    var numberOfValidItemsForDrop: Int {
        get { 1 }
        set {}
    }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    var draggedImage: NSImage? { nil }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(
        options: NSDraggingItemEnumerationOptions,
        for view: NSView?,
        classes: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    func resetSpringLoading() {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
}
