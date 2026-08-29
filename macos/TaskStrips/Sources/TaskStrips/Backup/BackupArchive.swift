import Compression
import Foundation

enum BackupArchiveError: LocalizedError {
    case notABackupArchive
    case manifestNotFirst(String)
    case unsupportedCompression(Int)
    case truncated
    case corruptManifest
    case noCentralDirectory
    case corruptCentralDirectory

    var errorDescription: String? {
        switch self {
        case .notABackupArchive:
            return "That file isn't a TaskStrip backup — it doesn't start with a zip header."
        case .manifestNotFirst(let name):
            return """
                This backup's first entry is \"\(name)\", not backup.json, so it wasn't written by \
                the Android app's Backup screen. Unzip it and pick the backup.json inside instead.
                """
        case .unsupportedCompression(let method):
            return "This backup stores backup.json with zip compression method \(method), which isn't supported."
        case .truncated:
            return "This backup file is truncated — backup.json ends mid-stream."
        case .corruptManifest:
            return "This backup's backup.json couldn't be decompressed."
        case .noCentralDirectory:
            return "This backup's index is missing — the file looks truncated or isn't a zip."
        case .corruptCentralDirectory:
            return "This backup's index couldn't be read."
        }
    }
}

/// Reads the `backup.json` manifest out of an Android TaskStrip backup zip.
///
/// This deliberately does *not* implement a general zip reader. `BackupHelper.createBackupZip`
/// (app/src/main/java/com/saud/taskstrip/backup/BackupHelper.kt) always writes the manifest as the
/// **first** entry, before any `media/` payload, so the manifest's local file header sits at
/// offset 0 and its data follows immediately — no central directory walk, and no zip64 handling,
/// which matters because a media-heavy backup can run past the 4 GB that plain zip offsets hold.
///
/// Java's `ZipOutputStream` deflates entries with the streaming bit (general purpose bit 3) set,
/// which leaves the compressed size as 0 in the local header and puts the real sizes in a trailing
/// data descriptor. That's fine here: a raw DEFLATE stream is self-terminating, so the decoder
/// reports END exactly at the manifest's last byte and everything after it — descriptor, media
/// entries, central directory — is simply never read.
enum BackupArchive {
    static let manifestEntryName = "backup.json"
    /// Everything else in a backup lives behind this, at the path it had under filesDir.
    static let mediaPrefix = "media/"

    /// Accepts either a backup `.zip` or a `backup.json` extracted from one by hand.
    static func manifestData(at url: URL) throws -> Data {
        if url.pathExtension.lowercased() == "json" {
            return try Data(contentsOf: url)
        }
        // Memory-mapped: a backup with videos in it can be gigabytes, and only the first entry
        // is ever touched.
        let archive = try Data(contentsOf: url, options: .mappedIfSafe)
        return try manifestData(inArchive: archive)
    }

    static func manifestData(inArchive archive: Data) throws -> Data {
        let localHeaderSignature = 0x0403_4b50
        guard archive.count >= 30, readUInt32(archive, 0) == localHeaderSignature else {
            throw BackupArchiveError.notABackupArchive
        }
        let flags = readUInt16(archive, 6)
        let method = readUInt16(archive, 8)
        let storedSize = readUInt32(archive, 18)
        let nameLength = readUInt16(archive, 26)
        let extraLength = readUInt16(archive, 28)
        let nameStart = 30
        let dataStart = nameStart + nameLength + extraLength
        guard archive.count >= dataStart else { throw BackupArchiveError.truncated }

        let nameBytes = archive[(archive.startIndex + nameStart)..<(archive.startIndex + nameStart + nameLength)]
        let name = String(decoding: nameBytes, as: UTF8.self)
        guard name == manifestEntryName else { throw BackupArchiveError.manifestNotFirst(name) }

        let payload = archive[(archive.startIndex + dataStart)...]
        switch method {
        case 0:
            // Stored. A zip writer may not use the streaming bit with method 0 precisely because
            // the size would then be unrecoverable, so the local header's size is authoritative.
            guard flags & 0x8 == 0 else { throw BackupArchiveError.truncated }
            guard payload.count >= storedSize else { throw BackupArchiveError.truncated }
            return payload.prefix(storedSize)
        case 8:
            return try inflate(payload)
        default:
            throw BackupArchiveError.unsupportedCompression(method)
        }
    }

