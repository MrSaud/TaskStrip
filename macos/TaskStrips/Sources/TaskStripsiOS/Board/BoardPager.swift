import SwiftUI

/// Two pages side by side, moved by a horizontal drag — built by hand instead of a page-style
/// TabView, for the same reason Android's board is.
///
/// A paging scroll view claims every horizontal pan in both directions, even at its first page
/// where it has nowhere to go, so a strip's swipe-right-to-complete never fires (checked in the
/// simulator: the row doesn't move). This pager claims only the direction that leads somewhere:
/// on the first page a drag to the right is left alone for the strip under the finger, and
/// on the last page a drag to the left is. Its gesture runs alongside the list's, so a list row
/// with a swipe action for that direction still gets it.
struct BoardPager<Page: Hashable, Content: View>: View {
    let pages: [Page]
    @Binding var selection: Page
    @ViewBuilder let content: (Page) -> Content

    @State private var dragOffset: CGFloat = 0
    /// Decided once per drag from its first movement, so a vertical scroll that wobbles sideways
    /// never turns into a page change halfway through.
    @State private var isHorizontalDrag: Bool?

    /// How far, as a fraction of the width, a drag must go to turn the page on release. A fast
    /// flick turns it sooner — see `predictedEndTranslation`.
    private let turnThreshold: CGFloat = 0.25

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let index = CGFloat(pages.firstIndex(of: selection) ?? 0)

            HStack(spacing: 0) {
                ForEach(pages, id: \.self) { page in
                    content(page)
                        .frame(width: width)
                }
            }
            .offset(x: -index * width + dragOffset)
            .frame(width: width, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(drag(width: width, index: Int(index)))
        }
    }

    private func drag(width: CGFloat, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let dx = value.translation.width
                if isHorizontalDrag == nil {
                    isHorizontalDrag = abs(dx) > abs(value.translation.height)
                }
                guard isHorizontalDrag == true else { return }
                dragOffset = allowed(dx, index: index)
            }
            .onEnded { value in
                defer { isHorizontalDrag = nil }
                guard isHorizontalDrag == true else { return }
                let travel = allowed(value.predictedEndTranslation.width, index: index)
                var target = index
                if travel < -width * turnThreshold { target = index + 1 }
                if travel > width * turnThreshold { target = index - 1 }
                target = min(max(target, 0), pages.count - 1)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    dragOffset = 0
                    selection = pages[target]
                }
            }
    }

    /// Zero for a drag toward a page that doesn't exist, which is what leaves it for the row.
    private func allowed(_ dx: CGFloat, index: Int) -> CGFloat {
        if dx > 0 && index == 0 { return 0 }
        if dx < 0 && index == pages.count - 1 { return 0 }
        return dx
    }
}
