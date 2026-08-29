import XCTest
@testable import TaskStrips

/// Reads Fixtures/android_backup.zip, which is byte-for-byte the shape Java's ZipOutputStream
/// emits from BackupHelper.createBackupZip — deflated, general purpose bit 3 set, manifest first,
/// a media entry behind it. Regenerate it with Fixtures/make_fixture.py.
final class BackupArchiveTests: XCTestCase {
    private func fixtureArchive() throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "android_backup", withExtension: "zip"),
            "android_backup.zip is missing from the test bundle"
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
}