    /// Raw DEFLATE (RFC 1951) — which is what a zip entry holds, and what Apple's
    /// `COMPRESSION_ZLIB` decodes, header-free.
    static func inflate(_ input: Data) throws -> Data {
        guard !input.isEmpty else { throw BackupArchiveError.truncated }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(&stream.pointee, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            == COMPRESSION_STATUS_OK
        else { throw BackupArchiveError.corruptManifest }
        defer { compression_stream_destroy(&stream.pointee) }

        let bufferSize = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        var output = Data()
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw BackupArchiveError.truncated
            }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = raw.count

            var status = COMPRESSION_STATUS_OK
            repeat {
                stream.pointee.dst_ptr = destination
                stream.pointee.dst_size = bufferSize
                status = compression_stream_process(&stream.pointee, 0)
                guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END else {
                    throw BackupArchiveError.corruptManifest
                }
                let produced = bufferSize - stream.pointee.dst_size
                output.append(destination, count: produced)
                // The decoder asks for more input by returning OK without consuming or producing
                // anything. There is no more input, so the deflate stream ended early.
                if status == COMPRESSION_STATUS_OK, produced == 0, stream.pointee.src_size == 0 {
                    throw BackupArchiveError.truncated
                }
            } while status == COMPRESSION_STATUS_OK
        }
        return output
    }

    // MARK: - Reading every entry

    /// One file in the archive, as the central directory describes it.
    struct Entry {
        let name: String
        let method: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int

        var isDirectory: Bool { name.hasSuffix("/") }
    }

    /// Walks the central directory.
    ///
    /// The manifest fast path above can skip all of this because it only ever wants the first
    /// entry. Reaching the media behind it can't: the entries are written with sizes unknown
    /// (general purpose bit 3), so there's no way to step from one local header to the next
    /// without the central directory's authoritative sizes. Which also means zip64 has to be
    /// handled for real — a backup with videos in it can pass the 4 GB that plain zip offsets
    /// hold, and that's exactly the backup someone will try to import.
    static func entries(inArchive archive: Data) throws -> [Entry] {
        let (entryCount, directoryOffset) = try locateCentralDirectory(archive)

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)
        var offset = directoryOffset

        for _ in 0..<entryCount {
            guard offset + 46 <= archive.count, readUInt32(archive, offset) == 0x0201_4b50 else {
                throw BackupArchiveError.corruptCentralDirectory
            }
            let method = readUInt16(archive, offset + 10)
            var compressedSize = readUInt32(archive, offset + 20)
            var uncompressedSize = readUInt32(archive, offset + 24)
            let nameLength = readUInt16(archive, offset + 28)
            let extraLength = readUInt16(archive, offset + 30)
            let commentLength = readUInt16(archive, offset + 32)
            var localHeaderOffset = readUInt32(archive, offset + 42)

            let nameStart = offset + 46
            guard nameStart + nameLength + extraLength + commentLength <= archive.count else {
                throw BackupArchiveError.corruptCentralDirectory
            }
            let name = String(
                decoding: archive[(archive.startIndex + nameStart)..<(archive.startIndex + nameStart + nameLength)],
                as: UTF8.self
            )

            // 0xFFFFFFFF is zip64's "look in the extra field for the real number". The zip64
            // extra carries only the fields that overflowed, in this order.
            let sentinel = 0xFFFF_FFFF
            if compressedSize == sentinel || uncompressedSize == sentinel || localHeaderOffset == sentinel {
                var cursor = nameStart + nameLength
                let extraEnd = cursor + extraLength
                var found = false
                while cursor + 4 <= extraEnd {
                    let headerID = readUInt16(archive, cursor)
                    let size = readUInt16(archive, cursor + 2)
                    guard cursor + 4 + size <= extraEnd else { break }
                    if headerID == 0x0001 {
                        var field = cursor + 4
                        if uncompressedSize == sentinel, field + 8 <= extraEnd {
                            uncompressedSize = readUInt64(archive, field); field += 8
                        }
                        if compressedSize == sentinel, field + 8 <= extraEnd {
                            compressedSize = readUInt64(archive, field); field += 8
                        }
                        if localHeaderOffset == sentinel, field + 8 <= extraEnd {
                            localHeaderOffset = readUInt64(archive, field); field += 8
                        }
                        found = true
                        break
                    }
                    cursor += 4 + size
                }
                guard found else { throw BackupArchiveError.corruptCentralDirectory }
            }

            entries.append(Entry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// The bytes of one entry, decompressed.
    static func data(for entry: Entry, inArchive archive: Data) throws -> Data {
        let offset = entry.localHeaderOffset
        guard offset + 30 <= archive.count, readUInt32(archive, offset) == 0x0403_4b50 else {
            throw BackupArchiveError.corruptCentralDirectory
        }
        // The local header's name and extra lengths are read here rather than reused from the
        // central directory: the two are allowed to differ, and the extra field routinely does.
        let nameLength = readUInt16(archive, offset + 26)
        let extraLength = readUInt16(archive, offset + 28)
        let dataStart = offset + 30 + nameLength + extraLength
        guard dataStart + entry.compressedSize <= archive.count else {
            throw BackupArchiveError.truncated
        }

        let payload = archive[(archive.startIndex + dataStart)...].prefix(entry.compressedSize)
        switch entry.method {
        case 0:
            return payload.prefix(entry.uncompressedSize)
        case 8:
            return try inflate(payload)
        default:
            throw BackupArchiveError.unsupportedCompression(entry.method)
        }
    }

    /// Returns (entry count, offset of the first central directory header).
    private static func locateCentralDirectory(_ archive: Data) throws -> (Int, Int) {
        let endSignature = 0x0605_4b50
        // The end record is last, but a trailing comment can push it up to 64 KB back.
        let searchLimit = min(archive.count, 22 + 65_535)
        var end = -1
        var candidate = archive.count - 22
        while candidate >= 0, archive.count - candidate <= searchLimit {
            if readUInt32(archive, candidate) == endSignature {
                end = candidate
                break
            }
            candidate -= 1
        }
        guard end >= 0 else { throw BackupArchiveError.noCentralDirectory }

        var entryCount = readUInt16(archive, end + 10)
        var directoryOffset = readUInt32(archive, end + 16)

        // Either sentinel means the real values live in the zip64 end record, which a locator
        // sitting just before the end record points at.
        if entryCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF {
            let locator = end - 20
            guard locator >= 0, readUInt32(archive, locator) == 0x0706_4b50 else {
                throw BackupArchiveError.corruptCentralDirectory
            }
            let zip64End = readUInt64(archive, locator + 8)
            guard zip64End >= 0, zip64End + 56 <= archive.count,
                  readUInt32(archive, zip64End) == 0x0606_4b50
            else { throw BackupArchiveError.corruptCentralDirectory }
            entryCount = readUInt64(archive, zip64End + 32)
            directoryOffset = readUInt64(archive, zip64End + 48)
        }

        guard directoryOffset >= 0, directoryOffset <= archive.count, entryCount >= 0 else {
            throw BackupArchiveError.corruptCentralDirectory
        }
        return (entryCount, directoryOffset)
    }

    private static func readUInt64(_ data: Data, _ offset: Int) -> Int {
        var value = 0
        for byte in 0..<8 {
            value |= Int(data[data.startIndex + offset + byte]) << (8 * byte)
        }
        return value
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> Int {
        let index = data.startIndex + offset
        return Int(data[index]) | Int(data[index + 1]) << 8
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> Int {
        let index = data.startIndex + offset
        return Int(data[index]) | Int(data[index + 1]) << 8 | Int(data[index + 2]) << 16
            | Int(data[index + 3]) << 24
    }
}
