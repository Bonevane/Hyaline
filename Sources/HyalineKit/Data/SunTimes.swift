// Sunrise and sunset (NOAA approximation).

import AppKit
import IOKit
import IOKit.ps
import CoreWLAN
import Darwin

enum SunTimes {
    /// Lahore: the Mac is on Pakistan time and the user's weather widget says Punjab.
    /// Replaced by the real location once the app asks for Location access.
    static let latitude = 31.55, longitude = 74.34
    /// Set once Location access gives a real position.
    static var override: (Double, Double)?

    /// Sunrise and sunset in local time for the given day, or nil at polar latitudes.
    static func times(on date: Date = Date()) -> (Date, Date)? {
        let cal = Calendar.current
        let day = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let gamma = 2 * Double.pi / 365 * (day - 1)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let (latitude, longitude) = override ?? (Self.latitude, Self.longitude)
        let lat = latitude * .pi / 180
        let cosH = (cos(90.833 * .pi / 180) / (cos(lat) * cos(decl))) - tan(lat) * tan(decl)
        guard abs(cosH) <= 1 else { return nil }
        let ha = acos(cosH) * 180 / .pi
        let startOfDay = cal.startOfDay(for: date)
        let tzOffset = Double(TimeZone.current.secondsFromGMT(for: date)) / 60
        let rise = 720 - 4 * (longitude + ha) - eqTime + tzOffset
        let set = 720 - 4 * (longitude - ha) - eqTime + tzOffset
        return (startOfDay.addingTimeInterval(rise * 60), startOfDay.addingTimeInterval(set * 60))
    }
}
