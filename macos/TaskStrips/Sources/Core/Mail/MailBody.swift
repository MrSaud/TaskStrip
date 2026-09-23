import Foundation

/// A message's text, once it has been dug out of what the server actually sends.
///
/// Almost nothing arrives as the words someone typed. A mail is a MIME tree: a plain-text version
/// and an HTML version of the same message, the HTML wrapped around inline images, everything
/// base64'd or quoted-printable'd and in whichever charset the sender's mail program liked. This
/// takes all that and hands back the reading.
/// A file that came with a message: the bytes, and what to call it.
struct MailAttachment: Identifiable, Equatable {
    /// Stable within one message, which is all this needs: the list is rebuilt on every fetch.
    var id: String { "\(name)-\(bytes.count)" }
    var name: String
    var type: String
    var bytes: Data

    /// "412 KB", for a row that has to say whether this is worth waiting for.
    var size: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes.count), countStyle: .file)
    }

    /// Inline images are part of the layout rather than something someone attached — a signature
    /// logo, a tracking pixel — so they're listed after the real files and can be told apart.
    var isInline = false
}

struct MailBody: Equatable {
    var text: String
    /// True when the plain-text version was missing and this was made out of the HTML one, which
    /// is worth knowing: the result reads well enough but isn't laid out the way it was sent.
    var fromHTML = false
    /// The fetch stopped at the size limit, so the tail is missing.
    var isTruncated = false
    /// The files that came with it, real attachments first.
    var attachments: [MailAttachment] = []

    static let empty = MailBody(text: "")
}

enum MailBodyParser {
    /// How much of a message to ask for. Enough for any amount of reading; short of the
    /// twenty-megabyte ones with a slide deck inside, which nobody wants to wait for on a phone.
    static let byteLimit = 256 * 1024

    /// What "fetch the whole thing" means, for a message whose attachments someone actually
    /// wants. Above this nothing is fetched at all: it's a strip's attachment, not a film.
    static let wholeMessageLimit = 25 * 1024 * 1024

    /// Reads a whole RFC 822 message — headers, then body.
    static func read(_ raw: Data, wasTruncated: Bool = false) -> MailBody {
        let part = part(from: raw)
        var body = text(of: part) ?? MailBody(text: "")
        body.isTruncated = wasTruncated || body.isTruncated
        let files = attachments(in: part)
        // A logo in a signature is not what anyone means by an attachment, so the files someone
        // deliberately attached are listed first.
        body.attachments = files.filter { !$0.isInline } + files.filter(\.isInline)
        return body
    }

    /// Every file in the tree: anything that isn't the reading.
    ///
    /// A part counts as a file if it was attached on purpose, or if it simply isn't text — a PDF,
    /// an image, a spreadsheet. A truncated fetch cuts the last one short, which is why an
    /// attachment is worth having only when the whole message came down.
    static func attachments(in part: Part) -> [MailAttachment] {
        if part.type.hasPrefix("multipart/"), let boundary = part.boundary {
            return pieces(of: part.body, boundary: boundary)
                .map { self.part(from: $0) }
                .flatMap { attachments(in: $0) }
        }

        let disposition = part.disposition.lowercased()
        let attached = disposition.hasPrefix("attachment")
        let inline = disposition.hasPrefix("inline")
        let isText = part.type.hasPrefix("text/") || part.type.isEmpty
        guard attached || !isText else { return [] }
        // A part with nothing in it is a part the fetch didn't reach.
        guard !part.body.isEmpty else { return [] }

        return [
            MailAttachment(
                name: filename(of: part),
                type: part.type,
                bytes: decoded(part.body, encoding: part.encoding),
                isInline: inline && !attached
            ),
        ]
    }

    /// What to call the file. Mail says so twice — in the disposition and in the content type —
    /// and non-English names arrive encoded in one of two different ways.
    static func filename(of part: Part) -> String {
        for (header, keys) in [(part.disposition, ["filename*", "filename"]), (part.typeHeader, ["name*", "name"])] {
            for key in keys {
                guard let raw = parameter(key, in: header) else { continue }
                let name = key.hasSuffix("*") ? extended(raw) : IMAPHeaders.decodeWords(raw)
                if !name.isEmpty { return name }
            }
        }
        // Nothing named it, so the type does: image/png becomes attachment.png.
        let extensionName = part.type.split(separator: "/").last.map(String.init) ?? "dat"
        return "attachment.\(extensionName)"
    }

