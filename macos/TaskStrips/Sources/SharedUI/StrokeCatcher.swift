#if os(iOS)
import SwiftUI
import UIKit

/// Catches the strokes on iOS, in place of a SwiftUI drag gesture.
///
/// SwiftUI's gestures don't say what touched the screen, and the sketch pad has to know: with
/// "Draw with Finger" off, only an Apple Pencil draws, and a hand resting on the page is ignored
/// rather than being drawn as a blot. It also reads the touches the system coalesces between
/// screen refreshes, so a fast stroke comes out as a curve rather than a row of corners.
struct StrokeCatcher: UIViewRepresentable {
    /// When true, a finger is ignored and only a Pencil draws.
    var pencilOnly: Bool
    var onBegan: (CGPoint) -> Void
    var onMoved: ([CGPoint]) -> Void
    var onEnded: () -> Void
    /// A finger arrived while only a Pencil is allowed — worth saying, or the pad looks broken.
    var onRefused: () -> Void

    func makeUIView(context: Context) -> TouchView { TouchView() }

    func updateUIView(_ view: TouchView, context: Context) {
        view.pencilOnly = pencilOnly
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
        view.onRefused = onRefused
    }

    final class TouchView: UIView {
        var pencilOnly = false
        var onBegan: (CGPoint) -> Void = { _ in }
        var onMoved: ([CGPoint]) -> Void = { _ in }
        var onEnded: () -> Void = {}
        var onRefused: () -> Void = {}

        /// One stroke at a time: a second finger during a stroke is another hand on the page, not
        /// a second pen.
        private weak var drawing: UITouch?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = true
        }

        required init?(coder: NSCoder) { fatalError("Made in code, never from a storyboard.") }

        private func accepts(_ touch: UITouch) -> Bool { !pencilOnly || touch.type == .pencil }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard drawing == nil else { return }
            guard let touch = touches.first(where: accepts) else {
                onRefused()
                return
            }
            drawing = touch
            onBegan(touch.location(in: self))
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let drawing, touches.contains(drawing) else { return }
            let steps = event?.coalescedTouches(for: drawing) ?? [drawing]
            onMoved(steps.map { $0.location(in: self) })
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        private func finish(_ touches: Set<UITouch>) {
            guard let drawing, touches.contains(drawing) else { return }
            self.drawing = nil
            onEnded()
        }
    }
}
#endif
