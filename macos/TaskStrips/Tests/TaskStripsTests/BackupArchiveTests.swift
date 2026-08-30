import XCTest
@testable import TaskStrips

/// Reads Fixtures/android_backup.zip, which is byte-for-byte the shape Java's ZipOutputStream
/// emits from BackupHelper.createBackupZip — deflated, general purpose bit 3 set, manifest first,
/// a media entry behind it. Regenerate it with Fixtures/make_fixture.py.
final class BackupArchiveTests: XCTestCase {
    private func fixtureArchive(_ name: String = "android_backup") throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "zip"),
            "\(name).zip is missing from the test bundle"
        )
        return try Data(contentsOf: url)
    }

    func testReadsManifestFromStreamedDeflateEntry() throws {
        let manifest = try BackupArchive.manifestData(inArchive: fixtureArchive())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: manifest) as? [String: Any])
        XCTAssertEqual(root["version"] as? Int, 1)
        XCTAssertEqual((root["tasks"] as? [Any])?.count, 3)
    }

    /// The manifest's compressed size is 0 in its local header, so the reader has to stop at the
    /// end of the deflate stream on its own rather than swallowing the data descriptor and the
    /// media entry that follow it.
    func testStopsAtEndOfManifestStream() throws {
        let manifest = try BackupArchive.manifestData(inArchive: fixtureArchive())
        let text = String(decoding: manifest, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{"))
        XCTAssertTrue(text.hasSuffix("}"))
        XCTAssertFalse(text.contains("not a real jpeg"))
    }

    func testRejectsFileThatIsNotAZip() {
        let notAZip = Data("plain text, no local file header".utf8)
        XCTAssertThrowsError(try BackupArchive.manifestData(inArchive: notAZip)) { error in
            guard case BackupArchiveError.notABackupArchive = error else {
                return XCTFail("expected .notABackupArchive, got \(error)")
            }
        }
    }

    func testRejectsZipWhoseFirstEntryIsNotTheManifest() throws {
        var archive = try fixtureArchive()
        // Rename the first entry in place — same length, so every following offset still holds.
        let nameStart = archive.startIndex + 30
        archive.replaceSubrange(nameStart..<(nameStart + 11), with: Data("readme.json".utf8))
        XCTAssertThrowsError(try BackupArchive.manifestData(inArchive: archive)) { error in
            guard case BackupArchiveError.manifestNotFirst(let name) = error else {
                return XCTFail("expected .manifestNotFirst, got \(error)")
            }
            XCTAssertEqual(name, "readme.json")
        }
    }

    func testRejectsTruncatedManifestStream() throws {
        let archive = try fixtureArchive()
        let truncated = archive.prefix(60)
        XCTAssertThrowsError(try BackupArchive.manifestData(inArchive: truncated))
    }

    /// Data slices don't start at index 0, and every offset the reader computes is relative to
    /// `startIndex` — a reader that assumed 0 would read garbage from any sliced buffer.
    func testReadsFromASliceWithANonZeroStartIndex() throws {
        var padded = Data([0xAA])
        padded.append(try fixtureArchive())
        let slice = padded.dropFirst()
        XCTAssertNotEqual(slice.startIndex, 0)

        let manifest = try BackupArchive.manifestData(inArchive: slice)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: manifest) as? [String: Any])
        XCTAssertEqual((root["tasks"] as? [Any])?.count, 3)
    }

    // MARK: - Every entry, not just the manifest

    func testListsEveryEntryInOrder() throws {
        let entries = try BackupArchive.entries(inArchive: fixtureArchive())
        XCTAssertEqual(
            entries.map(\.name),
            [
                "backup.json",
                "media/images/passport.jpg",
                "media/images/form.jpg",
                // Belongs to no strip and is named by nothing in the manifest — see
                // SketchPassThroughTests for why a backup carries it anyway.
                "media/sketches/note_1787000000000/page1.png",
            ]
        )
        XCTAssertTrue(entries.allSatisfy { $0.uncompressedSize > 0 })
        XCTAssertTrue(entries.allSatisfy { !$0.isDirectory })
    }

    func testReadsAMediaEntryByName() throws {
        let archive = try fixtureArchive()
        let entries = try BackupArchive.entries(inArchive: archive)
        let passport = try XCTUnwrap(entries.first { $0.name == "media/images/passport.jpg" })

        let bytes = try BackupArchive.data(for: passport, inArchive: archive)
        XCTAssertEqual(bytes.count, passport.uncompressedSize)
        XCTAssertEqual(Array(bytes.prefix(4)), [0xFF, 0xD8, 0xFF, 0xE0])
    }

    /// The same manifest reached the long way round, which has to agree with the fast path.
    func testTheManifestReadsTheSameThroughTheCentralDirectory() throws {
        let archive = try fixtureArchive()
        let entries = try BackupArchive.entries(inArchive: archive)
        let manifest = try XCTUnwrap(entries.first { $0.name == "backup.json" })

        XCTAssertEqual(
            try BackupArchive.data(for: manifest, inArchive: archive),
            try BackupArchive.manifestData(inArchive: archive)
        )
    }

    // MARK: - zip64
    //
    // A backup with videos in it can pass the 4 GB that plain zip offsets hold, so the sizes and
    // offsets move into zip64 extra fields behind sentinels. The fixture describes the same bytes
    // that way without being four gigabytes.

    func testReadsAZip64Archive() throws {
        let archive = try fixtureArchive("android_backup_zip64")
        let entries = try BackupArchive.entries(inArchive: archive)

        XCTAssertEqual(
            entries.map(\.name),
            [
                "backup.json",
                "media/images/passport.jpg",
                "media/images/form.jpg",
                // Belongs to no strip and is named by nothing in the manifest — see
                // SketchPassThroughTests for why a backup carries it anyway.
                "media/sketches/note_1787000000000/page1.png",
            ]
        )
        let passport = try XCTUnwrap(entries.first { $0.name == "media/images/passport.jpg" })
        XCTAssertEqual(
            try BackupArchive.data(for: passport, inArchive: archive),
            try BackupArchive.data(
                for: try XCTUnwrap(
                    try BackupArchive.entries(inArchive: try fixtureArchive())
                        .first { $0.name == "media/images/passport.jpg" }
                ),
                inArchive: try fixtureArchive()
            ),
            "zip64 and plain descriptions of the same file must yield the same bytes"
        )
    }

    func testTheManifestFastPathStillWorksOnAZip64Archive() throws {
        let manifest = try BackupArchive.manifestData(inArchive: fixtureArchive("android_backup_zip64"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: manifest) as? [String: Any])
        XCTAssertEqual((root["tasks"] as? [Any])?.count, 3)
    }

    // MARK: - Refusals

    func testEntriesRejectsSomethingWithNoEndRecord() {
        XCTAssertThrowsError(
            try BackupArchive.entries(inArchive: Data(repeating: 0x41, count: 512))
        )
    }

    func testEntriesReadsFromASliceWithANonZeroStartIndex() throws {
        var padded = Data([0xAA, 0xBB])
        padded.append(try fixtureArchive())
        let slice = padded.dropFirst(2)

        XCTAssertEqual(try BackupArchive.entries(inArchive: slice).map(\.name).first, "backup.json")
    }
}
