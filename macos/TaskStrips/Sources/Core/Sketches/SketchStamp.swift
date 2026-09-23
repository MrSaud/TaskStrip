import Foundation

/// Something you can drop on a page without drawing it: a tick, an arrow, a star, a face.
///
/// Two kinds, because they behave differently once they're down. An emoji brings its own colours
/// and is drawn as the character it is; an icon is a symbol drawn in whatever ink is selected, so
/// a page marked up in red stays marked up in red.
enum SketchStamp: Equatable, Identifiable {
    case emoji(String)
    /// An SF Symbol name.
    case icon(String)

    var id: String {
        switch self {
        case .emoji(let character): return "emoji:\(character)"
        case .icon(let name): return "icon:\(name)"
        }
    }

    /// Takes the ink it's stamped with, rather than bringing its own colour.
    var followsInk: Bool {
        if case .icon = self { return true }
        return false
    }

    struct Group: Identifiable {
        var title: String
        var stamps: [SketchStamp]
        var id: String { title }
    }

    /// What the picker offers. Marks first, because marking up a page is what a stamp is mostly
    /// for; the faces are last, where they don't crowd the things that mean something.
    static let groups: [Group] = [
        Group(title: "Marks", stamps: [
            .icon("checkmark"), .icon("xmark"), .icon("questionmark"), .icon("exclamationmark"),
            .icon("star.fill"), .icon("heart.fill"), .icon("flag.fill"), .icon("bolt.fill"),
            .icon("pin.fill"), .icon("bookmark.fill"), .icon("lightbulb.fill"), .icon("magnifyingglass"),
        ]),
        Group(title: "Arrows", stamps: [
            .icon("arrow.right"), .icon("arrow.left"), .icon("arrow.up"), .icon("arrow.down"),
            .icon("arrow.turn.down.right"), .icon("arrow.triangle.branch"),
            .icon("arrow.2.squarepath"), .icon("arrow.uturn.left"),
        ]),
        Group(title: "Shapes", stamps: [
            .icon("circle"), .icon("square"), .icon("triangle"), .icon("diamond"),
            .icon("rectangle"), .icon("capsule"), .icon("hexagon"), .icon("cloud.fill"),
        ]),
        Group(title: "Work", stamps: [
            .emoji("✅"), .emoji("❌"), .emoji("⚠️"), .emoji("📌"), .emoji("📅"), .emoji("⏰"),
            .emoji("💡"), .emoji("🔥"), .emoji("🎯"), .emoji("💰"), .emoji("📎"), .emoji("🔒"),
        ]),
        Group(title: "Faces", stamps: [
            .emoji("🙂"), .emoji("😀"), .emoji("😐"), .emoji("🙁"), .emoji("😮"), .emoji("😴"),
            .emoji("👍"), .emoji("👎"), .emoji("👏"), .emoji("🙏"), .emoji("❤️"), .emoji("⭐️"),
        ]),
    ]

    static var all: [SketchStamp] { groups.flatMap(\.stamps) }
}
