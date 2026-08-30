import SwiftUI
import UniformTypeIdentifiers

/// One sketch note, one page at a time. Mirrors ui/screens/SketchCanvasScreen.kt.
///
/// The page you see is a PNG on disk plus whatever you've drawn since it was last saved. Saving
/// re-renders the two together into that same file, which is why the stroke list is cleared on
/// every page change and why undo only reaches back through this sitting — exactly as on the
/// phone. What's *not* mirrored is palm rejection: there is no palm on a trackpad, and the pointer
/// is the pointer.
struct SketchCanvasView: View {
    @Environment(\.dismiss) private var dismiss

    let noteID: String
    var store: SketchStore = .shared
    /// Called after every save, so a list behind this can catch up without watching the disk.
    var onChange: () -> Void = {}

    @State private var pages: [URL] = []
    /// May be one past the last saved page: that's a blank page that will only exist on disk once
    /// something is drawn on it. A note you open and back out of leaves nothing behind.
    @State private var pageIndex = 0
    @State private var strokes: [SketchStroke] = []
    @State private var currentStroke: SketchStroke?
    @State private var ink: SketchInk = .ink
    @State private var penWidth: SketchPenWidth = .fine
    @State private var canvasSize: CGSize = .zero
    @State private var background: CGImage?
    @State private var showDeletePageConfirm = false

    @State private var pendingImage: CGImage?
    @State private var placement = SketchImagePlacement(offset: .zero, scale: 1)
    @State private var isPickingImage = false

    private var currentPageURL: URL? { pages.indices.contains(pageIndex) ? pages[pageIndex] : nil }

    /// A blank page being drawn on isn't in `pages` yet, so counting them alone would show
    /// "1 of 1" while you look at the second page.
    private var pageCount: Int { max(pages.count, pageIndex + 1) }

