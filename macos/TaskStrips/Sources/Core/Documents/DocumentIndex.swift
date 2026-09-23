import Foundation

/// What a document says, kept so it can be searched for.
struct IndexedDocument: Codable, Equatable {
    /// The attachment's path inside the store, which is what a strip points at.
    var path: String
    var name: String
    /// The words, folded to lower case and squeezed — this is for matching, not for reading.
    var text: String
    var readAt: Date
    /// True when the file held no words at all. Kept so it isn't read again every time.
    var wasEmpty: Bool = false
}

/// The searchable text of the files on the board.
///
/// A board with fifty invoices on it can only be searched by what somebody remembered to type in
/// the title. The words are already in the files — this is where they're kept once something has
/// read them, so "412.500" finds the invoice rather than nothing.
///
/// On the device, in the app's own folder, and never sent anywhere.
enum DocumentIndex {
    /// How much of one document to keep. The first pages carry the reference numbers, the names
    /// and the amounts; a hundred-page contract's back matter is not what anybody searches for.
    static let charactersPerDocument = 20_000

    /// Squeezed for matching: lower case, one space between words, no line breaks. A search for
    /// "invoice 4471" should find it whether the document broke the line between them or not.
    static func folded(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .prefix(charactersPerDocument)
            .description
    }

    /// Whether a document's words answer a search.
    ///
    /// Every word of the query has to appear, in any order — "invoice kfas" finds a document with
    /// both, wherever they sit. A single word is matched as written, so a reference number typed
    /// in part still finds its document.
    static func matches(_ document: IndexedDocument, query: String) -> Bool {
        let words = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return false }
        return words.allSatisfy { document.text.contains($0) }
    }

    /// Which of a strip's files answer a search — the name of the first is what the board shows
    /// as the reason a strip turned up.
    static func matching(paths: [String], query: String, in index: [String: IndexedDocument]) -> [IndexedDocument] {
        paths.compactMap { index[$0] }.filter { matches($0, query: query) }
    }

    /// Searching for two letters would return the whole board, which is not a search.
    static let shortestQuery = 3

    static func isWorthSearching(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespaces).count >= shortestQuery
    }
}

/// Where the index lives: one file beside the board, written whole.
///
/// A file rather than the settings: the text of a hundred documents is megabytes, and settings
/// are read into memory by everything that asks for any of them.
struct DocumentIndexStore {
    let url: URL

    init(url: URL = BoardLocation.directory.appending(path: "DocumentIndex.json")) {
        self.url = url
    }

    func read() -> [String: IndexedDocument] {
        guard let data = try? Data(contentsOf: url),
              let documents = try? JSONDecoder().decode([IndexedDocument].self, from: data)
        else { return [:] }
        return Dictionary(documents.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func write(_ index: [String: IndexedDocument]) {
        guard let data = try? JSONEncoder().encode(Array(index.values)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Files that have gone from the board take their words with them.
    func pruned(_ index: [String: IndexedDocument], keeping paths: Set<String>) -> [String: IndexedDocument] {
        index.filter { paths.contains($0.key) }
    }
}
