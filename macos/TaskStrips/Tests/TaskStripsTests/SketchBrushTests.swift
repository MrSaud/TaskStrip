import XCTest
@testable import TaskStrips

final class SketchBrushTests: XCTestCase {
    func testTheNibWidthIsScaledByTheBrush() {
        XCTAssertEqual(SketchBrush.pen.width(forNib: 10), 10)
        XCTAssertGreaterThan(SketchBrush.highlighter.width(forNib: 10), 10)
        XCTAssertLessThan(SketchBrush.pencil.width(forNib: 10), 10)
    }

    func testOnlyTheHighlighterIsSeeThroughEnoughToReadUnder() {
        XCTAssertEqual(SketchBrush.pen.opacity, 1)
        XCTAssertLessThan(SketchBrush.highlighter.opacity, 0.5)
        XCTAssertEqual(SketchBrush.eraser.opacity, 1, "paper has to go back solid")
    }

    func testOnlyTheEraserPutsPaperBack() {
        for brush in SketchBrush.allCases {
            XCTAssertEqual(brush.drawsInPaperColour, brush == .eraser, "\(brush)")
        }
    }

    func testAStrokeTakesItsColourFromTheBrushBeforeTheInk() {
        let ink = SketchStroke(points: [.zero], ink: .urgent, width: 6, brush: .pen)
        XCTAssertEqual(ink.colour.red, SketchInk.urgent.components.red)

        let rubbed = SketchStroke(points: [.zero], ink: .urgent, width: 6, brush: .eraser)
        XCTAssertEqual(rubbed.colour.red, SketchRenderer.paper.red)
    }

    // MARK: - The taper

    func testATaperedStrokeIsThinAtBothEndsAndFullInTheMiddle() {
        let widths = SketchBrush.taperedWidths(pointCount: 21, width: 10)
        XCTAssertEqual(widths.count, 21)
        XCTAssertEqual(widths.first, widths.last)
        XCTAssertLessThan(try XCTUnwrap(widths.first), 10)
        XCTAssertEqual(widths[10], 10, accuracy: 0.001)
        // It only ever grows towards the middle.
        for index in 1...10 {
            XCTAssertGreaterThanOrEqual(widths[index], widths[index - 1])
        }
    }

    func testAStrokeTooShortToTaperKeepsItsWidth() {
        for count in 1...4 {
            let widths = SketchBrush.taperedWidths(pointCount: count, width: 8)
            XCTAssertEqual(widths, Array(repeating: 8, count: count), "\(count) points")
        }
        XCTAssertTrue(SketchBrush.taperedWidths(pointCount: 0, width: 8).isEmpty)
    }

    func testNoPartOfAStrokeIsDrawnAtNothing() {
        for count in [5, 9, 40, 200] {
            for width in SketchBrush.taperedWidths(pointCount: count, width: 12) {
                XCTAssertGreaterThan(width, 0)
                XCTAssertLessThanOrEqual(width, 12)
            }
        }
    }
}

final class SketchStampTests: XCTestCase {
    func testEveryStampIsOfferedOnceAndNoGroupIsEmpty() {
        let ids = SketchStamp.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "a stamp is offered twice")
        for group in SketchStamp.groups {
            XCTAssertFalse(group.stamps.isEmpty, group.title)
        }
    }

    func testIconsTakeTheInkAndEmojiKeepTheirOwnColours() {
        XCTAssertTrue(SketchStamp.icon("checkmark").followsInk)
        XCTAssertFalse(SketchStamp.emoji("✅").followsInk)
    }
}
