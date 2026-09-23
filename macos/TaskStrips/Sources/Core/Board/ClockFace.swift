import Foundation

/// How the board shows the time, beside the date.
enum BoardClockStyle: String, CaseIterable, Identifiable, Equatable {
    case digital
    case analog
    /// No clock at all — every other device in the room already has one.
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .digital: return "Digital"
        case .analog: return "Analog"
        case .off: return "Off"
        }
    }
}

/// Where the hands point, as fractions of a full turn measured from twelve o'clock.
///
/// Minutes, not seconds: a sweeping second hand would have to redraw the board's header once a
/// second all day, and the header is redrawn on the minute as it is. The hour hand still creeps
/// between the hours, because an hour hand parked on the hour reads as a stopped clock.
enum ClockFace {
    struct Hands: Equatable {
        /// 0 at twelve, 0.5 at six — a fraction of the way round.
        var hour: Double
        var minute: Double
    }

    static func hands(at date: Date, calendar: Calendar = .current) -> Hands {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double((parts.hour ?? 0) % 12)
        let minute = Double(parts.minute ?? 0)
        return Hands(hour: (hour + minute / 60) / 12, minute: minute / 60)
    }
}
