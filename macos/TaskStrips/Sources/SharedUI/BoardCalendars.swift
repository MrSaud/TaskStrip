import Foundation

/// What today is, in both calendars, and how long each month runs.
///
/// "Is this month 29, 30 or 31 days?" is two different questions at once: a Gregorian month runs
/// 28 to 31, an Umm al-Qura one 29 or 30, and neither answers the other. The board shows both
/// rather than making you convert.
/// Which calendar the board's date line speaks in. Both, for someone who lives in the two at
/// once; one, for someone who doesn't — and one calendar leaves room for a bigger line.
enum BoardDateStyle: String, CaseIterable, Identifiable, Equatable {
    case gregorian
    case hijri
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gregorian: return "Gregorian"
        case .hijri: return "Hijri"
        case .both: return "Both"
        }
    }
}

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

    /// The date line broken into the lines it wants: one per calendar.
    ///
    /// A phone can't hold both calendars on one readable line — at a size worth reading it runs
    /// off the screen — so the two are stacked there and joined on a Mac, and the weekday leads
    /// the first line either way.
    static func headerLines(
        _ now: Date = .now,
        style: BoardDateStyle = .both,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [String] {
        let weekday = weekday(now, locale: locale, timeZone: timeZone)
        let gregorian = gregorian(now, locale: locale, timeZone: timeZone).text
        let hijri = hijri(now, locale: locale, timeZone: timeZone).text
        switch style {
        case .gregorian: return ["\(weekday), \(gregorian)"]
        case .hijri: return ["\(weekday), \(hijri)"]
        case .both: return ["\(weekday), \(gregorian)", hijri]
        }
    }

    /// The whole line, as a Mac shows it — one line, however many calendars are in it.
    static func headerText(
        _ now: Date = .now,
        style: BoardDateStyle = .both,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        headerLines(now, style: style, locale: locale, timeZone: timeZone).joined(separator: " · ")
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
