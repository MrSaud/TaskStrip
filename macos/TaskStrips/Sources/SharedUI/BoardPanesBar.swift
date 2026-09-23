import SwiftUI

/// The row that decides which lists the board keeps on screen — one chip per pane, lit when it's
/// showing. Not a segmented picker: these aren't a choice of one, they're three switches, and a
/// picker would say otherwise.
///
/// The chip for the last pane standing is dimmed rather than removed, so the rule explains itself
/// the moment someone tries it.
struct BoardPanesBar: View {
    @Binding var panes: BoardPanes

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BoardPane.onThisPlatform) { pane in
                let isOn = panes.shows(pane)
                let isLast = panes.isOnlyPane(pane)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { panes = panes.toggling(pane) }
                } label: {
                    Label(pane.title, systemImage: pane.symbol)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(isOn ? TaskStripTheme.ink : TaskStripTheme.paper.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isOn ? TaskStripTheme.amber : TaskStripTheme.baySurface)
                        .clipShape(Capsule())
                        .opacity(isLast ? 0.65 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isLast)
                .help(isLast ? "The board keeps at least one list" : (isOn ? "Hide \(pane.title.lowercased())" : "Show \(pane.title.lowercased())"))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(TaskStripTheme.baySurfaceFaded)
    }
}
