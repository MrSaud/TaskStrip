import Foundation
import Network

/// One conversation with an IMAP server: connect, log in, choose the inbox, ask for the newest
/// few headers, say goodbye.
///
/// TLS from the first byte, on 993 — there is no plaintext path here and no falling back to one.
/// It fetches headers only, with BODY.PEEK so nothing is marked read by being looked at, and it
/// never asks for a message body: this is a list to glance at.
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
    private var buffer = ""

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
            if let outcome = IMAPResponse.completion(for: tag, in: buffer) {
                let answer = buffer
                buffer = ""
                switch outcome {
                case .ok: return answer
                case .no(let detail), .bad(let detail): throw failure(detail)
                }
            }
            buffer += try await receive()
        }
    }

    /// The server speaks first; its greeting is read before anything is asked of it.
    private func waitForGreeting() async throws -> String {
        while !buffer.contains("\r\n") {
            buffer += try await receive()
        }
        let greeting = buffer
        buffer = ""
        return greeting
    }

    private func receive() async throws -> String {
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
                // Headers can carry any encoding; anything that isn't valid UTF-8 is read as
                // Latin-1 rather than dropped, since a mangled subject beats a missing message.
                let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                continuation.resume(returning: text)
            }
        }
    }
}
