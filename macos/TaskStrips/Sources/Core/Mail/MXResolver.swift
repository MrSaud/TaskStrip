import Foundation
import dnssd

/// A DNS MX lookup, through the system resolver both platforms already have.
///
/// There is no Foundation call for this — URLSession resolves names for you and tells you
/// nothing — so it goes through dnssd, which is the same resolver everything else on the device
/// uses, honours the network's DNS, and needs no entitlement.
struct MXResolver: MXResolving {
    func mailExchangers(for domain: String, timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { continuation in
            Self.query(domain: domain, timeout: timeout) { continuation.resume(returning: $0) }
        }
    }

    /// Collected until the deadline rather than stopping at the first answer: a domain lists
    /// several mail exchangers and they arrive as separate callbacks.
    private static func query(domain: String, timeout: TimeInterval, completion: @escaping ([String]) -> Void) {
        final class Collected: @unchecked Sendable {
            var records: [(preference: UInt16, host: String)] = []
            var finished = false
        }
        let collected = Collected()
        let queue = DispatchQueue(label: "mx-resolver")

        var service: DNSServiceRef?
        let context = Unmanaged.passRetained(collected).toOpaque()

        let callback: DNSServiceQueryRecordReply = { _, _, _, error, _, _, _, length, data, _, context in
            guard error == kDNSServiceErr_NoError,
                  let context,
                  let data,
                  let record = MXResolver.parse(Data(bytes: data, count: Int(length)))
            else { return }
            Unmanaged<Collected>.fromOpaque(context).takeUnretainedValue().records.append(record)
        }

        let status = DNSServiceQueryRecord(
            &service,
            0,
            0,
            domain,
            UInt16(kDNSServiceType_MX),
            UInt16(kDNSServiceClass_IN),
            callback,
            context
        )
        guard status == kDNSServiceErr_NoError, let service else {
            Unmanaged<Collected>.fromOpaque(context).release()
            completion([])
            return
        }
        DNSServiceSetDispatchQueue(service, queue)

        queue.asyncAfter(deadline: .now() + timeout) {
            guard !collected.finished else { return }
            collected.finished = true
            DNSServiceRefDeallocate(service)
            let hosts = collected.records.sorted { $0.preference < $1.preference }.map(\.host)
            Unmanaged<Collected>.fromOpaque(context).release()
            completion(hosts)
        }
    }

    /// An MX record's wire format: two bytes of preference, then the host as DNS writes a name —
    /// each label preceded by its length, the whole thing ended by a zero.
    static func parse(_ data: Data) -> (preference: UInt16, host: String)? {
        let bytes = [UInt8](data)
        guard bytes.count > 3 else { return nil }
        let preference = UInt16(bytes[0]) << 8 | UInt16(bytes[1])

        var labels: [String] = []
        var index = 2
        while index < bytes.count {
            let length = Int(bytes[index])
            if length == 0 { break }
            // A compression pointer (top two bits set) can't be followed without the whole
            // message, which this callback doesn't hand over. Answers to a direct query aren't
            // compressed in practice; anything that is, is skipped rather than mangled.
            guard length < 64, index + length < bytes.count else { return nil }
            let label = bytes[(index + 1)...(index + length)]
            guard let text = String(bytes: label, encoding: .utf8) else { return nil }
            labels.append(text)
            index += length + 1
        }
        guard !labels.isEmpty else { return nil }
        return (preference, labels.joined(separator: "."))
    }
}
