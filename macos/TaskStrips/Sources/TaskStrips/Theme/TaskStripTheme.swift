import SwiftUI

// Mirrors ui/theme/Color.kt's exact hex values, so the Mac app reads as the same app rather
// than a generic macOS list.
enum TaskStripTheme {
    static let bayBackground = Color(hex: 0x14171C)
    static let baySurface = Color(hex: 0x1C2027)
    static let baySurfaceFaded = Color(hex: 0x181B21)
    static let paper = Color(hex: 0xF4EFE1)
    static let ink = Color(hex: 0x262220)
    static let amber = Color(hex: 0xE0A63A)
    static let urgent = Color(hex: 0xC0392B)
    static let high = Color(hex: 0xE08E2D)
    static let normal = Color(hex: 0x3D7A5C)
    static let low = Color(hex: 0x5B6B7A)
}

extension Priority {
    // Mirrors ui/theme/PriorityStyle.kt's Priority.tabColor().
    var tabColor: Color {
        switch self {
        case .urgent: TaskStripTheme.urgent
        case .high: TaskStripTheme.high
        case .normal: TaskStripTheme.normal
        case .low: TaskStripTheme.low
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
