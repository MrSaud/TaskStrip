import AppKit
import SwiftUI

/// The quote of the day, mirroring HomeScreen.kt's QuoteOfDayCard.
///
/// Android renders it to a bitmap and shares it to WhatsApp status. The Mac equivalent isn't a
/// share sheet — it's the clipboard and a file, which is how anything leaves a Mac.
struct QuoteOfDayCard: View {
    let quote: Quote

    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("QUOTE OF THE DAY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TaskStripTheme.amber)
                Text("\u{201C}\(quote.text)\u{201D}")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Text("— \(quote.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            Menu {
                Button("Copy Text") { copyText() }
                Button("Copy as Image") { copyImage() }
                Button("Save Image…") { saveImage() }
            } label: {
                Label(copied ? "Copied" : "Share", systemImage: copied ? "checkmark" : "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(14)
        .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(TaskStripTheme.paper.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    /// The card as a picture, drawn at the same proportions Android's renderer uses so a quote
    /// shared from either device looks like it came from the same app.
    private var shareable: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("QUOTE OF THE DAY")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(TaskStripTheme.amber)
            Text("\u{201C}\(quote.text)\u{201D}")
                .font(.system(size: 34, design: .monospaced))
                .foregroundStyle(TaskStripTheme.paper)
                .fixedSize(horizontal: false, vertical: true)
            Text("— \(quote.author)")
                .font(.system(size: 22))
                .foregroundStyle(TaskStripTheme.paper.opacity(0.6))
            Spacer(minLength: 0)
            Text("TASK STRIPS")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TaskStripTheme.paper.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(56)
        .frame(width: 900, height: 700, alignment: .topLeading)
        .background(TaskStripTheme.bayBackground)
    }

    @MainActor
    private func renderedImage() -> NSImage? {
        let renderer = ImageRenderer(content: shareable)
        // Retina, so the picture doesn't look soft everywhere it's pasted.
        renderer.scale = 2
        return renderer.nsImage
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\u{201C}\(quote.text)\u{201D} — \(quote.author)", forType: .string)
        flash()
    }

    private func copyImage() {
        guard let image = renderedImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        flash()
    }

    private func saveImage() {
        guard let image = renderedImage(),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "quote-of-the-day.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url)
    }

    /// Says it happened, then goes back to normal — a clipboard write is otherwise silent.
    private func flash() {
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
