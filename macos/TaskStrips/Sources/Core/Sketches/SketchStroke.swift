import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One drag of the pen. Mirrors SketchCanvasScreen.kt's private SketchStroke: a list of points, an
/// ink and a width, with no smoothing — the line is exactly where the pointer went.
struct SketchStroke: Identifiable, Equatable {
    let id = UUID()
    var points: [CGPoint]
    var ink: SketchInk
    /// The nib width the person picked, before the brush has its say.
    var width: CGFloat
    var brush: SketchBrush = .pen

    /// What this stroke is actually drawn at, brush included.
    var drawnWidth: CGFloat { brush.width(forNib: width) }

    /// The colour to draw it in: its ink, unless the brush puts paper back instead.
    var colour: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        brush.drawsInPaperColour ? SketchRenderer.paper : ink.components
    }

    static func == (lhs: SketchStroke, rhs: SketchStroke) -> Bool {
        lhs.id == rhs.id && lhs.points == rhs.points && lhs.ink == rhs.ink
            && lhs.width == rhs.width && lhs.brush == rhs.brush
    }
}

/// The five colours on Android's palette, in that order: InkColor, PriorityUrgent, PriorityNormal,
/// AmberTab, and the one blue that only exists here.
enum SketchInk: String, CaseIterable, Identifiable {
    case ink, urgent, normal, amber, blue

    var id: String { rawValue }

    var hex: UInt32 {
        switch self {
        case .ink: 0x262220
        case .urgent: 0xC0392B
        case .normal: 0x3D7A5C
        case .amber: 0xE0A63A
        case .blue: 0x3E5C8A
        }
    }

    var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        (
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255
        )
    }
}

/// The two nib sizes Android offers. Not a free slider: two widths you can tell apart at a glance
/// are more use than a hundred you can't.
enum SketchPenWidth: CGFloat, CaseIterable, Identifiable {
    case fine = 6
    case bold = 14

    var id: CGFloat { rawValue }
}

/// Turns strokes into the PNG that *is* the page.
///
/// Deliberately CoreGraphics rather than SwiftUI's ImageRenderer: this has to run off the main
/// actor (saving shouldn't block drawing) and it has to run in a test with no window, and
/// ImageRenderer gives neither. Everything it does — paper first, then the old page scaled to fit,
/// then the strokes — is the order saveSketch() does it in on Android, and the order matters:
/// each save re-renders the whole page from what's already on disk plus what's new, so the strokes
/// list only ever holds this sitting's work.
enum SketchRenderer {

    /// 0xF4EFE1 — the same paper the strips are printed on.
    static let paper: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0xF4 / 255, 0xEF / 255, 0xE1 / 255)

    /// An image the user has just positioned, baked in on top of everything else. Android does
    /// this as a second pass over the file it has only just written; doing it in the same pass
    /// gets the same picture without the page briefly existing without it.
    struct Overlay {
        var image: CGImage
        var rect: CGRect
    }

    static func png(
        size: CGSize,
        background: CGImage? = nil,
        strokes: [SketchStroke],
        overlay: Overlay? = nil
    ) -> Data? {
        guard let image = render(size: size, background: background, strokes: strokes, overlay: overlay) else {
            return nil
        }
        return encodePNG(image)
    }

    static func render(
        size: CGSize,
        background: CGImage? = nil,
        strokes: [SketchStroke],
        overlay: Overlay? = nil
    ) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Top-left origin, so a point the canvas reported at y=0 lands at the top of the PNG
        // rather than the bottom. Every coordinate below is in the canvas's own space.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(red: paper.red, green: paper.green, blue: paper.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let background {
            // Stretched to the current canvas, matching Android's createScaledBitmap: a page
            // drawn on a phone should fill a Mac window, not sit in its corner.
            draw(background, in: CGRect(x: 0, y: 0, width: width, height: height), into: context)
        }

        context.setLineJoin(.round)
        context.setShouldAntialias(true)

        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            let (red, green, blue) = stroke.colour
            let alpha = stroke.brush.opacity
            let width = stroke.drawnWidth
            context.setLineCap(stroke.brush.isSquareNib ? .square : .round)

            if stroke.points.count == 1 {
                // A tap is a dot, not nothing: a zero-length path with a round cap draws nothing
                // at all, so fill a circle the width of the nib instead.
                context.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
                context.fillEllipse(in: CGRect(
                    x: first.x - width / 2,
                    y: first.y - width / 2,
                    width: width,
                    height: width
                ))
            } else if stroke.brush.tapers {
                // One filled shape, because a width that changes can't be one stroked path, and
                // stroking it piece by piece beads at every join.
                let line = SketchStrokeShape.smoothed(SketchStrokeShape.cleaned(stroke.points))
                let widths = SketchStrokeShape.widths(for: line, stroke: stroke)
                let outline = SketchStrokeShape.outline(points: line, widths: widths)
                guard let start = outline.first else { break }
                context.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
                context.beginPath()
                context.move(to: start)
                for point in outline.dropFirst() { context.addLine(to: point) }
                context.closePath()
                context.fillPath()
                // The ends: a filled outline stops flat, and a nib doesn't.
                for (point, index) in [(line.first, 0), (line.last, line.count - 1)] {
                    guard let point else { continue }
                    let radius = widths[index] / 2
                    context.fillEllipse(in: CGRect(
                        x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2
                    ))
                }
            } else {
                let line = SketchStrokeShape.smoothed(SketchStrokeShape.cleaned(stroke.points))
                context.setStrokeColor(red: red, green: green, blue: blue, alpha: alpha)
                context.setLineWidth(width)
                context.beginPath()
                context.move(to: line.first ?? first)
                for point in line.dropFirst() { context.addLine(to: point) }
                context.strokePath()
            }
        }

        if let overlay {
            draw(overlay.image, in: overlay.rect, into: context)
        }

        return context.makeImage()
    }

    /// The context is deliberately upside down so canvas coordinates work unchanged, and an image
    /// drawn straight into it comes out mirrored. Flipping once more about the target rect's own
    /// centre leaves the rect exactly where it was and the picture the right way up.
    private static func draw(_ image: CGImage, in rect: CGRect, into context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.midY * 2)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func image(atPath url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
