import CoreGraphics
import Foundation

/// Turns the points a finger or a Pencil left into the shape that gets drawn.
///
/// A touch arrives a few times per frame, so a stroke is a short list of corners, not a line. Drawn
/// straight it looks like one: flat facets on every curve, and for a stroke whose width changes,
/// a bead at every join where two differently-sized round caps overlap. So the points are cleaned
/// of the jitter a hand leaves, run through a curve that passes through each of them, and — when
/// the width varies — turned into an outline that is filled in one piece rather than stroked
/// segment by segment.
///
/// It lives here, not in either renderer, because the line on screen while you draw and the line
/// in the PNG afterwards have to be the same line.
enum SketchStrokeShape {
    /// Points closer together than this say nothing about where the hand went; they're the sensor
    /// arguing with itself, and keeping them only makes the curve wobble.
    static let minimumSpacing: CGFloat = 1.2

    static func cleaned(_ points: [CGPoint], spacing: CGFloat = minimumSpacing) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var result = [first]
        for point in points.dropFirst() {
            guard let last = result.last else { continue }
            if hypot(point.x - last.x, point.y - last.y) >= spacing { result.append(point) }
        }
        // A stroke that never moved is still a dot, and a two-point stroke is still a line.
        if result.count == 1, points.count > 1, let last = points.last, last != first {
            result.append(last)
        }
        return result
    }

    /// A Catmull-Rom spline through the points — it passes through every one of them, so the line
    /// still goes exactly where the hand went; it only stops being made of corners.
    static func smoothed(_ points: [CGPoint], subdivisions: Int = 6) -> [CGPoint] {
        guard points.count > 2, subdivisions > 1 else { return points }

        var result: [CGPoint] = [points[0]]
        for index in 0..<(points.count - 1) {
            // The ends double up their neighbour, which is what keeps the curve from flying off
            // past the first and last point.
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]

            for step in 1...subdivisions {
                let t = CGFloat(step) / CGFloat(subdivisions)
                result.append(catmullRom(p0, p1, p2, p3, t))
            }
        }
        return result
    }

    private static func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t
        func axis(_ a0: CGFloat, _ a1: CGFloat, _ a2: CGFloat, _ a3: CGFloat) -> CGFloat {
            0.5 * ((2 * a1) + (-a0 + a2) * t
                   + (2 * a0 - 5 * a1 + 4 * a2 - a3) * t2
                   + (-a0 + 3 * a1 - 3 * a2 + a3) * t3)
        }
        return CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y))
    }

    /// The width at every point of the drawn line.
    ///
    /// A pen keeps one width. A brush tapers at both ends and thins where the hand moved fast,
    /// which is the difference between a line and a stroke — and it's smoothed afterwards, since
    /// a width that jumps from point to point reads as a lumpy nib rather than a fast hand.
    static func widths(for points: [CGPoint], stroke: SketchStroke) -> [CGFloat] {
        let base = stroke.drawnWidth
        guard stroke.brush.tapers else { return Array(repeating: base, count: points.count) }

        let tapered = SketchBrush.taperedWidths(pointCount: points.count, width: base)
        guard points.count > 2 else { return tapered }

        let speeds = (0..<points.count).map { index -> CGFloat in
            let previous = points[max(index - 1, 0)]
            let next = points[min(index + 1, points.count - 1)]
            return hypot(next.x - previous.x, next.y - previous.y) / 2
        }
        let average = max(speeds.reduce(0, +) / CGFloat(speeds.count), 0.001)

        let modulated = zip(tapered, speeds).map { width, speed -> CGFloat in
            // Fast is thinner, slow is fuller, and neither runs away with the line.
            let factor = min(max(1.15 - 0.35 * (speed / average), 0.65), 1.2)
            return width * factor
        }
        return smoothedWidths(modulated)
    }

    /// A three-point average, twice: enough to take the steps out without flattening the taper.
    private static func smoothedWidths(_ widths: [CGFloat]) -> [CGFloat] {
        guard widths.count > 2 else { return widths }
        var result = widths
        for _ in 0..<2 {
            var pass = result
            for index in 1..<(result.count - 1) {
                pass[index] = (result[index - 1] + result[index] + result[index + 1]) / 3
            }
            result = pass
        }
        return result
    }

    /// The edge of a stroke whose width changes: out along one side and back along the other, so
    /// the whole thing can be filled as one shape. Stroking it segment by segment instead leaves
    /// a bead at every join, which is what a variable-width line drawn the lazy way looks like.
    static func outline(points: [CGPoint], widths: [CGFloat]) -> [CGPoint] {
        guard points.count > 1, points.count == widths.count else { return [] }

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for index in points.indices {
            let previous = points[max(index - 1, 0)]
            let next = points[min(index + 1, points.count - 1)]
            var dx = next.x - previous.x
            var dy = next.y - previous.y
            let length = hypot(dx, dy)
            // A direction is needed even where the hand paused; straight up is as good as any,
            // and one point of a long stroke can't be seen anyway.
            if length < 0.0001 {
                dx = 0
                dy = 1
            } else {
                dx /= length
                dy /= length
            }
            let half = widths[index] / 2
            left.append(CGPoint(x: points[index].x - dy * half, y: points[index].y + dx * half))
            right.append(CGPoint(x: points[index].x + dy * half, y: points[index].y - dx * half))
        }
        return left + right.reversed()
    }
}
