import Foundation

/// The rules the library view runs on: what's taggable, what a tag filter means, and what's
/// visible once one is applied. Pure, so they can be checked without a window.
enum StorageLibrary {
    /// The categories Android offers as one-tap chips. Free text is still allowed — these just
    /// spare the user from typing "Invoice" for the hundredth time.
    static let tagPresets: [(tag: String, emoji: String)] = [
        ("Invoice", "🧾"),
        ("Contract", "✍️"),
        ("Receipt", "💳"),
        ("Manual", "📘"),
        ("ID", "🪪"),
        ("Medical", "💊"),
        ("Travel", "✈️"),
        ("Warranty", "🛡️"),
    ]

    // The tag rules themselves live in Tagging, since the reminders list runs on the same ones.

    static func tagEmojis(in items: [StorageItem]) -> [String: String] { Tagging.emojis(in: items) }

    static func availableTags(in items: [StorageItem]) -> [String] { Tagging.availableTags(in: items) }

    static func activeTag(_ tag: String?, in items: [StorageItem]) -> String? {
        Tagging.activeTag(tag, in: items)
    }

    /// One filter for the whole library, not one per section: "show me everything tagged Travel"
    /// is the question actually being asked.
    static func visible(_ items: [StorageItem], tag: String?) -> [StorageItem] {
        Tagging.filtered(items, tag: tag)
    }

    static func items(_ items: [StorageItem], ofType type: StorageItemType) -> [StorageItem] {
        items.filter { $0.type == type }
    }

    /// Newest first, matching StorageItemDao's `ORDER BY createdAt DESC` — the file you just
    /// added is the one you're looking for.
    static func sorted(_ items: [StorageItem]) -> [StorageItem] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Quick Look

    /// What the space bar should do, given what's selected and whether a preview is already up.
    ///
    /// Toggling rather than always opening is Finder's behaviour, and it's the half people
    /// actually rely on: space to look, space to stop looking, without reaching for the mouse.
    enum QuickLook: Equatable {
        case open(UUID)
        case close
        case nothing
    }

    static func quickLookAction(selection: UUID?, in items: [StorageItem], isPreviewing: Bool) -> QuickLook {
        if isPreviewing { return .close }
        // A selection can outlive the row it names — the file was deleted, or the tag filter
        // moved on — and a preview of something no longer on screen would be a small mystery.
        guard let selection, items.contains(where: { $0.id == selection }) else { return .nothing }
        return .open(selection)
    }

    /// A size a person can read. Files here run from a scanned receipt to a video, so the unit
    /// has to move with them.
    static func readableSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
