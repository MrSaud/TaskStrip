import Foundation

/// How the board is narrowed down and ordered: search, one tag, priorities, today and overdue,
/// a range of due dates, and the progress sort. One copy for the Mac and the iPhone/iPad, so the
/// same question gives the same answer on both — and so the rules can be tested without a board
/// on screen.
///
/// Mirrors what Android's home screen offers (ui/screens/HomeScreen.kt), including its search
/// across titles, notes and tags.
struct BoardFilter: Equatable {
    enum Sort: String, CaseIterable, Identifiable, Equatable {
        case manual = "Manual order"
        case progressAscending = "Progress ↑"
        case progressDescending = "Progress ↓"
        var id: String { rawValue }
    }

    var search = ""
    var tag: String?
    /// Empty means every priority, as on Android.
    var priorities: Set<Priority> = []
    /// Due today or already overdue. A finished strip stays visible, so completing something
    /// doesn't make it vanish from under the finger that completed it.
    var todayOnly = false
    var dueFrom: Date?
    var dueTo: Date?
    var sort: Sort = .manual

    var trimmedSearch: String { search.trimmingCharacters(in: .whitespaces) }

    /// Whether anything is narrowing the board — the sort doesn't hide strips, so it isn't part
    /// of this, but it does decide whether dragging can mean anything.
    var isNarrowing: Bool {
        !trimmedSearch.isEmpty || tag != nil || !priorities.isEmpty || todayOnly || dueFrom != nil || dueTo != nil
    }

    /// Dragging a strip only means something when every strip is showing, in board order.
    var allowsReordering: Bool { sort == .manual && !isNarrowing }

    /// How many things are hiding strips right now, for a badge on the filter button.
    var narrowingCount: Int {
        [!trimmedSearch.isEmpty, tag != nil, !priorities.isEmpty, todayOnly, dueFrom != nil || dueTo != nil]
            .filter { $0 }.count
    }

    mutating func clear() {
        self = BoardFilter(search: search, sort: sort)
    }

    func apply(to tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> [TaskItem] {
        var result = tasks.filter { matches($0, now: now, calendar: calendar) }
        switch sort {
        case .manual: break
        case .progressAscending: result.sort { $0.progress < $1.progress }
        case .progressDescending: result.sort { $0.progress > $1.progress }
        }
        return result
    }

    private func matches(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        let query = trimmedSearch
        if !query.isEmpty {
            let inTitle = task.title.localizedCaseInsensitiveContains(query)
            let inNotes = task.notes.localizedCaseInsensitiveContains(query)
            let inTags = task.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            guard inTitle || inNotes || inTags else { return false }
        }
        if let tag, !task.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { return false }
        if !priorities.isEmpty, !priorities.contains(task.priority) { return false }
        if todayOnly, !task.isDone {
            guard let due = task.dueAt, calendar.startOfDay(for: due) <= calendar.startOfDay(for: now) else { return false }
        }
        if dueFrom != nil || dueTo != nil {
            guard let due = task.dueAt else { return false }
            if let dueFrom, due < dueFrom { return false }
            if let dueTo, due > dueTo { return false }
        }
        return true
    }
}
