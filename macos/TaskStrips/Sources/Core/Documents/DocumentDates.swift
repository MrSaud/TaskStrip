import Foundation

/// A date found in a document, and enough of the line around it to know what it was for.
struct FoundDate: Identifiable, Equatable {
    var id: String { "\(date.timeIntervalSince1970)-\(matched)" }
    var date: Date
    /// The words that were read as a date, as they appear in the document.
    var matched: String
    /// The line it was found on — "Expiry date: 14/03/2027" — which is what tells somebody
    /// whether this is the date they were looking for.
    var context: String
    /// What the line calls it, where it calls it anything: an expiry, a due date, a deadline.
    var kind: DocumentDates.Meaning
}

/// Reading the dates out of a document's text, and working out which ones matter.
///
/// A scanned invoice has half a dozen dates on it — printed, issued, due, paid by, the copyright
/// line at the bottom — and only one or two are worth putting on a strip. The words around a date
/// are what say which: "due", "expires", "deadline", "صالح حتى". That's the whole trick here, and
/// it's why this reads lines rather than dates alone.
enum DocumentDates {
    /// What the document seems to think the date is for. The order is the order of usefulness.
    enum Meaning: String, CaseIterable, Equatable {
        case deadline
        case expiry
        case appointment
        case issued
        case unknown

        var label: String {
            switch self {
            case .deadline: return "Deadline"
            case .expiry: return "Expires"
            case .appointment: return "Appointment"
            case .issued: return "Issued"
            case .unknown: return "Date"
            }
        }

        /// Lower sorts first.
        var rank: Int {
            switch self {
            case .deadline: return 0
            case .expiry: return 1
            case .appointment: return 2
            case .unknown: return 3
            case .issued: return 4
            }
        }

        /// Both languages, because half the documents here are in Arabic and a bilingual invoice
        /// often labels the same date twice.
        var words: [String] {
            switch self {
            case .deadline:
                return ["due", "payable", "deadline", "last day", "pay by", "payment date",
                        "الاستحقاق", "آخر موعد", "تاريخ الدفع", "موعد السداد"]
            case .expiry:
                return ["expiry", "expires", "expiration", "valid until", "valid through",
                        "renewal", "renew by", "الانتهاء", "انتهاء", "صالح حتى", "تجديد"]
            case .appointment:
                return ["appointment", "meeting", "visit", "interview", "scheduled",
                        "موعد", "اجتماع", "زيارة", "مقابلة"]
            case .issued:
                return ["issued", "issue date", "printed", "dated", "invoice date", "created",
                        "الإصدار", "الطباعة", "تحرير"]
            case .unknown:
                return []
            }
        }
    }

    /// Every date in the text, best first.
    static func find(in text: String, now: Date = .now) -> [FoundDate] {
        let normalised = normalisingDigits(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }

        var found: [FoundDate] = []
        for line in normalised.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            // Detected on a line with its label words blanked out — see `sanitised`.
            let readable = sanitised(text)
            let range = NSRange(readable.startIndex..., in: readable)
            for match in detector.matches(in: readable, range: range) {
                guard let date = match.date, let matchedRange = Range(match.range, in: readable) else { continue }
                found.append(
                    FoundDate(
                        date: date,
                        matched: String(readable[matchedRange]).trimmingCharacters(in: .whitespaces),
                        context: shortened(text),
                        kind: meaning(of: text)
                    )
                )
            }
        }
        return ordered(deduplicated(found), now: now)
    }

    /// The words that turn a date into a duration, as far as a date detector is concerned.
    ///
    /// This is the trap in the whole feature. Foundation reads "Payment due 14 March 2027" as a
    /// phrase about how long something takes and answers with *today* — the very word that marks
    /// the date worth having is the word that ruins it. Blanked out, the same line reads as the
    /// fourteenth of March, which is what it says.
    ///
    /// Blanked rather than deleted so the line keeps its length, and what was matched can still
    /// be pointed at in the original.
    static let confusingWords: Set<String> = [
        "due", "by", "until", "till", "before", "after", "within", "from", "through", "in",
    ]

    static func sanitised(_ line: String) -> String {
        var output = ""
        var word = ""

        func flush() {
            guard !word.isEmpty else { return }
            let bare = word.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            output += confusingWords.contains(bare) ? String(repeating: " ", count: word.count) : word
            word = ""
        }

        for character in line {
            if character.isLetter {
                word.append(character)
            } else {
                flush()
                output.append(character)
            }
        }
        flush()
        return output
    }

    /// What the line says this date is for.
    static func meaning(of line: String) -> Meaning {
        let text = line.lowercased()
        for meaning in Meaning.allCases where meaning != .unknown {
            if meaning.words.contains(where: { text.contains($0.lowercased()) }) { return meaning }
        }
        return .unknown
    }

    /// The same date labelled twice — a bilingual invoice does this on purpose — is one date, and
    /// the line that names what it's for wins.
    static func deduplicated(_ found: [FoundDate]) -> [FoundDate] {
        var best: [Date: FoundDate] = [:]
        for date in found {
            if let existing = best[date.date], existing.kind.rank <= date.kind.rank { continue }
            best[date.date] = date
        }
        return Array(best.values)
    }

    /// Deadlines first, then expiries, then the rest; inside a kind, the soonest first. A date
    /// that has already passed sorts after every date that hasn't — last year's deadline is
    /// history, and history isn't what anybody opened this for.
    static func ordered(_ found: [FoundDate], now: Date = .now) -> [FoundDate] {
        found.sorted { one, other in
            let past = (one.date < now, other.date < now)
            if past.0 != past.1 { return !past.0 }
            if one.kind.rank != other.kind.rank { return one.kind.rank < other.kind.rank }
            return past.0 ? one.date > other.date : one.date < other.date
        }
    }

    /// Arabic-Indic digits as their western equivalents: a date detector doesn't read ١٤/٠٣/٢٠٢٧,
    /// and an OCR of an Arabic document is full of them.
    static func normalisingDigits(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        for character in text.unicodeScalars {
            switch character.value {
            case 0x0660...0x0669:
                output.append(Character(UnicodeScalar(character.value - 0x0660 + 48)!))
            case 0x06F0...0x06F9:   // Persian digits, which some fonts produce instead
                output.append(Character(UnicodeScalar(character.value - 0x06F0 + 48)!))
            default:
                output.unicodeScalars.append(character)
            }
        }
        return output
    }

    /// A line of a document can be the width of a page; a list needs a phrase.
    static func shortened(_ line: String, limit: Int = 90) -> String {
        guard line.count > limit else { return line }
        return String(line.prefix(limit)) + "…"
    }
}
