import SwiftUI

/// The stamps, in a grid. Picking one hands back a picture of it, which the canvas then places
/// exactly the way it places an image from disk — drag to move, pinch to size, then confirm.
struct SketchStampPicker: View {
    /// The ink icons are drawn in; emoji ignore it and keep their own colours.
    let ink: SketchInk
    let onPick: (CGImage) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(SketchStamp.groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TaskStripTheme.amber)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(group.stamps) { stamp in
                                Button {
                                    pick(stamp)
                                } label: {
                                    SketchStampLabel(stamp: stamp, ink: ink)
                                        .frame(width: 52, height: 52)
                                        // Paper, not the sheet's own dark: an icon takes the ink
                                        // it will be stamped in, and dark ink on a dark tile is
                                        // a stamp you can't see until it's on the page.
                                        .background(TaskStripTheme.paper, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(stamp.id)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .macFrame(minWidth: 420, minHeight: 460)
        .background(TaskStripTheme.bayBackground)
        .navigationTitle("STAMPS")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    /// Drawn big and handed over as a picture: the page is a bitmap, so a stamp has to become one
    /// too. 256 points keeps it sharp when it's dropped at any size the page allows.
    @MainActor
    private func pick(_ stamp: SketchStamp) {
        let renderer = ImageRenderer(
            content: SketchStampLabel(stamp: stamp, ink: ink, size: 200)
                .frame(width: 256, height: 256)
        )
        renderer.scale = 2
        renderer.isOpaque = false
        if let image = renderer.cgImage { onPick(image) }
        dismiss()
    }
}

/// One stamp, drawn. Shared by the grid and by the picture that lands on the page, so what you
/// tapped is what you get.
struct SketchStampLabel: View {
    let stamp: SketchStamp
    let ink: SketchInk
    var size: CGFloat = 26

    var body: some View {
        switch stamp {
        case .emoji(let character):
            Text(character)
                .font(.system(size: size))
        case .icon(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.86, weight: .semibold))
                .foregroundStyle(SketchCanvasView.color(of: ink))
        }
    }
}
