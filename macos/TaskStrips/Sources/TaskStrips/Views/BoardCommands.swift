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
            Button(board?.selection?.isDone == true ? "Reopen" : "Complete") {
                board?.selection?.toggleDone()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(board?.selection == nil)

            Button("Edit…") { board?.selection?.edit() }
                .keyboardShortcut("e")
                .disabled(board?.selection == nil)

            Divider()

            ForEach(BoardMove.allCases, id: \.self) { move in
                Button(move.label) { board?.selection?.move(move) }
                    .keyboardShortcut(move.keyboardShortcut)
                    .disabled(board?.selection?.canMove(move) != true)
            }

            Divider()

            Button("Archive") { board?.selection?.archive() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(board?.selection == nil)

            Button("Delete") { board?.selection?.delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(board?.selection == nil)
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
