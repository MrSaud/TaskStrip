import SwiftUI

/// The board's colours, copied rather than shared.
///
/// TaskStripTheme lives in the app target and pulls in the rest of the app with it; a widget
/// extension should stay small, so the four colours it actually needs are restated here. They must
/// stay in step with Theme/TaskStripTheme.swift — the widget sitting beside the window in a
/// different shade of red would be worse than no widget.
enum WidgetTheme {
    static let bayBackground = Color(red: 0x14 / 255, green: 0x17 / 255, blue: 0x1C / 255)
    static let paper = Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE1 / 255)
    static let amber = Color(red: 0xE0 / 255, green: 0xA6 / 255, blue: 0x3A / 255)

    static let urgent = Color(red: 0xC0 / 255, green: 0x39 / 255, blue: 0x2B / 255)
    static let high = Color(red: 0xE0 / 255, green: 0x8E / 255, blue: 0x2D / 255)
    static let normal = Color(red: 0x3D / 255, green: 0x7A / 255, blue: 0x5C / 255)
    static let low = Color(red: 0x5B / 255, green: 0x6B / 255, blue: 0x7A / 255)

    /// Keyed off the raw string the snapshot carries, which is the Android enum's own name.
    static func color(forPriority raw: String) -> Color {
        switch raw {
        case "URGENT": return urgent
        case "HIGH": return high
        case "LOW": return low
        default: return normal
        }
    }

    /// "30 Aug, 14:30" — the same short form the phone's widget uses, so a glance at either
    /// reads the same way.
    static func due(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute())
    }
}
