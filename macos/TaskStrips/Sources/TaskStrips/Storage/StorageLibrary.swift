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

    /// Tag to the emoji shown beside it. If two items share a tag with different emoji, the last
    /// one wins — the same rule Android's filter menu applies rather than showing the tag twice.
    static func tagEmojis(in items: [StorageItem]) -> [String: String] {
        var emojis: [String: String] = [:]
        for item in items where item.isTagged {
            emojis[item.tag] = item.tagEmoji
        }
        return emojis
    }

    static func availableTags(in items: [StorageItem]) -> [String] {
        tagEmojis(in: items).keys.sorted()
    }

    /// A filter whose last item was deleted or retagged stops applying, rather than leaving the
    /// library filtered down to nothing with no obvious way back.
    static func activeTag(_ tag: String?, in items: [StorageItem]) -> String? {
        guard let tag, availableTags(in: items).contains(tag) else { return nil }
        return tag
    }

    /// One filter for the whole library, not one per section: "show me everything tagged Travel"
    /// is the question actually being asked.
    static func visible(_ items: [StorageItem], tag: String?) -> [StorageItem] {
        guard let tag = activeTag(tag, in: items) else { return items }
        return items.filter { $0.tag == tag }
    }

    static func items(_ items: [StorageItem], ofType type: StorageItemType) -> [StorageItem] {
        items.filter { $0.type == type }
    }

    /// Newest first, matching StorageItemDao's `ORDER BY createdAt DESC` — the file you just
    /// added is the one you're looking for.
    static func sorted(_ items: [StorageItem]) -> [StorageItem] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    /// A size a person can read. Files here run from a scanned receipt to a video, so the unit
    /// has to move with them.
    static func readableSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
