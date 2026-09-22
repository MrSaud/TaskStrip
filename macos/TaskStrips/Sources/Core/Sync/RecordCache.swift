import CloudKit

/// The last copy of each record this device received from iCloud, kept on disk.
///
/// It's three things at once: the base the field-by-field merge compares against; the record
/// every edit is written onto (so its change tag and any fields from a newer version survive);
/// and the list of what iCloud holds, so an item deleted here is known to need deleting there.
///
/// Lives beside the store it describes, so wiping one wipes the other.
final class RecordCache {
    let directory: URL
    private var memory: [String: CKRecord] = [:]
    private var loaded = false

    init(directory: URL) {
        self.directory = directory
    }

    private func key(_ id: CKRecord.ID) -> String { id.recordName }

    private func file(for name: String) -> URL {
        // Record names can contain "/" (sketch pages); the file name mustn't.
        let safe = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        return directory.appending(path: safe + ".ckrecord")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "ckrecord" {
            guard let data = try? Data(contentsOf: url),
                  let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
            else { continue }
            unarchiver.requiresSecureCoding = true
            if let record = CKRecord(coder: unarchiver) { memory[record.recordID.recordName] = record }
            unarchiver.finishDecoding()
        }
    }

    func record(named name: String) -> CKRecord? {
        loadIfNeeded()
        return memory[name]
    }

    func records(ofType type: String) -> [CKRecord] {
        loadIfNeeded()
        return memory.values.filter { $0.recordType == type }
    }

    var count: Int {
        loadIfNeeded()
        return memory.count
    }

    /// A copy the caller can write on without changing what's cached.
    func workingCopy(named name: String) -> CKRecord? {
        guard let record = record(named: name) else { return nil }
        return record.copy() as? CKRecord
    }

    func store(_ record: CKRecord) {
        loadIfNeeded()
        memory[record.recordID.recordName] = record
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encode(with: archiver)
        archiver.finishEncoding()
        try? archiver.encodedData.write(to: file(for: record.recordID.recordName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(named name: String) {
        loadIfNeeded()
        memory[name] = nil
        try? FileManager.default.removeItem(at: file(for: name))
    }

    func removeAll() {
        memory.removeAll()
        loaded = true
        try? FileManager.default.removeItem(at: directory)
    }
}
