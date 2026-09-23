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
            // Shared onto a strip that already exists: the link, the files and anything written
            // join it rather than starting something new.
            if let id = entry.targetStripID, let strip = tasks.first(where: { $0.id == id }) {
                apply(entry, in: folder, to: strip, store: store, filed: &filed)
                do {
                    try context.save()
                    ShareInbox.remove(folder)
                } catch {
                    filed.failures += 1
                }
                continue
            }

            switch entry.kind {
            case .strip:
                let task = TaskItem(title: entry.title, orderIndex: nextIndex, priority: defaultPriority)
                nextIndex += 1
                task.notes = entry.notes
                task.contacts = entry.contacts.map { TaskContact(name: $0.name, email: $0.email, phone: $0.phone) }
                // A shared email is a link back to the message, named with its subject.
                task.links = entry.links.map { url in
                    TaskLink(url: url, label: EmailLink.isMessage(url) ? entry.title : "")
                }
                // A strip can arrive with files too — a shared email brings the message itself
                // along with the link back to it.
                for name in entry.fileNames {
                    let url = folder.appending(path: name)
                    guard let copy = try? store.add(
                        contentsOf: url, kind: AttachmentKind.inferred(fromExtension: url.pathExtension)
                    ) else {
                        filed.failures += 1
                        continue
                    }
                    task.attachments.append(copy)
                }
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

    /// Adds what was shared to a strip that's already on the board.
    private static func apply(
        _ entry: SharedEntry,
        in folder: URL,
        to strip: TaskItem,
        store: AttachmentStore,
        filed: inout Filed
    ) {
        for address in entry.links where !strip.links.contains(where: { $0.url == address }) {
            strip.links.append(
                TaskLink(url: address, label: EmailLink.isMessage(address) ? entry.title : "")
            )
            strip.actionLog.append(TaskActionLogEntry(text: "Linked an email"))
        }
        for name in entry.fileNames {
            let url = folder.appending(path: name)
            guard let copy = try? store.add(
                contentsOf: url, kind: AttachmentKind.inferred(fromExtension: url.pathExtension)
            ) else {
                filed.failures += 1
                continue
            }
            strip.attachments.append(copy)
        }
        let notes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty, !strip.notes.contains(notes) {
            strip.notes = strip.notes.isEmpty ? notes : strip.notes + "\n\n" + notes
        }
        filed.strips += 1
    }
}

extension StripIndexEntry {
    /// The board as the share sheet needs to see it: what each strip is called, and enough to
    /// find it again. Archived strips are left out — nothing is filed onto them.
    static func board(_ tasks: [TaskItem]) -> [StripIndexEntry] {
        tasks
            .filter { !$0.isArchived && !$0.isTombstoned }
            .map {
                StripIndexEntry(
                    id: $0.id, title: $0.title, tags: $0.tags,
                    isDone: $0.isDone, orderIndex: $0.orderIndex
                )
            }
    }
}
