import Foundation

/// One of the lists the board can keep on screen.
///
/// The Mac and the iPad have the room to hold more than one at a time; the iPhone doesn't, and
/// keeps its pager. Quick Notes is here because a scratchpad you have to open is a scratchpad you
/// forget — pinned beside the strips it works the way a pad of sticky notes on a desk does.
enum BoardPane: String, CaseIterable, Identifiable, Equatable {
    case strips
    case reminders
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strips: return "STRIPS"
        case .reminders: return "REMINDERS"
        case .notes: return "NOTES"
        }
    }

    var symbol: String {
        switch self {
        case .strips: return "list.bullet.rectangle"
        case .reminders: return "bell"
        case .notes: return "note.text"
        }
    }

    var flag: BoardPanes { BoardPanes(pane: self) }
}

/// Which panes are showing, remembered per device.
///
/// A set rather than a choice of one: the point is to see the strips and the reminders together,
/// and to put either away when they're in the way. The last pane can't be switched off — a board
/// with nothing on it is a blank window, and there'd be nothing left to click to get back.
struct BoardPanes: OptionSet, Equatable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    init(pane: BoardPane) {
        switch pane {
        case .strips: self = BoardPanes(rawValue: 1 << 0)
        case .reminders: self = BoardPanes(rawValue: 1 << 1)
        case .notes: self = BoardPanes(rawValue: 1 << 2)
        }
    }

    static let strips = BoardPanes(pane: .strips)
    static let reminders = BoardPanes(pane: .reminders)
    static let notes = BoardPanes(pane: .notes)

    /// What a Mac or an iPad opens with: everything, since the reason to have the room is to use
    /// it. Whatever gets in the way is one tap from gone, and it stays gone.
    static let everything: BoardPanes = [.strips, .reminders, .notes]

    var showing: [BoardPane] { BoardPane.allCases.filter { contains($0.flag) } }

    func shows(_ pane: BoardPane) -> Bool { contains(pane.flag) }

    var count: Int { showing.count }

    /// True when this pane is the only one left, and so the one that can't be put away.
    func isOnlyPane(_ pane: BoardPane) -> Bool { showing == [pane] }

    /// Turns a pane on, or off if it's on — unless it's the last one showing, which stays.
    func toggling(_ pane: BoardPane) -> BoardPanes {
        if !shows(pane) { return union(pane.flag) }
        if isOnlyPane(pane) { return self }
        return subtracting(pane.flag)
    }

    /// Brings a pane into view without disturbing the others — what a menu item or a shortcut
    /// that names a pane should do.
    func showing(_ pane: BoardPane) -> BoardPanes { union(pane.flag) }

    /// The next pane on its own, for a swipe on a board showing a single pane. Nil at the ends,
    /// like the phone's pager: running off the edge stops rather than looping.
    func single(after pane: BoardPane) -> BoardPanes? {
        guard let index = BoardPane.allCases.firstIndex(of: pane), index + 1 < BoardPane.allCases.count else { return nil }
        return BoardPanes(pane: BoardPane.allCases[index + 1])
    }

    func single(before pane: BoardPane) -> BoardPanes? {
        guard let index = BoardPane.allCases.firstIndex(of: pane), index > 0 else { return nil }
        return BoardPanes(pane: BoardPane.allCases[index - 1])
    }

    /// The one pane showing, if only one is.
    var lonePane: BoardPane? { count == 1 ? showing.first : nil }
}
