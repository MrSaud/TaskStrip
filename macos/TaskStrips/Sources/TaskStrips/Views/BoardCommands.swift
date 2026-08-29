import SwiftUI

/// What the menu bar can do to the strip the board has selected.
struct SelectedStripCommands {
    var isDone: Bool
    var edit: () -> Void
    var toggleDone: () -> Void
    var archive: () -> Void
    var delete: () -> Void
    var canMove: (BoardMove) -> Bool
    var move: (BoardMove) -> Void
}

/// What the menu bar can do to the board itself. `selection` is nil when no strip is picked, and
/// that's what greys out half the Strip menu.
struct BoardCommandTarget {
    var newStrip: () -> Void
    var importBackup: () -> Void
    var showArchived: () -> Void
    var clearFilters: () -> Void
    var isFiltered: Bool
    var sortMode: ProgressSort
    var setSortMode: (ProgressSort) -> Void
    var selection: SelectedStripCommands?
}

private struct BoardCommandTargetKey: FocusedValueKey {
    typealias Value = BoardCommandTarget
}

extension FocusedValues {
    /// Published by the board window, read by the menu bar. A focused *scene* value rather than a
    /// focused value: the menus should follow the front window, not whichever control inside it
    /// happens to hold keyboard focus.
    var boardCommands: BoardCommandTarget? {
        get { self[BoardCommandTargetKey.self] }
        set { self[BoardCommandTargetKey.self] = newValue }
    }
}

extension BoardMove {
    var keyboardShortcut: KeyboardShortcut {
        switch self {
        case .up: return KeyboardShortcut(.upArrow, modifiers: .command)
        case .down: return KeyboardShortcut(.downArrow, modifiers: .command)
        case .top: return KeyboardShortcut(.upArrow, modifiers: [.command, .option])
        case .bottom: return KeyboardShortcut(.downArrow, modifiers: [.command, .option])
        }
    }
}

/// The app's menu bar.
///
/// Everything here already exists on the board as a toolbar button or a context-menu item — the
/// point is that a Mac app's capabilities are supposed to be discoverable in its menus and
/// reachable from the keyboard, not only by finding the right thing to right-click.
struct BoardCommandMenus: Commands {
    @FocusedValue(\.boardCommands) private var board

    private var sortMode: Binding<ProgressSort> {
        Binding(
            get: { board?.sortMode ?? .manual },
            set: { board?.setSortMode($0) }
        )
    }

    var body: some Commands {
        // Replacing rather than extending: cmd-N on a single-board app should file a strip, not
        // open a second window onto the same one.
        CommandGroup(replacing: .newItem) {
            Button("New Strip") { board?.newStrip() }
                .keyboardShortcut("n")
                .disabled(board == nil)
            Divider()
            Button("Import Android Backup…") { board?.importBackup() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(board == nil)
        }

        CommandMenu("Strip") {
            // Gated on the board rather than on the selection, and that difference is load-
            // bearing: a menu item that starts disabled doesn't get its enabled state pushed into
            // the real NSMenu until the menu is first opened, so its key equivalent is silently
            // dropped until then. CI pinned that down exactly — the shortcut failed cold and
            // passed once the menu had been opened and closed. These four are the ones people
            // press without ever pulling the menu down, so they stay enabled and simply do
            // nothing when no strip is selected.
            Button(board?.selection?.isDone == true ? "Reopen" : "Complete") {
                board?.selection?.toggleDone()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(board == nil)

            // Not cmd-E: `.searchable` on the board installs the standard Find group, whose
            // "Use Selection for Find" already owns cmd-E — and the Edit menu comes before this
            // one, so it won. CI caught it as the menu item being enabled while the shortcut did
            // nothing. Worth knowing that the same Find group means cmd-F reaches the search
            // field for free.
            Button("Edit…") { board?.selection?.edit() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(board == nil)

            Divider()

            // Kept gated on the selection, unlike the four above: "this strip is already at the
            // top" is worth showing, and it's only ever visible with the menu open — which is
            // also what makes these shortcuts live. The cost is that cmd-arrow does nothing until
            // the menu has been pulled down once.
            ForEach(BoardMove.allCases, id: \.self) { move in
                Button(move.label) { board?.selection?.move(move) }
                    .keyboardShortcut(move.keyboardShortcut)
                    .disabled(board?.selection?.canMove(move) != true)
            }

            Divider()

            Button("Archive") { board?.selection?.archive() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(board == nil)

            Button("Delete") { board?.selection?.delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(board == nil)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Picker("Sort By", selection: sortMode) {
                ForEach(ProgressSort.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .disabled(board == nil)

            Button("Show All Strips") { board?.clearFilters() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(board?.isFiltered != true)

            Button("Archived Strips…") { board?.showArchived() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(board == nil)
        }
    }
}
