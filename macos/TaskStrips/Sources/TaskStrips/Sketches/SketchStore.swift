import Foundation

/// A sketch note: a folder of page PNGs, mirroring SketchStorage.kt.
struct SketchNote: Identifiable, Equatable {
    /// The folder name, which is also what a strip's linkedSketchID points at.
    let id: String
    var name: String?
    var pageCount: Int
    var lastModified: Date
    var createdAt: Date

    /// What to call it in a list: its name if it has one, otherwise when it was last touched.
    /// Mirrors SketchStorage.displayLabel.
    var displayName: String {
        name ?? SketchStore.dateLabel(lastModified)
    }

    var createdLabel: String { SketchStore.dateLabel(createdAt) }
}

/// Where sketches live, mirroring SketchStorage.kt exactly — `sketches/<note>/page1.png`, with an
/// optional `.name` beside the pages.
///
/// Deliberately the same folder the backup import already restores into, so a sketch drawn on the
/// phone opens here rather than sitting on disk as bytes nothing can read. That pass-through came
/// first; this is what makes it worth having.
struct SketchStore {
    let root: URL

    static let shared = SketchStore(root: AttachmentStore.shared.url(forRelativePath: BackupArchive.sketchesPrefix))

    private static let nameFile = ".name"
    private static let createdFile = ".created"

    /// Android formats these with "dd MMM yyyy, HH:mm", and the two apps show the same sketch.
    private static let labelFormat: Date.FormatStyle = .dateTime
        .day(.twoDigits).month(.abbreviated).year()
        .hour(.twoDigits(amPM: .omitted)).minute()

    static func dateLabel(_ date: Date) -> String { date.formatted(labelFormat) }

    /// Newest first. A folder with no pages isn't a note — backing out of a blank one leaves
    /// nothing behind, which is why the folder is only made when a page is saved.
    func notes() -> [SketchNote] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .compactMap { note($0.lastPathComponent) }
            .sorted { $0.lastModified > $1.lastModified }
    }

    func note(_ id: String) -> SketchNote? {
        let pages = pages(of: id)
        guard !pages.isEmpty else { return nil }
        return SketchNote(
            id: id,
            name: name(of: id),
            pageCount: pages.count,
            lastModified: lastModified(of: id),
            createdAt: createdAt(of: id)
        )
    }

    /// Doesn't touch the disk: the folder appears when the first page is saved, so a note
    /// abandoned before drawing anything never existed.
    static func newNoteID(now: Date = .now) -> String {
        "note_\(Int(now.timeIntervalSince1970 * 1000))"
    }

    func folder(of id: String) -> URL {
        root.appending(path: id, directoryHint: .isDirectory)
    }

    /// Pages in page-number order, not the alphabetical order the filesystem gives back — page10
    /// sorts before page2 as text.
    func pages(of id: String) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder(of: id), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { Self.pageNumber($0) < Self.pageNumber($1) }
    }

    static func pageNumber(_ url: URL) -> Int {
        Int(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "page", with: "")) ?? 0
    }

    func nextPageURL(of id: String) -> URL {
        let next = (pages(of: id).map(Self.pageNumber).max() ?? 0) + 1
        return folder(of: id).appending(path: "page\(next).png")
    }

    /// A page's own date, which changes when it's redrawn in place — the folder's doesn't.
    func lastModified(of id: String) -> Date {
        let dates = pages(of: id).compactMap {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return dates.max() ?? .distantPast
    }

    // MARK: - Created

    /// A page is overwritten in place on every edit, so its own date can't answer "when was this
    /// drawn" — Android stamps that once, into a hidden file, the first time a page is saved.
    func createdAt(of id: String) -> Date {
        let url = folder(of: id).appending(path: Self.createdFile)
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let millis = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Date(timeIntervalSince1970: millis / 1000)
        }
        // Sketches drawn before the stamp existed still carry their creation time in the folder
        // name the app gave them. Only then fall back to the pages' own dates.
        if id.hasPrefix("note_"), let millis = Double(id.dropFirst("note_".count)) {
            return Date(timeIntervalSince1970: millis / 1000)
        }
        return lastModified(of: id)
    }

    func stampCreatedIfMissing(_ id: String, now: Date = .now) {
        let url = folder(of: id).appending(path: Self.createdFile)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: folder(of: id), withIntermediateDirectories: true)
        try? String(Int(now.timeIntervalSince1970 * 1000)).write(to: url, atomically: true, encoding: .utf8)
    }

    func write(_ png: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try png.write(to: url)
    }

    // MARK: - Names

    /// A hidden file inside the note's own folder, so it needs no filter of its own: it isn't a
    /// .png, so nothing that lists pages ever sees it.
    func name(of id: String) -> String? {
        let url = folder(of: id).appending(path: Self.nameFile)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func setName(_ name: String, of id: String) {
        let url = folder(of: id).appending(path: Self.nameFile)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? FileManager.default.createDirectory(at: folder(of: id), withIntermediateDirectories: true)
            try? trimmed.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Removing

    func deletePage(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func deleteNote(_ id: String) {
        try? FileManager.default.removeItem(at: folder(of: id))
    }
}
