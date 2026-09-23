import CoreFoundation
import Foundation

/// The headers of a message, as they arrive in a FETCH reply, turned into something to show.
///
/// Mail headers are ASCII, so anything that isn't — an Arabic subject, a name with an accent —
/// arrives encoded as `=?UTF-8?B?…?=`. Decoding that is most of the work here, and the reason
/// this is a type of its own rather than three lines of string splitting.
enum IMAPHeaders {
    struct Fields: Equatable {
        var subject = ""
        var from = ""
        var messageID = ""
        var date: Date?
        /// Everyone else the message went to, as written.
        var to = ""
        var cc = ""
        /// Where the sender asked for replies to go, when that isn't the From address — a mailing
        /// list, or a no-reply address with a real one behind it.
        var replyTo = ""
    }

    static func parse(_ raw: String, now: Date = .now) -> Fields {
        var fields = Fields()
        for line in unfolded(raw) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            // Newlines as well as spaces: the last header of a block often arrives with the
            // line break still attached, which left a ">" on the end of every Message-ID.
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            switch parts[0].trimmingCharacters(in: .whitespaces).lowercased() {
            case "subject": fields.subject = decodeWords(value)
            case "from": fields.from = decodeWords(value)
            case "message-id": fields.messageID = value.trimmingCharacters(in: .init(charactersIn: "<>"))
            case "date": fields.date = date(from: value)
            case "to": fields.to = decodeWords(value)
            case "cc": fields.cc = decodeWords(value)
            case "reply-to": fields.replyTo = decodeWords(value)
            default: continue
            }
        }
        return fields
    }

    /// A header can be split across lines, with the continuations indented. Putting them back
    /// together first is what stops a long Arabic subject arriving in halves.
    static func unfolded(_ raw: String) -> [String] {
        var lines: [String] = []
        for line in raw.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                let continuation = line.trimmingCharacters(in: .whitespaces)
                if var last = lines.popLast() {
                    // Encoded words that were split are joined without a space between them,
                    // which is what the encoding intends; plain text keeps its space.
                    last += (last.hasSuffix("?=") && continuation.hasPrefix("=?")) ? continuation : " " + continuation
                    lines.append(last)
                }
            } else if !line.isEmpty {
                lines.append(String(line))
            }
        }
        return lines
    }

    /// `=?charset?B?base64?=` and `=?charset?Q?quoted?=`, anywhere in the text, as many as there are.
    static func decodeWords(_ text: String) -> String {
        guard text.contains("=?") else { return text }
        var result = ""
        var rest = Substring(text)

        while let start = rest.range(of: "=?") {
            result += rest[rest.startIndex..<start.lowerBound]
            let afterStart = rest[start.upperBound...]
            guard let end = afterStart.range(of: "?=") else {
                result += rest[start.lowerBound...]
                return result
            }
            let word = afterStart[afterStart.startIndex..<end.lowerBound]
            let pieces = word.split(separator: "?", maxSplits: 2, omittingEmptySubsequences: false)
            if pieces.count == 3, let decoded = decode(
                text: String(pieces[2]), encoding: String(pieces[1]), charset: String(pieces[0])
            ) {
                result += decoded
            } else {
                result += "=?" + word + "?="
            }
            rest = afterStart[end.upperBound...]
        }
        return result + rest
    }

    private static func decode(text: String, encoding: String, charset: String) -> String? {
        let bytes: Data?
        switch encoding.uppercased() {
        case "B":
            bytes = Data(base64Encoded: text)
        case "Q":
            // Quoted-printable, with the one difference that matters in a header: underscore is
            // a space.
            var output = Data()
            var characters = Array(text.utf8)
            var index = 0
            while index < characters.count {
                if characters[index] == UInt8(ascii: "=") , index + 2 < characters.count,
                   let value = UInt8(String(decoding: characters[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                    output.append(value)
                    index += 3
                } else if characters[index] == UInt8(ascii: "_") {
                    output.append(UInt8(ascii: " "))
                    index += 1
                } else {
                    output.append(characters[index])
                    index += 1
                }
            }
            bytes = output
        default:
            return nil
        }
        guard let bytes else { return nil }
        return string(from: bytes, charset: charset)
    }

    /// Bytes as the charset they were written in. Shared with the body reader, which meets the
    /// same handful of charsets a header does.
    static func string(from bytes: Data, charset: String) -> String? {
        let encodingName = charset.lowercased()
        if encodingName.contains("utf-8") || encodingName.contains("utf8") {
            return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1)
        }
        if encodingName.contains("1256") {   // Arabic Windows, which older mail still uses
            return String(data: bytes, encoding: .windowsCP1256)
        }
        if encodingName.contains("1252") {
            return String(data: bytes, encoding: .windowsCP1252)
        }
        if encodingName.contains("8859-6") {   // Arabic ISO, which Foundation only names in CF
            let arabic = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.isoLatinArabic.rawValue)
            )
            return String(data: bytes, encoding: String.Encoding(rawValue: arabic))
        }
        if encodingName.contains("8859-1") || encodingName.contains("latin") {
            return String(data: bytes, encoding: .isoLatin1)
        }
        return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1)
    }

    /// RFC 5322 dates, in the two shapes servers actually send.
    static func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
            // A trailing "(GMT)" or similar is legal and common.
            if let bracket = trimmed.firstIndex(of: "("),
               let date = formatter.date(from: String(trimmed[..<bracket]).trimmingCharacters(in: .whitespaces)) {
                return date
            }
        }
        return nil
    }
}

extension String.Encoding {
    static let windowsCP1256 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsArabic.rawValue))
    )
}
