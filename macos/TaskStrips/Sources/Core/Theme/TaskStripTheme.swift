import SwiftUI

/// Which way the app is painted. Auto follows the system, the way every other app on the device
/// does; the other two are for people who have made up their mind.
enum BoardTheme: String, CaseIterable, Identifiable, Equatable {
    case auto
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    /// Nil means "whatever the system is doing", which is what Auto means.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

extension BoardTheme {
    #if DEBUG
    /// `-Theme light|dark|auto`, for trying a theme on a real device from a Mac — there's no way
    /// to reach into Settings on a phone from here.
    static var launchOverride: BoardTheme? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-Theme"), index + 1 < arguments.count else {
            return nil
        }
        return BoardTheme(rawValue: arguments[index + 1])
    }
    #endif
}

extension View {
    /// Wears the chosen theme — and on Auto wears nothing at all, which is how a view inherits
    /// the system's own light or dark rather than being told.
    @ViewBuilder
    func boardTheme(_ theme: BoardTheme) -> some View {
        #if DEBUG
        let theme = BoardTheme.launchOverride ?? theme
        #endif
        if let scheme = theme.colorScheme {
            preferredColorScheme(scheme)
        } else {
            self
        }
    }
}

// The dark values mirror ui/theme/Color.kt's exact hex values, so the app reads as the same app
// it always was rather than a generic list. The light ones are the same board in daylight: the
// bay becomes the paper it was printed on, and the ink and the paper swap places.
//
// They live in the asset catalogue rather than in code: a colour set is resolved against the
// view's own traits by the system, which is exactly what following the device means, and it
// needs no dynamic-colour plumbing of ours on two platforms.
enum TaskStripTheme {
    /// The board itself.
    static let bayBackground = Color("BayBackground")
    /// A strip, a card, a pane.
    static let baySurface = Color("BaySurface")
    /// The bands a header or a toolbar sits on.
    static let baySurfaceFaded = Color("BaySurfaceFaded")
    /// What's written on the board: the light one in the dark and the dark one in the light,
    /// which is the whole trick.
    static let paper = Color("Paper")
    /// What sits on amber — the opposite of `paper`, so a lit chip always reads.
    static let ink = Color("Ink")

    /// The colours that mean something stay themselves in both, darkened a little in daylight so
    /// they hold their weight on pale paper.
    static let amber = Color("Amber")
    static let urgent = Color("Urgent")
    static let high = Color("High")
    static let normal = Color("Normal")
    static let low = Color("Low")
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
