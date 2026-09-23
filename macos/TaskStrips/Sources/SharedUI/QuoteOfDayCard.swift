#if os(macOS)
import AppKit
#endif
import SwiftUI

/// The quote of the day, mirroring HomeScreen.kt's QuoteOfDayCard.
///
/// Android renders it to a bitmap and shares it to WhatsApp status. The Mac equivalent isn't a
/// share sheet — it's the clipboard and a file, which is how anything leaves a Mac.
struct QuoteOfDayCard: View {
    let quote: Quote

    /// Rolled up to its title line, remembered across launches: on a phone the card takes a good
    /// share of the board, and someone who wants it back should only have to tap the line it left.
    @AppStorage(AppSettingsKey.quoteCollapsed) private var collapsed = false
    /// Gone from the board altogether, from the card's own menu. Settings brings it back.
    @AppStorage(AppSettingsKey.showQuote) private var showQuote = true

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("QUOTE OF THE DAY")
                            .font(.caption.weight(.semibold))
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TaskStripTheme.amber.opacity(0.7))
                    }
                    .foregroundStyle(TaskStripTheme.amber)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsed ? "Show the quote of the day" : "Roll up the quote of the day")

                Spacer(minLength: 0)

                // Its own button, always there: hiding the card was buried in the Share menu,
                // which on a phone is a menu you have to know about to find.
                Button {
                    showQuote = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TaskStripTheme.paper.opacity(0.5))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide the quote — Settings brings it back")
                .accessibilityLabel("Hide the quote of the day")

                // Only while the words are showing: there is nothing to share from a title line.
                if !collapsed {
                    Menu {
                        Button("Copy Text") { copyText() }
                        Button("Copy as Image") { copyImage() }
                        #if os(macOS)
                        Button("Save Image…") { saveImage() }
                        #endif
                        Divider()
                        Button("Hide From the Board") { showQuote = false }
                    } label: {
                        Label(copied ? "Copied" : "Share", systemImage: copied ? "checkmark" : "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if !collapsed {
                Text("\u{201C}\(quote.text)\u{201D}")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Text("— \(quote.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        // The board's own background rather than a card on top of it: in daylight the surface
        // colour reads as a white panel stuck over the paper, which is the one thing on the board
        // that looks like it came from somewhere else. A hairline underneath is enough to separate
        // it from the strips.
        .background(TaskStripTheme.bayBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TaskStripTheme.paper.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
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
    private func renderedImage() -> CGImage? {
        let renderer = ImageRenderer(content: shareable)
        // Retina, so the picture doesn't look soft everywhere it's pasted.
        renderer.scale = 2
        return renderer.cgImage
    }

    private func copyText() {
        Platform.copy("\u{201C}\(quote.text)\u{201D} — \(quote.author)")
        flash()
    }

    private func copyImage() {
        guard let image = renderedImage() else { return }
        Platform.copy(image)
        flash()
    }

    #if os(macOS)
    private func saveImage() {
        guard let image = renderedImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "quote-of-the-day.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url)
    }
    #endif

    /// Says it happened, then goes back to normal — a clipboard write is otherwise silent.
    private func flash() {
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
