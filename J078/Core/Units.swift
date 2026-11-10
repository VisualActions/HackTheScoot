import Foundation

enum Units {
    static let mphPerKmh = 0.621371
    static func kmhToMph(_ v: Double) -> Double { return v * mphPerKmh }
    static func mphToKmh(_ v: Double) -> Double { return v / mphPerKmh }
    static func kmToMiles(_ v: Double) -> Double { return v * mphPerKmh }
    static func milesToKm(_ v: Double) -> Double { return v / mphPerKmh }
}

/// Speed in the unit the user wants to see. The J078 reports speed x10 in its
/// own current unit (mph while it is set to mile). VERIFIED on Nov 9.
struct SpeedDisplay: Equatable {
    let value: Double
    let unit: String
    let isMile: Bool

    /// display: "scooter" (whatever the scooter uses), "mph" or "kmh".
    static func make(raw: Double, scooterIsMile: Bool, display: String) -> SpeedDisplay {
        switch display {
        case "mph":
            return SpeedDisplay(value: scooterIsMile ? raw : Units.kmhToMph(raw), unit: "mph", isMile: true)
        case "kmh":
            return SpeedDisplay(value: scooterIsMile ? Units.mphToKmh(raw) : raw, unit: "km/h", isMile: false)
        default:
            return SpeedDisplay(value: raw, unit: scooterIsMile ? "mph" : "km/h", isMile: scooterIsMile)
        }
    }

    /// Any speed to km/h, for storing trips in one unit.
    static func toKmh(_ raw: Double, scooterIsMile: Bool) -> Double {
        return scooterIsMile ? Units.mphToKmh(raw) : raw
    }
}

/// Smooths what the gauge SHOWS between real samples. It never invents a speed:
/// the displayed value always moves toward the last real sample and never past it,
/// and after `staleAfter` seconds with no sample the gauge is marked stale.
struct SpeedInterpolator {
    private(set) var target: Double = 0
    private(set) var shown: Double = 0
    private(set) var lastSampleAt: Date?
    var staleAfter: TimeInterval = 1.5

    mutating func sample(_ v: Double, at t: Date) {
        target = max(0, v)
        lastSampleAt = t
    }

    /// intensity 0 = jump straight to the sample, 1 = smoothest.
    mutating func step(dt: Double, intensity: Double) -> Double {
        let k = max(0.0, min(1.0, intensity))
        if k < 0.01 { shown = target; return shown }
        let rate = 4.0 + (1.0 - k) * 26.0         // 1/s
        let alpha = 1.0 - exp(-rate * max(0, dt))
        shown += (target - shown) * alpha
        // never overshoot the real value
        if (shown - target).magnitude < 0.01 { shown = target }
        return shown
    }

    func isStale(now: Date) -> Bool {
        guard let t = lastSampleAt else { return true }
        return now.timeIntervalSince(t) > staleAfter
    }
}
