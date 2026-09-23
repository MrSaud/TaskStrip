import CoreLocation
import Foundation

/// Asks the device where it is, once, and the service what it's like there.
///
/// Where matters only to three decimal places — a street is as good as a city for a temperature,
/// and it keeps the request from being a fingerprint. Nothing is stored anywhere but this
/// device's own defaults, and nothing is asked for at all until the board is told to show it.
@MainActor
final class BoardWeatherReader: NSObject, ObservableObject {
    static let shared = BoardWeatherReader()

    @Published private(set) var weather: BoardWeather?

    private let locations = CLLocationManager()
    private let cache = BoardWeatherCache()
    private var asking = false

    override init() {
        super.init()
        locations.delegate = self
        locations.desiredAccuracy = kCLLocationAccuracyKilometer
        weather = cache.last
    }

    /// What's stopping a reading, if anything — so a board with nothing to show can say why
    /// rather than showing nothing and looking broken.
    enum State: Equatable {
        case reading
        case refused
        case waiting
        case unavailable
    }

    var isAllowed: Bool {
        switch locations.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    var state: State {
        switch locations.authorizationStatus {
        case .denied, .restricted: return .refused
        case .authorizedAlways, .authorizedWhenInUse: return weather == nil ? .waiting : .reading
        default: return weather == nil ? .unavailable : .reading
        }
    }

    /// Reads it again if what's cached has gone stale. Safe to call as often as the board likes;
    /// `force` is for the person tapping it, who means now rather than when it suits.
    func refresh(now: Date = .now, force: Bool = false) {
        if !force, let weather, weather.isFresh(now: now) { return }
        if force { asking = false }
        guard !asking else { return }
        asking = true

        switch locations.authorizationStatus {
        case .notDetermined:
            locations.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locations.requestLocation()
        default:
            asking = false
        }
    }

    private func read(at location: CLLocation) {
        guard let url = BoardWeather.endpoint(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude
        ) else {
            asking = false
            return
        }
        Task { [weak self] in
            defer { Task { @MainActor in self?.asking = false } }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let reading = BoardWeather.read(data)
            else { return }
            await MainActor.run {
                self?.weather = reading
                self?.cache.last = reading
            }
        }
    }
}

extension BoardWeatherReader: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard isAllowed else {
                asking = false
                return
            }
            locations.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in read(at: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in asking = false }
    }
}
