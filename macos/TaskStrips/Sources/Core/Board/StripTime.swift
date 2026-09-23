import Foundation

/// Time spent on a strip: one stretch at a time, added up.
///
/// The clock isn't a number that ticks somewhere — it's a list of stretches with a start and an
/// end, and a running one is simply the stretch that hasn't ended yet. That's what makes it
/// survive a crash, a reboot and the trip through iCloud: there's no state to lose, only history.
enum StripTime {
    /// A stretch with no end is the one running now.
    static func running(in sessions: [TaskWorkSession]) -> TaskWorkSession? {
        sessions.first { $0.endedAt == nil }
    }

    static func isRunning(_ sessions: [TaskWorkSession]) -> Bool { running(in: sessions) != nil }

    /// Everything spent so far, the running stretch included up to now.
    static func total(of sessions: [TaskWorkSession], now: Date = .now) -> TimeInterval {
        sessions.reduce(0) { total, session in
            let end = session.endedAt ?? now
            return total + max(end.timeIntervalSince(session.startedAt), 0)
        }
    }

    /// What's been spent since the week began, with a stretch that straddles the boundary counted
    /// only from the moment the week started.
    static func thisWeek(
        _ sessions: [TaskWorkSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TimeInterval {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return sessions.reduce(0) { total, session in
            let end = session.endedAt ?? now
            let from = max(session.startedAt, week.start)
            let to = min(end, week.end)
            return total + max(to.timeIntervalSince(from), 0)
        }
    }

    static func start(_ sessions: [TaskWorkSession], now: Date = .now) -> [TaskWorkSession] {
        guard !isRunning(sessions) else { return sessions }
        return sessions + [TaskWorkSession(startedAt: now)]
    }

    /// Below this a stretch is a misclick rather than work, and it's thrown away rather than
    /// cluttering the history with seconds.
    static let shortestWorthKeeping: TimeInterval = 10

    static func stop(_ sessions: [TaskWorkSession], now: Date = .now) -> [TaskWorkSession] {
        guard let running = running(in: sessions) else { return sessions }
        guard now.timeIntervalSince(running.startedAt) >= shortestWorthKeeping else {
            return sessions.filter { $0.id != running.id }
        }
        return sessions.map { session in
            guard session.id == running.id else { return session }
            var stopped = session
            stopped.endedAt = now
            return stopped
        }
    }

    /// "1h 05m", "45m", "30s" — what a person would say, not what a stopwatch shows.
    static func label(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        guard seconds >= 60 else { return "\(max(seconds, 0))s" }
        let minutes = seconds / 60
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    /// What the strip's log should say when a stretch ends. Nil for one too short to keep.
    static func logEntry(for interval: TimeInterval) -> String? {
        guard interval >= shortestWorthKeeping else { return nil }
        return "Worked \(label(interval))"
    }
}
