import Foundation
import SwiftData

/// How often a standalone reminder comes back. Raw values match the strings Android stores in
/// `reminders.repeatUnit` and writes into a backup.
enum ReminderRepeatUnit: String, Codable, CaseIterable, Identifiable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case yearly = "YEARLY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "Days"
        case .weekly: return "Weeks"
        case .monthly: return "Months"
        case .yearly: return "Years"
        }
    }

    /// Calendar arithmetic rather than a fixed number of days, so a monthly repeat lands on the
    /// same day of the month instead of drifting a little further each time.
    var component: Calendar.Component {
        switch self {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }
}

/// A reminder with no strip behind it, mirroring ReminderEntity.kt.
///
/// The board is for work; this is for the things that are only a moment in time — a birthday, a
/// service due, a document that expires.
@Model
final class Reminder: Identifiable, Taggable {
    @Attribute(.unique) var id: UUID
    /// The one-line title. Android calls this column `text` and kept the name through the
    /// addition of `description` below, so a backup uses it too.
    var text: String
    /// Android's `description`. Renamed here because `description` is spoken for in Swift — every
    /// type has one — and shadowing it on a model invites confusing printouts.
    var details: String
    /// When it's for. Stored as a real instant; a backup's value is a UTC-pinned wall clock and
    /// is converted on the way in, exactly like a strip's due date.
    var triggerAt: Date
    /// Minutes to fire ahead of `triggerAt`; nil fires exactly on it. When set, this is the only
    /// alarm — the same choice a strip's due-date reminder makes.
    var leadMinutesBefore: Int?
    var repeatAmount: Int?
    var repeatUnitRaw: String?
    var tag: String
    var tagEmoji: String
    var isDone: Bool
    var createdAt: Date

    var repeatUnit: ReminderRepeatUnit? {
        get { repeatUnitRaw.flatMap(ReminderRepeatUnit.init(rawValue:)) }
        set { repeatUnitRaw = newValue?.rawValue }
    }

    /// A repeat needs both halves to mean anything, and an amount of zero repeats nothing.
    var repeats: Bool {
        guard let amount = repeatAmount, amount > 0 else { return false }
        return repeatUnit != nil
    }

    var repeatLabel: String? {
        guard repeats, let amount = repeatAmount, let unit = repeatUnit else { return nil }
        let noun = unit.label.lowercased()
        return amount == 1
            ? "Every \(noun.dropLast())"
            : "Every \(amount) \(noun)"
    }

    init(
        text: String,
        triggerAt: Date,
        details: String = "",
        leadMinutesBefore: Int? = nil,
        repeatAmount: Int? = nil,
        repeatUnit: ReminderRepeatUnit? = nil,
        tag: String = "",
        tagEmoji: String = "",
        isDone: Bool = false,
        id: UUID = UUID(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.details = details
        self.triggerAt = triggerAt
        self.leadMinutesBefore = leadMinutesBefore
        self.repeatAmount = repeatAmount
        self.repeatUnitRaw = repeatUnit?.rawValue
        self.tag = tag
        self.tagEmoji = tagEmoji
        self.isDone = isDone
        self.createdAt = createdAt
    }
}
