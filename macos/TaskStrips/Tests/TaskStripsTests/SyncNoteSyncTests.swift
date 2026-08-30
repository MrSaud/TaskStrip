import XCTest
@testable import TaskStrips

/// One round trip against canned Drive replies: what gets sent, and when nothing should be.
private struct StubTransport: DriveTransport {
    var responses: [(status: Int, body: Data)]
    final class Log: @unchecked Sendable {
        var requests: [URLRequest] = []
    }
    var log = Log()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.requests.append(request)
        let index = min(log.requests.count - 1, responses.count - 1)
        let response = responses[index]
        let http = HTTPURLResponse(
            url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: nil
        )!
        return (response.body, http)
    }
}

final class SyncNoteSyncTests: XCTestCase {

    private func record(_ id: String, _ text: String, at seconds: TimeInterval) -> SyncNoteRecord {
        SyncNoteRecord(
            id: id, title: "", text: text,
            updatedAt: Date(timeIntervalSince1970: seconds), isDeleted: false
        )
    }

    private let folderReply = Data(#"{"files":[{"id":"folder1","name":"TaskStripBackups"}]}"#.utf8)
    private let noFile = Data(#"{"files":[]}"#.utf8)
    private func existingFile(_ id: String) -> Data {
        Data(#"{"files":[{"id":"\#(id)","name":"sync_notes.json"}]}"#.utf8)
    }

    func testTheFileIsLookedUpByNameInsideTheSharedFolder() throws {
        let url = try XCTUnwrap(
            DriveClient.fileLookupRequest(accessToken: "at", folderID: "f1", name: "sync_notes.json").url
        )
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "q" }?.value)

        XCTAssertTrue(query.contains("name='sync_notes.json'"), query)
        XCTAssertTrue(query.contains("'f1' in parents"), query)
        XCTAssertTrue(query.contains("trashed=false"), query)
    }

    /// Keeping the file's id matters: a delete-and-recreate from two devices at once would leave
    /// two sync documents and no way to say which is the real one.
    func testReplacingKeepsTheFileAndSendsJSON() throws {
        let request = DriveClient.updateRequest(
            accessToken: "at", fileID: "doc1", contents: Data("{}".utf8), mimeType: "application/json"
        )

        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(try XCTUnwrap(request.url?.absoluteString).contains("/files/doc1"))
        XCTAssertTrue(try XCTUnwrap(request.url?.absoluteString).contains("uploadType=media"))
    }

    func testTheFirstSyncCreatesTheDocument() async throws {
        let transport = StubTransport(responses: [
            (200, folderReply),
            (200, noFile),
            (200, Data(#"{"id":"new"}"#.utf8)),
        ])
        let sync = SyncNoteSync(client: DriveClient(transport: transport, accessToken: "at"))

        let outcome = try await sync.run(local: [record("a", "hello", at: 10)])

        XCTAssertTrue(outcome.pushed)
        XCTAssertFalse(outcome.pulled)
        XCTAssertEqual(outcome.merged.map(\.text), ["hello"])
        // Created, not patched: there was nothing there to patch.
        XCTAssertEqual(transport.log.requests.last?.httpMethod, "POST")
    }

    func testAnExistingDocumentIsMergedAndPatchedBack() async throws {
        let remote = try SyncNoteDocument.data(for: [record("b", "from the phone", at: 20)])
        let transport = StubTransport(responses: [
            (200, folderReply),
            (200, existingFile("doc1")),
            (200, remote),
            (200, Data(#"{"id":"doc1"}"#.utf8)),
        ])
        let sync = SyncNoteSync(client: DriveClient(transport: transport, accessToken: "at"))

        let outcome = try await sync.run(local: [record("a", "from the Mac", at: 10)])

        XCTAssertTrue(outcome.pushed, "the phone hasn't seen the Mac's note")
        XCTAssertTrue(outcome.pulled, "the Mac hasn't seen the phone's")
        XCTAssertEqual(Set(outcome.merged.map(\.text)), ["from the Mac", "from the phone"])
        XCTAssertEqual(transport.log.requests.last?.httpMethod, "PATCH")
    }

    /// A sync that changed nothing must not rewrite the file. Otherwise every open of the page
    /// writes to Drive and two devices take turns doing it forever.
    func testNothingIsWrittenWhenBothSidesAlreadyAgree() async throws {
        let shared = [record("a", "same", at: 10)]
        let transport = StubTransport(responses: [
            (200, folderReply),
            (200, existingFile("doc1")),
            (200, try SyncNoteDocument.data(for: shared)),
        ])
        let sync = SyncNoteSync(client: DriveClient(transport: transport, accessToken: "at"))

        let outcome = try await sync.run(local: shared)

        XCTAssertFalse(outcome.pushed)
        XCTAssertFalse(outcome.pulled)
        XCTAssertEqual(outcome.summary, "Already up to date.")
        // Folder, lookup, download — and no fourth request.
        XCTAssertEqual(transport.log.requests.count, 3)
    }

    /// Pulling without pushing: the phone knows everything this Mac does, plus more.
    func testTakingChangesWithoutSendingAny() async throws {
        let mine = record("a", "same", at: 10)
        let theirs = record("b", "newer", at: 20)
        let transport = StubTransport(responses: [
            (200, folderReply),
            (200, existingFile("doc1")),
            (200, try SyncNoteDocument.data(for: [mine, theirs])),
        ])
        let sync = SyncNoteSync(client: DriveClient(transport: transport, accessToken: "at"))

        let outcome = try await sync.run(local: [mine])

        XCTAssertFalse(outcome.pushed)
        XCTAssertTrue(outcome.pulled)
        XCTAssertEqual(outcome.summary, "Took changes from the other device.")
        XCTAssertEqual(transport.log.requests.count, 3)
    }

    /// Running it twice with nothing happening in between has to be a no-op the second time, or
    /// the two devices would push to each other forever.
    func testASecondSyncWithNothingNewWritesNothing() async throws {
        let shared = [record("a", "settled", at: 10)]
        let document = try SyncNoteDocument.data(for: shared)
        // Two full rounds of replies: the stub repeats its last answer once it runs out, and a
        // sync document handed back as a folder lookup would fail for the wrong reason.
        let transport = StubTransport(responses: [
            (200, folderReply),
            (200, existingFile("doc1")),
            (200, document),
            (200, folderReply),
            (200, existingFile("doc1")),
            (200, document),
        ])
        let sync = SyncNoteSync(client: DriveClient(transport: transport, accessToken: "at"))

        let first = try await sync.run(local: shared)
        let second = try await sync.run(local: first.merged)

        XCTAssertFalse(second.pushed)
        XCTAssertFalse(second.pulled)
    }
}
