import XCTest
@testable import TaskStrips

/// Drive's API is reached through a transport this can stand in for, so the request-building and
/// reply-parsing — nearly all of the client — is checked without a network.
private struct StubTransport: DriveTransport {
    var responses: [(status: Int, body: Data)]
    /// Every request that went out, in order, so a test can assert on what was actually sent.
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

final class DriveClientTests: XCTestCase {
    private let token = "at"

    // MARK: - Requests

    func testEveryRequestCarriesTheBearerToken() {
        let requests = [
            DriveClient.folderLookupRequest(accessToken: token),
            DriveClient.createFolderRequest(accessToken: token),
            DriveClient.listRequest(accessToken: token, folderID: "f1"),
            DriveClient.downloadRequest(accessToken: token, fileID: "x1"),
        ]
        for request in requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer at")
        }
    }

    /// The same folder the phone uses — a different name would leave two folders and two halves
    /// of a backup history.
    func testTheFolderLookupAsksForTaskStripBackups() throws {
        let url = try XCTUnwrap(DriveClient.folderLookupRequest(accessToken: token).url)
        let query = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value
        )
        XCTAssertTrue(query.contains("name='TaskStripBackups'"))
        XCTAssertTrue(query.contains("mimeType='application/vnd.google-apps.folder'"))
        XCTAssertTrue(query.contains("trashed=false"))
    }

    func testTheListingAsksForTheFolderAndNewestFirst() throws {
        let url = try XCTUnwrap(DriveClient.listRequest(accessToken: token, folderID: "f1").url)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["q"], "'f1' in parents and trashed=false")
        XCTAssertEqual(values["orderBy"], "createdTime desc")
        XCTAssertTrue(try XCTUnwrap(values["fields"]).contains("createdTime"))
    }

    func testTheDownloadAsksForTheBytesRatherThanTheMetadata() throws {
        let url = try XCTUnwrap(DriveClient.downloadRequest(accessToken: token, fileID: "x1").url)
        XCTAssertTrue(url.absoluteString.hasSuffix("/files/x1?alt=media"))
    }

    func testTheUploadIsMultipartWithTheMetadataFirst() throws {
        let request = DriveClient.uploadRequest(
            accessToken: token,
            folderID: "f1",
            fileName: "taskstrip_backup_20260830-0530.zip",
            archive: Data("PK zip bytes".utf8),
            boundary: "BOUNDARY"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/related; boundary=BOUNDARY")
        XCTAssertTrue(try XCTUnwrap(request.url).absoluteString.contains("uploadType=multipart"))

        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("--BOUNDARY"))
        XCTAssertTrue(body.contains("\"name\":\"taskstrip_backup_20260830-0530.zip\""))
        // The parent is what puts it in the folder rather than loose in My Drive.
        XCTAssertTrue(body.contains("\"parents\":[\"f1\"]"))
        XCTAssertTrue(body.contains("PK zip bytes"))
        XCTAssertTrue(body.hasSuffix("--BOUNDARY--\r\n"))
    }

    // MARK: - Replies

    func testTheFolderIDIsReadFromEitherShapeOfReply() {
        XCTAssertEqual(
            DriveClient.folderID(from: Data(#"{"files":[{"id":"f1","name":"TaskStripBackups"}]}"#.utf8)),
            "f1"
        )
        // The create call answers with the object itself, not a list.
        XCTAssertEqual(DriveClient.folderID(from: Data(#"{"id":"f2"}"#.utf8)), "f2")
        XCTAssertNil(DriveClient.folderID(from: Data(#"{"files":[]}"#.utf8)))
    }

    /// Drive sends sizes as strings and times as RFC 3339, with or without fractional seconds.
    func testBackupsAreReadWithTheirTimesAndSizes() throws {
        let data = Data("""
        {"files":[
          {"id":"a","name":"taskstrip_backup_20260830-0530.zip","createdTime":"2026-08-30T05:30:00.000Z","size":"2048"},
          {"id":"b","name":"older.zip","createdTime":"2026-08-29T05:30:00Z"}
        ]}
        """.utf8)
        let backups = DriveClient.backups(from: data)

        XCTAssertEqual(backups.map(\.id), ["a", "b"])
        XCTAssertEqual(backups.first?.sizeBytes, 2048)
        XCTAssertFalse(try XCTUnwrap(backups.first).readableSize.isEmpty)
        XCTAssertNotNil(backups.first?.createdAt)
        // No fractional seconds, and no size at all — neither is allowed to lose the row.
        XCTAssertNotNil(backups.last?.createdAt)
        XCTAssertNil(backups.last?.sizeBytes)
        XCTAssertEqual(backups.last?.readableSize, "")
    }

    func testAFileWithNoIDIsSkippedRatherThanCrashing() {
        let data = Data(#"{"files":[{"name":"nameless.zip"},{"id":"a","name":"fine.zip"}]}"#.utf8)
        XCTAssertEqual(DriveClient.backups(from: data).map(\.name), ["fine.zip"])
    }

    func testNonsenseGivesAnEmptyListRatherThanThrowing() {
        XCTAssertTrue(DriveClient.backups(from: Data("not json".utf8)).isEmpty)
        XCTAssertTrue(DriveClient.backups(from: Data()).isEmpty)
    }

    /// The status alone rarely says which of several things went wrong; Drive puts that in
    /// error.message.
    func testDrivesOwnErrorMessageIsPulledOut() {
        let data = Data(#"{"error":{"code":403,"message":"Insufficient permission"}}"#.utf8)
        XCTAssertEqual(DriveClient.errorMessage(from: data), "Insufficient permission")
        XCTAssertEqual(DriveClient.errorMessage(from: Data("not json".utf8)), "")
    }

    // MARK: - Calls

    func testEnsureFolderUsesTheOneThatIsAlreadyThere() async throws {
        let transport = StubTransport(responses: [(200, Data(#"{"files":[{"id":"f1"}]}"#.utf8))])
        let client = DriveClient(transport: transport, accessToken: token)

        let id = try await client.ensureBackupFolder()
        XCTAssertEqual(id, "f1")
        XCTAssertEqual(transport.log.requests.count, 1, "it shouldn't create a second folder")
    }

    func testEnsureFolderMakesOneWhenThereIsNone() async throws {
        let transport = StubTransport(responses: [
            (200, Data(#"{"files":[]}"#.utf8)),
            (200, Data(#"{"id":"new"}"#.utf8)),
        ])
        let client = DriveClient(transport: transport, accessToken: token)

        XCTAssertEqual(try await client.ensureBackupFolder(), "new")
        XCTAssertEqual(transport.log.requests.count, 2)
        XCTAssertEqual(transport.log.requests.last?.httpMethod, "POST")
    }

    func testAFailedCallCarriesDrivesExplanation() async {
        let transport = StubTransport(responses: [
            (403, Data(#"{"error":{"message":"Insufficient permission"}}"#.utf8)),
        ])
        let client = DriveClient(transport: transport, accessToken: token)

        do {
            _ = try await client.ensureBackupFolder()
            XCTFail("a 403 should not read as success")
        } catch let error as DriveError {
            XCTAssertEqual(error, .http(403, "Insufficient permission"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDownloadingHandsBackTheBytesUntouched() async throws {
        let archive = Data("PK\u{03}\u{04} pretend zip".utf8)
        let transport = StubTransport(responses: [(200, archive)])
        let client = DriveClient(transport: transport, accessToken: token)

        let data = try await client.download(DriveBackup(id: "x", name: "b.zip", createdAt: nil, sizeBytes: nil))
        XCTAssertEqual(data, archive)
    }
}
