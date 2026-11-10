import AppKit
import SwiftUI
import CoreLocation

struct WeatherNow: Equatable {
    var temp: Int
    var code: Int
    var high: Int
    var low: Int
    var rainChance: Int
    var place: String

    var symbol: String { WeatherService.symbol(for: code) }
    var summary: String { WeatherService.summary(for: code) }
}

/// Current weather from Open-Meteo (free, no API key) using your Mac's location.
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var weather: WeatherNow?
    @Published private(set) var denied = false

    private let manager = CLLocationManager()
    private var location: CLLocation?
    private var timer: Timer?
    private var lastFetch = Date.distantPast

    func start() {
        guard Prefs.showWeather, timer == nil else { return }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: denied = true
        default: manager.requestLocation()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.manager.requestLocation()
            self?.fetch()
        }
    }

    func refresh() {
        manager.requestLocation()
        fetch()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted: denied = true
        case .notDetermined: break
        default:
            denied = false
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let moved = location.map { $0.distance(from: loc) > 5000 } ?? true
        location = loc
        if moved || Date().timeIntervalSince(lastFetch) > 25 * 60 { fetch() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("Location error: \(error.localizedDescription)")
    }

    // MARK: Open-Meteo

    private struct Response: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]?
        }
        let current: Current
        let daily: Daily
    }

    private func fetch() {
        guard Prefs.showWeather, let loc = location else { return }
        lastFetch = Date()
        let unit = Locale.current.measurementSystem == .us ? "fahrenheit" : "celsius"
        let lat = String(format: "%.3f", loc.coordinate.latitude)
        let lon = String(format: "%.3f", loc.coordinate.longitude)
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,weather_code"
            + "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            + "&forecast_days=1&timezone=auto&temperature_unit=\(unit)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let r = try? JSONDecoder().decode(Response.self, from: data) else { return }
            let rain = (r.daily.precipitation_probability_max?.first ?? nil) ?? 0
            var w = WeatherNow(temp: Int(r.current.temperature_2m.rounded()), code: r.current.weather_code,
                               high: Int((r.daily.temperature_2m_max.first ?? 0).rounded()),
                               low: Int((r.daily.temperature_2m_min.first ?? 0).rounded()),
                               rainChance: rain, place: "")
            CLGeocoder().reverseGeocodeLocation(loc) { marks, _ in
                w.place = marks?.first?.locality ?? ""
                DispatchQueue.main.async { self?.weather = w }
            }
        }.resume()
    }

    // MARK: WMO weather codes

    static func symbol(for code: Int) -> String {
        let night: Bool = {
            let h = Calendar.current.component(.hour, from: Date())
            return h < 6 || h >= 20
        }()
        switch code {
        case 0: return night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func summary(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 80, 81, 82: return "Showers"
        case 71, 73, 75, 77, 85, 86: return "Snow"
        case 95, 96, 99: return "Thunderstorm"
        default: return "—"
        }
    }
}
