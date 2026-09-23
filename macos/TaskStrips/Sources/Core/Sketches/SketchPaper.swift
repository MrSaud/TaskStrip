import CoreGraphics
import Foundation

/// The paper a sketch note is drawn on: a tint over the page and a ruling over that.
///
/// Neither is ever baked into the page. A page is a PNG of cream paper and the strokes on it —
/// that's the format Android wrote and the one backups carry — so the paper is laid over it as it
/// is shown, which means it can be changed at any time, on a note drawn today or one drawn a year
/// ago, and changing it never costs a stroke.
enum SketchPaper: String, CaseIterable, Identifiable, Equatable {
    /// Plain paper, the way it always was.
    case clean
    case lined
    case grid
    case dots
    /// A yellow legal pad.
    case legal
    case mint
    case sky
    /// Fine squared paper in pale blue, for drawing to scale rather than writing.
    case graph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "Clean"
        case .lined: return "Lined"
        case .grid: return "Grid"
        case .dots: return "Dots"
        case .legal: return "Legal pad"
        case .mint: return "Mint"
        case .sky: return "Sky"
        case .graph: return "Graph"
        }
    }

    enum Ruling: Equatable {
        case none
        /// Horizontal rules, `spacing` apart.
        case lines(spacing: CGFloat)
        /// Squares.
        case squares(spacing: CGFloat)
        /// A dot at every corner of a square grid.
        case dots(spacing: CGFloat)
    }

    var ruling: Ruling {
        switch self {
        case .clean, .mint, .sky: return .none
        case .lined, .legal: return .lines(spacing: 30)
        case .grid: return .squares(spacing: 24)
        case .dots: return .dots(spacing: 22)
        case .graph: return .squares(spacing: 13)
        }
    }

    /// Multiplied over the page, so the strokes already on it stay where they are and keep their
    /// weight — the paper goes under the ink, not over it.
    var tint: (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        switch self {
        case .clean, .lined, .grid, .dots: return nil
        case .legal: return (0.99, 0.92, 0.55)
        case .mint: return (0.80, 0.94, 0.86)
        case .sky: return (0.82, 0.90, 0.98)
        case .graph: return (0.88, 0.94, 1.0)
        }
    }

    /// Every paper here is light paper. A page is a PNG of cream paper with its strokes already
    /// on it, and the tint is multiplied over that — so dark paper would multiply the ink down to
    /// the paper's own colour and swallow every stroke already drawn. Tints stay pale for that
    /// reason, not for taste.
    var ruleOpacity: CGFloat { self == .graph ? 0.3 : 0.22 }

    // MARK: - Where the rules go

    /// The y of every rule across a page of this height, top to bottom. Empty unless the paper
    /// is ruled with lines.
    func lineOffsets(forHeight height: CGFloat) -> [CGFloat] {
        guard case .lines(let spacing) = ruling, spacing > 0, height > 0 else { return [] }
        return offsets(upTo: height, spacing: spacing)
    }

    /// The x and y of a squared or dotted grid over a page of this size.
    func gridOffsets(forSize size: CGSize) -> (columns: [CGFloat], rows: [CGFloat]) {
        let spacing: CGFloat
        switch ruling {
        case .squares(let step), .dots(let step): spacing = step
        case .none, .lines: return ([], [])
        }
        guard spacing > 0, size.width > 0, size.height > 0 else { return ([], []) }
        return (offsets(upTo: size.width, spacing: spacing), offsets(upTo: size.height, spacing: spacing))
    }

    /// One step in from the edge, so no rule sits on the very edge of the page.
    private func offsets(upTo end: CGFloat, spacing: CGFloat) -> [CGFloat] {
        var result: [CGFloat] = []
        var position = spacing
        while position < end {
            result.append(position)
            position += spacing
        }
        return result
    }
}
