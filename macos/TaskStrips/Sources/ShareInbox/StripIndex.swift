import Foundation

/// The board's strips, by name, for the Share Extension to offer.
///
/// The extension is its own program and can't open the app's store, so it can't know what's on
/// the board — which is why sharing something could only ever make a new strip. The app leaves
/// this list in the App Group whenever the board changes, the same arrangement the widget has,
/// and the extension reads it to let you file an email onto a strip that already exists.
///
/// Titles only. Nothing here is the board: it's a menu of names, rewritten from the board every
/// time it changes, and a name that's gone by the time the app files the entry simply falls back
/// to making a strip.
struct StripIndexEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var tags: [String] = []
    var isDone = false
    /// Newest first is wrong for a board; this keeps the board's own order.
    var orderIndex: Int = 0
}

enum StripIndex {
    private static let file = "strips.json"

    static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareInbox.appGroup)?
            .appending(path: file)
    }

    static func write(_ strips: [StripIndexEntry], to url: URL? = url) {
        guard let url, let data = try? JSONEncoder().encode(strips) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read(from url: URL? = url) -> [StripIndexEntry] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StripIndexEntry].self, from: data)) ?? []
    }

    /// The strips whose title or tags match what's been typed, in board order. An empty search is
    /// every strip, because the first thing someone does is look at the list.
    static func matching(_ query: String, in strips: [StripIndexEntry]) -> [StripIndexEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matches = trimmed.isEmpty ? strips : strips.filter { strip in
            strip.title.localizedCaseInsensitiveContains(trimmed)
                || strip.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
        return matches.sorted { ($0.isDone ? 1 : 0, $0.orderIndex) < ($1.isDone ? 1 : 0, $1.orderIndex) }
    }
}
