import XCTest
@testable import TaskStrips

/// The month lengths themselves are the point of the header, so they're what's checked — in both
/// calendars, including the cases that make the question worth asking.
final class BoardCalendarsTests: XCTestCase {
    private let english = Locale(identifier: "en_US_POSIX")
    private var utc: TimeZone { TimeZone(identifier: "UTC") ?? .gmt }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func gregorian(_ date: Date) -> BoardCalendars.Reading {
        BoardCalendars.gregorian(date, locale: english, timeZone: utc)
    }

    private func hijri(_ date: Date) -> BoardCalendars.Reading {
        BoardCalendars.hijri(date, locale: english, timeZone: utc)
    }

    // MARK: - Gregorian

    func testTheLongAndShortMonths() {
        XCTAssertEqual(gregorian(date(2026, 8, 30)).daysInMonth, 31)
        XCTAssertEqual(gregorian(date(2026, 9, 10)).daysInMonth, 30)
        XCTAssertEqual(gregorian(date(2026, 2, 10)).daysInMonth, 28)
    }

    /// The case the question is usually about.
    func testFebruaryInALeapYear() {
        XCTAssertEqual(gregorian(date(2028, 2, 10)).daysInMonth, 29)
        // A century that isn't a leap year, since the rule catches people out.
        XCTAssertEqual(gregorian(date(2100, 2, 10)).daysInMonth, 28)
        XCTAssertEqual(gregorian(date(2000, 2, 10)).daysInMonth, 29)
    }

    /// The length is the month's, not "days left" or "days since" — it doesn't move within a
    /// month.
    func testTheLengthIsTheSameOnEveryDayOfThatMonth() {
        XCTAssertEqual(gregorian(date(2026, 8, 1)).daysInMonth, gregorian(date(2026, 8, 31)).daysInMonth)
    }

    func testTheDateReadsAsADate() {
        XCTAssertEqual(gregorian(date(2026, 8, 30)).date, "30 Aug 2026")
        XCTAssertEqual(gregorian(date(2026, 8, 30)).text, "30 AUG 2026 · 31 DAYS")
    }

    // MARK: - Hijri

    /// Umm al-Qura months are 29 or 30 days, never anything else — that's the whole reason the
    /// question is asked in the first place.
    func testAHijriMonthIsAlwaysTwentyNineOrThirtyDays() {
        // A year's worth of samples, one per Gregorian month, to cross a full Hijri year.
        for month in 1...12 {
            let days = hijri(date(2026, month, 15)).daysInMonth
            XCTAssertTrue((29...30).contains(days), "\(days) days is not a Hijri month length")
        }
    }

    /// Deliberately not pinned to a specific date: the Umm al-Qura tables live in the system, and
    /// asserting an exact day would be testing ICU's version rather than this code. The year
    /// being in the right neighbourhood is what proves the calendar is Hijri at all.
    func testTheHijriYearIsTheHijriOne() {
        let text = hijri(date(2026, 8, 30)).date
        let year = Int(text.split(separator: " ").last ?? "") ?? 0
        XCTAssertTrue((1447...1449).contains(year), "expected a Hijri year around 1448, got \(text)")
    }

    func testTheTwoCalendarsDisagreeAboutTheDayAsTheyShould() {
        let now = date(2026, 8, 30)
        XCTAssertNotEqual(gregorian(now).date, hijri(now).date)
    }

    // MARK: - The line the board shows

    func testTheHeaderCarriesBothAnswers() {
        let text = BoardCalendars.headerText(date(2026, 8, 30), locale: english, timeZone: utc)

        XCTAssertTrue(text.hasPrefix("SUN,"), "got \(text)")
        XCTAssertTrue(text.contains("30 AUG 2026 · 31 DAYS"), "got \(text)")
        // Two month lengths, one per calendar.
        XCTAssertEqual(text.components(separatedBy: "DAYS").count - 1, 2, "got \(text)")
    }

    /// A board open past midnight has to move on to the new day, which is why the header is built
    /// from a date rather than captured once.
    func testTheHeaderFollowsTheDayItIsGiven() {
        let first = BoardCalendars.headerText(date(2026, 8, 31), locale: english, timeZone: utc)
        let second = BoardCalendars.headerText(date(2026, 9, 1), locale: english, timeZone: utc)

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.contains("31 DAYS"))
        XCTAssertTrue(second.contains("30 DAYS"))
    }
}
