import SwiftUI

/// The stamps, in a grid. Picking one hands back a picture of it, which the canvas then places
/// exactly the way it places an image from disk — drag to move, pinch to size, then confirm.
struct SketchStampPicker: View {
    /// The ink icons are drawn in; emoji ignore it and keep their own colours.
    let ink: SketchInk
    let onPick: (CGImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 10)]
    private var groups: [SketchStamp.Group] { SketchStamp.groups(matching: search) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if groups.isEmpty {
                empty
            } else {
                grid
            }
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

    /// A field of its own rather than `.searchable`: this is a sheet inside a sheet, and on a Mac
    /// that search would land in the window's toolbar, which belongs to the page behind it.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search stamps", text: $search)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .accessibilityIdentifier("stampSearch")
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(TaskStripTheme.baySurface)
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
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
                                        // The page's own paper, not the sheet's background: an
                                        // icon takes the ink it will be stamped in, so it has to
                                        // be shown on what it will be stamped on.
                                        .background(TaskStripTheme.sketchPaper, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .help(stamp.name)
                                .accessibilityLabel(stamp.name)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("NOTHING BY THAT NAME")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Try \u{201C}tick\u{201D}, \u{201C}arrow\u{201D}, \u{201C}idea\u{201D} \u{2014} or the emoji itself.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
        switch stamp.kind {
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
