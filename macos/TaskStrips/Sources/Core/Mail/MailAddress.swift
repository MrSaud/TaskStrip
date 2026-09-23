import Foundation

/// The addresses in a header, and the one thing that makes reading them awkward: a name with a
/// comma in it.
///
/// `"Alenezi, Ahmad" <ahmad@example.com>, sales@example.com` is two people, not three. Splitting on
/// commas alone turns the first into two half-addresses, which on a Reply All means a message
/// addressed to nobody and copied to a fragment.
enum MailAddress {
    /// Every address in a To or Cc header, in the order written.
    static func list(in header: String) -> [String] {
        entries(in: header).compactMap { address(in: $0) }
    }

    /// Every entry, address or not — what somebody typed, split on the commas that separate
    /// people rather than the ones inside their names. Used to tell "one address" from "one
    /// address and a typo".
    static func entries(in header: String) -> [String] {
        var addresses: [String] = []
        var current = ""
        var inQuotes = false
        var inAngles = false

        for character in header {
            switch character {
            case "\"": inQuotes.toggle()
            case "<": inAngles = true
            case ">": inAngles = false
            case "," where !inQuotes && !inAngles:
                addresses.append(current)
                current = ""
                continue
            default: break
            }
            current.append(character)
        }
        addresses.append(current)

        return addresses
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The address out of one entry, with any name around it dropped.
    static func address(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let open = trimmed.firstIndex(of: "<"), let close = trimmed[open...].firstIndex(of: ">") {
            let inside = trimmed[trimmed.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            return inside.contains("@") ? inside : nil
        }
        return trimmed.contains("@") ? trimmed : nil
    }

    /// Two addresses are the same person whatever the capitals: mail hosts don't care, and a
    /// Reply All that copies someone twice because one header shouted their name is a bug.
    static func same(_ one: String, _ other: String) -> Bool {
        one.compare(other, options: .caseInsensitive) == .orderedSame
    }

    /// The list with duplicates and the named addresses removed, keeping the order it arrived in.
    static func without(_ excluded: [String], from addresses: [String]) -> [String] {
        var seen: [String] = []
        for address in addresses {
            guard !excluded.contains(where: { same($0, address) }) else { continue }
            guard !seen.contains(where: { same($0, address) }) else { continue }
            seen.append(address)
        }
        return seen
    }
}
