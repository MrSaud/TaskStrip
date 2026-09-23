import Foundation

/// Something you can drop on a page without drawing it: a tick, an arrow, a number, a face.
///
/// Two kinds, because they behave differently once they're down. An emoji brings its own colours
/// and is drawn as the character it is; an icon is a symbol drawn in whatever ink is selected, so
/// a page marked up in red stays marked up in red.
///
/// Every stamp carries a name and a few other words to find it by — with a hundred and more of
/// them, scrolling isn't a way of finding anything.
struct SketchStamp: Identifiable, Equatable {
    enum Kind: Equatable {
        case emoji(String)
        /// An SF Symbol name.
        case icon(String)
    }

    var kind: Kind
    /// What it's called, which is also the first thing a search matches.
    var name: String
    /// The other words someone might reach for.
    var keywords: [String] = []

    var id: String {
        switch kind {
        case .emoji(let character): return "emoji:\(character)"
        case .icon(let symbol): return "icon:\(symbol)"
        }
    }

    /// Takes the ink it's stamped with, rather than bringing its own colour.
    var followsInk: Bool {
        if case .icon = kind { return true }
        return false
    }

    /// Everything a search looks at: the name, the extra words, and for an emoji the character
    /// itself, so pasting or typing 🔥 finds it.
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        if name.localizedCaseInsensitiveContains(trimmed) { return true }
        if keywords.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) { return true }
        if case .emoji(let character) = kind, character.contains(trimmed) { return true }
        return false
    }

    struct Group: Identifiable, Equatable {
        var title: String
        var stamps: [SketchStamp]
        var id: String { title }
    }

    /// The groups with only the stamps that match, and the empty groups left out — a search that
    /// finds three things should show three things, not three things and eight headings.
    static func groups(matching query: String) -> [Group] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return groups }
        return groups.compactMap { group in
            let matching = group.stamps.filter { $0.matches(trimmed) }
            // A group whose own name is what was typed keeps all of it: "arrows" means the lot.
            if group.title.localizedCaseInsensitiveContains(trimmed) { return group }
            return matching.isEmpty ? nil : Group(title: group.title, stamps: matching)
        }
    }

    static var all: [SketchStamp] { groups.flatMap(\.stamps) }

    private static func icon(_ symbol: String, _ name: String, _ keywords: String...) -> SketchStamp {
        SketchStamp(kind: .icon(symbol), name: name, keywords: keywords)
    }

    private static func emoji(_ character: String, _ name: String, _ keywords: String...) -> SketchStamp {
        SketchStamp(kind: .emoji(character), name: name, keywords: keywords)
    }

    /// What the picker offers. Marks first, because marking up a page is what a stamp is mostly
    /// for; the faces and the rest are further down, where they don't crowd it.
    static let groups: [Group] = [
        Group(title: "Marks", stamps: [
            icon("checkmark", "Tick", "check", "done", "yes", "ok"),
            icon("checkmark.circle.fill", "Tick in a circle", "done", "complete", "approved"),
            icon("xmark", "Cross", "no", "wrong", "delete", "cancel"),
            icon("xmark.circle.fill", "Cross in a circle", "no", "rejected", "stop"),
            icon("questionmark", "Question", "ask", "unsure", "why"),
            icon("exclamationmark", "Exclamation", "important", "urgent", "warning"),
            icon("exclamationmark.triangle.fill", "Warning", "caution", "danger", "risk"),
            icon("info.circle.fill", "Information", "info", "note", "detail"),
            icon("star.fill", "Star", "favourite", "favorite", "best", "rating"),
            icon("heart.fill", "Heart", "love", "like", "favourite"),
            icon("flag.fill", "Flag", "mark", "report", "milestone"),
            icon("bolt.fill", "Bolt", "fast", "power", "energy", "quick"),
            icon("pin.fill", "Pin", "stick", "fix", "attach"),
            icon("bookmark.fill", "Bookmark", "save", "later", "read"),
            icon("lightbulb.fill", "Idea", "bulb", "think", "insight"),
            icon("magnifyingglass", "Search", "look", "find", "review", "zoom"),
            icon("eye.fill", "Eye", "watch", "look", "review", "see"),
            icon("hand.raised.fill", "Stop", "wait", "hold", "hand"),
            icon("plus", "Plus", "add", "more", "new"),
            icon("minus", "Minus", "remove", "less", "subtract"),
            icon("asterisk", "Asterisk", "footnote", "note", "star"),
            icon("quote.opening", "Quote", "said", "citation", "speech"),
        ]),
        Group(title: "Numbers", stamps: [
            icon("1.circle.fill", "One", "1", "first", "step"),
            icon("2.circle.fill", "Two", "2", "second", "step"),
            icon("3.circle.fill", "Three", "3", "third", "step"),
            icon("4.circle.fill", "Four", "4", "fourth", "step"),
            icon("5.circle.fill", "Five", "5", "fifth", "step"),
            icon("6.circle.fill", "Six", "6", "sixth", "step"),
            icon("7.circle.fill", "Seven", "7", "seventh", "step"),
            icon("8.circle.fill", "Eight", "8", "eighth", "step"),
            icon("9.circle.fill", "Nine", "9", "ninth", "step"),
            icon("a.circle.fill", "A", "letter", "option", "first"),
            icon("b.circle.fill", "B", "letter", "option", "second"),
            icon("c.circle.fill", "C", "letter", "option", "third"),
        ]),
        Group(title: "Arrows", stamps: [
            icon("arrow.right", "Arrow right", "next", "forward", "then"),
            icon("arrow.left", "Arrow left", "back", "previous", "return"),
            icon("arrow.up", "Arrow up", "rise", "increase", "above"),
            icon("arrow.down", "Arrow down", "fall", "decrease", "below"),
            icon("arrow.up.right", "Arrow up right", "growth", "increase", "rise"),
            icon("arrow.down.right", "Arrow down right", "drop", "decrease", "fall"),
            icon("arrow.turn.down.right", "Turn down", "branch", "then", "flow"),
            icon("arrow.turn.up.right", "Turn up", "branch", "back", "flow"),
            icon("arrow.triangle.branch", "Branch", "split", "fork", "option"),
            icon("arrow.triangle.merge", "Merge", "join", "combine", "together"),
            icon("arrow.2.squarepath", "Repeat", "loop", "cycle", "again"),
            icon("arrow.uturn.left", "Undo", "back", "revert", "return"),
            icon("arrow.up.arrow.down", "Swap", "exchange", "reorder", "both ways"),
            icon("arrow.right.to.line", "To the end", "finish", "last", "push"),
        ]),
        Group(title: "Shapes", stamps: [
            icon("circle", "Circle", "round", "ring", "o"),
            icon("circle.fill", "Filled circle", "dot", "bullet", "point"),
            icon("square", "Square", "box", "tick box", "block"),
            icon("square.fill", "Filled square", "block", "box", "solid"),
            icon("triangle", "Triangle", "peak", "delta", "shape"),
            icon("diamond", "Diamond", "rhombus", "decision", "shape"),
            icon("rectangle", "Rectangle", "box", "frame", "block"),
            icon("capsule", "Capsule", "pill", "rounded", "tag"),
            icon("hexagon", "Hexagon", "six", "cell", "shape"),
            icon("pentagon", "Pentagon", "five", "shape"),
            icon("seal.fill", "Seal", "badge", "approved", "stamp"),
            icon("cloud.fill", "Cloud", "server", "online", "sky"),
        ]),
        Group(title: "Work", stamps: [
            emoji("✅", "Done", "tick", "check", "complete", "yes"),
            emoji("❌", "Not done", "cross", "no", "wrong", "fail"),
            emoji("⚠️", "Warning", "caution", "risk", "careful"),
            emoji("📌", "Pinned", "pin", "stick", "important"),
            emoji("📅", "Date", "calendar", "day", "schedule"),
            emoji("⏰", "Alarm", "clock", "time", "deadline", "reminder"),
            emoji("⏳", "Waiting", "hourglass", "later", "pending", "time"),
            emoji("💡", "Idea", "bulb", "think", "suggestion"),
            emoji("🔥", "Hot", "fire", "urgent", "priority"),
            emoji("🎯", "Target", "goal", "aim", "focus"),
            emoji("💰", "Money", "cost", "budget", "cash", "price"),
            emoji("📎", "Attachment", "clip", "file", "paper"),
            emoji("🔒", "Locked", "secure", "private", "closed"),
            emoji("🔑", "Key", "access", "password", "login"),
            emoji("📝", "Note", "write", "memo", "draft"),
            emoji("📊", "Chart", "data", "report", "stats"),
            emoji("📈", "Up", "growth", "increase", "trend"),
            emoji("📉", "Down", "drop", "decrease", "trend"),
            emoji("📥", "Inbox", "in", "receive", "incoming"),
            emoji("📤", "Outbox", "out", "send", "outgoing"),
            emoji("🏆", "Win", "trophy", "award", "best", "prize"),
            emoji("🗑️", "Bin", "trash", "delete", "remove"),
        ]),
        Group(title: "Faces", stamps: [
            emoji("🙂", "Slight smile", "happy", "fine", "ok"),
            emoji("😀", "Grin", "happy", "great", "smile"),
            emoji("😂", "Laughing", "funny", "lol", "joke"),
            emoji("😐", "Neutral", "meh", "flat", "unsure"),
            emoji("🙁", "Frown", "sad", "unhappy", "bad"),
            emoji("😮", "Surprised", "wow", "shock", "oh"),
            emoji("🤔", "Thinking", "hmm", "consider", "question"),
            emoji("😅", "Awkward", "phew", "close", "nervous"),
            emoji("😴", "Sleepy", "tired", "later", "dormant"),
            emoji("😤", "Frustrated", "annoyed", "angry", "ugh"),
            emoji("😎", "Cool", "sunglasses", "easy", "confident"),
            emoji("🥳", "Celebrate", "party", "done", "launch"),
        ]),
        Group(title: "Hands", stamps: [
            emoji("👍", "Thumbs up", "yes", "good", "approve", "like"),
            emoji("👎", "Thumbs down", "no", "bad", "reject", "dislike"),
            emoji("👏", "Applause", "clap", "well done", "praise"),
            emoji("🙏", "Please", "thanks", "pray", "ask"),
            emoji("👌", "OK", "fine", "good", "agreed"),
            emoji("✌️", "Peace", "two", "victory"),
            emoji("🤝", "Agreement", "handshake", "deal", "partner"),
            emoji("☝️", "Point up", "one", "note", "attention"),
            emoji("👈", "Point left", "back", "this", "here"),
            emoji("👉", "Point right", "next", "this", "there"),
            emoji("✍️", "Writing", "sign", "note", "author"),
            emoji("💪", "Strong", "effort", "power", "push"),
        ]),
        Group(title: "Nature", stamps: [
            emoji("☀️", "Sun", "sunny", "day", "clear", "weather"),
            emoji("🌙", "Moon", "night", "late", "dark"),
            emoji("⭐️", "Star", "favourite", "rating", "best"),
            emoji("☁️", "Cloud", "cloudy", "weather", "sky"),
            emoji("🌧️", "Rain", "wet", "weather", "storm"),
            emoji("⚡️", "Lightning", "power", "fast", "energy"),
            emoji("❄️", "Snow", "cold", "winter", "freeze"),
            emoji("🌈", "Rainbow", "colour", "color", "hope"),
            emoji("🌱", "Seedling", "new", "grow", "start"),
            emoji("🌳", "Tree", "nature", "grow", "green"),
            emoji("💧", "Water", "drop", "wet", "liquid"),
            emoji("🌊", "Wave", "sea", "water", "flow"),
        ]),
        Group(title: "Tech", stamps: [
            emoji("💻", "Laptop", "computer", "work", "code"),
            emoji("📱", "Phone", "mobile", "ios", "device"),
            emoji("🖥️", "Desktop", "mac", "computer", "screen"),
            emoji("⌨️", "Keyboard", "type", "input", "shortcut"),
            emoji("🔌", "Plug", "power", "connect", "socket"),
            emoji("🔋", "Battery", "power", "charge", "energy"),
            emoji("📡", "Signal", "network", "sync", "antenna"),
            emoji("⚙️", "Settings", "gear", "config", "options"),
            emoji("🛠️", "Tools", "fix", "build", "maintain"),
            emoji("🐛", "Bug", "defect", "issue", "error"),
            emoji("🧪", "Test", "experiment", "lab", "trial"),
            emoji("💾", "Backup", "save", "disk", "copy", "storage"),
        ]),
        Group(title: "Places", stamps: [
            emoji("🏠", "Home", "house", "personal", "family"),
            emoji("🏢", "Office", "work", "building", "company"),
            emoji("🏥", "Hospital", "health", "doctor", "clinic"),
            emoji("🏫", "School", "study", "class", "learn"),
            emoji("🏦", "Bank", "money", "finance", "account"),
            emoji("✈️", "Flight", "travel", "plane", "trip"),
            emoji("🚗", "Car", "drive", "travel", "vehicle"),
            emoji("🚕", "Taxi", "ride", "travel", "cab"),
            emoji("🚀", "Launch", "rocket", "ship", "release"),
            emoji("🗺️", "Map", "plan", "route", "where"),
            emoji("📍", "Location", "place", "pin", "here"),
            emoji("🛒", "Shopping", "buy", "cart", "order"),
        ]),
        Group(title: "Everyday", stamps: [
            emoji("☕️", "Coffee", "break", "morning", "drink"),
            emoji("🍽️", "Meal", "food", "lunch", "dinner", "eat"),
            emoji("🎂", "Birthday", "cake", "celebrate", "anniversary"),
            emoji("🎁", "Gift", "present", "reward", "surprise"),
            emoji("🎵", "Music", "song", "audio", "sound"),
            emoji("📷", "Photo", "camera", "picture", "image"),
            emoji("📞", "Call", "phone", "ring", "talk"),
            emoji("✉️", "Email", "mail", "message", "send"),
            emoji("💬", "Comment", "chat", "message", "talk"),
            emoji("❤️", "Heart", "love", "like", "favourite"),
            emoji("🩺", "Health", "doctor", "medical", "check-up"),
            emoji("🧹", "Cleanup", "tidy", "sweep", "chore"),
        ]),
    ]
}
