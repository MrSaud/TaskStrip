import AppKit
import SwiftUI

/// Catches a message dragged out of Mail, in AppKit rather than SwiftUI.
///
/// SwiftUI's own drop wouldn't do it. Mail puts several things on the pasteboard at once — a
/// `message:` URL, the subject beside it, and a promise of the .eml — and SwiftUI picks whichever
/// it likes, which meant resolving the promise and quietly attaching a copy of the email instead
/// of linking the message. Read straight from the dragging pasteboard there's no guessing: the
/// link is the link, the subject is the subject, and a file is only a file when there's nothing
/// better on offer.
///
/// It sits behind the row rather than over it, so it catches drags without swallowing clicks.
struct MailDropCatcher: NSViewRepresentable {
    /// The message link and the subject Mail sent with it.
    let onEmail: (URL, String) -> Void
    let onFiles: ([URL]) -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.onEmail = onEmail
        view.onFiles = onFiles
        return view
    }

    func updateNSView(_ view: DropView, context: Context) {
        view.onEmail = onEmail
        view.onFiles = onFiles
    }

    final class DropView: NSView {
        var onEmail: (URL, String) -> Void = { _, _ in }
        var onFiles: ([URL]) -> Void = { _ in }

        private static let urlName = NSPasteboard.PasteboardType("public.url-name")
        private var isTargeted = false {
            didSet { if isTargeted != oldValue { needsDisplay = true } }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.URL, .fileURL, .string])
        }

        required init?(coder: NSCoder) { fatalError("Made in code, never from a storyboard.") }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let operation = accepts(sender.draggingPasteboard) ? NSDragOperation.copy : []
            isTargeted = !operation.isEmpty
            return operation
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            accepts(sender.draggingPasteboard) ? .copy : []
        }

        override func draggingExited(_ sender: NSDraggingInfo?) { isTargeted = false }
        override func draggingEnded(_ sender: NSDraggingInfo) { isTargeted = false }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            isTargeted = false
            let pasteboard = sender.draggingPasteboard

            if let link = messageLink(on: pasteboard) {
                onEmail(link, pasteboard.string(forType: Self.urlName) ?? "")
                return true
            }
            let files = (pasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
            ) as? [URL]) ?? []
            guard !files.isEmpty else { return false }
            onFiles(files)
            return true
        }

        /// The message: URL among whatever was dragged, however the pasteboard is carrying it.
        private func messageLink(on pasteboard: NSPasteboard) -> URL? {
            var candidates: [String] = []
            if let text = pasteboard.string(forType: .URL) { candidates.append(text) }
            if let text = pasteboard.string(forType: .string) { candidates.append(text) }
            for item in pasteboard.pasteboardItems ?? [] {
                if let text = item.string(forType: .URL) { candidates.append(text) }
            }
            return candidates.lazy
                .filter { EmailLink.isMessage($0) }
                .compactMap { URL(string: $0) }
                .first
        }

        private func accepts(_ pasteboard: NSPasteboard) -> Bool {
            if messageLink(on: pasteboard) != nil { return true }
            return pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        }

        /// Says the row will take it, the way a drop target should.
        override func draw(_ dirtyRect: NSRect) {
            guard isTargeted else { return }
            NSColor(srgbRed: 0xE0 / 255, green: 0xA6 / 255, blue: 0x3A / 255, alpha: 0.9).setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
            path.lineWidth = 3
            path.stroke()
        }
    }
}
