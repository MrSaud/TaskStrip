import Foundation

/// How far along each tag is, mirroring ui/screens/TagProgressScreen.kt.
///
/// Tags are user-typed, so "Travel" and "travel" are the same tag — they're grouped
/// case-insensitively and shown in the spelling that appears first on the board.
struct TagProgress: Identifiable, Equatable {
    let tag: String
    let done: Int
    let total: Int

    var id: String { tag.lowercased() }
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }

    /// Busiest tag first. Ties keep the order the tags were first seen in, so the list doesn't
    /// reshuffle itself every time a strip is completed.
    static func stats(for tasks: [TaskItem]) -> [TagProgress] {
        var order: [String] = []
        var display: [String: String] = [:]
        var totals: [String: Int] = [:]
        var completed: [String: Int] = [:]

        for task in tasks {
            for tag in task.tags {
                let key = tag.lowercased()
                if display[key] == nil {
                    display[key] = tag
                    order.append(key)
                }
                totals[key, default: 0] += 1
                if task.isDone { completed[key, default: 0] += 1 }
            }
        }

        return order
            .map { key in
                TagProgress(tag: display[key] ?? key, done: completed[key] ?? 0, total: totals[key] ?? 0)
            }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.total == rhs.element.total
                    ? lhs.offset < rhs.offset
                    : lhs.element.total > rhs.element.total
            }
            .map(\.element)
    }
}
