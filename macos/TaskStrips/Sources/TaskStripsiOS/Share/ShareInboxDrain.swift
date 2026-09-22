import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Files whatever the Share Extension left in the inbox: strips onto the bottom of the board,
/// files into the storage library. Each entry is removed only once it's in the store, so a crash
/// halfway leaves the rest to be filed next time rather than lost.
@MainActor
enum ShareInboxDrain {
    struct Filed: Equatable {
        var strips = 0
        var files = 0
        var failures = 0
        var isEmpty: Bool { strips == 0 && files == 0 && failures == 0 }

        var summary: String {
            var parts: [String] = []
            if strips > 0 { parts.append("\(strips) strip\(strips == 1 ? "" : "s") filed") }
            if files > 0 { parts.append("\(files) file\(files == 1 ? "" : "s") added to storage") }
            if failures > 0 { parts.append("\(failures) couldn't be filed") }
            return parts.joined(separator: ", ") + "."
        }
    }

    static func run(
        context: ModelContext,
        tasks: [TaskItem],
        defaultPriority: Priority,
        store: AttachmentStore = .shared,
        root: URL? = ShareInbox.root
    ) -> Filed {
        var filed = Filed()
        var nextIndex = StripActions.nextOrderIndex(in: tasks)

        for (entry, folder) in ShareInbox.pending(root: root) {
            switch entry.kind {
            case .strip:
                let task = TaskItem(title: entry.title, orderIndex: nextIndex, priority: defaultPriority)
                nextIndex += 1
                task.notes = entry.notes
                task.contacts = entry.contacts.map { TaskContact(name: $0.name, email: $0.email, phone: $0.phone) }
                context.insert(task)
                filed.strips += 1
            case .files:
                for name in entry.fileNames {
                    let url = folder.appending(path: name)
                    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    let type = StorageItemType.inferred(mimeType: mime, name: name)
                    do {
                        let copy = try store.add(contentsOf: url, kind: type.attachmentKind)
                        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        context.insert(StorageItem(
                            name: name, path: copy.path, type: type,
                            mimeType: mime ?? "", sizeBytes: size, tag: entry.tag
                        ))
                        filed.files += 1
                    } catch {
                        filed.failures += 1
                    }
                }
            }
            do {
                try context.save()
                ShareInbox.remove(folder)
            } catch {
                filed.failures += 1
            }
        }
        return filed
    }
}
