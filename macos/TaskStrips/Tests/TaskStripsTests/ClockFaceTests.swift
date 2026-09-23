import XCTest
@testable import TaskStrips

final class ClockFaceTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func time(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: hour, minute: minute))!
    }

    func testNoonAndMidnightPutBothHandsAtTwelve() {
        for hour in [0, 12] {
            let hands = ClockFace.hands(at: time(hour, 0), calendar: calendar)
            XCTAssertEqual(hands.hour, 0, accuracy: 0.0001)
            XCTAssertEqual(hands.minute, 0, accuracy: 0.0001)
        }
    }

    func testQuarterPastThree() {
        let hands = ClockFace.hands(at: time(3, 15), calendar: calendar)
        XCTAssertEqual(hands.minute, 0.25, accuracy: 0.0001)
        // A quarter past, so the hour hand has left the 3 by a quarter of an hour's worth.
        XCTAssertEqual(hands.hour, (3 + 0.25) / 12, accuracy: 0.0001)
    }

    func testAfternoonReadsTheSameAsMorning() {
        XCTAssertEqual(
            ClockFace.hands(at: time(21, 40), calendar: calendar),
            ClockFace.hands(at: time(9, 40), calendar: calendar)
        )
    }
}
