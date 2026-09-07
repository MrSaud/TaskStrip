import XCTest
@testable import TaskStrips

/// The requests this transport actually sends, and the choices it makes before sending them.
///
/// The network is faked, so what these pin down is the shape of the conversation — the URLs, and
/// which round trips are skipped — rather than whether Drive replies. Only running it against a
/// real account proves that.
final class DriveBoardTransportTests: XCTestCase {

    /// Replies in order, and remembers what it was asked.
    private final class FakeDrive: DriveTransport {
        var replies: [Data]
        private(set) var requests: [URLRequest] = []

        init(replies: [Data]) { self.replies = replies }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            let body = replies.isEmpty ? Data("{}".utf8) : replies.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (body, response)
        }
    }

    private let folderReply = Data(#"{"files":[{"id":"folder1","name":"TaskStripBackups"}]}"#.utf8)

    private func transport(_ replies: [Data]) -> (DriveBoardTransport, FakeDrive) {
        let fake = FakeDrive(replies: replies)
        return (DriveBoardTransport(client: DriveClient(transport: fake, accessToken: "at")), fake)
    }

    func testAMissingDocumentReadsAsNothingRatherThanFailing() async throws {
        let (subject, _) = transport([folderReply, Data(#"{"files":[]}"#.utf8)])

        let loaded = try await subject.loadDocument()

        XCTAssertNil(loaded)
    }

    func testTheDocumentIsLookedUpByNameInTheSharedFolder() async throws {
        let (subject, fake) = transport([folderReply, Data(#"{"files":[]}"#.utf8)])

        _ = try await subject.loadDocument()

        let query = (fake.requests.last?.url?.absoluteString ?? "").removingPercentEncoding ?? ""
        XCTAssertTrue(query.contains("name='\(SyncBoardDocument.fileName)'"), query)
        // And scoped to the shared folder rather than the whole Drive.
        XCTAssertTrue(query.contains("'folder1' in parents"), query)
    }

    /// Only files carrying the store's own prefix are its own. The backups and the documents share
    /// this folder, and mistaking one for a file would try to download a zip as an attachment.
    func testOnlyPrefixedNamesAreCountedAsFiles() async throws {
        let listing = Data(#"""
        {"files":[
          {"id":"1","name":"file-aaa"},
          {"id":"2","name":"sync_board.json"},
          {"id":"3","name":"TaskStrips-20260830.zip"},
          {"id":"4","name":"file-bbb"}
        ]}
        """#.utf8)
        let (subject, _) = transport([folderReply, listing])

        let hashes = try await subject.remoteHashes()

        XCTAssertEqual(hashes, ["aaa", "bbb"])
    }

    /// A file already in the folder holds exactly these bytes, because the name is the hash of
    /// them. Uploading again would spend the bandwidth to change nothing and leave two Drive files
    /// with one name.
    func testAFileAlreadyThereIsNotUploadedAgain() async throws {
        let listing = Data(#"{"files":[{"id":"1","name":"file-aaa"}]}"#.utf8)
        let (subject, fake) = transport([folderReply, listing])
        _ = try await subject.remoteHashes()
        let before = fake.requests.count

        try await subject.upload(hash: "aaa", data: Data("anything".utf8))

        XCTAssertEqual(fake.requests.count, before)
    }

    func testAFileNotThereIsUploaded() async throws {
        let listing = Data(#"{"files":[]}"#.utf8)
        let (subject, fake) = transport([folderReply, listing, Data(#"{"id":"new1"}"#.utf8)])
        _ = try await subject.remoteHashes()
        let before = fake.requests.count

        try await subject.upload(hash: "aaa", data: Data("a photo".utf8))

        XCTAssertEqual(fake.requests.count, before + 1)
        XCTAssertEqual(fake.requests.last?.httpMethod, "POST")
    }

    /// Two devices can sweep the same orphan; the second arriving to find it gone is the system
    /// working, not failing.
    func testDeletingAFileTheFolderHasntGotSendsNothing() async throws {
        let (subject, fake) = transport([folderReply, Data(#"{"files":[]}"#.utf8)])
        _ = try await subject.remoteHashes()
        let before = fake.requests.count

        try await subject.deleteFile(hash: "neverexisted")

        XCTAssertEqual(fake.requests.count, before)
    }

    func testDeletingAKnownFileAsksDriveToRemoveIt() async throws {
        let listing = Data(#"{"files":[{"id":"file1","name":"file-aaa"}]}"#.utf8)
        let (subject, fake) = transport([folderReply, listing, Data("{}".utf8)])
        _ = try await subject.remoteHashes()

        try await subject.deleteFile(hash: "aaa")

        XCTAssertEqual(fake.requests.last?.httpMethod, "DELETE")
        XCTAssertTrue(fake.requests.last?.url?.absoluteString.contains("file1") == true)
    }
}
