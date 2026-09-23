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

    func testEveryStampCanBeFoundByName() {
        for stamp in SketchStamp.all {
            XCTAssertFalse(stamp.name.isEmpty, stamp.id)
            XCTAssertTrue(stamp.matches(stamp.name), stamp.id)
        }
    }

    func testIconsTakeTheInkAndEmojiKeepTheirOwnColours() {
        let icon = SketchStamp.all.first { if case .icon = $0.kind { return true } else { return false } }
        let emoji = SketchStamp.all.first { if case .emoji = $0.kind { return true } else { return false } }
        XCTAssertEqual(icon?.followsInk, true)
        XCTAssertEqual(emoji?.followsInk, false)
    }

    // MARK: - Finding one

    func testSearchMatchesTheNameAnyKeywordAndTheCharacterItself() {
        let fire = try? XCTUnwrap(SketchStamp.all.first { $0.id == "emoji:🔥" })
        XCTAssertEqual(fire?.matches("hot"), true, "by name")
        XCTAssertEqual(fire?.matches("URGENT"), true, "by keyword, whatever the case")
        XCTAssertEqual(fire?.matches("🔥"), true, "by the emoji itself")
        XCTAssertEqual(fire?.matches("aubergine"), false)
    }

    func testAnEmptySearchIsNoSearchAtAll() {
        XCTAssertEqual(SketchStamp.groups(matching: "").count, SketchStamp.groups.count)
        XCTAssertEqual(SketchStamp.groups(matching: "   ").count, SketchStamp.groups.count)
    }

    func testASearchDropsTheGroupsWithNothingInThem() {
        let found = SketchStamp.groups(matching: "arrow")
        XCTAssertFalse(found.isEmpty)
        for group in found {
            XCTAssertFalse(group.stamps.isEmpty, group.title)
        }
        XCTAssertLessThan(found.flatMap(\.stamps).count, SketchStamp.all.count)
    }

    func testNamingAGroupKeepsTheWholeGroup() {
        let arrows = try? XCTUnwrap(SketchStamp.groups.first { $0.title == "Arrows" })
        let found = SketchStamp.groups(matching: "arrows")
        XCTAssertEqual(found.first { $0.title == "Arrows" }?.stamps.count, arrows?.stamps.count)
    }

    func testASearchThatFindsNothingFindsNothing() {
        XCTAssertTrue(SketchStamp.groups(matching: "qwertyuiop").isEmpty)
    }

    /// The point of the search is that there are too many to scroll.
    func testThereAreEnoughStampsToBeWorthSearching() {
        XCTAssertGreaterThan(SketchStamp.all.count, 100)
    }
}

extension SketchBrushTests {
    func testTheHighlighterArrivesWithAmberInIt() {
        XCTAssertEqual(SketchBrush.highlighter.inkFollowingBrush(from: .ink, previous: .pen), .amber)
    }

    func testLeavingTheHighlighterGivesTheDarkInkBack() {
        XCTAssertEqual(SketchBrush.pen.inkFollowingBrush(from: .amber, previous: .highlighter), .ink)
    }

    func testAColourPickedOnPurposeIsNeverTakenAway() {
        // Red while highlighting stays red.
        XCTAssertNil(SketchBrush.highlighter.inkFollowingBrush(from: .urgent, previous: .pen))
        // Amber picked with the pen isn't touched by switching to another pen.
        XCTAssertNil(SketchBrush.pencil.inkFollowingBrush(from: .amber, previous: .pen))
        // Already amber, already highlighting: nothing to do.
        XCTAssertNil(SketchBrush.highlighter.inkFollowingBrush(from: .amber, previous: .highlighter))
    }
}
