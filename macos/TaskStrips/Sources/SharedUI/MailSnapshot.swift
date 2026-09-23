import SwiftUI

/// A message as a picture, for marking up.
///
/// Not a screen grab — the message drawn again at a size worth annotating, on the sketch's own
/// paper so a highlighter over it looks like a highlighter over paper rather than over a website.
/// What gets drawn is what's on screen: who wrote, what about, when, and the words.
enum MailSnapshot {
    /// The width the picture is drawn at. Wide enough for ordinary paragraphs not to wrap every
    /// few words once it's scaled onto a page.
    static let width: CGFloat = 900

    /// How much of a message goes into the picture.
    ///
    /// A page you can mark on is a page you can read, and a screenshot of forty thousand
    /// characters scaled onto a canvas is a grey smear. Long messages are cut, and say so.
    static let characterLimit = 2_600

    static func shown(_ text: String, limit: Int = characterLimit) -> (text: String, wasCut: Bool) {
        guard text.count > limit else { return (text, false) }
        // Cut at a line break rather than mid-sentence where there's one close enough.
        let cut = String(text.prefix(limit))
        if let lastBreak = cut.lastIndex(of: "\n"), cut.distance(from: lastBreak, to: cut.endIndex) < 400 {
            return (String(cut[..<lastBreak]), true)
        }
        return (cut, true)
    }

    @MainActor
    static func image(of message: MailMessage, body: MailBody?) -> CGImage? {
        let renderer = ImageRenderer(content: page(message: message, body: body))
        // Twice the size, so the picture still holds up when it's scaled onto a page and then
        // zoomed into with a pencil.
        renderer.scale = 2
        return renderer.cgImage
    }

    private static func page(message: MailMessage, body: MailBody?) -> some View {
        let shown = shown(body?.text ?? "")
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(message.subject)
                    .font(.system(size: 30, weight: .semibold))
                Text(message.sender)
                    .font(.system(size: 19, design: .monospaced))
                HStack(spacing: 8) {
                    Text(message.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    if let account = message.account, !account.isEmpty {
                        Text("· \(account)")
                    }
                }
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(.black.opacity(0.15))
                .frame(height: 1)

            Text(shown.text.isEmpty ? "(no text — see the attachments)" : shown.text)
                .font(.system(size: 21))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            if shown.wasCut {
                Text("… message continues")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }

            if let attachments = body?.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(attachments) { attachment in
                        Text("\u{1F4CE} \(attachment.name) · \(attachment.size)")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(32)
        .frame(width: width, alignment: .topLeading)
        // The page's own colours, not the app's: this is about to become part of a drawing, and a
        // dark rectangle dropped on cream paper looks like a mistake.
        .foregroundStyle(.black)
        .background(TaskStripTheme.sketchPaper)
    }
}
