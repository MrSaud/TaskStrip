import Foundation

/// What it's like outside, beside the clock.
///
/// Open-Meteo rather than WeatherKit: no key, no account, and no capability to add to an App ID
/// before Phase 7 — the same reasoning that put the quote of the day on zenquotes. Like the
/// quote, it's a service nobody set up, so it can be switched off.
struct BoardWeather: Equatable, Codable {
    /// Always Celsius from the service; the label converts where a place prefers Fahrenheit.
    var celsius: Double
    /// Open-Meteo's WMO code, which says whether it's clear, raining or snowing.
    var code: Int
    var measuredAt: Date

    static func endpoint(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            // Three decimal places is a neighbourhood: enough for a temperature, and not a
            // fingerprint of where someone is standing.
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
        ]
        return components?.url
    }

    /// Reads the reply. Separated from the fetching so the shape of what comes back is pinned by
    /// a test rather than by a service being up.
    static func read(_ data: Data, now: Date = .now) -> BoardWeather? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = object["current"] as? [String: Any],
              let temperature = current["temperature_2m"] as? Double
        else { return nil }
        return BoardWeather(
            celsius: temperature,
            code: (current["weather_code"] as? Int) ?? 0,
            measuredAt: now
        )
    }

    /// Rounded, in the unit the place uses: "24°" here, "75°" in Miami.
    func label(locale: Locale = .current) -> String {
        let fahrenheit = locale.measurementSystem == .us
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    /// The sky, as an SF Symbol. WMO's codes in the groups they actually come in.
    var symbol: String {
        switch code {
        case 0: return "sun.max"
        case 1, 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51...57: return "cloud.drizzle"
        case 61...67, 80...82: return "cloud.rain"
        case 71...77, 85, 86: return "cloud.snow"
        case 95...99: return "cloud.bolt.rain"
        default: return "thermometer.medium"
        }
    }

    /// Half an hour is often enough for weather, and rare enough to be no burden on anyone.
    static let freshFor: TimeInterval = 30 * 60

    func isFresh(now: Date = .now) -> Bool {
        now.timeIntervalSince(measuredAt) < Self.freshFor && now >= measuredAt
    }
}

/// The last reading, kept so the board shows something the instant it opens rather than a gap
/// that fills in a second later.
struct BoardWeatherCache {
    private let defaults: UserDefaults
    private static let key = "boardWeather.last"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var last: BoardWeather? {
        get {
            guard let data = defaults.data(forKey: Self.key) else { return nil }
            return try? JSONDecoder().decode(BoardWeather.self, from: data)
        }
        nonmutating set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: Self.key)
                return
            }
            defaults.set(data, forKey: Self.key)
        }
    }
}
