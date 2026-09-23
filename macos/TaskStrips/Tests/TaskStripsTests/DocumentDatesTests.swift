import XCTest
@testable import TaskStrips

/// Reading the dates off a document, and knowing which of them anyone cares about.
final class DocumentDatesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)   // 21 Sep 2026

    private func date(_ day: Int, _ month: Int, _ year: Int) -> Date {
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }

    private func day(of found: FoundDate?) -> DateComponents? {
        guard let found else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day, .month, .year], from: found.date)
    }

    func testADateInALineIsFoundWithTheLineAroundIt() throws {
        let found = DocumentDates.find(in: "Invoice 4471\nPayment due 14 March 2027\nThank you", now: now)
        let first = try XCTUnwrap(found.first)
        XCTAssertEqual(day(of: first)?.day, 14)
        XCTAssertEqual(day(of: first)?.month, 3)
        XCTAssertEqual(day(of: first)?.year, 2027)
        XCTAssertEqual(first.context, "Payment due 14 March 2027")
        XCTAssertEqual(first.kind, .deadline)
    }

    /// The point of the whole thing: an invoice has half a dozen dates and one of them matters.
    func testTheDateThatMattersComesFirst() throws {
        let document = """
        ACME Trading Company
        Invoice date: 01 February 2027
        Printed 02 February 2027
        Amount due: KD 412.500
        Payment due by 15 March 2027
        © 2019 ACME Trading
        """
        let found = DocumentDates.find(in: document, now: now)
        XCTAssertEqual(found.first?.kind, .deadline)
        XCTAssertEqual(day(of: found.first)?.day, 15)
        // The issue date is still there, at the bottom where it belongs.
        XCTAssertEqual(found.last?.kind, .issued)
    }

    func testWhatTheLineCallsItIsWhatItIs() {
        XCTAssertEqual(DocumentDates.meaning(of: "Expiry date: 14/03/2027"), .expiry)
        XCTAssertEqual(DocumentDates.meaning(of: "Valid until 14/03/2027"), .expiry)
        XCTAssertEqual(DocumentDates.meaning(of: "Last day to pay: 14/03/2027"), .deadline)
        XCTAssertEqual(DocumentDates.meaning(of: "Your appointment is on 14/03/2027"), .appointment)
        XCTAssertEqual(DocumentDates.meaning(of: "Issued 14/03/2027"), .issued)
        XCTAssertEqual(DocumentDates.meaning(of: "14/03/2027"), .unknown)
    }

    /// Half the documents here are in Arabic, and an Arabic OCR is full of Arabic-Indic digits.
    func testArabicDigitsAreReadAsNumbers() {
        XCTAssertEqual(DocumentDates.normalisingDigits("١٤/٠٣/٢٠٢٧"), "14/03/2027")
        XCTAssertEqual(DocumentDates.normalisingDigits("٠١٢٣٤٥٦٧٨٩"), "0123456789")
        // Persian digits, which some fonts produce instead.
        XCTAssertEqual(DocumentDates.normalisingDigits("۱۴/۰۳"), "14/03")
        // Everything else is left exactly as it was.
        XCTAssertEqual(DocumentDates.normalisingDigits("تاريخ الانتهاء"), "تاريخ الانتهاء")
    }

    func testAnArabicLabelIsUnderstoodToo() {
        let found = DocumentDates.find(in: "تاريخ الانتهاء: ١٤/٠٣/٢٠٢٧", now: now)
        XCTAssertEqual(found.first?.kind, .expiry)
        XCTAssertEqual(day(of: found.first)?.year, 2027)
    }

    /// A bilingual document labels the same date twice, and it's still one date.
    func testTheSameDateTwiceIsOneDate() {
        let found = DocumentDates.find(
            in: "Expiry date: 14 March 2027\nتاريخ الانتهاء: 14 March 2027", now: now
        )
        XCTAssertEqual(found.count, 1)
    }

    /// Between two labels for one date, the one that says what it's for wins.
    func testTheLabelledOneWinsOverThePlainOne() throws {
        let found = DocumentDates.find(in: "14 March 2027\nPayment due 14 March 2027", now: now)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.kind, .deadline)
    }

    /// Last year's deadline is history, and history isn't what anybody opened this for.
    func testDatesThatHavePassedSortAfterTheOnesThatHaveNot() throws {
        let found = DocumentDates.ordered(
            [
                FoundDate(date: date(1, 1, 2020), matched: "", context: "", kind: .deadline),
                FoundDate(date: date(1, 1, 2030), matched: "", context: "", kind: .issued),
            ],
            now: now
        )
        XCTAssertEqual(found.first?.kind, .issued)
    }

    func testTheSoonestComesFirstAmongEqualKinds() {
        let found = DocumentDates.ordered(
            [
                FoundDate(date: date(1, 6, 2030), matched: "", context: "", kind: .deadline),
                FoundDate(date: date(1, 1, 2030), matched: "", context: "", kind: .deadline),
            ],
            now: now
        )
        XCTAssertEqual(day(of: found.first)?.month, 1)
    }

    func testADocumentWithNoDatesGivesNothingRatherThanNonsense() {
        XCTAssertTrue(DocumentDates.find(in: "Dear Sir,\n\nThank you for your letter.\n\nYours,", now: now).isEmpty)
        XCTAssertTrue(DocumentDates.find(in: "", now: now).isEmpty)
    }

    func testALineTheWidthOfAPageIsShortenedForTheList() {
        let long = String(repeating: "word ", count: 40)
        XCTAssertTrue(DocumentDates.shortened(long).hasSuffix("…"))
        XCTAssertEqual(DocumentDates.shortened("short line"), "short line")
    }

    /// Only the things that can hold words are offered a date search.
    func testOnlyReadableFilesAreOffered() {
        for name in ["invoice.pdf", "scan.png", "photo.HEIC", "receipt.jpg"] {
            XCTAssertTrue(DocumentTextReader.canRead(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
        for name in ["note.m4a", "clip.mov", "data.zip"] {
            XCTAssertFalse(DocumentTextReader.canRead(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
    }
}

/// The trap underneath all of this: the words that mark an important date are the words a date
/// detector reads as "some time from now".
final class DocumentDateWordTests: XCTestCase {
    private func year(of text: String) -> Int? {
        guard let found = DocumentDates.find(in: text).first else { return nil }
        return Calendar(identifier: .gregorian).component(.year, from: found.date)
    }

    func testTheWordsThatConfuseADateDetectorAreBlankedOut() {
        XCTAssertEqual(DocumentDates.sanitised("Payment due 14 March 2027"), "Payment     14 March 2027")
        XCTAssertEqual(DocumentDates.sanitised("Valid until 14 March 2027"), "Valid       14 March 2027")
        // Only whole words: a name is not a preposition.
        XCTAssertEqual(DocumentDates.sanitised("Byron Ltd"), "Byron Ltd")
        XCTAssertEqual(DocumentDates.sanitised("Induction day"), "Induction day")
    }

    /// Each of these read as today's date before the blanking went in.
    func testTheDatesThoseLinesActuallyCarry() {
        XCTAssertEqual(year(of: "Payment due 14 March 2027"), 2027)
        XCTAssertEqual(year(of: "Payment due by 15 March 2027"), 2027)
        XCTAssertEqual(year(of: "Valid until 14 March 2029"), 2029)
        XCTAssertEqual(year(of: "Pay before 1 Jan 2028"), 2028)
        XCTAssertEqual(year(of: "Renewal due 30/06/2031"), 2031)
    }

    func testTheLineIsStillReportedAsItWasWritten() throws {
        let found = try XCTUnwrap(DocumentDates.find(in: "Payment due 14 March 2027").first)
        XCTAssertEqual(found.context, "Payment due 14 March 2027")
        XCTAssertEqual(found.matched, "14 March 2027")
    }
}

/// What Vision actually read off a rendered invoice, word for word, kept as the shape of a real
/// document rather than one written to suit the parser.
final class ScannedInvoiceTests: XCTestCase {
    private let read = """
    ACME TRADING COMPANY
    Invoice date: 01 February 2027
    Amount due: KD 412.500
    Payment due by 15 March 2027
    Expiry date: 30/06/2028
    """

    func testTheDeadlineIsWhatTheDocumentIsOffering() throws {
        let found = DocumentDates.find(in: read, now: Date(timeIntervalSince1970: 1_790_000_000))
        let first = try XCTUnwrap(found.first)
        XCTAssertEqual(first.kind, .deadline)
        XCTAssertEqual(
            Calendar(identifier: .gregorian).dateComponents([.day, .month, .year], from: first.date),
            DateComponents(year: 2027, month: 3, day: 15)
        )
        XCTAssertEqual(first.context, "Payment due by 15 March 2027")
    }

    func testTheExpiryAndTheIssueDateAreBothThereInOrder() {
        let found = DocumentDates.find(in: read, now: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(found.map(\.kind), [.deadline, .expiry, .issued])
    }

    /// "Amount due: KD 412.500" is money, not a date, however much it looks like one to a parser
    /// that has been told to expect dates.
    func testAnAmountOfMoneyIsNotADate() {
        let found = DocumentDates.find(in: "Amount due: KD 412.500")
        XCTAssertTrue(found.isEmpty, found.map(\.matched).joined(separator: ", "))
    }
}
