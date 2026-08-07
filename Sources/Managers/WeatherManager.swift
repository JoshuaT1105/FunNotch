//
//  WeatherManager.swift
//  FunNotch
//
//  Current conditions for the weather widget, from Open-Meteo — no API key and
//  no account. Location comes from CoreLocation; if the user says no, the
//  widget just says so rather than the app pretending otherwise.
//
//  Wi-Fi network names also need location access on modern macOS, so the same
//  authorisation covers both widgets.
//

import Combine
import CoreLocation
import AppKit
import CoreWLAN
import Foundation

@MainActor
final class WeatherManager: NSObject, ObservableObject {
    static let shared = WeatherManager()

    struct Conditions: Equatable {
        var temperatureCelsius: Double
        var weatherCode: Int
        var isDay: Bool
        var placeName: String?
    }

    @Published private(set) var conditions: Conditions?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastError: String?
    /// Current Wi-Fi network, which also needs location permission to read.
    @Published private(set) var wifiNetwork: String?

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var subscribers = 0
    private var lastFetch: Date?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorization = locationManager.authorizationStatus
    }

    func addSubscriber() {
        subscribers += 1
        if subscribers == 1 { start() }
    }

    func removeSubscriber() {
        subscribers = max(subscribers - 1, 0)
        if subscribers == 0 { stop() }
    }

    private func start() {
        guard timer == nil else { return }

        if authorization == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        refresh()

        let timer = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        readWiFi()

        guard isLocationAuthorized else {
            lastError = "Location access needed"
            return
        }
        locationManager.requestLocation()
    }

    /// True once the user has said yes. macOS hides the Wi-Fi network name
    /// behind location access as well, not just the weather.
    var isLocationAuthorized: Bool {
        authorization == .authorized || authorization == .authorizedAlways
    }

    /// Whether there is a Wi-Fi interface associated with a network at all,
    /// which is knowable even when the name is not.
    @Published private(set) var isWiFiConnected = false

    private func readWiFi() {
        let interface = CWWiFiClient.shared().interface()
        isWiFiConnected = interface?.powerOn() == true && interface?.serviceActive() == true
        wifiNetwork = interface?.ssid()
    }

    private func fetch(for location: CLLocation) {
        // Open-Meteo is rate-limited by courtesy, so keep it to a slow trickle.
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 300 { return }
        lastFetch = Date()

        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            guard let data, error == nil else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.lastError = "Weather unavailable" }
                }
                return
            }

            struct Response: Decodable {
                struct Current: Decodable {
                    let temperature_2m: Double
                    let weather_code: Int
                    let is_day: Int
                }
                let current: Current
            }

            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.lastError = nil
                    self.conditions = Conditions(
                        temperatureCelsius: decoded.current.temperature_2m,
                        weatherCode: decoded.current.weather_code,
                        isDay: decoded.current.is_day == 1,
                        placeName: self.conditions?.placeName
                    )
                }
            }
        }.resume()

        // A place name is nice to have but never worth blocking on.
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let name = placemarks?.first?.locality else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.conditions?.placeName = name }
            }
        }
    }

    // MARK: - Presentation

    var temperatureText: String? {
        guard let conditions else { return nil }
        let usesFahrenheit = Locale.current.measurementSystem == .us
        let value = usesFahrenheit
            ? conditions.temperatureCelsius * 9 / 5 + 32
            : conditions.temperatureCelsius
        return "\(Int(round(value)))°"
    }

    /// WMO weather code → SF Symbol.
    var symbolName: String {
        guard let conditions else { return "cloud" }
        let isDay = conditions.isDay
        switch conditions.weatherCode {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    /// Asks for access, or sends the user to Privacy settings if they already
    /// said no — macOS will not ask twice.
    func requestAccess() {
        switch authorization {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices") {
                NSWorkspace.shared.open(url)
            }
        default:
            refresh()
        }
    }
}

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.authorization = status
                if status == .authorized || status == .authorizedAlways {
                    self.lastError = nil
                    self.refresh()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.fetch(for: location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.lastError = "Location unavailable" }
        }
    }
}

/// Moon phase, computed rather than fetched.
enum MoonPhase {
    /// 0 = new, 0.5 = full, wrapping at 1.
    static func fraction(on date: Date = Date()) -> Double {
        // Days since a known new moon (2000-01-06 18:14 UTC).
        let reference = Date(timeIntervalSince1970: 947_182_440)
        let synodicMonth = 29.530588853
        let days = date.timeIntervalSince(reference) / 86400
        let phase = (days / synodicMonth).truncatingRemainder(dividingBy: 1)
        return phase < 0 ? phase + 1 : phase
    }

    static func symbol(on date: Date = Date()) -> String {
        switch fraction(on: date) {
        case ..<0.0625, 0.9375...: return "moonphase.new.moon"
        case ..<0.1875: return "moonphase.waxing.crescent"
        case ..<0.3125: return "moonphase.first.quarter"
        case ..<0.4375: return "moonphase.waxing.gibbous"
        case ..<0.5625: return "moonphase.full.moon"
        case ..<0.6875: return "moonphase.waning.gibbous"
        case ..<0.8125: return "moonphase.last.quarter"
        default: return "moonphase.waning.crescent"
        }
    }

    static func name(on date: Date = Date()) -> String {
        switch fraction(on: date) {
        case ..<0.0625, 0.9375...: return "New"
        case ..<0.1875: return "Waxing crescent"
        case ..<0.3125: return "First quarter"
        case ..<0.4375: return "Waxing gibbous"
        case ..<0.5625: return "Full"
        case ..<0.6875: return "Waning gibbous"
        case ..<0.8125: return "Last quarter"
        default: return "Waning crescent"
        }
    }
}
