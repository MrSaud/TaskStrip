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
    // The third dotfile, hidden the same way and for the same reason. A sketch is the only thing
    // this app keeps with no row anywhere, so its shared id has to live beside it. Mirrors
    // SketchStorage.kt.
    private static let syncIDFile = ".syncid"
    // A folder whose pages are gone but which still says "this existed and was deleted".
    private static let deletedFile = ".deleted"

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

    /// A tombstone, not a removal.
    ///
    /// The pages go — they are the bulk, and nothing should point at them once the note is gone —
    /// but the folder stays, holding the id and the moment of the delete. Removed outright, the
    /// note would be indistinguishable from one the other device has never seen, and the next sync
    /// would draw it again. `notes()` never shows what is left, because it only lists folders that
    /// still have pages.
    func deleteNote(_ id: String) {
        // Minted before the pages go, so a note deleted having never synced still has a name to be
        // deleted by.
        _ = syncID(of: id)
        for page in pages(of: id) { try? FileManager.default.removeItem(at: page) }
        // The name goes with the pages. A tombstone is only a name to be deleted by and the moment
        // it happened — keeping the title of a note nobody can open would be keeping the one part
        // of it that still reads like content.
        try? FileManager.default.removeItem(at: folder(of: id).appending(path: Self.nameFile))
        let marker = folder(of: id).appending(path: Self.deletedFile)
        try? String(Int(Date.now.timeIntervalSince1970 * 1000)).write(to: marker, atomically: true, encoding: .utf8)
    }

    // MARK: - Syncing

    /// The id both devices know this sketch by, minted the first time it is asked for.
    ///
    /// On demand rather than at creation: sketches drawn before any of this existed have no id,
    /// and the first sync should carry them across rather than skip them for being old.
    func syncID(of id: String) -> String {
        let url = folder(of: id).appending(path: Self.syncIDFile)
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let minted = UUID().uuidString
        setSyncID(minted, of: id)
        return minted
    }

    func setSyncID(_ syncID: String, of id: String) {
        try? FileManager.default.createDirectory(at: folder(of: id), withIntermediateDirectories: true)
        try? syncID.write(to: folder(of: id).appending(path: Self.syncIDFile), atomically: true, encoding: .utf8)
    }

    func isDeleted(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: folder(of: id).appending(path: Self.deletedFile).path)
    }

    /// When it was deleted, so the merge can tell a fresh delete from a stale one.
    func deletedAt(of id: String) -> Int64 {
        let url = folder(of: id).appending(path: Self.deletedFile)
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let millis = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return 0 }
        return millis
    }

    /// Every folder the sync cares about: live notes and the tombstones of dead ones.
    func allIDsForSync() -> [String] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )
        return (contents ?? []).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }.map(\.lastPathComponent)
    }
}
