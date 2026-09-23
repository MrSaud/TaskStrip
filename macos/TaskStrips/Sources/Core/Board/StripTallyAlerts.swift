import Foundation

/// Telling somebody their total has got where it was going.
///
/// A budget is only useful if it speaks before it's spent. A tally with a target says something
/// twice: once at nine tenths, while there's still room to act, and once when it's reached. Each
/// is said once — a notification on every entry would be noise, and noise is what gets turned off.
enum StripTallyAlerts {
    /// Nine tenths is early enough to do something about and late enough to mean it.
    static let thresholds = [90, 100]

    /// What to say, and which thresholds have now been passed.
    struct Alert: Equatable {
        var tallyID: UUID
        var threshold: Int
        var title: String
        var body: String
    }

    /// Works out what to announce, and marks it announced.
    ///
    /// The marking lives on the tally itself, which is why this hands back the edited tallies: it
    /// travels with the strip, so a budget passed on the Mac doesn't announce itself again on the
    /// phone.
    static func check(_ tallies: [TaskTally], stripTitle: String, locale: Locale = .current) -> (tallies: [TaskTally], alerts: [Alert]) {
        var edited = tallies
        var alerts: [Alert] = []

        for index in edited.indices {
            let tally = edited[index]
            guard let target = tally.target, target > 0 else {
                // A target removed is a slate wiped: if one is set again later, it announces
                // itself again.
                edited[index].announced = []
                continue
            }
            let percent = tally.total / target * 100

            for threshold in thresholds {
                let passed = percent >= Double(threshold)
                if passed, !tally.announced.contains(threshold) {
                    edited[index].announced.append(threshold)
                    alerts.append(
                        Alert(
                            tallyID: tally.id,
                            threshold: threshold,
                            title: stripTitle.isEmpty ? "A total on your board" : stripTitle,
                            body: message(for: tally, threshold: threshold, locale: locale)
                        )
                    )
                } else if !passed {
                    // Back under: entries get corrected, and a total that falls below the line
                    // should speak again when it crosses it a second time.
                    edited[index].announced.removeAll { $0 == threshold }
                }
            }
        }
        return (edited, alerts)
    }

    static func message(for tally: TaskTally, threshold: Int, locale: Locale = .current) -> String {
        let name = tally.name.isEmpty ? "A total" : tally.name
        let total = StripTally.formatted(tally.total, unit: tally.unit, locale: locale)
        let target = StripTally.formatted(tally.target ?? 0, unit: tally.unit, locale: locale)

        if threshold >= 100 {
            guard let remaining = tally.remaining, remaining < 0 else {
                return "\(name) has reached its target of \(target)."
            }
            return "\(name) is over its target of \(target) — \(total) so far."
        }
        let left = tally.remaining.map { StripTally.formatted($0, unit: tally.unit, locale: locale) }
        return left.map { "\(name) is at \(total) of \(target) — \($0) left." }
            ?? "\(name) is at \(total) of \(target)."
    }

    /// One per tally and threshold, so the ninety and the hundred don't overwrite each other.
    static func identifier(stripID: UUID, alert: Alert) -> String {
        "tally-\(stripID.uuidString)-\(alert.tallyID.uuidString)-\(alert.threshold)"
    }
}
