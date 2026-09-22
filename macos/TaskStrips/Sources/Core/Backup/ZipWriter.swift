import Compression
import Foundation

/// Builds the zip a backup is, from the other side of BackupArchive.
///
/// Written by hand for the same reason BackupArchive reads by hand: what matters is that Java's
/// ZipInputStream can read the result, which is a narrower target than "a valid zip". Every entry
/// carries its sizes and CRC in the local header — no data descriptors — because a reader
/// streaming this file forwards should never have to seek back for them.
enum ZipWriter {
    struct Entry {
        var name: String
        var data: Data
        /// Media is nearly always already compressed — jpegs, mp4s, pdfs — so deflating it again
        /// spends time to gain nothing. The manifest is JSON and compresses to a fraction.
        var compress: Bool = true
    }

    static func archive(_ entries: [Entry]) -> Data {
        var body = Data()
        var directory = Data()
        var offset = 0

        for entry in entries {
            let name = Data(entry.name.utf8)
            let stored = entry.compress ? deflate(entry.data) : nil
            let payload = stored ?? entry.data
            let method: UInt16 = stored == nil ? 0 : 8
            let crc = crc32(entry.data)

            var local = Data()
            local.append(uint32: 0x0403_4B50)
            local.append(uint16: 20)              // version needed
            local.append(uint16: 0)               // flags: sizes are in this header, not a descriptor
            local.append(uint16: method)
            local.append(uint16: dosTime)
            local.append(uint16: dosDate)
            local.append(uint32: crc)
            local.append(uint32: UInt32(payload.count))
            local.append(uint32: UInt32(entry.data.count))
            local.append(uint16: UInt16(name.count))
            local.append(uint16: 0)               // extra field length
            local.append(name)
            local.append(payload)

            var central = Data()
            central.append(uint32: 0x0201_4B50)
            central.append(uint16: 20)            // version made by
            central.append(uint16: 20)            // version needed
            central.append(uint16: 0)
            central.append(uint16: method)
            central.append(uint16: dosTime)
            central.append(uint16: dosDate)
            central.append(uint32: crc)
            central.append(uint32: UInt32(payload.count))
            central.append(uint32: UInt32(entry.data.count))
            central.append(uint16: UInt16(name.count))
            central.append(uint16: 0)             // extra
            central.append(uint16: 0)             // comment
            central.append(uint16: 0)             // disk number
            central.append(uint16: 0)             // internal attributes
            central.append(uint32: 0)             // external attributes
            central.append(uint32: UInt32(offset))
            central.append(name)

            body.append(local)
            directory.append(central)
            offset += local.count
        }

        var end = Data()
        end.append(uint32: 0x0605_4B50)
        end.append(uint16: 0)                     // this disk
        end.append(uint16: 0)                     // disk with the directory
        end.append(uint16: UInt16(entries.count))
        end.append(uint16: UInt16(entries.count))
        end.append(uint32: UInt32(directory.count))
        end.append(uint32: UInt32(body.count))
        end.append(uint16: 0)                     // comment length

        return body + directory + end
    }

    /// Raw DEFLATE, the same encoding BackupArchive inflates. Returns nil when the result would
    /// be no smaller — storing it is then both faster and honest about what happened.
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var destination = [UInt8](repeating: 0, count: data.count)
        let written = data.withUnsafeBytes { source -> Int in
            guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(
                &destination, destination.count,
                sourceBase, data.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard written > 0, written < data.count else { return nil }
        return Data(destination.prefix(written))
    }

    /// A fixed timestamp, so exporting the same board twice produces the same bytes. The date a
    /// backup was taken is the file's own modification date; stamping every entry with the
    /// current second only makes two identical backups look different.
    private static let dosTime: UInt16 = 0x9C00
    private static let dosDate: UInt16 = 0x5919

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }
}
