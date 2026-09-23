import Foundation

/// The few lines at the bottom of everything you send, and how they should look.
///
/// Styling a signature means the message has to go out twice over: once as plain text, for mail
/// programs and for anyone who prefers it, and once as HTML, which is the only way a colour or a
/// size survives the journey. Both halves are written from the same signature, so they can't
/// disagree about what it says.
struct MailSignature: Codable, Equatable {
    var text: String = ""
    /// The colour, as the six hex digits an email understands. The app's own amber by default,
    /// which is the one colour the board is sure of.
    var colorHex: String = "B8860B"
    var size: Int = 13
    var family: Family = .system
    var isBold = false
    var isItalic = false

    enum Family: String, Codable, CaseIterable, Identifiable {
        case system
        case serif
        case monospaced

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "Sans serif"
            case .serif: return "Serif"
            case .monospaced: return "Monospaced"
            }
        }

        /// What to ask an email client for. A stack rather than one name: a font that isn't there
        /// is a signature in whatever the client felt like.
        var cssStack: String {
            switch self {
            case .system: return "-apple-system, Helvetica, Arial, sans-serif"
            case .serif: return "Georgia, 'Times New Roman', serif"
            case .monospaced: return "'SF Mono', Menlo, Consolas, monospace"
            }
        }
    }

    /// Sizes worth offering. A signature larger than the message is a signature that reads as
    /// shouting, so this stops where it stops.
    static let sizes = [11, 12, 13, 14, 16, 18]

    /// Colours from the board's own palette, plus the two anybody expects to find.
    static let colours: [(name: String, hex: String)] = [
        ("Amber", "B8860B"),
        ("Ink", "1C1C1E"),
        ("Grey", "6E6E73"),
        ("Urgent", "C1453B"),
        ("High", "C77B27"),
        ("Normal", "3F7D4E"),
        ("Low", "3A6EA5"),
    ]

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The plain half: the text as written, under the two dashes and a space that every mail
    /// program in the world reads as "the signature starts here".
    var plainText: String {
        isEmpty ? "" : "-- \n" + text
    }

    /// The styled half.
    var html: String {
        guard !isEmpty else { return "" }
        var style = "font-family: \(family.cssStack); font-size: \(size)px; color: #\(colorHex);"
        if isBold { style += " font-weight: bold;" }
        if isItalic { style += " font-style: italic;" }
        let lines = MailSignature.escaped(text).replacingOccurrences(of: "\n", with: "<br>\n")
        return "<div style=\"\(style)\">\(lines)</div>"
    }

    /// The four characters that mean something else in HTML. Without this, a signature with an
    /// ampersand in the company name arrives broken, or worse, arrives as markup.
    static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
