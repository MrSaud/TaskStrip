import Compression
import Foundation

enum BackupArchiveError: LocalizedError {
    case notABackupArchive
    case manifestNotFirst(String)
    case unsupportedCompression(Int)
    case truncated
    case corruptManifest

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
