import SwiftData
import SwiftUI

/// "Put this on a strip" — the board's active strips, in board order, as a menu.
///
/// Active means on the board and not finished: an archived strip or one already ticked off is not
/// somewhere anyone means to file today's email or today's invoice, and a menu of everything ever
/// filed is a menu nobody can read.
struct StripPickerMenu<Label: View>: View {
    var title: String = "Add to a strip"
    /// Something to say about a particular strip in its own row — "replaces its sketch", say.
    var note: (TaskItem) -> String? = { _ in nil }
    let onPick: (TaskItem) -> Void
    @ViewBuilder var label: () -> Label

    /// The board's own order, so the menu reads the way the board does.
    @Query(
        filter: #Predicate<TaskItem> { !$0.isArchived && !$0.isDone },
        sort: [SortDescriptor(\TaskItem.orderIndex)]
    ) private var strips: [TaskItem]

    /// As far as a menu is worth reading. A board with two hundred strips on it doesn't want all
    /// of them here.
    static var limit: Int { 40 }

    var body: some View {
        Menu {
            if strips.isEmpty {
                Text("No active strips on the board")
            } else {
                Section(title) {
                    ForEach(strips.prefix(Self.limit)) { strip in
                        let name = strip.title.isEmpty ? "(untitled strip)" : strip.title
                        Button(note(strip).map { "\(name) — \($0)" } ?? name) { onPick(strip) }
                    }
                }
                if strips.count > Self.limit {
                    Text("…and \(strips.count - Self.limit) more")
                }
            }
        } label: {
            label()
        }
    }
}
