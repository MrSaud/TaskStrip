import Foundation
import PDFKit
import Vision

/// Getting the words out of a document, so the dates in it can be found.
///
/// Two ways in, in this order: a PDF that was made on a computer already carries its text, and
/// taking it is instant and perfect. Everything else — a photograph of a letter, a scan, a
/// screenshot — goes through Vision, which reads it the way a person would.
///
/// All of it happens on the device. Nothing about someone's documents is sent anywhere.
enum DocumentTextReader {
    enum Failure: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Couldn't read \"\(name)\"."
            }
        }
    }

    /// Both languages, Arabic first, and spelled the way Vision spells them.
    ///
    /// This list is fussier than it looks. "ar" is not an identifier Vision knows — it wants
    /// "ar-SA" — and one it doesn't know doesn't fail loudly: it reads the English and silently
    /// returns nothing at all for the Arabic. A whole Arabic document came back empty that way.
    static let wantedLanguages = ["ar-SA", "en-US"]

    /// Only the ones this device actually offers, so a language dropped or renamed in a future
    /// release can't take the rest down with it.
    static func languages(for request: VNRecognizeTextRequest) -> [String] {
        let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
        let wanted = wantedLanguages.filter { supported.contains($0) }
        return wanted.isEmpty ? ["en-US"] : wanted
    }

    /// How many pages of a long PDF to read. The dates that matter are at the front of a letter
    /// or an invoice, and a hundred-page contract shouldn't hold up a sheet.
    static let pageLimit = 12

    static func text(of url: URL) async throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            return try await pdfText(of: url)
        }
        guard let image = image(at: url) else { throw Failure.unreadable(url.lastPathComponent) }
        return try await recognise(image)
    }

    /// Whether this is worth offering at all: a voice note has no dates in it to find.
    static func canRead(_ url: URL) -> Bool {
        ["pdf", "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"]
            .contains(url.pathExtension.lowercased())
    }

    // MARK: - PDFs

    private static func pdfText(of url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable(url.lastPathComponent) }
        let pages = min(document.pageCount, pageLimit)

        var written = ""
        for index in 0..<pages {
            guard let page = document.page(at: index) else { continue }
            written += (page.string ?? "") + "\n"
        }
        // A scan saved as a PDF is a picture of a page: it carries no text at all, and has to be
        // read rather than copied.
        guard written.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else {
            return try await scannedPDFText(document, pages: pages)
        }
        return written
    }

    private static func scannedPDFText(_ document: PDFDocument, pages: Int) async throws -> String {
        var written = ""
        for index in 0..<pages {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            // Twice the page size: OCR of a 72-dpi render misreads digits, and digits are the
            // whole point here.
            let scale: CGFloat = 2
            let width = Int(bounds.width * scale)
            let height = Int(bounds.height * scale)
            guard width > 0, height > 0,
                  let context = CGContext(
                      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                  )
            else { continue }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            guard let image = context.makeImage() else { continue }
            written += try await recognise(image) + "\n"
        }
        return written
    }

    // MARK: - Pictures

    private static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Vision's own text recognition, asked for accuracy rather than speed: this runs once, on a
    /// document somebody is waiting to see the dates from.
    private static func recognise(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = Self.languages(for: request)

            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
