import Foundation

/// What today is, in both calendars, and how long each month runs.
///
/// "Is this month 29, 30 or 31 days?" is two different questions at once: a Gregorian month runs
/// 28 to 31, an Umm al-Qura one 29 or 30, and neither answers the other. The board shows both
/// rather than making you convert.
enum BoardCalendars {
    struct Reading: Equatable {
        /// The date as it reads in that calendar, e.g. "30 Aug 2026".
        var date: String
        var daysInMonth: Int

        /// "30 AUG 2026 · 31 DAYS" — the board's own voice, which is uppercase.
        var text: String {
            "\(date) · \(daysInMonth) days".uppercased()
        }
    }

    static func gregorian(
        _ now: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> Reading {
        reading(now, identifier: .gregorian, format: "d MMM yyyy", locale: locale, timeZone: timeZone)
    }

    /// Umm al-Qura, which is the civil Hijri calendar in Saudi Arabia and what Android's
    /// HijrahChronology uses too — so both apps say the same thing on the same day.
    static func hijri(
        _ now: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> Reading {
        reading(now, identifier: .islamicUmmAlQura, format: "d MMMM yyyy", locale: locale, timeZone: timeZone)
    }

    /// The whole line, as the board shows it.
    static func headerText(
        _ now: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let weekday = weekday(now, locale: locale, timeZone: timeZone)
        let both = [
            gregorian(now, locale: locale, timeZone: timeZone).text,
            hijri(now, locale: locale, timeZone: timeZone).text,
        ].joined(separator: " · ")
        return "\(weekday), \(both)"
    }

    private static func reading(
        _ now: Date,
        identifier: Calendar.Identifier,
        format: String,
        locale: Locale,
        timeZone: TimeZone
    ) -> Reading {
        var calendar = Calendar(identifier: identifier)
        calendar.locale = locale
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = format

        return Reading(
            date: formatter.string(from: now),
            // A month always has a range of days; the fallback is only here because the API is
            // optional, not because it can happen.
            daysInMonth: calendar.range(of: .day, in: .month, for: now)?.count ?? 0
        )
    }

    private static func weekday(_ now: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: now).uppercased()
    }
}