    /// RFC 2231: `filename*=UTF-8\'\'%D9%85%D9%84%D9%81.pdf` — the charset, the language, then
    /// percent-encoded bytes.
    static func extended(_ raw: String) -> String {
        let pieces = raw.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return raw.removingPercentEncoding ?? raw }
        let charset = String(pieces[0])
        var bytes = Data()
        var rest = Substring(pieces[2])
        while let character = rest.first {
            if character == "%", rest.count >= 3, let byte = UInt8(rest.dropFirst().prefix(2), radix: 16) {
                bytes.append(byte)
                rest = rest.dropFirst(3)
            } else {
                bytes.append(contentsOf: Array(String(character).utf8))
                rest = rest.dropFirst()
            }
        }
        return IMAPHeaders.string(from: bytes, charset: charset) ?? raw
    }

    // MARK: - One part of the tree

    struct Part {
        var type = "text/plain"
        var charset = "utf-8"
        var encoding = ""
        var boundary: String?
        /// The whole Content-Type line, kept for the parameters a filename can hide in.
        var typeHeader = ""
        var disposition = ""
        var body = Data()
    }

    /// Splits headers from body and reads the three headers that decide how to read the rest.
    static func part(from raw: Data) -> Part {
        var part = Part()
        let (headerBytes, bodyBytes) = split(raw)
        part.body = bodyBytes

        // Headers are ASCII by definition; Latin-1 reads any byte without failing.
        let headers = String(data: headerBytes, encoding: .isoLatin1) ?? ""
        for line in IMAPHeaders.unfolded(headers) {
            let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { continue }
            let value = String(pieces[1]).trimmingCharacters(in: .whitespaces)
            switch pieces[0].trimmingCharacters(in: .whitespaces).lowercased() {
            case "content-type":
                part.type = value.split(separator: ";").first.map {
                    String($0).trimmingCharacters(in: .whitespaces).lowercased()
                } ?? "text/plain"
                part.charset = parameter("charset", in: value) ?? "utf-8"
                part.boundary = parameter("boundary", in: value)
                part.typeHeader = value
            case "content-transfer-encoding":
                part.encoding = value.lowercased()
            case "content-disposition":
                // Not lowercased wholesale any more: the filename lives in here and a file
                // called Invoice.PDF should keep its capitals.
                part.disposition = value
            default: continue
            }
        }
        return part
    }

    /// The readable text of a part, looking inside it when it's a multipart.
    static func text(of part: Part) -> MailBody? {
        if part.type.hasPrefix("multipart/"), let boundary = part.boundary {
            let parts = pieces(of: part.body, boundary: boundary).map { self.part(from: $0) }
            // Plain text wins wherever it exists — it's what the sender's own words look like.
            // Failing that, the HTML version, turned into something readable.
            if let plain = parts.compactMap({ text(of: $0) }).first(where: { !$0.fromHTML && !$0.text.isEmpty }) {
                return plain
            }
            return parts.compactMap { text(of: $0) }.first { !$0.text.isEmpty }
        }

        // An attachment is not the message, even when it happens to be text.
        guard !part.disposition.lowercased().hasPrefix("attachment") else { return nil }

        let bytes = decoded(part.body, encoding: part.encoding)
        guard let text = IMAPHeaders.string(from: bytes, charset: part.charset) else { return nil }

        if part.type == "text/html" {
            return MailBody(text: readable(fromHTML: text), fromHTML: true)
        }
        guard part.type.hasPrefix("text/") else { return nil }
        return MailBody(text: tidied(text))
    }

    // MARK: - The pieces

    /// Headers end at the first blank line. A message truncated before one has no body at all.
    static func split(_ raw: Data) -> (headers: Data, body: Data) {
        let separators: [[UInt8]] = [[13, 10, 13, 10], [10, 10]]
        for separator in separators {
            if let range = raw.range(of: Data(separator)) {
                return (raw[..<range.lowerBound], raw[range.upperBound...])
            }
        }
        return (raw, Data())
    }

    /// A multipart body, cut at its boundaries. The preamble before the first boundary and the
    /// epilogue after the last are not parts and are dropped.
    static func pieces(of body: Data, boundary: String) -> [Data] {
        let marker = Data("--\(boundary)".utf8)
        var pieces: [Data] = []
        var searchFrom = body.startIndex
        var previousEnd: Data.Index?

        while let range = body[searchFrom...].range(of: marker) {
            if let start = previousEnd {
                var piece = body[start..<range.lowerBound]
                // The boundary owns the line break in front of it, not the part.
                if piece.last == 10 { piece = piece.dropLast() }
                if piece.last == 13 { piece = piece.dropLast() }
                pieces.append(Data(piece))
            }
            // Past the marker and the line break after it — or the closing "--".
            var next = range.upperBound
            if next < body.endIndex, body[next] == UInt8(ascii: "-") { break }
            if next < body.endIndex, body[next] == 13 { next = body.index(after: next) }
            if next < body.endIndex, body[next] == 10 { next = body.index(after: next) }
            previousEnd = next
            searchFrom = next
            if searchFrom >= body.endIndex { break }
        }
        // A part cut short by the size limit is still worth showing.
        if pieces.isEmpty, let start = previousEnd, start < body.endIndex {
            pieces.append(Data(body[start...]))
        }
        return pieces
    }

    static func decoded(_ body: Data, encoding: String) -> Data {
        switch encoding {
        case "base64":
            let text = String(data: body, encoding: .isoLatin1) ?? ""
            let stripped = text.filter { !$0.isWhitespace }
            return Data(base64Encoded: stripped, options: .ignoreUnknownCharacters) ?? body
        case "quoted-printable":
            return quotedPrintable(body)
        default:
            return body
        }
    }

    /// `=XX` is a byte written in hex; `=` at the end of a line is a line that was too long and
    /// isn't really a line break at all.
    static func quotedPrintable(_ body: Data) -> Data {
        var output = Data()
        let bytes = [UInt8](body)
        var index = 0
        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "=") else {
                output.append(bytes[index])
                index += 1
                continue
            }
            if index + 2 < bytes.count,
               let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) {
                output.append(high << 4 | low)
                index += 3
            } else if index + 2 < bytes.count, bytes[index + 1] == 13, bytes[index + 2] == 10 {
                index += 3
            } else if index + 1 < bytes.count, bytes[index + 1] == 10 {
                index += 2
            } else {
                output.append(bytes[index])
                index += 1
            }
        }
        return output
    }

    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        default: return nil
        }
    }

    static func parameter(_ name: String, in value: String) -> String? {
        for piece in value.split(separator: ";").dropFirst() {
            let pair = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces).lowercased() == name
            else { continue }
            return pair[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    // MARK: - Making HTML readable

    /// Not a rendering — a reading. Scripts and styles go, block tags become line breaks, the
    /// rest of the tags go, and the entities become the characters they stand for.
    static func readable(fromHTML html: String) -> String {
        var text = html
        for tag in ["script", "style", "head"] {
            text = removing("<\(tag)", until: "</\(tag)>", in: text)
        }
        for (pattern, replacement) in [
            ("<br", "\n<br"), ("</p", "\n</p"), ("</div", "\n</div"), ("</tr", "\n</tr"),
            ("</h1", "\n</h1"), ("</h2", "\n</h2"), ("</h3", "\n</h3"), ("</li", "\n</li"),
        ] {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .caseInsensitive)
        }
        text = removingTags(from: text)
        text = decodingEntities(in: text)
        return tidied(text)
    }

    private static func removing(_ opening: String, until closing: String, in text: String) -> String {
        var result = text
        while let start = result.range(of: opening, options: .caseInsensitive) {
            guard let end = result.range(of: closing, options: .caseInsensitive, range: start.upperBound..<result.endIndex) else {
                result = String(result[..<start.lowerBound])
                break
            }
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result
    }

    private static func removingTags(from text: String) -> String {
        var result = ""
        var insideTag = false
        for character in text {
            if character == "<" { insideTag = true; continue }
            if character == ">" { insideTag = false; continue }
            if !insideTag { result.append(character) }
        }
        return result
    }

    static func decodingEntities(in text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, character) in [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&apos;", "'"), ("&#39;", "'"), ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
            ("&rsquo;", "\u{2019}"), ("&lsquo;", "\u{2018}"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
        ] {
            result = result.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        // Anything else numeric: &#1575; is an Arabic letter, and there are a lot of them.
        while let start = result.range(of: "&#"), let end = result.range(of: ";", range: start.upperBound..<result.endIndex) {
            let digits = result[start.upperBound..<end.lowerBound]
            let value = digits.hasPrefix("x") || digits.hasPrefix("X")
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            guard let value, let scalar = Unicode.Scalar(value) else {
                result.replaceSubrange(start.lowerBound..<end.upperBound, with: "")
                continue
            }
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: String(Character(scalar)))
        }
        return result
    }

    /// Mail is full of blank lines that were layout rather than paragraphs: a run of them becomes
    /// the single one that means "new paragraph", and the trailing whitespace of every line goes.
    static func tidied(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var result: [String] = []
        var blanks = 0
        for line in lines {
            if line.isEmpty {
                blanks += 1
                if blanks > 1 { continue }
            } else {
                blanks = 0
            }
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
