import XCTest
@testable import TaskStrips

/// The network call can't be made from here, so what's checked is everything around it: what the
/// reply has to look like to count, and the rule that keeps the board off the network for the
/// rest of the day.
final class QuoteOfTheDayTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "quote-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var utc: TimeZone { TimeZone(identifier: "UTC") ?? .gmt }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Reading the reply

    func testAQuoteIsReadOutOfTheArray() {
        let data = Data(#"[{"q":"The obstacle is the way.","a":"Marcus Aurelius","h":"<blockquote>"}]"#.utf8)
        XCTAssertEqual(
            QuoteOfTheDay.quote(from: data),
            Quote(text: "The obstacle is the way.", author: "Marcus Aurelius")
        )
    }

    /// The service pads its strings; a quote that renders with a leading newline looks broken.
    func testSurroundingWhitespaceIsTrimmed() {
        let data = Data(#"[{"q":"  Keep going.\n","a":" Anonymous "}]"#.utf8)
        XCTAssertEqual(QuoteOfTheDay.quote(from: data), Quote(text: "Keep going.", author: "Anonymous"))
    }

    /// A line with nobody attached still reads fine; a line with no words does not.
    func testAMissingAuthorBecomesUnknownButMissingWordsAreFatal() {
        XCTAssertEqual(
            QuoteOfTheDay.quote(from: Data(#"[{"q":"Keep going.","a":""}]"#.utf8)),
            Quote(text: "Keep going.", author: "Unknown")
        )
        XCTAssertNil(QuoteOfTheDay.quote(from: Data(#"[{"q":"   ","a":"Nobody"}]"#.utf8)))
        XCTAssertNil(QuoteOfTheDay.quote(from: Data(#"[{"a":"Nobody"}]"#.utf8)))
    }

    /// Anything unexpected is simply no quote — the card doesn't appear, and nothing is said about
    /// it. A service being down isn't the user's problem.
    func testNonsenseIsNotAQuote() {
        XCTAssertNil(QuoteOfTheDay.quote(from: Data("not json".utf8)))
        XCTAssertNil(QuoteOfTheDay.quote(from: Data("[]".utf8)))
        XCTAssertNil(QuoteOfTheDay.quote(from: Data(#"{"q":"an object, not an array"}"#.utf8)))
        XCTAssertNil(QuoteOfTheDay.quote(from: Data()))
    }

    // MARK: - Once a day

    func testAQuoteSavedTodayComesBackToday() {
        let cache = QuoteCache(defaults: defaults)
        let quote = Quote(text: "The obstacle is the way.", author: "Marcus Aurelius")
        cache.save(quote, on: date(2026, 8, 30), timeZone: utc)

        XCTAssertEqual(cache.quote(on: date(2026, 8, 30, 23), timeZone: utc), quote)
    }

    /// A calendar day, not twenty-four hours: "today's quote" means what a person means by it.
    func testTomorrowAsksAgain() {
        let cache = QuoteCache(defaults: defaults)
        cache.save(Quote(text: "Keep going.", author: "Anonymous"), on: date(2026, 8, 30, 23), timeZone: utc)

        XCTAssertNil(cache.quote(on: date(2026, 8, 31, 0), timeZone: utc), "an hour later, but a new day")
    }

    func testNothingCachedIsNoQuote() {
        XCTAssertNil(QuoteCache(defaults: defaults).quote(on: date(2026, 8, 30), timeZone: utc))
    }

    func testTheDayKeyIsTheLocalDay() {
        // 23:00 UTC on the 30th is already the 31st in Riyadh.
        let riyadh = TimeZone(identifier: "Asia/Riyadh")!
        XCTAssertEqual(QuoteCache.dayKey(for: date(2026, 8, 30, 23), timeZone: utc), "2026-08-30")
        XCTAssertEqual(QuoteCache.dayKey(for: date(2026, 8, 30, 23), timeZone: riyadh), "2026-08-31")
    }
}
