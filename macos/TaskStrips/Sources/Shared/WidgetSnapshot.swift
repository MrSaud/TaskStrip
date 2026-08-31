import Foundation

/// What the board looks like from outside the app.
///
/// The widget runs in its own sandboxed process and cannot open the app's SwiftData store, which
/// lives in Application Support where a sandboxed extension has no business. Rather than move the
/// live store into a group container — a migration of real data for the sake of a read-only view —
/// the app writes this small snapshot into the group container whenever the board changes and the
/// widget reads it.
///
/// That is also how the phone works. Android's widget is never given the database either: the app
/// renders it and pushes it, in WidgetUpdater. Same shape, different plumbing.
struct WidgetSnapshot: Codable, Equatable {
    /// The same counts the phone's widget shows, so the two say the same thing side by side.
    static let maxStrips = 5
    static let maxReminders = 3

    static let widgetBundleID = "com.saud.taskstrip.mac.widget"
    static let fileName = "widget-snapshot.json"

    struct Strip: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        /// The Android enum's name — URGENT, HIGH, NORMAL, LOW — matching TaskItem.priorityRaw.
        var priority: String
        var dueAt: Date?
    }

    struct Reminder: Codable, Equatable, Identifiable {
        var id: String
        var text: String
        var triggerAt: Date
    }

    var strips: [Strip]
    var reminders: [Reminder]
    var writtenAt: Date

    /// Equality is about what is shown, not when it was written. writtenAt moves every time a
    /// snapshot is built, so leaving it in would make every snapshot differ from the last one and
    /// turn "publish only on a real change" into "publish on every render".
    static func == (lhs: WidgetSnapshot, rhs: WidgetSnapshot) -> Bool {
        lhs.strips == rhs.strips && lhs.reminders == rhs.reminders
    }

    static let empty = WidgetSnapshot(strips: [], reminders: [], writtenAt: .distantPast)

    // Both sides address the same file, from opposite sides of a sandbox boundary.
    //
    // The obvious mechanism is an App Group, and it is not available here: the entitlement is
    // one Xcode refuses to sign without a development certificate and team, which would bind this
    // project to an Apple Developer account and require registering the group on the portal — a
    // large price for a read-only view of five rows.
    //
    // What makes the alternative work is that the app is not sandboxed (it reads files all over
    // the user's disk for storage and attachments) while the widget always is. So the app writes
    // straight into the widget's own container, which the widget can read with no entitlement at
    // all because it is its own. The two paths below are the same file said two ways.

    /// Where the widget looks. Inside its sandbox this resolves to its own container.
    static var readURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: fileName)
    }

    /// Where the app writes: the widget's container, addressed from outside it.
    ///
    /// The directory is created if it isn't there — the container exists only once the extension
    /// has run at least once, and the board should not have to wait for that to publish.
    static var writeURL: URL? {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/\(widgetBundleID)/Data/Library/Application Support",
                       directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: fileName)
    }

    /// Written atomically: the widget may read at any moment, and half a JSON file is worse than
    /// a stale whole one.
    func write() {
        guard let url = Self.writeURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// An unreadable or missing snapshot is an empty board rather than an error — a widget has
    /// nowhere to report a failure to, so it shows nothing and waits for the next write.
    ///
    /// Reads the widget's own path first and falls back to the app's, so the same call works in
    /// both processes: in the extension the first hits, in the app the second does.
    static func read() -> WidgetSnapshot {
        for url in [readURL, writeURL].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
                return snapshot
            }
        }
        return .empty
    }
}
