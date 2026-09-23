import Foundation

/// Whether a strip is waiting for its day.
///
/// A board that shows everything at once stops being read. Deferring is the opposite of a due
/// date: the due date says when it has to be done, this says when it's worth thinking about —
/// and until then the strip is off the board rather than on it in grey.
enum StripDeferral {
    /// Still deferred as of `now`. The whole day counts: something deferred to the 1st is back
    /// at midnight on the 1st, not at the hour it was deferred.
    static func isDeferred(_ deferUntil: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let deferUntil else { return false }
        return calendar.startOfDay(for: deferUntil) > calendar.startOfDay(for: now)
    }

    /// "NOT BEFORE 1 OCT" for the strip to wear while it's waiting.
    static func label(_ deferUntil: Date?, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard isDeferred(deferUntil, now: now, calendar: calendar), let deferUntil else { return nil }
        return "NOT BEFORE \(deferUntil.formatted(.dateTime.day().month(.abbreviated)))".uppercased()
    }
}
