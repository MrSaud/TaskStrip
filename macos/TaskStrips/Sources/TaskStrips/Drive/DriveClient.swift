import Foundation

/// One backup file as Drive describes it.
struct DriveBackup: Identifiable, Equatable {
    let id: String
    let name: String
    let createdAt: Date?
    let sizeBytes: Int?

    var readableSize: String {
        guard let sizeBytes else { return "" }
        return StorageLibrary.readableSize(sizeBytes)
    }
}

/// Whatever actually performs the request.
///
/// A protocol so the request-building and reply-parsing — which is nearly all of this file — can
/// be tested against canned responses. What can't be tested here is the network itself and the
/// browser consent screen; those are exercised by using the app.
protocol DriveTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: DriveTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DriveError.malformedResponse }
        return (data, http)
    }
}

/// Talks to Drive's REST API, mirroring DriveApi.kt: one folder named TaskStripBackups, holding
/// the backup zips, newest first.
struct DriveClient {
    static let folderName = "TaskStripBackups"
    static let folderMimeType = "application/vnd.google-apps.folder"
    private static let base = "https://www.googleapis.com/drive/v3"
    private static let uploadBase = "https://www.googleapis.com/upload/drive/v3"

    var transport: DriveTransport = URLSessionTransport()
    var accessToken: String

    // MARK: - Requests

    static func folderLookupRequest(accessToken: String) -> URLRequest {
        var components = URLComponents(string: "\(base)/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "mimeType='\(folderMimeType)' and name='\(folderName)' and trashed=false"),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
        ]
        return authorized(URLRequest(url: components.url!), accessToken: accessToken)
    }

    static func createFolderRequest(accessToken: String) -> URLRequest {
        var request = authorized(URLRequest(url: URL(string: "\(base)/files?fields=id")!), accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["name": folderName, "mimeType": folderMimeType]
        )
        return request
    }

    static func listRequest(accessToken: String, folderID: String) -> URLRequest {
        var components = URLComponents(string: "\(base)/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed=false"),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "fields", value: "files(id,name,createdTime,size)"),
            URLQueryItem(name: "orderBy", value: "createdTime desc"),
        ]
        return authorized(URLRequest(url: components.url!), accessToken: accessToken)
    }

    static func downloadRequest(accessToken: String, fileID: String) -> URLRequest {
        authorized(URLRequest(url: URL(string: "\(base)/files/\(fileID)?alt=media")!), accessToken: accessToken)
    }

    /// A multipart upload: the metadata naming the file and its parent, then the bytes. One
    /// request rather than Drive's resumable dance, which a backup is small enough not to need.
    static func uploadRequest(
        accessToken: String,
        folderID: String,
        fileName: String,
        archive: Data,
        boundary: String = "taskstrip-\(UUID().uuidString)"
    ) -> URLRequest {
        var request = authorized(
            URLRequest(url: URL(string: "\(uploadBase)/files?uploadType=multipart&fields=id,name")!),
            accessToken: accessToken
        )
        request.httpMethod = "POST"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let metadata = (try? JSONSerialization.data(
            withJSONObject: ["name": fileName, "parents": [folderID]]
        )) ?? Data()

        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(metadata)
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/zip\r\n\r\n".utf8))
        body.append(archive)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    private static func authorized(_ request: URLRequest, accessToken: String) -> URLRequest {
        var request = request
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Replies

    static func folderID(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let id = object["id"] as? String { return id }
        guard let files = object["files"] as? [[String: Any]] else { return nil }
        return files.first?["id"] as? String
    }

    /// Drive sends sizes as strings and times as RFC 3339. Both are optional in practice — a file
    /// still being written has no size yet — so neither is allowed to lose the row.
    static func backups(from data: Data) -> [DriveBackup] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = object["files"] as? [[String: Any]]
        else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        return files.compactMap { file in
            guard let id = file["id"] as? String, let name = file["name"] as? String else { return nil }
            let created = (file["createdTime"] as? String).flatMap {
                formatter.date(from: $0) ?? plain.date(from: $0)
            }
            let size = (file["size"] as? String).flatMap(Int.init) ?? (file["size"] as? NSNumber)?.intValue
            return DriveBackup(id: id, name: name, createdAt: created, sizeBytes: size)
        }
    }

    /// Drive puts the interesting part of a failure in `error.message`; the status alone rarely
    /// says which of several things went wrong.
    static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return "" }
        return message
    }

    // MARK: - Calls

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw DriveError.http(response.statusCode, Self.errorMessage(from: data))
        }
        return data
    }

    /// The folder, made if it isn't there yet — the same "ensure" Android does, so a Mac that
    /// backs up first doesn't end up with a second folder.
    func ensureBackupFolder() async throws -> String {
        let found = try await perform(Self.folderLookupRequest(accessToken: accessToken))
        if let id = Self.folderID(from: found) { return id }

        let created = try await perform(Self.createFolderRequest(accessToken: accessToken))
        guard let id = Self.folderID(from: created) else { throw DriveError.malformedResponse }
        return id
    }

    func backups(inFolder folderID: String) async throws -> [DriveBackup] {
        Self.backups(from: try await perform(Self.listRequest(accessToken: accessToken, folderID: folderID)))
    }

    func download(_ backup: DriveBackup) async throws -> Data {
        try await perform(Self.downloadRequest(accessToken: accessToken, fileID: backup.id))
    }

    @discardableResult
    func upload(_ archive: Data, named name: String, toFolder folderID: String) async throws -> String {
        let data = try await perform(
            Self.uploadRequest(accessToken: accessToken, folderID: folderID, fileName: name, archive: archive)
        )
        guard let id = Self.folderID(from: data) else { throw DriveError.malformedResponse }
        return id
    }
}
