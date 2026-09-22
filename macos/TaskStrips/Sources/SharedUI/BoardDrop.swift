import Foundation
import UniformTypeIdentifiers

/// What a dropped thing becomes.
///
/// Android receives files and text through the system share sheet — ShareTargetScreen and
/// ShareStorageScreen. A Mac has no share sheet worth the name, but it has something better
/// suited: you drag the thing onto the window. Same idea, better idiom.
enum BoardDrop {
    /// Text dropped on the board becomes a strip, by the same rule a quick note does when it's
    /// promoted: the first non-blank line is the title, the whole text is the notes. One rule for
    /// "turn this prose into a strip", not two that drift apart.
    static func strip(fromDroppedText text: String, orderIndex: Int) -> TaskItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return NotePromotion.strip(from: Note(text: trimmed), orderIndex: orderIndex)
    }

    /// Only real files: a drag can carry a URL that points at a web page, and attaching that
    /// would produce a strip pointing at a file that was never there.
    static func usableFiles(among urls: [URL]) -> [URL] {
        urls.filter { $0.isFileURL }
    }

    /// What a dropped file lands as in the library, using the same rules a picked one does.
    static func storageType(for url: URL) -> StorageItemType {
        StorageItemType.inferred(
            mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType,
            name: url.lastPathComponent
        )
    }

    /// What it lands as on a strip.
    static func attachmentKind(for url: URL) -> AttachmentKind {
        AttachmentKind.inferred(fromExtension: url.pathExtension)
    }
}
