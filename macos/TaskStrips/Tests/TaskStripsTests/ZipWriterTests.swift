import Security
import XCTest
@testable import TaskStrips

/// The zip has to be readable by a stream reader that never seeks — Java's ZipInputStream — so
/// what's checked here is the framing, not just that the bytes come back.
final class ZipWriterTests: XCTestCase {
    /// The standard check value for CRC-32: the digits "123456789" hash to 0xCBF43926. Getting
    /// this wrong produces an archive every unzipper rejects as corrupt.
    func testCRC32MatchesTheStandardCheckValue() {
        XCTAssertEqual(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(ZipWriter.crc32(Data()), 0)
    }

    func testAWrittenArchiveReadsBackThroughTheSameReaderAsThePhones() throws {
        let archive = ZipWriter.archive([
            ZipWriter.Entry(name: "backup.json", data: Data(#"{"tasks":[]}"#.utf8)),
            ZipWriter.Entry(name: "media/images/a.jpg", data: Data(repeating: 0xAB, count: 4096), compress: false),
        ])

        let entries = try BackupArchive.entries(inArchive: archive)
        XCTAssertEqual(entries.map(\.name), ["backup.json", "media/images/a.jpg"])
        XCTAssertEqual(
            try BackupArchive.manifestData(inArchive: archive),
            Data(#"{"tasks":[]}"#.utf8)
        )

        let media = try XCTUnwrap(entries.last)
        XCTAssertEqual(try BackupArchive.data(for: media, inArchive: archive), Data(repeating: 0xAB, count: 4096))
    }

    /// Sizes in the local header rather than a trailing data descriptor: a reader going forwards
    /// through the file should never need to come back for them.
    func testTheLocalHeaderCarriesTheSizesRatherThanADescriptor() throws {
        let archive = ZipWriter.archive([ZipWriter.Entry(name: "a.txt", data: Data("hello".utf8))])

        let flags = archive.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 6, as: UInt16.self) }
        XCTAssertEqual(flags & 0x8, 0, "bit 3 would move the sizes into a data descriptor")

        let uncompressed = archive.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 22, as: UInt32.self) }
        XCTAssertEqual(uncompressed, 5)
    }

    func testCompressibleDataIsDeflatedAndComesBackIntact() throws {
        let repetitive = Data(String(repeating: "the same line over and over\n", count: 200).utf8)
        let archive = ZipWriter.archive([ZipWriter.Entry(name: "notes.txt", data: repetitive)])

        let entry = try XCTUnwrap(try BackupArchive.entries(inArchive: archive).first)
        XCTAssertEqual(entry.method, 8, "this should have been worth deflating")
        XCTAssertLessThan(entry.compressedSize, repetitive.count)
        XCTAssertEqual(try BackupArchive.data(for: entry, inArchive: archive), repetitive)
    }

    /// Already-compressed bytes don't deflate, and storing them beats growing them.
    func testIncompressibleDataIsStoredRatherThanGrown() throws {
        var random = Data(count: 2048)
        random.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 2048, $0.baseAddress!) }

        let archive = ZipWriter.archive([ZipWriter.Entry(name: "photo.jpg", data: random)])
        let entry = try XCTUnwrap(try BackupArchive.entries(inArchive: archive).first)

        XCTAssertEqual(entry.method, 0)
        XCTAssertEqual(try BackupArchive.data(for: entry, inArchive: archive), random)
    }

    func testAnEmptyArchiveIsStillAValidOne() throws {
        let archive = ZipWriter.archive([])
        XCTAssertTrue(try BackupArchive.entries(inArchive: archive).isEmpty)
    }
}
