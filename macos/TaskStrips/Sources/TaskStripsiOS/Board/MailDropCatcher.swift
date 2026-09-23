import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Catches a message dragged onto a strip, on an iPad.
///
/// The same job as the Mac's catcher and for the same reason: Mail hands over several things at
/// once and the URL among them is the one worth keeping. UIKit's drop interaction is used rather
/// than SwiftUI's `dropDestination` so the item is read as it arrives instead of being resolved
/// into whatever SwiftUI prefers — on the Mac that meant a copy of the email instead of a link
/// to it.
///
/// An iPhone can't take a drag from another app at all, so there it simply never fires; sharing
/// the message into the app is the way in there.
struct MailDropCatcher: UIViewRepresentable {
    /// The message link and whatever the drag called it.
    let onEmail: (URL, String) -> Void
    let onFiles: ([URL]) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        // Drops pass through to it; taps and drags to reorder don't stop here.
        view.isUserInteractionEnabled = true
        view.addInteraction(UIDropInteraction(delegate: context.coordinator))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onEmail = onEmail
        context.coordinator.onFiles = onFiles
    }

    func makeCoordinator() -> Coordinator { Coordinator(onEmail: onEmail, onFiles: onFiles) }

    final class Coordinator: NSObject, UIDropInteractionDelegate {
        var onEmail: (URL, String) -> Void
        var onFiles: ([URL]) -> Void

        init(onEmail: @escaping (URL, String) -> Void, onFiles: @escaping ([URL]) -> Void) {
            self.onEmail = onEmail
            self.onFiles = onFiles
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
            session.canLoadObjects(ofClass: URL.self)
                || session.hasItemsConforming(toTypeIdentifiers: [UTType.data.identifier])
        }

        func dropInteraction(
            _ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession
        ) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
            for item in session.items {
                let name = item.itemProvider.suggestedName ?? ""
                if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    _ = item.itemProvider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                        guard let self, let url else { return }
                        if EmailLink.isMessage(url.absoluteString) {
                            Task { @MainActor in self.onEmail(url, name) }
                            return
                        }
                        guard url.isFileURL else { return }
                        Task { @MainActor in self.onFiles([url]) }
                    }
                    continue
                }
                // Everything else worth having is a file: copied out of the provider first,
                // because what it hands over is gone the moment the drop finishes.
                item.itemProvider.loadFileRepresentation(
                    forTypeIdentifier: UTType.data.identifier
                ) { [weak self] url, _ in
                    guard let self, let url else { return }
                    let copy = FileManager.default.temporaryDirectory
                        .appending(path: name.isEmpty ? url.lastPathComponent : name)
                    try? FileManager.default.removeItem(at: copy)
                    guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return }
                    Task { @MainActor in self.onFiles([copy]) }
                }
            }
        }
    }
}
