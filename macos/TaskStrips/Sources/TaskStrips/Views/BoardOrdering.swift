import Foundation

/// Where a strip is being sent, for the reorder actions that don't involve a drag.
enum BoardMove: CaseIterable {
    case up
    case down
    case top
    case bottom

    var label: String {
        switch self {
        case .up: return "Move Up"
        case .down: return "Move Down"
        case .top: return "Move to Top"
        case .bottom: return "Move to Bottom"
        }
    }

    var systemImage: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .top: return "arrow.up.to.line"
        case .bottom: return "arrow.down.to.line"
        }
    }
}

/// The board's manual order, kept out of the view so it can be tested without a trackpad.
///
/// `List.onMove` is the only reorder path SwiftUI gives us and it needs a real drag gesture —
/// the same limitation that made swipe actions unreachable for a mouse-only or VoiceOver user
/// (see the context menu in `TaskListView.row(for:)`). Everything here is driven by the menu
/// actions instead, and `move(from:to:)` is what the drag calls when a trackpad is available, so
/// both paths land in the same renumbering.
enum BoardOrdering {
    /// Rewrites `ordered`'s strips to 0..<n so `orderIndex` always matches what the board shows,
    /// skipping the ones already in place rather than dirtying every row on every move.
    static func renumber(_ ordered: [TaskItem]) {
        for (position, task) in ordered.enumerated() where task.orderIndex != position {
            task.orderIndex = position
        }
    }

    /// The drag path.
    static func move(from source: IndexSet, to destination: Int, in visible: [TaskItem]) {
        var reordered = visible
        reordered.move(fromOffsets: source, toOffset: destination)
        renumber(reordered)
    }

    /// The index `task` would land on, or nil when the move is a no-op (already at that end).
    static func destination(for move: BoardMove, from index: Int, count: Int) -> Int? {
        switch move {
        case .up: return index > 0 ? index - 1 : nil
        case .down: return index < count - 1 ? index + 1 : nil
        case .top: return index > 0 ? 0 : nil
        case .bottom: return index < count - 1 ? count - 1 : nil
        }
    }

    static func canMove(_ task: TaskItem, _ move: BoardMove, in visible: [TaskItem]) -> Bool {
        guard let index = visible.firstIndex(where: { $0.id == task.id }) else { return false }
        return destination(for: move, from: index, count: visible.count) != nil
    }

    /// The menu path. Returns false when there was nowhere to go.
    @discardableResult
    static func move(_ task: TaskItem, _ move: BoardMove, in visible: [TaskItem]) -> Bool {
        guard let index = visible.firstIndex(where: { $0.id == task.id }),
              let target = destination(for: move, from: index, count: visible.count)
        else { return false }

        var reordered = visible
        reordered.remove(at: index)
        reordered.insert(task, at: target)
        renumber(reordered)
        return true
    }
}
