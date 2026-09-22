import Foundation

/// The four kinds Android keeps as separate lists on TaskEntity. One enum here rather than four
/// arrays, with the split back out to those lists happening only at the backup boundary.
enum AttachmentKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case image
    case voiceNote
    case document
    case video

    var id: String { rawValue }

    /// The key this kind lives under in a backup's task JSON.
    var backupKey: String {
        switch self {
        case .image: return "images"
        case .voiceNote: return "voiceNotes"
        case .document: return "documents"
        case .video: return "videos"
        }
    }

    /// The folder under the media root. Matches MediaStorage.kt's layout under filesDir — note
    /// voice notes live in "audio", not "voiceNotes" — so a path out of a backup needs no
    /// rewriting to land in the right place.
    var folder: String {
        switch self {
        case .image: return "images"
        case .voiceNote: return "audio"
        case .document: return "documents"
        case .video: return "videos"
        }
    }

    var label: String {
        switch self {
        case .image: return "Image"
        case .voiceNote: return "Voice note"
        case .document: return "Document"
        case .video: return "Video"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .voiceNote: return "waveform"
        case .document: return "doc"
        case .video: return "film"
        }
    }

    /// What a file with this extension is. Everything unrecognised is a document, which is also
    /// how Android treats anything picked through the document picker.
    static func inferred(fromExtension ext: String) -> AttachmentKind {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp":
            return .image
        case "mov", "mp4", "m4v", "avi", "mkv", "webm":
            return .video
        case "m4a", "mp3", "wav", "aac", "caf", "aiff", "aif", "flac", "ogg":
            return .voiceNote
        default:
            return .document
        }
    }
}

/// A file attached to a strip.
///
/// `path` is relative to the media root, never absolute — unlike Android, which stores absolute
/// paths and converts them on the way into a backup. Relative from the start means the store
/// survives being moved and needs no rewriting on import or export.
struct TaskAttachment: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: AttachmentKind = .document
    var path: String = ""
    /// What to show the user — the file's original name, which the stored name may not be.
    var name: String = ""
    var addedAt: Date = .now
}
