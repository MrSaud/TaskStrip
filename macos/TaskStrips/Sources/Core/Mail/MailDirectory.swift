import Foundation

/// Somebody you've written to or heard from.
struct MailContact: Codable, Equatable, Identifiable {
    var address: String
    var name: String = ""
    var lastSeen: Date = .now
    /// How often they've turned up. A colleague you mail weekly should come before someone who
    /// sent one receipt in March.
    var timesSeen: Int = 1

    var id: String { address.lowercased() }

    /// What to show in a suggestion: the name where there is one, and the address either way.
    var display: String { name.isEmpty ? address : "\(name) — \(address)" }

    var domain: String { address.split(separator: "@").last.map { String($0).lowercased() } ?? "" }
}

/// The addresses this app has seen, and which of them to offer while somebody is typing.
///
/// Nobody types an address twice if the app can remember it. Everyone on every message read —
/// senders, recipients, the people copied in — goes in here, so the second message to a colleague
/// is a tap, and a whole Cc line of a team is four taps.
///
/// It's built from what's already been fetched, so it costs no extra request, and it never leaves
/// the device.
enum MailDirectory {
    /// How many to keep. Enough for years of ordinary correspondence, small enough to read and
    /// rank in a keystroke.
    static let limit = 500

    /// Folds what a batch of messages knows about people into what's already known.
    static func learning(
        from messages: [MailMessage],
        into known: [MailContact],
        mine: [String] = [],
        now: Date = .now
    ) -> [MailContact] {
        var byAddress: [String: MailContact] = [:]
        for contact in known { byAddress[contact.id] = contact }

        for message in messages {
            var seen: [(address: String, name: String, date: Date)] = []
            if let address = message.senderAddress {
                // A bare address has no name around it, and senderName falls back to the whole
                // field — which would leave contacts called "ahmad@example.com".
                let name = message.senderName
                seen.append((address, MailAddress.same(name, address) ? "" : name, message.receivedAt))
            }
            for field in [message.to, message.cc, message.replyTo].compactMap({ $0 }) {
                for entry in MailAddress.entries(in: field) {
                    guard let address = MailAddress.address(in: entry) else { continue }
                    seen.append((address, nameInside(entry), message.receivedAt))
                }
            }

            for person in seen {
                // My own addresses aren't suggestions: nobody writes to themselves.
                guard !mine.contains(where: { MailAddress.same($0, person.address) }) else { continue }
                let key = person.address.lowercased()
                if var existing = byAddress[key] {
                    existing.timesSeen += 1
                    existing.lastSeen = max(existing.lastSeen, person.date)
                    // A name is worth keeping once one arrives; an address with no name around it
                    // shouldn't erase the name learnt from an earlier message.
                    if existing.name.isEmpty { existing.name = person.name }
                    byAddress[key] = existing
                } else {
                    byAddress[key] = MailContact(
                        address: person.address, name: person.name, lastSeen: person.date, timesSeen: 1
                    )
                }
            }
        }

        // Trimmed by how likely someone is to be written to again, which is roughly how often and
        // how recently they've appeared.
        return Array(
            byAddress.values
                .sorted { ($0.timesSeen, $0.lastSeen) > ($1.timesSeen, $1.lastSeen) }
                .prefix(limit)
        )
    }

    /// "Ahmad Alenezi" out of `Ahmad Alenezi <ahmad@example.com>`, or nothing.
    static func nameInside(_ entry: String) -> String {
        guard let open = entry.firstIndex(of: "<") else { return "" }
        return String(entry[..<open])
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"")))
    }

    /// Who to offer for what's been typed so far.
    ///
    /// The people already written to come first, and among them the ones inside the same
    /// organisation: most mail is answered within the company it came from, and a colleague's
    /// address is the one worth guessing. Beyond that it's what was typed — a match at the start
    /// of a name or address beats one in the middle — then how often, then how recently.
    static func suggestions(
        for typed: String,
        in contacts: [MailContact],
        domain: String? = nil,
        excluding already: [String] = [],
        limit: Int = 6
    ) -> [MailContact] {
        let query = typed.trimmingCharacters(in: .whitespaces).lowercased()
        let home = domain?.lowercased()

        let matching = contacts.filter { contact in
            guard !already.contains(where: { MailAddress.same($0, contact.address) }) else { return false }
            guard !query.isEmpty else { return true }
            return contact.address.lowercased().contains(query) || contact.name.lowercased().contains(query)
        }

        return Array(
            matching
                .sorted { one, other in
                    let ranks = (rank(one, query: query, home: home), rank(other, query: query, home: home))
                    if ranks.0 != ranks.1 { return ranks.0 < ranks.1 }
                    if one.timesSeen != other.timesSeen { return one.timesSeen > other.timesSeen }
                    return one.lastSeen > other.lastSeen
                }
                .prefix(limit)
        )
    }

    /// Lower is better.
    private static func rank(_ contact: MailContact, query: String, home: String?) -> Int {
        let sameDomain = home.map { contact.domain == $0 } ?? false
        guard !query.isEmpty else { return sameDomain ? 0 : 1 }
        let starts = contact.address.lowercased().hasPrefix(query) || contact.name.lowercased().hasPrefix(query)
        switch (starts, sameDomain) {
        case (true, true): return 0
        case (true, false): return 1
        case (false, true): return 2
        case (false, false): return 3
        }
    }

    /// Replaces the half-typed entry with the one that was picked, leaving the rest of the field
    /// alone — a Cc line is built one person at a time.
    static func completing(_ field: String, with address: String) -> String {
        var entries = MailAddress.entries(in: field)
        // What's being typed is the last entry, unless the field ends in a comma, in which case a
        // new one is being started.
        if !field.trimmingCharacters(in: .whitespaces).hasSuffix(","), !entries.isEmpty {
            entries.removeLast()
        }
        entries.append(address)
        return entries.joined(separator: ", ") + ", "
    }

    /// What's being typed right now, which is what the suggestions are for.
    static func partial(in field: String) -> String {
        guard !field.trimmingCharacters(in: .whitespaces).hasSuffix(",") else { return "" }
        return MailAddress.entries(in: field).last ?? ""
    }
}

/// Where the directory is kept: this device's own settings, never sent anywhere.
struct MailDirectoryStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "mailContacts") {
        self.defaults = defaults
        self.key = key
    }

    var contacts: [MailContact] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([MailContact].self, from: data)) ?? []
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }
}
