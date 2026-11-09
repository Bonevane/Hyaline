// Weather from Open-Meteo (free, no key), for your location.

import AppKit
import EventKit
import CoreLocation
import IOKit

struct HourWeather: Identifiable { let id: Date; let temp: Double; let code: Int }
struct DayWeather: Identifiable { let id: Date; let low: Double; let high: Double; let code: Int }

final class WeatherStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherStore()
    @Published var place = "Lahore"
    @Published var current: Double?
    @Published var code = 0
    @Published var hours: [HourWeather] = []
    @Published var days: [DayWeather] = []
    @Published var sunset: Date?
    private let location = CLLocationManager()
    private var coordinate = CLLocationCoordinate2D(latitude: SunTimes.latitude, longitude: SunTimes.longitude)
    private var started = false
    private var lastFetch = Date.distantPast

    func start() {
        guard !started else { return }
        started = true
        if !GalleryMode.on {
            location.delegate = self
            location.desiredAccuracy = kCLLocationAccuracyKilometer
            location.requestWhenInUseAuthorization()
            location.startUpdatingLocation()
        }
        fetch()
        let t = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.fetch() }
        t.tolerance = 120
        RunLoop.main.add(t, forMode: .common)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        manager.stopUpdatingLocation()
        coordinate = loc.coordinate
        SunTimes.override = (loc.coordinate.latitude, loc.coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(loc) { marks, _ in
            if let m = marks?.first { DispatchQueue.main.async { self.place = m.locality ?? m.administrativeArea ?? self.place } }
        }
        lastFetch = .distantPast
        fetch()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func fetch() {
        guard Date().timeIntervalSince(lastFetch) > 60 else { return }
        lastFetch = Date()
        let c = coordinate
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)"
            + "&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code"
            + "&daily=temperature_2m_max,temperature_2m_min,weather_code,sunset&timezone=auto&forecast_days=7")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd'T'HH:mm"
            let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
            if let tz = json["timezone"] as? String, let zone = TimeZone(identifier: tz) { iso.timeZone = zone; dayFmt.timeZone = zone }
            let cur = json["current"] as? [String: Any]
            let hourly = json["hourly"] as? [String: Any], daily = json["daily"] as? [String: Any]
            let hTimes = (hourly?["time"] as? [String]) ?? [], hTemps = (hourly?["temperature_2m"] as? [Double]) ?? []
            let hCodes = (hourly?["weather_code"] as? [Int]) ?? []
            let now = Date()
            var hours: [HourWeather] = []
            for (i, t) in hTimes.enumerated() where i < hTemps.count && i < hCodes.count {
                if let d = iso.date(from: t), d > now.addingTimeInterval(-3600), hours.count < 12 { hours.append(HourWeather(id: d, temp: hTemps[i], code: hCodes[i])) }
            }
            let dTimes = (daily?["time"] as? [String]) ?? [], lows = (daily?["temperature_2m_min"] as? [Double]) ?? []
            let highs = (daily?["temperature_2m_max"] as? [Double]) ?? [], dCodes = (daily?["weather_code"] as? [Int]) ?? []
            var days: [DayWeather] = []
            for (i, t) in dTimes.enumerated() where i < lows.count && i < highs.count && i < dCodes.count {
                if let d = dayFmt.date(from: t) { days.append(DayWeather(id: d, low: lows[i], high: highs[i], code: dCodes[i])) }
            }
            let sunset = ((daily?["sunset"] as? [String])?.first).flatMap { iso.date(from: $0) }
            DispatchQueue.main.async {
                self.current = cur?["temperature_2m"] as? Double
                self.code = cur?["weather_code"] as? Int ?? 0
                self.hours = hours; self.days = days; self.sunset = sunset
            }
        }.resume()
    }

    /// WMO weather code to an SF Symbol and a short name.
    static func describe(_ code: Int, night: Bool = false) -> (String, String) {
        switch code {
        case 0: return (night ? "moon.stars.fill" : "sun.max.fill", "Clear")
        case 1, 2: return (night ? "cloud.moon.fill" : "cloud.sun.fill", "Partly cloudy")
        case 3: return ("cloud.fill", "Cloudy")
        case 45, 48: return ("cloud.fog.fill", "Fog")
        case 51...57: return ("cloud.drizzle.fill", "Drizzle")
        case 61...67, 80...82: return ("cloud.rain.fill", "Rain")
        case 71...77, 85, 86: return ("cloud.snow.fill", "Snow")
        case 95...99: return ("cloud.bolt.rain.fill", "Thunderstorm")
        default: return ("cloud.fill", "Cloudy")
        }
    }
}
