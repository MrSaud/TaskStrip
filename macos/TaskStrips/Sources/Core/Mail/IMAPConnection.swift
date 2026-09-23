import Foundation
import Network

/// One conversation with an IMAP server: connect, log in, choose the inbox, ask for the newest
/// few headers, say goodbye.
///
/// TLS from the first byte, on 993 — there is no plaintext path here and no falling back to one.
/// Everything is asked for with BODY.PEEK, so nothing is marked read by being looked at, and
/// nothing here moves, deletes or sends anything: it reads a list, and it reads a message.
actor IMAPConnection {
    enum Failure: LocalizedError, Equatable {
        case couldNotConnect(String)
        case refused(String)
        case serverSaid(String)
        case silence

        var errorDescription: String? {
            switch self {
            case .couldNotConnect(let detail): return "Couldn't reach the server: \(detail)"
            case .refused(let detail): return "The server refused the sign-in: \(detail)"
            case .serverSaid(let detail): return "The server said: \(detail)"
            case .silence: return "The server stopped answering."
            }
        }
    }

    private let account: IMAPAccount
    private let password: String
    private var connection: NWConnection?
    private var tag = 0
    /// Everything read from the server that hasn't been matched to a command yet.
    ///
    /// Bytes, not text: a chunk can end halfway through a character, and decoding each chunk as
    /// it arrives turns those into question marks. It's decoded once, whole, at the end.
    private var buffer = Data()

    init(account: IMAPAccount, password: String) {
        self.account = account
        self.password = password
    }

    /// The whole errand. The connection is opened and closed around it, because a list fetched
    /// every few minutes doesn't justify holding a socket open.
    func fetchNewest(count: Int = MailInbox.askFor, now: Date = .now) async throws -> [MailMessage] {
        try await connect()
        defer { close() }

        _ = try await waitForGreeting()
        _ = try await send(IMAPCommand.login(tag: nextTag(), email: account.email, password: password), failure: Failure.refused)
        let select = try await send(IMAPCommand.selectInbox(tag: nextTag()), failure: Failure.serverSaid)
        guard let total = IMAPResponse.exists(in: select), total > 0 else { return [] }

        let fetch = try await send(
            IMAPCommand.fetchNewest(tag: nextTag(), total: total, count: count), failure: Failure.serverSaid
        )
        _ = try? await send(IMAPCommand.logout(tag: nextTag()), failure: Failure.serverSaid)
        return MailInbox.newest(IMAPFetch.messages(from: fetch, now: now), count: count)
    }

    /// One message, as the person reading it wants it: the words, not the MIME.
    ///
    /// A connection of its own, opened and closed around the one fetch — the list's connection is
    /// long gone by the time someone clicks a row.
    func fetchBody(uid: Int, limit: Int = MailBodyParser.byteLimit) async throws -> MailBody {
        try await connect()
        defer { close() }

        _ = try await waitForGreeting()
        _ = try await send(IMAPCommand.login(tag: nextTag(), email: account.email, password: password), failure: Failure.refused)
        _ = try await send(IMAPCommand.selectInbox(tag: nextTag()), failure: Failure.serverSaid)
        let answer = try await sendForBytes(
            IMAPCommand.fetchBody(tag: nextTag(), uid: uid, limit: limit), failure: Failure.serverSaid
        )
        _ = try? await send(IMAPCommand.logout(tag: nextTag()), failure: Failure.serverSaid)

        guard let raw = IMAPFetch.literal(in: answer) else { throw Failure.serverSaid("no message came back") }
        return MailBodyParser.read(raw, wasTruncated: raw.count >= limit)
    }

    // MARK: - The socket

    private func connect() async throws {
        let endpoint = NWEndpoint.Host(account.host)
        let port = NWEndpoint.Port(integerLiteral: UInt16(account.port))
        let connection = NWConnection(host: endpoint, port: port, using: .tls)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                case .failed(let error), .waiting(let error):
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(throwing: Failure.couldNotConnect(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private func close() {
        connection?.cancel()
        connection = nil
    }

    private func nextTag() -> String {
        tag += 1
        return IMAPCommand.tag(tag)
    }

    /// Sends a command and reads until the line wearing its tag arrives.
    @discardableResult
    private func send(_ command: String, failure: @escaping (String) -> Failure) async throws -> String {
        let answer = try await sendForBytes(command, failure: failure)
        return String(data: answer, encoding: .utf8) ?? String(data: answer, encoding: .isoLatin1) ?? ""
    }

    private func sendForBytes(_ command: String, failure: @escaping (String) -> Failure) async throws -> Data {
        guard let connection else { throw Failure.silence }
        let tag = String(command.prefix(while: { $0 != " " }))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(command.utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: Failure.couldNotConnect(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }

        while true {
            // Latin-1 for the protocol chatter only: it maps every byte to a character without
            // ever failing, so a tag can be found in a buffer that is half binary.
            if let outcome = IMAPResponse.completion(for: tag, in: String(decoding: buffer, as: UTF8.self)) ??
                IMAPResponse.completion(for: tag, in: String(data: buffer, encoding: .isoLatin1) ?? "") {
                let answer = buffer
                buffer = Data()
                switch outcome {
                case .ok: return answer
                case .no(let detail), .bad(let detail): throw failure(detail)
                }
            }
            buffer.append(try await receive())
        }
    }

    /// The server speaks first; its greeting is read before anything is asked of it.
    private func waitForGreeting() async throws -> String {
        while buffer.range(of: Data("\r\n".utf8)) == nil {
            buffer.append(try await receive())
        }
        let greeting = String(decoding: buffer, as: UTF8.self)
        buffer = Data()
        return greeting
    }

    private func receive() async throws -> Data {
        guard let connection else { throw Failure.silence }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: Failure.couldNotConnect(error.localizedDescription))
                    return
                }
                guard let data, !data.isEmpty else {
                    continuation.resume(throwing: isComplete ? Failure.silence : Failure.silence)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}
