import AppKit
import SwiftUI

/// A two-finger horizontal swipe, which SwiftUI has no gesture for on macOS.
///
/// A trackpad swipe arrives as a scroll event, not a drag, so `DragGesture` never sees it and the
/// event has to be read from AppKit. Only gesture-phase events whose intent is clearly horizontal
/// count, so scrolling a list up and down never moves the board sideways.
struct HorizontalSwipe: ViewModifier {
    /// `forward` is true when the content was pushed left, which is the direction that advances a
    /// page — the content follows the fingers, as it does on the phone.
    let onSwipe: (_ forward: Bool) -> Void

    @State private var monitor: Any?
    @State private var travel: CGFloat = 0

    /// Enough deliberate sideways movement that a slightly-off vertical scroll can't trip it.
    private static let threshold: CGFloat = 50

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    handle(event)
                    return event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
                monitor = nil
            }
    }

    private func handle(_ event: NSEvent) {
        switch event.phase {
        case .began:
            travel = 0
        case .changed:
            // A mostly-vertical scroll belongs to the list underneath, not to the board.
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
            travel += event.scrollingDeltaX
            guard abs(travel) >= Self.threshold else { return }
            onSwipe(travel < 0)
            // Zeroed rather than left to keep accumulating, so one long swipe moves one page.
            travel = 0
        case .ended, .cancelled:
            travel = 0
        default:
            break
        }
    }
}
