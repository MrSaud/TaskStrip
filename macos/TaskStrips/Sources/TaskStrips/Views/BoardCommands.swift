import SwiftUI

/// What the menu bar needs to *know*, as plain comparable data.
///
/// This used to be a struct of closures, and that was the bug: SwiftUI can't compare closures, so
/// it couldn't tell one value of the focused scene value from the next and never pushed the
/// Commands into the real NSMenu. The menu was only rebuilt when it was opened, which is why every
/// Strip shortcut was inert until you'd pulled the menu down once. Everything here is Equatable so
/// a change is a change.
///
/// `visibleIDs` earns its place: without it the state wouldn't change when the board reorders
/// underneath an unchanged selection, and the republished actions below would keep working off a
/// stale view of the board.
struct BoardCommandState: Equatable {
    var selectedID: TaskItem.ID?
    var selectionIsDone: Bool = false
    /// Whether the selected strip has anything worth reading out.
    var selectionHasNotes: Bool = false
    var availableMoves: Set<BoardMove> = []
    var isFiltered: Bool = false
    var sortMode: ProgressSort = .manual
    var visibleIDs: [TaskItem.ID] = []

    var hasSelection: Bool { selectedID != nil }
}

/// What the menu bar needs to *do*.
///
/// Deliberately not part of the focused value. A menu item captures its action closure once, and
/// if the menu isn't rebuilt that closure goes stale — pointing at whatever was selected when it
/// was captured, or at nothing. Every command below closes over this object instead, which never
/// changes identity, and reads the current action out of it at the moment the key is pressed. So
/// even an NSMenuItem SwiftUI never got round to refreshing still does the right thing.
///
/// A singleton because the app is one window onto one board. A second window would need this
/// scoped per scene.
final class BoardActions {
    static let shared = BoardActions()
    private init() {}

    var newStrip: () -> Void = {}
    var newStripByVoice: () -> Void = {}
    var readSelectionAloud: () -> Void = {}
    var importBackup: () -> Void = {}
    var exportBackup: () -> Void = {}
    var showDrive: () -> Void = {}
    var showArchived: () -> Void = {}
    var showNotes: () -> Void = {}
    var showStorage: () -> Void = {}
    var showReminders: () -> Void = {}
    var showCredentials: () -> Void = {}
    var showSketches: () -> Void = {}
    var showSyncNotes: () -> Void = {}
    var showRollUp: (RollUp) -> Void = { _ in }
    var clearFilters: () -> Void = {}
    var setSortMode: (ProgressSort) -> Void = { _ in }

    var editSelection: () -> Void = {}
    var toggleSelectionDone: () -> Void = {}
    var archiveSelection: () -> Void = {}
    var deleteSelection: () -> Void = {}
    var moveSelection: (BoardMove) -> Void = { _ in }

    /// Called when the board goes away or loses its selection, so a stale menu item can't act on
    /// a strip that isn't there any more.
    func clearSelectionActions() {
        readSelectionAloud = {}
        editSelection = {}
        toggleSelectionDone = {}
        archiveSelection = {}
        deleteSelection = {}
        moveSelection = { _ in }
    }
}

private struct BoardCommandStateKey: FocusedValueKey {
    typealias Value = BoardCommandState
}

extension FocusedValues {
    /// Published by the board window, read by the menu bar. A focused *scene* value rather than a
    /// focused value: the menus should follow the front window, not whichever control inside it
    /// happens to hold keyboard focus.
    var boardCommandState: BoardCommandState? {
        get { self[BoardCommandStateKey.self] }
        set { self[BoardCommandStateKey.self] = newValue }
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
    @FocusedValue(\.boardCommandState) private var state

    private var actions: BoardActions { .shared }

    private var sortMode: Binding<ProgressSort> {
        Binding(
            get: { state?.sortMode ?? .manual },
            set: { actions.setSortMode($0) }
        )
    }

    var body: some Commands {
        // Replacing rather than extending: cmd-N on a single-board app should file a strip, not
        // open a second window onto the same one.
        CommandGroup(replacing: .newItem) {
            Button("New Strip") { actions.newStrip() }
                .keyboardShortcut("n")
                .disabled(state == nil)

            Button("New Strip by Voice…") { actions.newStripByVoice() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(state == nil)
            Divider()
            Button("Import Android Backup…") { actions.importBackup() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(state == nil)

            Button("Export Backup…") { actions.exportBackup() }
                .keyboardShortcut("e", modifiers: [.command, .shift, .option])
                .disabled(state == nil)

            Button("Google Drive…") { actions.showDrive() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(state == nil)
        }

        CommandMenu("Strip") {
            // Selection-gated, because the greying is worth having and the shortcut is broken
            // either way — see the note on testTheEditShortcutOpensTheEditorForTheSelectedStrip
            // for the four explanations CI has ruled out, and the one still standing.
            Button(state?.selectionIsDone == true ? "Reopen" : "Complete") {
                actions.toggleSelectionDone()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(state?.hasSelection != true)

            // Not cmd-E: `.searchable` on the board installs the standard Find group, whose
            // "Use Selection for Find" already owns it, and the Edit menu comes first in the bar.
            Button("Edit…") { actions.editSelection() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(state?.hasSelection != true)

            Divider()

            ForEach(BoardMove.allCases, id: \.self) { move in
                Button(move.label) { actions.moveSelection(move) }
                    .keyboardShortcut(move.keyboardShortcut)
                    .disabled(state?.availableMoves.contains(move) != true)
            }

            Divider()

            Button("Read Notes Aloud") { actions.readSelectionAloud() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                // Greyed out for a strip with no notes: there would be nothing to read, and the
                // title is already on screen.
                .disabled(state?.selectionHasNotes != true)

            Divider()

            Button("Archive") { actions.archiveSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(state?.hasSelection != true)

            Button("Delete") { actions.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(state?.hasSelection != true)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Picker("Sort By", selection: sortMode) {
                ForEach(ProgressSort.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .disabled(state == nil)

            Button("Show All Strips") { actions.clearFilters() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(state?.isFiltered != true)

            Button("Archived Strips…") { actions.showArchived() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state == nil)

            Button("Quick Notes…") { actions.showNotes() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(state == nil)

            Button("Storage Library…") { actions.showStorage() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(state == nil)

            Button("Reminders…") { actions.showReminders() }
                .keyboardShortcut("y", modifiers: [.command, .shift])
                .disabled(state == nil)

            Button("Credentials…") { actions.showCredentials() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(state == nil)

            Button("Sketch Notes…") { actions.showSketches() }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(state == nil)

            Button("Sync Notes…") { actions.showSyncNotes() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(state == nil)

            Divider()

            Button("Standup Summary…") { actions.showRollUp(.standup) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(state == nil)

            Button("Tag Progress…") { actions.showRollUp(.tags) }
                .disabled(state == nil)
        }
    }
}
