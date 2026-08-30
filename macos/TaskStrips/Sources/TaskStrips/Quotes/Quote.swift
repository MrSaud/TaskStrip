import Foundation

/// Mirrors Quote.kt — a line and whoever said it.
struct Quote: Equatable {
    var text: String
    var author: String
}

/// The quote of the day, fetched once and then left alone until tomorrow.
///
/// Mirrors QuoteOfTheDayApi.kt and QuoteCache.kt. On Android this is the app's only network call;
/// here it's the only one that isn't Google Drive, and it's the only one that reaches a service
/// the user didn't set up — which is why it can be switched off.
enum QuoteOfTheDay {
    static let endpoint = URL(string: "https://zenquotes.io/api/today")!

    /// Reads the reply. Separated from the fetching so the shape of what comes back is pinned by
    /// a test rather than by a service being up.
    static func quote(from data: Data) -> Quote? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first
        else { return nil }

        let text = (first["q"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (first["a"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // A quote with nobody attached still reads fine; one with no words doesn't.
        return Quote(text: text, author: author.isEmpty ? "Unknown" : author)
    }

    /// Nil on anything going wrong — a missing quote is a card that doesn't appear, not an error
    /// worth interrupting anyone for.
    static func fetch(session: URLSession = .shared) async -> Quote? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return quote(from: data)
    }
}

/// One quote per calendar day, so the board reaches the network once and not once per launch.
struct QuoteCache {
    private let defaults: UserDefaults
    private static let dateKey = "quoteOfDay.date"
    private static let textKey = "quoteOfDay.text"
    private static let authorKey = "quoteOfDay.author"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The local calendar day, which is what "today's quote" means to a person — not 24 hours
    /// since the last fetch.
    static func dayKey(for date: Date = .now, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func quote(on date: Date = .now, timeZone: TimeZone = .current) -> Quote? {
        guard defaults.string(forKey: Self.dateKey) == Self.dayKey(for: date, timeZone: timeZone),
              let text = defaults.string(forKey: Self.textKey),
              let author = defaults.string(forKey: Self.authorKey)
        else { return nil }
        return Quote(text: text, author: author)
    }

    func save(_ quote: Quote, on date: Date = .now, timeZone: TimeZone = .current) {
        defaults.set(Self.dayKey(for: date, timeZone: timeZone), forKey: Self.dateKey)
        defaults.set(quote.text, forKey: Self.textKey)
        defaults.set(quote.author, forKey: Self.authorKey)
    }
}