    var body: some View {
        VStack(spacing: 0) {
            canvas
            palette
        }
        .frame(minWidth: 560, minHeight: 560)
        .background(TaskStripTheme.bayBackground)
        .navigationTitle(pendingImage == nil ? "PAGE \(pageIndex + 1)/\(pageCount)" : "DRAG TO MOVE · PINCH TO RESIZE")
        .toolbar { toolbarContent }
        .onAppear { reload(to: nil) }
        .confirmationDialog(
            "Delete this page?", isPresented: $showDeletePageConfirm, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteCurrentPage() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This page will be permanently deleted. This can't be undone.")
        }
        .fileImporter(isPresented: $isPickingImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { beginPlacing(url) }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            // Branched rather than handed an optional gesture: `.gesture` takes a gesture, not a
            // maybe-gesture, and drawing and placing are two different modes anyway.
            Group {
                if pendingImage == nil {
                    page(size: geometry.size).gesture(drawGesture)
                } else {
                    page(size: geometry.size)
                        .gesture(moveImageGesture)
                        .gesture(magnifyImageGesture)
                }
            }
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, size in canvasSize = size }
        }
        .padding(12)
    }

    private func page(size: CGSize) -> some View {
        ZStack {
            if let background {
                Image(decorative: background, scale: 1)
                    .resizable()
                    .frame(width: size.width, height: size.height)
            }

            Canvas { context, _ in
                for stroke in strokes + [currentStroke].compactMap({ $0 }) {
                    draw(stroke, in: &context)
                }
            }

            if let pendingImage {
                let rect = placement.rect(for: pendingImage.size)
                Image(decorative: pendingImage, scale: 1)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .border(TaskStripTheme.amber, width: 3)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(TaskStripTheme.paper)
        .contentShape(Rectangle())
    }

    private func draw(_ stroke: SketchStroke, in context: inout GraphicsContext) {
        guard let first = stroke.points.first else { return }
        let color = Self.color(of: stroke.ink)
        if stroke.points.count == 1 {
            let radius = stroke.width / 2
            context.fill(
                Path(ellipseIn: CGRect(
                    x: first.x - radius, y: first.y - radius, width: stroke.width, height: stroke.width
                )),
                with: .color(color)
            )
        } else {
            var path = Path()
            path.move(to: first)
            for point in stroke.points.dropFirst() { path.addLine(to: point) }
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// Zero minimum distance so a click is a dot — with the default, a tap would start no stroke
    /// at all and the pen would seem not to work until you moved it.
    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if var stroke = currentStroke {
                    stroke.points.append(value.location)
                    currentStroke = stroke
                } else {
                    currentStroke = SketchStroke(
                        points: [value.location], ink: ink, width: penWidth.rawValue
                    )
                }
            }
            .onEnded { _ in
                if let stroke = currentStroke { strokes.append(stroke) }
                currentStroke = nil
            }
    }

    private var moveImageGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                placement.offset.x += value.translation.width - dragged.width
                placement.offset.y += value.translation.height - dragged.height
                dragged = value.translation
            }
            .onEnded { _ in dragged = .zero }
    }

    @State private var dragged: CGSize = .zero
    @State private var magnified: CGFloat = 1

    private var magnifyImageGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                placement.magnify(by: value.magnification / magnified)
                magnified = value.magnification
            }
            .onEnded { _ in magnified = 1 }
    }

    /// A function rather than a computed property on SketchInk, which would drag SwiftUI into the
    /// model layer for the sake of one conversion.
    static func color(of ink: SketchInk) -> Color {
        let (red, green, blue) = ink.components
        return Color(red: red, green: green, blue: blue)
    }

    // MARK: - Palette

    private var palette: some View {
        HStack(spacing: 10) {
            ForEach(SketchInk.allCases) { swatch in
                Button {
                    ink = swatch
                } label: {
                    Circle()
                        .fill(Self.color(of: swatch))
                        .frame(width: ink == swatch ? 30 : 24, height: ink == swatch ? 30 : 24)
                        .overlay(Circle().stroke(TaskStripTheme.paper, lineWidth: ink == swatch ? 2 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(swatch.rawValue) ink")
            }

            Divider().frame(height: 24)

            ForEach(SketchPenWidth.allCases) { width in
                Button {
                    penWidth = width
                } label: {
                    Circle()
                        .fill(TaskStripTheme.paper)
                        .frame(width: width.rawValue, height: width.rawValue)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(TaskStripTheme.paper.opacity(penWidth == width ? 0.2 : 0))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(width == .fine ? "Fine pen" : "Bold pen")
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(TaskStripTheme.baySurface)
        .opacity(pendingImage == nil ? 1 : 0)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if pendingImage != nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { pendingImage = nil }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Place Image") { confirmImagePlacement() }
            }
        } else {
            ToolbarItemGroup {
                Button {
                    goToPage(pageIndex - 1)
                } label: {
                    Label("Previous page", systemImage: "chevron.left")
                }
                .disabled(pageIndex == 0)

                Button {
                    goToPage(pageIndex + 1)
                } label: {
                    Label("Next page", systemImage: "chevron.right")
                }
                .disabled(pageIndex >= pages.count - 1)

                Button {
                    isPickingImage = true
                } label: {
                    Label("Insert image", systemImage: "photo.badge.plus")
                }

                Button {
                    if !strokes.isEmpty { strokes.removeLast() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z")
                .disabled(strokes.isEmpty)

                Button {
                    strokes.removeAll()
                } label: {
                    Label("Clear this page", systemImage: "eraser")
                }
                .disabled(strokes.isEmpty)

                Button {
                    showDeletePageConfirm = true
                } label: {
                    Label("Delete this page", systemImage: "trash")
                }
                .disabled(pages.count <= 1)

                Button {
                    addPage()
                } label: {
                    Label("Add page", systemImage: "doc.badge.plus")
                }

                // "Save", not "Done": the list behind this has a Done of its own, and the two
                // sheets are stacked.
                Button("Save") {
                    persistCurrentPage()
                    dismiss()
                }
            }
        }
    }

    // MARK: - Pages

    /// Reloads the note from disk and shows `index`, or the last page if that's nil.
    private func reload(to index: Int?) {
        pages = store.pages(of: noteID)
        pageIndex = (index ?? pages.count - 1).clamped(0, max(pages.count - 1, 0))
        strokes = []
        currentStroke = nil
        background = currentPageURL.flatMap { SketchRenderer.image(atPath: $0) }
    }

    private func goToPage(_ index: Int) {
        persistCurrentPage()
        reload(to: index)
    }

    /// The new page isn't written until something is drawn on it, so adding one and changing your
    /// mind costs nothing.
    private func addPage() {
        persistCurrentPage()
        pages = store.pages(of: noteID)
        pageIndex = pages.count
        strokes = []
        currentStroke = nil
        background = nil
    }

    private func deleteCurrentPage() {
        guard let url = currentPageURL else { return }
        store.deletePage(url)
        onChange()
        reload(to: pageIndex)
    }

    /// Nothing drawn, nothing written: a page you only looked at keeps the bytes it already had,
    /// rather than being re-encoded on every visit.
    private func persistCurrentPage() {
        guard !strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }
        let target = currentPageURL ?? store.nextPageURL(of: noteID)
        guard let png = SketchRenderer.png(size: canvasSize, background: background, strokes: strokes) else {
            return
        }
        try? store.write(png, to: target)
        store.stampCreatedIfMissing(noteID)
        strokes = []
        onChange()
    }

    // MARK: - Images

    private func beginPlacing(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let image = SketchRenderer.image(atPath: url) else { return }
        placement = SketchImagePlacement.initial(imageSize: image.size, canvas: canvasSize)
        pendingImage = image
    }

    /// Bakes the image into the page along with whatever's been drawn, then reloads: from here on
    /// it's part of the picture and can be drawn over.
    private func confirmImagePlacement() {
        guard let image = pendingImage, canvasSize.width > 0, canvasSize.height > 0 else {
            pendingImage = nil
            return
        }
        let target = currentPageURL ?? store.nextPageURL(of: noteID)
        let png = SketchRenderer.png(
            size: canvasSize,
            background: background,
            strokes: strokes,
            overlay: SketchRenderer.Overlay(image: image, rect: placement.rect(for: image.size))
        )
        if let png {
            try? store.write(png, to: target)
            store.stampCreatedIfMissing(noteID)
            onChange()
        }
        pendingImage = nil
        // `pageIndex` still points at the right page either way: an existing one keeps its index,
        // and a blank one was already sitting at pages.count, which is where the page just
        // written lands once the list is re-read.
        reload(to: pageIndex)
    }
}

extension CGImage {
    var size: CGSize { CGSize(width: width, height: height) }
}
