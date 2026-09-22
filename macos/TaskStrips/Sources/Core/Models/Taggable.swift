import Foundation

/// Anything carrying one of the app's free-text tags and its emoji.
///
/// Two lists on Android filter by tag — the storage library and the reminders list — with the
/// same rules spelled out twice, and Android's own comment on the second says so ("the same rule
/// RemindersScreen applies"). One set of rules here instead.
protocol Taggable {
    var tag: String { get }
    var tagEmoji: String { get }
}

extension Taggable {
    var isTagged: Bool { !tag.isEmpty }

    /// "🧾 Invoice", or just the tag when there's no emoji, or nothing at all when untagged.
    var tagLabel: String {
        [tagEmoji, tag].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum Tagging {
    /// Tag to the emoji shown beside it. Two items sharing a tag with different emoji would
    /// otherwise put the tag in the menu twice; the last one wins.
    static func emojis<T: Taggable>(in items: [T]) -> [String: String] {
        var emojis: [String: String] = [:]
        for item in items where item.isTagged {
            emojis[item.tag] = item.tagEmoji
        }
        return emojis
    }

    static func availableTags<T: Taggable>(in items: [T]) -> [String] {
        emojis(in: items).keys.sorted()
    }

    /// A filter whose last item was deleted or retagged stops applying, rather than leaving the
    /// list showing nothing with no obvious way back.
    static func activeTag<T: Taggable>(_ tag: String?, in items: [T]) -> String? {
        guard let tag, availableTags(in: items).contains(tag) else { return nil }
        return tag
    }

    static func filtered<T: Taggable>(_ items: [T], tag: String?) -> [T] {
        guard let tag = activeTag(tag, in: items) else { return items }
        return items.filter { $0.tag == tag }
    }
}
