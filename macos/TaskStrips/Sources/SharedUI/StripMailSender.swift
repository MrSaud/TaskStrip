#if os(macOS)
import AppKit
#else
import MessageUI
import UIKit
#endif
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Hands a strip to whatever writes email on this device.
///
/// A Mac has a share service that opens a Mail draft with attachments in it; a phone has the mail
/// composer. Neither exists if nobody has set up mail, so both fall back to a mailto: link, which
/// every device knows what to do with — it just can't carry files.
@MainActor
enum StripMailSender {
    struct Draft {
        var subject: String
        var body: String
        var attachments: [URL]
    }

    /// The draft for a strip, with the files that fit and a note about the ones that didn't.
    static func draft(for task: TaskItem, files: [URL]) -> Draft {
        let sizes = files.map { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) as? Int ?? 0
        }
        let plan = StripMail.attachmentsThatFit(sizes)
        var body = StripMail.body(for: task)
        if let note = StripMail.note(forFilesLeftBehind: plan.left.map { files[$0].lastPathComponent }) {
            body += note
        }
        return Draft(
            subject: StripMail.subject(for: task),
            body: body,
            attachments: plan.sent.map { files[$0] }
        )
    }

    #if os(macOS)
    /// Opens a Mail draft. The sharing service takes the attachments with it; a mailto: can't, so
    /// that's only reached when there's no mail client at all.
    static func send(_ draft: Draft) {
        guard let service = NSSharingService(named: .composeEmail) else {
            openMailto(draft)
            return
        }
        service.subject = draft.subject
        let items: [Any] = [draft.body] + draft.attachments
        guard service.canPerform(withItems: items) else {
            openMailto(draft)
            return
        }
        service.perform(withItems: items)
    }

    private static func openMailto(_ draft: Draft) {
        guard let url = StripMail.mailtoURL(subject: draft.subject, body: draft.body) else { return }
        NSWorkspace.shared.open(url)
    }
    #endif
}

#if os(iOS)
/// The system mail composer, for the strip being sent.
struct StripMailComposer: UIViewControllerRepresentable {
    let draft: StripMailSender.Draft
    let onFinish: () -> Void

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setSubject(draft.subject)
        composer.setMessageBody(draft.body, isHTML: false)
        for file in draft.attachments {
            guard let data = try? Data(contentsOf: file) else { continue }
            composer.addAttachmentData(
                data,
                mimeType: UTType(filenameExtension: file.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream",
                fileName: file.lastPathComponent
            )
        }
        return composer
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish()
        }
    }
}
#endif
