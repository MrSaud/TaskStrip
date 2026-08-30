import CoreGraphics

/// Where a just-picked image starts out on the page.
///
/// Its own type because it's the one bit of the image-placement flow that can be checked without a
/// window: scaled to sit comfortably inside the page and centred there, so the whole thing is
/// visible and only needs nudging — never blown up past its own size, since an image that arrives
/// already bigger than life reads as a bug rather than a starting point.
struct SketchImagePlacement: Equatable {
    var offset: CGPoint
    var scale: CGFloat

    static let fillFraction: CGFloat = 0.7

    static func initial(imageSize: CGSize, canvas: CGSize) -> SketchImagePlacement {
        guard imageSize.width > 0, imageSize.height > 0, canvas.width > 0, canvas.height > 0 else {
            return SketchImagePlacement(offset: .zero, scale: 1)
        }
        let scale = min(
            canvas.width * fillFraction / imageSize.width,
            canvas.height * fillFraction / imageSize.height,
            1
        )
        return SketchImagePlacement(
            offset: CGPoint(
                x: (canvas.width - imageSize.width * scale) / 2,
                y: (canvas.height - imageSize.height * scale) / 2
            ),
            scale: scale
        )
    }

    /// Clamped the way Android's pinch handler clamps it, so a stray gesture can't scale the
    /// image into nothing or into something no page could hold.
    mutating func magnify(by factor: CGFloat) {
        scale = min(max(scale * factor, 0.1), 10)
    }

    func rect(for imageSize: CGSize) -> CGRect {
        CGRect(
            x: offset.x,
            y: offset.y,
            width: max(imageSize.width * scale, 1),
            height: max(imageSize.height * scale, 1)
        )
    }
}
