import Foundation

/// What a value is counted in.
///
/// Minutes and hours are the same thing underneath — a tally kept in either is shown as hours and
/// minutes once it passes an hour, because "3h 30m" is what somebody wants to read and "210" is
/// not. Money carries its own currency: a budget in dinars and a supplier's bill in dollars must
/// never quietly add up.
enum TallyUnit: Codable, Hashable {
    case minutes
    case hours
    case money(currency: String)
    case count
    case custom(String)

    var isTime: Bool {
        switch self {
        case .minutes, .hours: return true
        default: return false
        }
    }

    /// What one of these is called, for a picker.
    var label: String {
        switch self {
        case .minutes: return "Minutes"
        case .hours: return "Hours"
        case .money(let currency): return currency.isEmpty ? "Money" : currency
        case .count: return "Count"
        case .custom(let unit): return unit.isEmpty ? "Other" : unit
        }
    }

    /// The units offered before anybody types their own.
    static func offered(currency: String) -> [TallyUnit] {
        [.hours, .minutes, .money(currency: currency), .count]
    }
}

/// One addition to a tally: two hours today, a hundred dinars yesterday.
///
/// Dated, because a total nobody can take apart is a number to be distrusted — "where did the
/// three hours come from" has to have an answer.
struct TaskTallyEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var amount: Double = 0
    var at: Date = .now
    var note: String = ""
    /// Added by stopping the clock rather than typed in, which is worth telling apart when a
    /// total looks wrong.
    var fromTimer: Bool = false
}

/// A running total on a strip: hours spent, money spent, anything that accumulates.
///
/// A strip owns its tallies and nothing adds them up across strips. A strip is the piece of work,
/// and the total that matters is the total of this one.
struct TaskTally: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var unit: TallyUnit = .hours
    var entries: [TaskTallyEntry] = []
    /// A budget, or a goal. Optional because most tallies are just a total — a strip that is
    /// simply accumulating hours has no number it is aiming at or must stay under.
    var target: Double?

    var total: Double { entries.reduce(0) { $0 + $1.amount } }

    /// How far along, where there's something to be along towards. Above 1 when the target has
    /// been passed, which the bar shows as full and the colour shows as a problem.
    var progress: Double? {
        guard let target, target > 0 else { return nil }
        return total / target
    }

    /// What's left of a budget, or how far over it this has gone.
    var remaining: Double? {
        guard let target else { return nil }
        return target - total
    }

    var isOverTarget: Bool {
        guard let target, target > 0 else { return false }
        return total > target
    }

    /// The name a tally made by the timer gets, so there's something to add to before anybody
    /// has set one up by hand.
    static let timeName = "Time"

    var isFromTimer: Bool { entries.contains(where: \.fromTimer) }
}

/// The arithmetic and the wording, kept apart from the views so both platforms say the same thing
/// and a test can check it.
enum StripTally {
    /// A total as somebody reads it: "3h 30m", "KD 412.500", "12 km".
    static func formatted(_ amount: Double, unit: TallyUnit, locale: Locale = .current) -> String {
        switch unit {
        case .hours:
            return time(minutes: amount * 60)
        case .minutes:
            return time(minutes: amount)
        case .money(let currency):
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = locale
            formatter.currencyCode = currency
            return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
        case .count:
            return number(amount)
        case .custom(let unit):
            return unit.isEmpty ? number(amount) : "\(number(amount)) \(unit)"
        }
    }

    /// Hours and minutes, never a decimal: nobody books 2.75 hours of a meeting.
    static func time(minutes: Double) -> String {
        let whole = Int((minutes).rounded())
        guard whole >= 60 else { return "\(whole)m" }
        let hours = whole / 60
        let rest = whole % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    static func number(_ amount: Double) -> String {
        // A whole number reads as a whole number; a fraction keeps two places and no more.
        amount == amount.rounded()
            ? String(Int(amount))
            : String(format: "%.2f", amount)
    }

    /// What the strip shows in one line when it has tallies: the totals, in order, shortened to
    /// what fits on a row.
    static func summary(_ tallies: [TaskTally], locale: Locale = .current) -> String {
        tallies
            .filter { !$0.entries.isEmpty }
            .map { formatted($0.total, unit: $0.unit, locale: locale) }
            .joined(separator: " · ")
    }

    /// Adds to a tally, newest first so the list reads as a history.
    static func adding(_ amount: Double, to tally: TaskTally, note: String = "", at when: Date = .now, fromTimer: Bool = false) -> TaskTally {
        var edited = tally
        edited.entries.insert(
            TaskTallyEntry(amount: amount, at: when, note: note, fromTimer: fromTimer), at: 0
        )
        return edited
    }

    /// Where a stretch of time goes when the clock stops.
    ///
    /// The first stop on a strip with no hours tally makes one, because a feature that does
    /// nothing until somebody has set it up by hand is a feature nobody finds. Anything shorter
    /// than the clock's own floor is not an entry — a timer started and stopped by accident
    /// shouldn't leave a line behind.
    static func recording(
        seconds: TimeInterval,
        in tallies: [TaskTally],
        at when: Date = .now
    ) -> [TaskTally] {
        guard seconds >= StripTime.shortestWorthKeeping else { return tallies }
        var edited = tallies
        let hours = seconds / 3600

        if let index = edited.firstIndex(where: { $0.unit.isTime }) {
            let inUnit = edited[index].unit == .minutes ? seconds / 60 : hours
            edited[index] = adding(inUnit, to: edited[index], note: "From the timer", at: when, fromTimer: true)
            return edited
        }
        var made = TaskTally(name: TaskTally.timeName, unit: .hours)
        made = adding(hours, to: made, note: "From the timer", at: when, fromTimer: true)
        edited.append(made)
        return edited
    }
}
