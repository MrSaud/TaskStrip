import Foundation
import SwiftUI

/// Reads the board's files in the background so they can be searched.
///
/// A few at a time, and only ones it hasn't read: OCR of a scanned page costs a second or two,
/// and a board with two hundred files on it shouldn't spend two hundred seconds on the first
/// launch after this arrives. It gets through them over a few visits and then has nothing to do.
@MainActor
final class DocumentIndexer: ObservableObject {
    static let shared = DocumentIndexer()

    @Published private(set) var index: [String: IndexedDocument] = [:]
    @Published private(set) var isReading = false
    /// How many files are still waiting to be read, for a line in Settings.
    @Published private(set) var waiting = 0

    private let store = DocumentIndexStore()
    private let attachments = AttachmentStore.shared
    private var isLoaded = false

    /// Per visit. Enough to get through an ordinary board in two or three, few enough that a
    /// phone doesn't warm up in somebody's hand.
    static let perRun = 8

    private init() {}

    func load() {
        guard !isLoaded else { return }
        isLoaded = true
        index = store.read()
    }

    /// Reads whatever hasn't been read yet, and forgets files that have left the board.
    func refresh(for tasks: [TaskItem]) {
        load()
        guard !isReading else { return }

        let all = tasks.flatMap(\.attachments)
        let paths = Set(all.map(\.path))
        var current = store.pruned(index, keeping: paths)

        let unread = all.filter { attachment in
            current[attachment.path] == nil
                && DocumentTextReader.canRead(attachments.url(for: attachment))
                && attachments.exists(attachment)
        }
        waiting = unread.count
        guard !unread.isEmpty else {
            index = current
            store.write(current)
            return
        }

        isReading = true
        let batch = Array(unread.prefix(Self.perRun))
        let urls = batch.map { (attachment: $0, url: attachments.url(for: $0)) }

        Task {
            var read: [IndexedDocument] = []
            for file in urls {
                let text = (try? await DocumentTextReader.text(of: file.url)) ?? ""
                let folded = DocumentIndex.folded(text)
                read.append(
                    IndexedDocument(
                        path: file.attachment.path,
                        name: file.attachment.name,
                        text: folded,
                        readAt: .now,
                        // Remembered as empty rather than left unread, or a picture of a sunset
                        // is re-read on every visit forever.
                        wasEmpty: folded.isEmpty
                    )
                )
            }
            for document in read { current[document.path] = document }
            let settled = current
            await MainActor.run {
                index = settled
                store.write(settled)
                waiting = max(0, waiting - read.count)
                isReading = false
            }
        }
    }

    /// The strips whose files answer this search, and which file did — so the board can say why a
    /// strip it can't otherwise explain is on screen.
    func matches(for query: String, in tasks: [TaskItem]) -> [UUID: String] {
        guard DocumentIndex.isWorthSearching(query) else { return [:] }
        var found: [UUID: String] = [:]
        for task in tasks {
            let hits = DocumentIndex.matching(paths: task.attachments.map(\.path), query: query, in: index)
            if let first = hits.first { found[task.id] = first.name }
        }
        return found
    }

    /// Forgets everything it has read. The board reads what it needs again the next time it's
    /// open, which is the only place that knows which files are still on it.
    func forget() {
        load()
        index = [:]
        store.write([:])
        waiting = 0
    }

    /// How many files have been read, for a line in Settings.
    var readCount: Int { index.values.filter { !$0.wasEmpty }.count }

    /// Text already extracted elsewhere — the date reader does exactly this work — is worth
    /// keeping rather than doing twice.
    func remember(_ text: String, for attachment: TaskAttachment) {
        load()
        var current = index
        current[attachment.path] = IndexedDocument(
            path: attachment.path,
            name: attachment.name,
            text: DocumentIndex.folded(text),
            readAt: .now,
            wasEmpty: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        index = current
        store.write(current)
    }
}
