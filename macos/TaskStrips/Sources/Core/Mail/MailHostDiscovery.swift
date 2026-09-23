import Foundation

/// Which server actually holds a domain's mail, asked of DNS rather than guessed from the name.
///
/// `imap.<domain>` is right for a company that runs its own mail and wrong for everyone who pays
/// someone else to run it: swapkuwait.com has no imap.swapkuwait.com at all — its mail is Amazon
/// WorkMail, and its IMAP server is imap.mail.us-east-1.awsapps.com, which nothing about the
/// address would tell you. A domain's MX record does tell you, and it costs one query.
enum MailHost {
    /// Who runs the mail, worked out from the MX host the domain points at.
    enum Provider: Equatable {
        case google
        case microsoft
        case apple
        case yahoo
        case zoho
        case amazonWorkMail(region: String)
        /// Someone running their own, or a host nobody here recognises.
        case unknown

        /// Where its IMAP lives, where that's a fixed address.
        var imapHost: String? {
            switch self {
            case .google: return "imap.gmail.com"
            case .microsoft: return "outlook.office365.com"
            case .apple: return "imap.mail.me.com"
            case .yahoo: return "imap.mail.yahoo.com"
            case .zoho: return "imap.zoho.com"
            case .amazonWorkMail(let region): return "imap.mail.\(region).awsapps.com"
            case .unknown: return nil
            }
        }

        /// What to say about it while the password field is still empty.
        var note: String? {
            switch self {
            case .microsoft:
                return "This domain's mail is on Microsoft 365, which refuses IMAP passwords — "
                    + "it needs OAuth, which this app doesn't do yet."
            case .google:
                return "This domain's mail is Google's, so the password here is an app password."
            case .amazonWorkMail(let region):
                return "This domain's mail is Amazon WorkMail in \(region)."
            case .apple, .yahoo:
                return "This provider wants an app-specific password rather than your own."
            case .zoho, .unknown:
                return nil
            }
        }
    }

    /// Reads the MX host — "kfas-org-kw.mail.protection.outlook.com", "inbound-smtp.us-east-1.
    /// amazonaws.com", "aspmx.l.google.com" — and says who that is.
    static func provider(forMailExchanger host: String) -> Provider {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if name.hasSuffix("google.com") || name.hasSuffix("googlemail.com") { return .google }
        if name.hasSuffix("outlook.com") || name.hasSuffix("office365.com") { return .microsoft }
        if name.hasSuffix("icloud.com") || name.hasSuffix("apple.com") || name.hasSuffix("me.com") {
            return .apple
        }
        if name.contains("yahoodns") || name.hasSuffix("yahoo.com") { return .yahoo }
        if name.contains("zoho") { return .zoho }
        // WorkMail's inbound host carries the region it lives in, which is the one thing needed
        // to name its IMAP server: inbound-smtp.us-east-1.amazonaws.com.
        if name.hasSuffix("amazonaws.com") || name.hasSuffix("awsapps.com") {
            let parts = name.split(separator: ".")
            let region = parts.first { part in
                // us-east-1, eu-west-1, ap-southeast-2 — two or three letters, a word, a digit.
                let bits = part.split(separator: "-")
                return bits.count == 3 && bits[0].count <= 3 && Int(bits[2]) != nil
            }
            return .amazonWorkMail(region: region.map(String.init) ?? "us-east-1")
        }
        return .unknown
    }

    /// The best host for an address: what DNS says, and failing that the old guess by domain.
    ///
    /// DNS is asked with a short deadline and its answer only ever fills a field someone can
    /// overwrite — a form that waits on a network lookup to let you type is worse than a wrong
    /// default.
    static func best(for email: String, resolver: MXResolving = MXResolver(), timeout: TimeInterval = 3) async -> (host: String, port: Int, provider: Provider) {
        let fallback = IMAPHost.guess(for: email)
        guard let domain = email.split(separator: "@").last.map({ String($0).lowercased() }) else {
            return (fallback?.host ?? "", fallback?.port ?? 993, .unknown)
        }
        let exchangers = await resolver.mailExchangers(for: domain, timeout: timeout)
        for exchanger in exchangers {
            let provider = provider(forMailExchanger: exchanger)
            if let host = provider.imapHost {
                return (host, 993, provider)
            }
        }
        return (fallback?.host ?? "", fallback?.port ?? 993, .unknown)
    }
}

/// Asking DNS for a domain's mail servers, as a protocol so the mapping above can be tested
/// without a network.
protocol MXResolving: Sendable {
    /// The MX hosts, best preference first. Empty when DNS says nothing in time.
    func mailExchangers(for domain: String, timeout: TimeInterval) async -> [String]
}
