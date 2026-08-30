import Foundation
import SwiftData

/// The three categories the library sorts itself into. Raw values match the strings Android
/// writes into `storage_items.type` and into a backup, so a row round-trips unchanged.
enum StorageItemType: String, Codable, CaseIterable, Identifiable {
    case image = "IMAGE"
    case video = "VIDEO"
    case document = "DOCUMENT"

    var id: String { rawValue }

    /// The library keeps its files in the same folders strips keep theirs, so a file can be
    /// copied onto a strip without moving on disk.
    var attachmentKind: AttachmentKind {
        switch self {
        case .image: return .image
        case .video: return .video
        case .document: return .document
        }
    }

    var sectionTitle: String {
        switch self {
        case .image: return "PHOTOS"
        case .video: return "VIDEOS"
        case .document: return "DOCUMENTS"
        }
    }

    var systemImage: String { attachmentKind.systemImage }

    /// What category a picked file lands in.
    ///
    /// Android leads with the reported MIME type and falls back to the extension when that type
    /// is useless — null, a wildcard, or application/octet-stream — because share sheets report
    /// exactly that for perfectly ordinary photos, and a photo filed under Documents never turns
    /// up when a strip's picker is filtered to Photos. The Mac picks files through NSOpenPanel
    /// rather than a share sheet, so the extension is usually all there is; the MIME path is kept
    /// so an imported row keeps the category it had.
    static func inferred(mimeType: String?, name: String) -> StorageItemType {
        if let mimeType, !isUseless(mimeType) {
            if mimeType.hasPrefix("image/") { return .image }
            if mimeType.hasPrefix("video/") { return .video }
            return .document
        }
        switch AttachmentKind.inferred(fromExtension: (name as NSString).pathExtension) {
        case .image: return .image
        case .video: return .video
        // A voice note has no shelf of its own in the library — Android's picker files anything
        // that isn't an image or a video as a document, and audio is no exception.
        case .voiceNote, .document: return .document
        }
    }

    private static func isUseless(_ mimeType: String) -> Bool {
        let trimmed = mimeType.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty || trimmed == "*/*" || trimmed == "application/octet-stream"
    }
}

/// A file in the shared library, mirroring StorageItemEntity.kt.
///
/// The library is deliberately not part of any strip: files land here from a share or a manual
/// pick, and a strip takes its own copy when it needs one. `path` is relative to the media root,
/// the same convention TaskAttachment uses, so the two are interchangeable on disk.
@Model
final class StorageItem: Identifiable, Taggable {
    @Attribute(.unique) var id: UUID
    var name: String
    var path: String
    var typeRaw: String
    var mimeType: String
    var sizeBytes: Int
    /// Free text, not a fixed set — "Invoice", "Contract", whatever the user files things under.
    /// Blank means untagged.
    var tag: String
    /// Kept separate from `tag` so the emoji is decoration rather than part of the tag's
    /// identity, exactly as Android keeps them apart.
    var tagEmoji: String
    var createdAt: Date

    var type: StorageItemType {
        get { StorageItemType(rawValue: typeRaw) ?? .document }
        set { typeRaw = newValue.rawValue }
    }

    init(
        name: String,
        path: String,
        type: StorageItemType,
        mimeType: String = "",
        sizeBytes: Int = 0,
        tag: String = "",
        tagEmoji: String = "",
        id: UUID = UUID(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.typeRaw = type.rawValue
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.tag = tag
        self.tagEmoji = tagEmoji
        self.createdAt = createdAt
    }
}
