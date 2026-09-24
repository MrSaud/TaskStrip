import Foundation
import Network

/// One conversation with an outgoing mail server: hello, sign in, sender, recipients, message,
/// goodbye.
///
/// The first thing in this app that acts outward — everything else reads with BODY.PEEK and
/// changes nothing. So it does exactly one thing per connection, tells the caller precisely what
/// the server said when it refuses, and has no retry loop: a message that fails to send is a
/// message someone should look at, not one that quietly goes out three times.
actor SMTPConnection {
    enum Failure: LocalizedError, Equatable {
        case couldNotConnect(String)
        case refused(String)
        case serverSaid(String)
        case silence

        var errorDescription: String? {
            switch self {
            case .couldNotConnect(let detail): return "Couldn't reach the outgoing server: \(detail)"
            case .refused(let detail): return "The outgoing server refused the sign-in: \(detail)"
            case .serverSaid(let detail): return "The outgoing server said: \(detail)"
            case .silence: return "The outgoing server stopped answering."
            }
        }
    }

    private let host: String
    private let port: Int
    private let email: String
    private let password: String
    private var connection: NWConnection?
    private var buffer = ""

    /// `usesToken` says whether `password` is a password or an access token — the difference is
    /// one command, and everything after it is the same.
    private let usesToken: Bool

    init(host: String, port: Int = SMTPHost.port, email: String, password: String, usesToken: Bool = false) {
        self.host = host
        self.port = port
        self.email = email
        self.password = password
        self.usesToken = usesToken
    }

    /// Sends one message and returns what was actually sent, so a copy of exactly those bytes can
    /// be filed in the Sent folder.
    @discardableResult
    func send(_ draft: MailDraft, now: Date = .now) async throws -> String {
        guard draft.isSendable, !draft.recipients.isEmpty else {
            throw Failure.serverSaid("there's no valid address to send this to")
        }
        let message = draft.rendered(now: now)

        try await connect()
        defer { close() }

        try await expect(nil, positive: "greeting")
        try await expect(SMTPCommand.ehlo(), positive: "EHLO")
        if usesToken {
            // One line: the token carries both who and what.
            try await expect(
                XOAUTH2.smtpCommand(email: email, accessToken: password),
                positive: "AUTH XOAUTH2",
                failure: Failure.refused
            )
        } else {
            // AUTH LOGIN asks for the two halves separately, each one base64, each one answered
            // with a 334 until the last.
            try await expect(SMTPCommand.authLogin, positive: "AUTH", failure: Failure.refused)
            try await expect(SMTPCommand.base64(email), positive: "username", failure: Failure.refused)
            try await expect(SMTPCommand.base64(password), positive: "password", failure: Failure.refused)
        }

        try await expect(SMTPCommand.mailFrom(draft.from), positive: "MAIL FROM")
        for recipient in draft.recipients {
            try await expect(SMTPCommand.recipient(recipient), positive: "RCPT TO")
        }
        try await expect(SMTPCommand.data, positive: "DATA")
        try await expect(SMTPCommand.body(message), positive: "the message")
        _ = try? await exchange(SMTPCommand.quit)
        return message
    }

    /// Sends a command and insists the answer is a good one.
    private func expect(
        _ command: String?,
        positive what: String,
        failure: @escaping (String) -> Failure = Failure.serverSaid
    ) async throws {
        let reply = try await exchange(command)
        guard reply.isPositive else {
            throw failure("\(reply.text) (on \(what))")
        }
    }

    /// Writes a command, if there is one, and reads until the server has finished its answer.
    private func exchange(_ command: String?) async throws -> SMTPResponse.Reply {
        guard let connection else { throw Failure.silence }
        if let command {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: Data(command.utf8), completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: Failure.couldNotConnect(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                })
            }
        }
        while true {
            if let reply = SMTPResponse.complete(in: buffer) {
                buffer = ""
                return reply
            }
            buffer += try await receive()
        }
    }

    private func connect() async throws {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tls
        )
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

    private func receive() async throws -> String {
        guard let connection else { throw Failure.silence }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: Failure.couldNotConnect(error.localizedDescription))
                    return
                }
                guard let data, !data.isEmpty else {
                    continuation.resume(throwing: Failure.silence)
                    return
                }
                // SMTP's own chatter is ASCII.
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }

    private func close() {
        connection?.cancel()
        connection = nil
    }
}
