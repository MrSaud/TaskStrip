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
    @State private var brush: SketchBrush = .pen
    @State private var canvasSize: CGSize = .zero
    @State private var background: CGImage?
    /// This note's paper, kept beside its pages and shown over them.
    @State private var paper: SketchPaper = .clean
    @State private var showDeletePageConfirm = false
    /// Asked before closing a page with strokes on it that haven't been saved.
    @State private var showCloseConfirm = false

    /// iPad and iPhone only: whether a finger draws, or only an Apple Pencil. Off means a hand
    /// resting on the page leaves nothing behind, which is what palm rejection amounts to here.
    @AppStorage(AppSettingsKey.fingerDrawing) private var fingerDrawing = true
    /// Shown for a moment when a finger touches the page while only a Pencil may draw.
    @State private var refusedFinger = false

    @State private var pendingImage: CGImage?
    @State private var placement = SketchImagePlacement(offset: .zero, scale: 1)
    @State private var isPickingImage = false
    @State private var isPickingStamp = false

    private var currentPageURL: URL? { pages.indices.contains(pageIndex) ? pages[pageIndex] : nil }

    /// A blank page being drawn on isn't in `pages` yet, so counting them alone would show
    /// "1 of 1" while you look at the second page.
    private var pageCount: Int { max(pages.count, pageIndex + 1) }

    var body: some View {
        VStack(spacing: 0) {
            canvas
            palette
        }
        .macFrame(minWidth: 560, minHeight: 560)
        .background(TaskStripTheme.bayBackground)
        .navigationTitle(pendingImage == nil ? "PAGE \(pageIndex + 1)/\(pageCount)" : "DRAG TO MOVE · PINCH TO RESIZE")
        .toolbar { toolbarContent }
        .onAppear {
            paper = store.paper(of: noteID)
            reload(to: nil)
        }
        .onChange(of: brush) { previous, chosen in
            if let following = chosen.inkFollowingBrush(from: ink, previous: previous) { ink = following }
        }
        .onChange(of: paper) { _, chosen in
            // A note with no pages yet has no folder to write into; the choice is written again
            // when the first page is saved.
            store.setPaper(chosen, of: noteID)
            onChange()
        }
        .confirmationDialog(
            "Close without saving?", isPresented: $showCloseConfirm, titleVisibility: .visible
        ) {
            Button("Save and Close") {
                persistCurrentPage()
                dismiss()
            }
            Button("Discard Drawing", role: .destructive) {
                strokes = []
                dismiss()
            }
            Button("Keep Drawing", role: .cancel) {}
        } message: {
            Text("This page has strokes that haven't been saved yet.")
        }
        .confirmationDialog(
            "Delete this page?", isPresented: $showDeletePageConfirm, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteCurrentPage() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This page will be permanently deleted. This can't be undone.")
        }
        .sheet(isPresented: $isPickingStamp) {
            NavigationStack {
                SketchStampPicker(ink: ink) { image in beginPlacing(image) }
            }
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
                    #if os(iOS)
                    page(size: geometry.size)
                        .overlay(
                            StrokeCatcher(
                                pencilOnly: !fingerDrawing,
                                onBegan: { beginStroke(at: $0) },
                                onMoved: { extendStroke(through: $0) },
                                onEnded: { endStroke() },
                                onRefused: { flashPencilOnly() }
                            )
                        )
                    #else
                    page(size: geometry.size).gesture(drawGesture)
                    #endif
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

            // Over the page that's already drawn, under the strokes still being drawn.
            SketchPaperLayer(paper: paper, size: size)

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
        .background(TaskStripTheme.sketchPaper)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if refusedFinger {
                Label("Pencil only — turn on Draw with Finger to use a finger", systemImage: "applepencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TaskStripTheme.paper)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(TaskStripTheme.baySurface.opacity(0.95), in: Capsule())
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
    }

    /// The same brush rules the saved PNG is drawn with — see SketchRenderer.render. The two are
    /// kept side by side deliberately: what's on screen while drawing and what's on the page
    /// afterwards have to be the same line.
    private func draw(_ stroke: SketchStroke, in context: inout GraphicsContext) {
        guard let first = stroke.points.first else { return }
        let (red, green, blue) = stroke.colour
        let colour = Color(red: red, green: green, blue: blue).opacity(stroke.brush.opacity)
        let width = stroke.drawnWidth
        let cap: CGLineCap = stroke.brush.isSquareNib ? .square : .round

        if stroke.points.count == 1 {
            let radius = width / 2
            context.fill(
                Path(ellipseIn: CGRect(x: first.x - radius, y: first.y - radius, width: width, height: width)),
                with: .color(colour)
            )
        } else if stroke.brush.tapers {
            // One filled shape, ends rounded by hand — see SketchStrokeShape for why.
            let line = SketchStrokeShape.smoothed(SketchStrokeShape.cleaned(stroke.points))
            let widths = SketchStrokeShape.widths(for: line, stroke: stroke)
            let outline = SketchStrokeShape.outline(points: line, widths: widths)
            guard let start = outline.first else { return }

            var shape = Path()
            shape.move(to: start)
            for point in outline.dropFirst() { shape.addLine(to: point) }
            shape.closeSubpath()
            context.fill(shape, with: .color(colour))

            // The ends, filled separately: a nib is round, and an ellipse added to the outline's
            // own path winds the other way and punches a hole through the tip instead.
            for (point, index) in [(line.first, 0), (line.last, line.count - 1)] {
                guard let point else { continue }
                let radius = widths[index] / 2
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2
                    )),
                    with: .color(colour)
                )
            }
        } else {
            let line = SketchStrokeShape.smoothed(SketchStrokeShape.cleaned(stroke.points))
            var path = Path()
            path.move(to: line.first ?? first)
            for point in line.dropFirst() { path.addLine(to: point) }
            context.stroke(
                path,
                with: .color(colour),
                style: StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: .round)
            )
        }
    }

    /// Zero minimum distance so a click is a dot — with the default, a tap would start no stroke
    /// at all and the pen would seem not to work until you moved it.
    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if currentStroke == nil {
                    beginStroke(at: value.location)
                } else {
                    extendStroke(through: [value.location])
                }
            }
            .onEnded { _ in endStroke() }
    }

    // MARK: - One stroke, whatever drew it

    private func beginStroke(at point: CGPoint) {
        currentStroke = SketchStroke(points: [point], ink: ink, width: penWidth.rawValue, brush: brush)
    }

    private func extendStroke(through points: [CGPoint]) {
        guard var stroke = currentStroke else { return }
        stroke.points.append(contentsOf: points)
        currentStroke = stroke
    }

    private func endStroke() {
        if let stroke = currentStroke { strokes.append(stroke) }
        currentStroke = nil
    }

    /// Says why nothing happened, then gets out of the way.
    private func flashPencilOnly() {
        guard !refusedFinger else { return }
        withAnimation { refusedFinger = true }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { refusedFinger = false }
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
            Menu {
                Picker("Brush", selection: $brush) {
                    ForEach(SketchBrush.allCases) { candidate in
                        Label(candidate.title, systemImage: candidate.symbol).tag(candidate)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: brush.symbol)
                    Text(brush.title)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(brush == .eraser ? TaskStripTheme.ink : TaskStripTheme.paper)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(brush == .eraser ? TaskStripTheme.amber : TaskStripTheme.bayBackground, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("What the nib does with the ink")
            .accessibilityLabel("Brush: \(brush.title)")

            Divider().frame(height: 24)

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

            Divider().frame(height: 24)

            Button {
                isPickingStamp = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "face.smiling")
                    Text("Stamp")
                }
                .font(.caption)
                .foregroundStyle(TaskStripTheme.paper)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(TaskStripTheme.bayBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Drop an icon or an emoji on the page")

            SketchPaperPicker(paper: $paper)
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
            // The way out, before anything else: a sheet with only a Save is a sheet you can't
            // leave without saving, and on a Mac there's no back button to fall back on.
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { close() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

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

                #if os(iOS)
                // A switch rather than a settings trip: which hand is drawing changes while you
                // draw — Pencil for the diagram, finger for a quick scrawl.
                Toggle(isOn: $fingerDrawing) {
                    Label(
                        fingerDrawing ? "Draw with finger" : "Pencil only",
                        systemImage: fingerDrawing ? "hand.draw" : "applepencil"
                    )
                }
                .toggleStyle(.button)
                .help(fingerDrawing ? "A finger draws. Tap for Pencil only." : "Only an Apple Pencil draws.")
                #endif

                #if os(macOS)
                // "Save", not "Done": the list behind this has a Done of its own, and the two
                // sheets are stacked.
                Button("Save") {
                    persistCurrentPage()
                    dismiss()
                }
                #endif
            }
            #if os(iOS)
            // A phone's toolbar has room for a few buttons and folds the rest into a menu; the
            // way out must never be the one that gets folded away.
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    persistCurrentPage()
                    dismiss()
                }
            }
            #endif
        }
    }

    /// Leaves the page. Strokes that haven't been saved are worth a question — they're this
    /// sitting's work, and nothing else is holding them.
    private func close() {
        if strokes.isEmpty {
            dismiss()
        } else {
            showCloseConfirm = true
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
        // The folder exists now, so a paper chosen on a blank note finally has somewhere to live.
        store.setPaper(paper, of: noteID)
        strokes = []
        onChange()
    }

    // MARK: - Images

    /// A stamp arrives as a picture rather than a file, and is placed the same way from there.
    private func beginPlacing(_ image: CGImage) {
        placement = SketchImagePlacement.initial(imageSize: image.size, canvas: canvasSize)
        pendingImage = image
    }

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
