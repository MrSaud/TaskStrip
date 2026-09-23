import SwiftUI

/// The line between two panes, which can be dragged.
///
/// The Mac gets this from HSplitView; an iPad's HStack has no such thing, so the divider carries
/// the gesture itself. It adjusts the pane on its left and lets the rest of the row take up the
/// slack, which is how a split view behaves and how anyone expects a divider to.
struct PaneDivider: View {
    @Binding var width: Double
    /// How narrow and how wide that pane may get. A pane narrower than this is a column of
    /// truncated words, and one wider leaves nothing for its neighbours.
    var range: ClosedRange<Double> = 220...560

    /// Where the pane started when this drag began, so a drag is measured from where it started
    /// rather than accumulating rounding on every tick.
    @State private var startWidth: Double?
    @State private var isDragging = false

    var body: some View {
        Divider()
            .overlay {
                // A one-pixel line is not a target for a finger. The grab area is wider than the
                // line, and invisible.
                Rectangle()
                    .fill(isDragging ? TaskStripTheme.amber.opacity(0.35) : .clear)
                    .frame(width: isDragging ? 3 : 14)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                isDragging = true
                                let start = startWidth ?? width
                                startWidth = start
                                width = min(max(start + value.translation.width, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in
                                startWidth = nil
                                isDragging = false
                            }
                    )
                    #if os(macOS)
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    #endif
            }
            .accessibilityLabel("Resize this pane")
    }
}

/// How wide each pane is, remembered per pane and per device.
///
/// Not synced: an iPad's panes and a Mac's window are different shapes, and a width that suits one
/// is wrong on the other.
enum PaneWidth {
    static func key(_ pane: BoardPane) -> String { "paneWidth.\(pane.rawValue)" }

    /// What each pane opens at before anybody drags anything — the widths the board used when
    /// they were fixed.
    static func standard(_ pane: BoardPane) -> Double {
        switch pane {
        case .today: return 320
        case .strips: return 420
        case .reminders: return 380
        case .notes: return 260
        case .inbox: return 320
        }
    }
}
