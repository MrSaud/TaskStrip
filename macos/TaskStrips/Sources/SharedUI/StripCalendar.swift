import EventKit
import Foundation

/// The calendar, as far as a strip needs it: block an hour for this, find that block again, and
/// read what today already costs.
///
/// Everything it writes goes to the person's default calendar, so it lands where they'd have put
/// it by hand and syncs by whatever means their calendar already syncs. The strip only remembers
/// which event is its own, by the identifier that means the same event on every device.
@MainActor
final class StripCalendar {
    static let shared = StripCalendar()

    private let store = EKEventStore()

    enum Access {
        case allowed
        case refused
        /// Not asked yet, or asked and not answered.
        case unknown
    }

    var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .allowed
        case .writeOnly: .allowed
        case .denied, .restricted: .refused
        default: .unknown
        }
    }

    /// Asks once, for writing; reading today's events asks for the fuller kind when it's needed.
    func requestWriting() async -> Bool {
        (try? await store.requestWriteOnlyAccessToEvents()) ?? false
    }

    func requestReading() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Blocks time for a strip and hands back the identifier the strip should remember.
    ///
    /// Nil when the calendar refused — which is a thing to tell the person, not to retry.
    func block(
        _ task: TaskItem,
        at start: Date? = nil,
        duration: TimeInterval = StripCalendarPlan.defaultDuration
    ) -> String? {
        guard let calendar = store.defaultCalendarForNewEvents else { return nil }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = StripCalendarPlan.title(for: task)
        event.notes = StripCalendarPlan.notes(for: task)
        event.startDate = start ?? StripCalendarPlan.start(for: task)
        event.endDate = (start ?? StripCalendarPlan.start(for: task)).addingTimeInterval(duration)
        guard (try? store.save(event, span: .thisEvent, commit: true)) != nil else { return nil }
        // The external identifier is the one that means this event on the person's other devices;
        // the local one only means it here.
        return event.calendarItemExternalIdentifier
    }

    func event(for task: TaskItem) -> EKEvent? {
        guard let id = task.calendarEventID else { return nil }
        return store.calendarItems(withExternalIdentifier: id).compactMap { $0 as? EKEvent }.first
    }

    /// Removes the block a strip made, if it's still there.
    func unblock(_ task: TaskItem) {
        guard let event = event(for: task) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    /// What today already costs, in the person's own calendars.
    func today(now: Date = .now, calendar: Calendar = .current) -> [EKEvent] {
        guard case .allowed = access else { return [] }
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }
}
