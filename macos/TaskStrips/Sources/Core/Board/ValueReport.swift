import Foundation

/// A stretch of time to report on.
enum ValueRange: String, CaseIterable, Identifiable {
    case thisMonth
    case lastMonth
    case thisYear
    case everything

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        case .thisYear: return "This year"
        case .everything: return "All time"
        }
    }

    func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch self {
        case .everything:
            return true
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .lastMonth:
            guard let month = calendar.date(byAdding: .month, value: -1, to: now) else { return false }
            return calendar.isDate(date, equalTo: month, toGranularity: .month)
        case .thisYear:
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
        }
    }
}

/// What the board's totals add up to, gathered for reading rather than for keeping.
///
/// The strips themselves never add up across each other — a strip's total is its own. This is a
/// different thing: a question asked of the board at a moment, answered and forgotten. Nothing
/// here is stored, and nothing on a strip changes because a report was run.
enum ValueReport {
    /// One unit's worth inside a group. Hours and dinars can't be added together, so they never
    /// share a line.
    struct Amount: Equatable, Identifiable {
        var unit: TallyUnit
        var amount: Double
        var id: String { unit.label }
    }

    struct Group: Equatable, Identifiable {
        var name: String
        var amounts: [Amount]
        /// Which strips contributed, for the line under the group.
        var strips: [String]
        var id: String { name }
    }

    /// Strips with no tag at all still have to be counted somewhere.
    static let untagged = "No tag"

    /// Totals per tag. A strip with two tags counts under both — a report is a way of looking,
    /// and work done under WORK and MOSA belongs in both answers.
    static func byTag(
        _ tasks: [TaskItem],
        range: ValueRange,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Group] {
        var groups: [String: [String: Double]] = [:]   // tag → unit label → amount
        var units: [String: TallyUnit] = [:]
        var strips: [String: Set<String>] = [:]

        for task in tasks where !task.isTombstoned {
            let tags = task.tags.isEmpty ? [untagged] : task.tags
            for tally in task.tallies {
                let total = tally.entries
                    .filter { range.contains($0.at, now: now, calendar: calendar) }
                    .reduce(0) { $0 + $1.amount }
                guard total != 0 else { continue }
                for tag in tags {
                    groups[tag, default: [:]][tally.unit.label, default: 0] += total
                    units[tally.unit.label] = tally.unit
                    strips[tag, default: []].insert(task.title)
                }
            }
        }

        return groups
            .map { tag, amounts in
                Group(
                    name: tag,
                    amounts: amounts
                        .compactMap { label, amount in units[label].map { Amount(unit: $0, amount: amount) } }
                        .sorted { $0.unit.label < $1.unit.label },
                    strips: (strips[tag] ?? []).sorted()
                )
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// The same numbers per strip, for the detail behind a tag.
    static func byStrip(
        _ tasks: [TaskItem],
        range: ValueRange,
        tag: String? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Group] {
        tasks
            .filter { task in
                guard !task.isTombstoned else { return false }
                guard let tag else { return true }
                return tag == untagged
                    ? task.tags.isEmpty
                    : task.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
            .compactMap { task in
                let amounts: [Amount] = task.tallies.compactMap { tally in
                    let total = tally.entries
                        .filter { range.contains($0.at, now: now, calendar: calendar) }
                        .reduce(0) { $0 + $1.amount }
                    return total == 0 ? nil : Amount(unit: tally.unit, amount: total)
                }
                guard !amounts.isEmpty else { return nil }
                return Group(name: task.title.isEmpty ? "(untitled)" : task.title, amounts: amounts, strips: [])
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// One line per entry — the shape somebody can put in a spreadsheet, send to an accountant,
    /// or attach to an invoice. A summary can be rebuilt from lines; lines can't be rebuilt from
    /// a summary.
    static func csv(
        _ tasks: [TaskItem],
        range: ValueRange,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var lines = ["Date,Strip,Tags,Total,Unit,Amount,Note,Source"]
        for task in tasks.sorted(by: { $0.title.lowercased() < $1.title.lowercased() }) where !task.isTombstoned {
            for tally in task.tallies {
                for entry in tally.entries.sorted(by: { $0.at < $1.at })
                where range.contains(entry.at, now: now, calendar: calendar) {
                    lines.append(
                        [
                            formatter.string(from: entry.at),
                            quoted(task.title),
                            quoted(task.tags.joined(separator: " ")),
                            quoted(tally.name),
                            quoted(unitText(tally.unit)),
                            String(format: "%g", entry.amount),
                            quoted(entry.note),
                            entry.fromTimer ? "timer" : "typed",
                        ].joined(separator: ",")
                    )
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A title with a comma in it would otherwise become two columns.
    static func quoted(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// The unit as a word a spreadsheet can group by, with the currency spelled out.
    static func unitText(_ unit: TallyUnit) -> String {
        switch unit {
        case .hours: return "hours"
        case .minutes: return "minutes"
        case .count: return "count"
        case .money(let currency): return currency.isEmpty ? "money" : currency
        case .custom(let name): return name.isEmpty ? "other" : name
        }
    }

    static func fileName(for range: ValueRange, now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "TaskStrips-\(range.rawValue)-\(formatter.string(from: now)).csv"
    }
}
