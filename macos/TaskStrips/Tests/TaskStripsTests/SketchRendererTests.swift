import CoreGraphics
import XCTest
@testable import TaskStrips

/// What ends up in the PNG. A sketch is only the file it saves, so these read the pixels back
/// rather than trusting the drawing calls.
final class SketchRendererTests: XCTestCase {

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
        let count = image.width * image.height * 4
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        bytes.initialize(repeating: 0, count: count)
        defer { bytes.deallocate() }
        let context = try XCTUnwrap(CGContext(
            data: bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // The context is y-up and the canvas is y-down, so a caller's y counts from the top.
        let offset = ((image.height - 1 - y) * image.width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    private func isNear(_ pixel: (r: Int, g: Int, b: Int), _ hex: UInt32, tolerance: Int = 12) -> Bool {
        let red = Int((hex >> 16) & 0xFF)
        let green = Int((hex >> 8) & 0xFF)
        let blue = Int(hex & 0xFF)
        return abs(pixel.r - red) <= tolerance
            && abs(pixel.g - green) <= tolerance
            && abs(pixel.b - blue) <= tolerance
    }

    func testAnUntouchedPageIsPaper() throws {
        let image = try XCTUnwrap(SketchRenderer.render(size: CGSize(width: 40, height: 40), strokes: []))

        XCTAssertTrue(isNear(try pixel(image, x: 20, y: 20), 0xF4EFE1))
    }

    func testAStrokeLandsWhereTheCanvasSaidItWent() throws {
        let stroke = SketchStroke(
            points: [CGPoint(x: 5, y: 10), CGPoint(x: 35, y: 10)], ink: .urgent, width: 6
        )

        let image = try XCTUnwrap(
            SketchRenderer.render(size: CGSize(width: 40, height: 40), strokes: [stroke])
        )

        XCTAssertTrue(isNear(try pixel(image, x: 20, y: 10), 0xC0392B), "the line should be here")
        XCTAssertTrue(isNear(try pixel(image, x: 20, y: 30), 0xF4EFE1), "and nowhere else")
    }

    /// The whole reason single-point strokes are drawn as circles: a zero-length path draws
    /// nothing, so a click would leave no mark at all.
    func testAClickThatNeverMovesStillLeavesADot() throws {
        let dot = SketchStroke(points: [CGPoint(x: 20, y: 20)], ink: .ink, width: 14)

        let image = try XCTUnwrap(
            SketchRenderer.render(size: CGSize(width: 40, height: 40), strokes: [dot])
        )

        XCTAssertTrue(isNear(try pixel(image, x: 20, y: 20), 0x262220))
        XCTAssertTrue(isNear(try pixel(image, x: 20, y: 5), 0xF4EFE1))
    }

    func testABoldNibCoversMoreThanAFineOne() throws {
        func inkedRows(width: CGFloat) throws -> Int {
            let stroke = SketchStroke(
                points: [CGPoint(x: 5, y: 20), CGPoint(x: 35, y: 20)], ink: .ink, width: width
            )
            let image = try XCTUnwrap(
                SketchRenderer.render(size: CGSize(width: 40, height: 40), strokes: [stroke])
            )
            return try (0..<40).filter { try isNear(pixel(image, x: 20, y: $0), 0x262220, tolerance: 40) }.count
        }

        XCTAssertGreaterThan(
            try inkedRows(width: SketchPenWidth.bold.rawValue),
            try inkedRows(width: SketchPenWidth.fine.rawValue)
        )
    }

    /// Saving re-renders the page from what's on disk plus this sitting's strokes, so a page
    /// edited twice has to still show the first edit.
    func testAnEarlierPageShowsThroughTheNewStrokes() throws {
        let first = try XCTUnwrap(SketchRenderer.render(
            size: CGSize(width: 40, height: 40),
            strokes: [SketchStroke(points: [CGPoint(x: 5, y: 10), CGPoint(x: 35, y: 10)], ink: .urgent, width: 6)]
        ))

        let second = try XCTUnwrap(SketchRenderer.render(
            size: CGSize(width: 40, height: 40),
            background: first,
            strokes: [SketchStroke(points: [CGPoint(x: 5, y: 30), CGPoint(x: 35, y: 30)], ink: .blue, width: 6)]
        ))

        XCTAssertTrue(isNear(try pixel(second, x: 20, y: 10), 0xC0392B), "the first line survived")
        XCTAssertTrue(isNear(try pixel(second, x: 20, y: 30), 0x3E5C8A), "and the second one is there")
    }

    /// A page drawn on a phone is a different shape from the Mac window it opens in.
    func testAPageFromAnotherScreenIsStretchedToFillThisOne() throws {
        let small = try XCTUnwrap(SketchRenderer.render(
            size: CGSize(width: 20, height: 20),
            strokes: [SketchStroke(points: [CGPoint(x: 0, y: 5), CGPoint(x: 19, y: 5)], ink: .amber, width: 4)]
        ))

        let stretched = try XCTUnwrap(
            SketchRenderer.render(size: CGSize(width: 80, height: 80), background: small, strokes: [])
        )

        // A quarter of the way down the small page is a quarter of the way down the big one.
        XCTAssertTrue(isNear(try pixel(stretched, x: 40, y: 20), 0xE0A63A, tolerance: 30))
    }

    func testAPlacedImageEndsUpTheRightWayUpAndInTheRightPlace() throws {
        // A picture with a red top half and a green bottom half, so "upside down" is visible.
        let source = try XCTUnwrap(SketchRenderer.render(
            size: CGSize(width: 20, height: 20),
            strokes: [
                SketchStroke(points: [CGPoint(x: 0, y: 5), CGPoint(x: 20, y: 5)], ink: .urgent, width: 10),
                SketchStroke(points: [CGPoint(x: 0, y: 15), CGPoint(x: 20, y: 15)], ink: .normal, width: 10)
            ]
        ))

        let page = try XCTUnwrap(SketchRenderer.render(
            size: CGSize(width: 40, height: 40),
            strokes: [],
            overlay: SketchRenderer.Overlay(image: source, rect: CGRect(x: 10, y: 0, width: 20, height: 20))
        ))

        XCTAssertTrue(isNear(try pixel(page, x: 20, y: 5), 0xC0392B, tolerance: 40), "red stays on top")
        XCTAssertTrue(isNear(try pixel(page, x: 20, y: 15), 0x3D7A5C, tolerance: 40), "green stays below")
        XCTAssertTrue(isNear(try pixel(page, x: 3, y: 20), 0xF4EFE1), "and the rest is still paper")
    }

    func testAZeroSizedCanvasRendersNothingRatherThanCrashing() {
        XCTAssertNil(SketchRenderer.render(size: .zero, strokes: []))
    }

    func testWhatItWritesIsAPNG() throws {
        let data = try XCTUnwrap(
            SketchRenderer.png(size: CGSize(width: 8, height: 8), strokes: [])
        )

        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}

/// Where a picked image starts out.
final class SketchImagePlacementTests: XCTestCase {

    func testAPickedImageStartsCentredAndComfortablyInside() {
        let placement = SketchImagePlacement.initial(
            imageSize: CGSize(width: 1000, height: 1000), canvas: CGSize(width: 500, height: 400)
        )

        XCTAssertEqual(placement.scale, 0.28, accuracy: 0.0001)  // 400 * 0.7 / 1000
        let rect = placement.rect(for: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(rect.midX, 250, accuracy: 0.0001)
        XCTAssertEqual(rect.midY, 200, accuracy: 0.0001)
    }

    /// Blowing a small image up to fill the page would read as a bug, not a starting point.
    func testASmallImageIsNotBlownUpToFit() {
        let placement = SketchImagePlacement.initial(
            imageSize: CGSize(width: 10, height: 10), canvas: CGSize(width: 500, height: 400)
        )

        XCTAssertEqual(placement.scale, 1)
    }

    func testAnImageWithNoSizeIsLeftAlone() {
        let placement = SketchImagePlacement.initial(imageSize: .zero, canvas: CGSize(width: 500, height: 400))

        XCTAssertEqual(placement, SketchImagePlacement(offset: .zero, scale: 1))
    }

    func testPinchingCannotShrinkItAwayOrBlowItUpForever() {
        var placement = SketchImagePlacement(offset: .zero, scale: 1)

        for _ in 0..<50 { placement.magnify(by: 0.5) }
        XCTAssertEqual(placement.scale, 0.1, accuracy: 0.0001)

        for _ in 0..<50 { placement.magnify(by: 2) }
        XCTAssertEqual(placement.scale, 10, accuracy: 0.0001)
    }
}
