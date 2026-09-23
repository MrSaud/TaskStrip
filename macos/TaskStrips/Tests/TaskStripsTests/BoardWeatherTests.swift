import XCTest
@testable import TaskStrips

final class BoardWeatherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var reply: Data {
        Data("""
        {"latitude":24.7,"longitude":46.7,
         "current":{"time":"2026-09-23T12:00","temperature_2m":38.4,"weather_code":1}}
        """.utf8)
    }

    func testTheReplyIsReadForWhatItSays() throws {
        let weather = try XCTUnwrap(BoardWeather.read(reply, now: now))
        XCTAssertEqual(weather.celsius, 38.4, accuracy: 0.01)
        XCTAssertEqual(weather.code, 1)
        XCTAssertEqual(weather.measuredAt, now)
    }

    func testNonsenseIsNoReading() {
        XCTAssertNil(BoardWeather.read(Data("not json".utf8)))
        XCTAssertNil(BoardWeather.read(Data("{}".utf8)))
        XCTAssertNil(BoardWeather.read(Data("{\"current\":{}}".utf8)), "no temperature, nothing to show")
    }

    func testItReadsInTheUnitThePlaceUses() throws {
        let weather = try XCTUnwrap(BoardWeather.read(reply, now: now))
        XCTAssertEqual(weather.label(locale: Locale(identifier: "en_SA")), "38°")
        XCTAssertEqual(weather.label(locale: Locale(identifier: "en_US")), "101°")
    }

    func testTheSkyHasASymbolForEachKindOfWeather() {
        func symbol(_ code: Int) -> String {
            BoardWeather(celsius: 20, code: code, measuredAt: Date()).symbol
        }
        XCTAssertEqual(symbol(0), "sun.max")
        XCTAssertEqual(symbol(2), "cloud.sun")
        XCTAssertEqual(symbol(48), "cloud.fog")
        XCTAssertEqual(symbol(63), "cloud.rain")
        XCTAssertEqual(symbol(73), "cloud.snow")
        XCTAssertEqual(symbol(95), "cloud.bolt.rain")
        XCTAssertEqual(symbol(-1), "thermometer.medium", "something unheard of still shows something")
    }

    /// Half an hour: often enough for weather, rare enough to be no burden on the service.
    func testAReadingGoesStaleAfterHalfAnHour() {
        let weather = BoardWeather(celsius: 20, code: 0, measuredAt: now)
        XCTAssertTrue(weather.isFresh(now: now.addingTimeInterval(600)))
        XCTAssertFalse(weather.isFresh(now: now.addingTimeInterval(3600)))
        XCTAssertFalse(weather.isFresh(now: now.addingTimeInterval(-60)), "a reading from the future is no reading")
    }

    func testWhereItAsksAboutIsANeighbourhoodRatherThanAStreet() throws {
        let url = try XCTUnwrap(BoardWeather.endpoint(latitude: 24.7136123456, longitude: 46.6752987654))
        let text = url.absoluteString
        XCTAssertTrue(text.contains("latitude=24.714"), text)
        XCTAssertTrue(text.contains("longitude=46.675"), text)
        XCTAssertFalse(text.contains("24.7136123"), "three places is as close as it gets")
        XCTAssertTrue(text.hasPrefix("https://"), text)
    }

    func testTheLastReadingSurvivesUntilTheNextOne() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "weather-\(UUID().uuidString)"))
        let cache = BoardWeatherCache(defaults: defaults)
        XCTAssertNil(cache.last)

        let weather = BoardWeather(celsius: 31.5, code: 3, measuredAt: now)
        cache.last = weather
        XCTAssertEqual(cache.last, weather)

        cache.last = nil
        XCTAssertNil(cache.last)
    }
}
