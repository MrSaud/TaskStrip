import CoreGraphics
import Foundation

/// What the nib does with the ink.
///
/// Each one is the same list of points drawn differently — a width, an opacity, a cap, and for the
/// brush a taper along the stroke. Nothing here changes what a stroke *is*, so the two renderers
/// (the live canvas and the PNG the page is saved as) can both ask this and agree.
enum SketchBrush: String, CaseIterable, Identifiable, Equatable {
    /// The line as it always was: solid, even, round.
    case pen
    /// Broad and see-through, for going over what's already written.
    case highlighter
    /// Thin and a little dry.
    case pencil
    /// Thick, and tapered at both ends the way a loaded brush leaves the paper.
    case brush
    /// Paper-coloured, which on an opaque page is what rubbing out means.
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .pencil: return "Pencil"
        case .brush: return "Brush"
        case .eraser: return "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .pencil: return "pencil"
        case .brush: return "paintbrush.pointed"
        case .eraser: return "eraser"
        }
    }

    /// Multiplies the nib width the person picked, so fine and bold still mean something.
    var widthScale: CGFloat {
        switch self {
        case .pen: return 1
        case .highlighter: return 3.2
        case .pencil: return 0.6
        case .brush: return 2
        case .eraser: return 3
        }
    }

    var opacity: CGFloat {
        switch self {
        case .pen: return 1
        case .highlighter: return 0.28
        case .pencil: return 0.75
        case .brush: return 0.95
        case .eraser: return 1
        }
    }

    /// A highlighter's nib is flat, so its line ends square; everything else is round.
    var isSquareNib: Bool { self == .highlighter }

    /// Rubbing out is drawing in the paper's own colour: a page is an opaque PNG, so there's
    /// nothing to make transparent — there's only paper to put back.
    var drawsInPaperColour: Bool { self == .eraser }

    /// Whether the line thins towards both ends rather than running at one width.
    var tapers: Bool { self == .brush }

    /// Whether a pen pressing harder draws heavier. A highlighter's nib is a felt block and an
    /// eraser is an eraser: neither cares how hard you lean.
    var answersToPressure: Bool {
        switch self {
        case .pen, .pencil, .brush: return true
        case .highlighter, .eraser: return false
        }
    }

    func width(forNib nib: CGFloat) -> CGFloat { nib * widthScale }

    /// The ink to switch to when this brush is picked, or nil to leave the choice alone.
    ///
    /// A highlighter is yellow — black ink at a quarter opacity is grey, which is not what anyone
    /// reaches for a highlighter to do. Only the two defaults are ever swapped, so a colour
    /// someone picked on purpose is never taken off them: pick red while highlighting and it
    /// stays red.
    func inkFollowingBrush(from current: SketchInk, previous: SketchBrush) -> SketchInk? {
        if self == .highlighter, current == .ink { return .amber }
        if previous == .highlighter, self != .highlighter, current == .amber { return .ink }
        return nil
    }

    /// The width at each point of a tapered stroke: thin where the brush lands and where it
    /// leaves, full in between. One width per point, so both renderers draw the same line.
    ///
    /// A stroke too short to taper stays at full width — tapering two points would draw a line
    /// that's thin at both ends and nowhere else, which reads as a mistake.
    static func taperedWidths(pointCount: Int, width: CGFloat, thinnest: CGFloat = 0.35) -> [CGFloat] {
        guard pointCount > 0 else { return [] }
        guard pointCount >= 5 else { return Array(repeating: width, count: pointCount) }

        // The ends taper over a fifth of the stroke each, however long it is.
        let rampLength = max(1, pointCount / 5)
        return (0..<pointCount).map { index in
            let fromStart = CGFloat(index) / CGFloat(rampLength)
            let fromEnd = CGFloat(pointCount - 1 - index) / CGFloat(rampLength)
            let nearestEnd = min(min(fromStart, fromEnd), 1)
            return width * (thinnest + (1 - thinnest) * nearestEnd)
        }
    }
}
