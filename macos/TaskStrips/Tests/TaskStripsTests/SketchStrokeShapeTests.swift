import XCTest
@testable import TaskStrips

final class SketchStrokeShapeTests: XCTestCase {
    private func line(count: Int, step: CGFloat = 10) -> [CGPoint] {
        (0..<count).map { CGPoint(x: CGFloat($0) * step, y: 0) }
    }

    // MARK: - Cleaning

    func testPointsTooCloseTogetherToMeanAnythingAreDropped() {
        let jittery = [CGPoint(x: 0, y: 0), CGPoint(x: 0.2, y: 0.1), CGPoint(x: 0.3, y: 0), CGPoint(x: 20, y: 0)]
        XCTAssertEqual(SketchStrokeShape.cleaned(jittery), [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)])
    }

    func testAStrokeKeepsItsStartAndItsEnd() {
        let points = line(count: 12)
        let cleaned = SketchStrokeShape.cleaned(points)
        XCTAssertEqual(cleaned.first, points.first)
        XCTAssertEqual(cleaned.last, points.last)
    }

    func testAShortMoveIsStillALineAndNoMoveIsStillADot() {
        let tiny = [CGPoint(x: 0, y: 0), CGPoint(x: 0.4, y: 0)]
        XCTAssertEqual(SketchStrokeShape.cleaned(tiny).count, 2, "the hand did move")
        XCTAssertEqual(SketchStrokeShape.cleaned([CGPoint(x: 5, y: 5)]), [CGPoint(x: 5, y: 5)])
        XCTAssertTrue(SketchStrokeShape.cleaned([]).isEmpty)
    }

    // MARK: - Smoothing

    func testTheSmoothedLineStillPassesThroughTheEnds() throws {
        let points = line(count: 6)
        let smoothed = SketchStrokeShape.smoothed(points)
        XCTAssertEqual(try XCTUnwrap(smoothed.first).x, try XCTUnwrap(points.first).x, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(smoothed.last).x, try XCTUnwrap(points.last).x, accuracy: 0.0001)
        XCTAssertGreaterThan(smoothed.count, points.count, "it has to have more points to be smoother")
    }

    func testAStraightLineStaysStraight() {
        for point in SketchStrokeShape.smoothed(line(count: 8)) {
            XCTAssertEqual(point.y, 0, accuracy: 0.0001)
        }
    }

    func testTheCurveNeverLeavesTheGroundItWasDrawnOver() {
        // A right angle: the smoothed line may round the corner, but it can't wander off the page.
        let corner = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50)]
        for point in SketchStrokeShape.smoothed(corner) {
            XCTAssertTrue((-15...65).contains(point.x), "x \(point.x)")
            XCTAssertTrue((-15...65).contains(point.y), "y \(point.y)")
        }
    }

    func testTwoPointsAreAlreadyAsSmoothAsTheyGet() {
        let two = line(count: 2)
        XCTAssertEqual(SketchStrokeShape.smoothed(two), two)
    }

    // MARK: - Widths

    func testAPenKeepsOneWidthAndABrushDoesNot() {
        let points = SketchStrokeShape.smoothed(line(count: 12))
        let pen = SketchStroke(points: points, ink: .ink, width: 6, brush: .pen)
        XCTAssertEqual(Set(SketchStrokeShape.widths(for: points, stroke: pen)).count, 1)

        let brush = SketchStroke(points: points, ink: .ink, width: 6, brush: .brush)
        let widths = SketchStrokeShape.widths(for: points, stroke: brush)
        XCTAssertEqual(widths.count, points.count)
        XCTAssertGreaterThan(Set(widths).count, 1)
        XCTAssertLessThan(try XCTUnwrap(widths.first), try XCTUnwrap(widths.max()), "thin where it lands")
        for width in widths {
            XCTAssertGreaterThan(width, 0)
        }
    }

    // MARK: - The outline

    func testTheOutlineGoesOutAlongOneSideAndBackTheOther() {
        let points = line(count: 5)
        let widths = Array(repeating: CGFloat(4), count: points.count)
        let outline = SketchStrokeShape.outline(points: points, widths: widths)

        XCTAssertEqual(outline.count, points.count * 2)
        // A horizontal line offset by half the width, one side then the other.
        XCTAssertEqual(outline[0].y, 2, accuracy: 0.0001)
        XCTAssertEqual(outline[outline.count - 1].y, -2, accuracy: 0.0001)
        XCTAssertEqual(outline[0].x, outline[outline.count - 1].x, accuracy: 0.0001)
    }

    func testAWiderStrokeMakesAWiderOutline() {
        let points = line(count: 4)
        let thin = SketchStrokeShape.outline(points: points, widths: Array(repeating: 2, count: 4))
        let thick = SketchStrokeShape.outline(points: points, widths: Array(repeating: 10, count: 4))
        XCTAssertGreaterThan(abs(thick[0].y), abs(thin[0].y))
    }

    func testNothingToDrawMakesNoOutline() {
        XCTAssertTrue(SketchStrokeShape.outline(points: [], widths: []).isEmpty)
        XCTAssertTrue(SketchStrokeShape.outline(points: [.zero], widths: [4]).isEmpty)
        // Mismatched lists would draw nonsense, so they draw nothing.
        XCTAssertTrue(SketchStrokeShape.outline(points: line(count: 3), widths: [4]).isEmpty)
    }

    /// A stroke that stopped dead still has to have a direction, or the outline collapses.
    func testAPausedHandStillHasADirection() {
        let paused = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]
        let outline = SketchStrokeShape.outline(points: paused, widths: [4, 4, 4])
        XCTAssertEqual(outline.count, 6)
        for point in outline {
            XCTAssertFalse(point.x.isNaN || point.y.isNaN)
        }
    }
}
