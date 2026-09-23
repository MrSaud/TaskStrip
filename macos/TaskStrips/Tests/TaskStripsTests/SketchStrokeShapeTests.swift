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

/// What a Pencil adds: a line that answers to the hand pressing it.
final class SketchPressureTests: XCTestCase {
    private func line(count: Int, pressures: [CGFloat]) -> SketchStrokeShape.Line {
        SketchStrokeShape.Line(
            points: (0..<count).map { CGPoint(x: CGFloat($0) * 10, y: 0) },
            pressures: pressures
        )
    }

    func testPressingHarderDrawsHeavier() {
        let light = SketchStrokeShape.pressureFactor(0.1)
        let firm = SketchStrokeShape.pressureFactor(0.5)
        let hard = SketchStrokeShape.pressureFactor(1)

        XCTAssertLessThan(light, firm)
        XCTAssertLessThan(firm, hard)
        XCTAssertGreaterThan(light, 0.4, "a light touch still draws")
        XCTAssertLessThan(hard, 1.5, "leaning on it doesn't make a blob")
    }

    func testAPressedStrokeVariesAndAnUnpressedOneDoesNot() {
        let points = (0..<5).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        let pressed = SketchStroke(
            points: points, pressures: [0.1, 0.4, 0.9, 0.4, 0.1], ink: .ink, width: 6, brush: .pen
        )
        let widths = SketchStrokeShape.widths(
            for: SketchStrokeShape.Line(points: points, pressures: pressed.pressures), stroke: pressed
        )
        XCTAssertEqual(widths.count, points.count)
        XCTAssertGreaterThan(widths[2], widths[0], "hardest in the middle")

        let finger = SketchStroke(points: points, ink: .ink, width: 6, brush: .pen)
        let even = SketchStrokeShape.widths(
            for: SketchStrokeShape.Line(points: points, pressures: []), stroke: finger
        )
        XCTAssertEqual(Set(even).count, 1, "nothing pressing, one width")
    }

    func testAFeltNibAndAnEraserIgnoreHowHardYouLean() {
        let points = (0..<4).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        let pressures: [CGFloat] = [0.1, 0.9, 0.2, 1]
        for brush in [SketchBrush.highlighter, .eraser] {
            let stroke = SketchStroke(points: points, pressures: pressures, ink: .ink, width: 6, brush: brush)
            let widths = SketchStrokeShape.widths(
                for: SketchStrokeShape.Line(points: points, pressures: pressures), stroke: stroke
            )
            XCTAssertEqual(Set(widths).count, 1, "\(brush) doesn't answer to pressure")
        }
    }

    // MARK: - Carrying the pressures along the line

    func testCleaningKeepsEachPressureWithItsOwnPoint() {
        let jittery = SketchStrokeShape.Line(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.2, y: 0), CGPoint(x: 20, y: 0)],
            pressures: [0.2, 0.9, 0.7]
        )
        let cleaned = SketchStrokeShape.cleaned(jittery)
        XCTAssertEqual(cleaned.points.count, cleaned.pressures.count)
        XCTAssertEqual(cleaned.pressures, [0.2, 0.7], "the dropped point took its pressure with it")
    }

    func testSmoothingSpreadsThePressuresAcrossTheNewPoints() throws {
        let smoothed = SketchStrokeShape.smoothed(line(count: 4, pressures: [0, 0.5, 0.5, 1]))
        XCTAssertEqual(smoothed.points.count, smoothed.pressures.count)
        XCTAssertTrue(smoothed.hasPressure)
        XCTAssertEqual(try XCTUnwrap(smoothed.pressures.first), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(smoothed.pressures.last), 1, accuracy: 0.001)
        for pressure in smoothed.pressures {
            XCTAssertTrue((0...1).contains(pressure), "\(pressure)")
        }
    }

    func testAStrokeWithNoPressuresStaysThatWay() {
        let plain = SketchStrokeShape.line(
            of: SketchStroke(points: [.zero, CGPoint(x: 30, y: 0), CGPoint(x: 60, y: 10)], ink: .ink, width: 4)
        )
        XCTAssertFalse(plain.hasPressure)
        XCTAssertTrue(plain.pressures.isEmpty)
    }
}
