import Foundation

// v4.2 pure logic (unit-tested): speed alert, ride timer with laps, maintenance
// reminders, lifetime ride totals and the Garage's vehicle / controller types.
// Nothing here touches Bluetooth, the UI or the network.

// MARK: - Speed alert

/// Fires once when the speed goes over the rider's own threshold, then re-arms only after
/// dropping clearly below it (so hovering at the line doesn't buzz every sample).
struct SpeedAlertLogic: Equatable {
    var thresholdKmh: Double
    var rearmMarginKmh: Double = 1.5
    var minInterval: TimeInterval = 5
    private(set) var armed = true
    private(set) var lastFired: Date?

    init(thresholdKmh: Double) { self.thresholdKmh = thresholdKmh }

    /// true = alert now.
    mutating func sample(kmh: Double, at t: Date) -> Bool {
        guard kmh.isFinite, thresholdKmh.isFinite, thresholdKmh > 0 else { return false }
        if kmh >= thresholdKmh {
            guard armed else { return false }
            if let l = lastFired, t.timeIntervalSince(l) < minInterval { return false }
            armed = false
            lastFired = t
            return true
        }
        if kmh < thresholdKmh - rearmMarginKmh { armed = true }
        return false
    }

    mutating func reset() { armed = true; lastFired = nil }
}

// MARK: - Ride timer

struct RideTimer: Equatable {
    private(set) var startedAt: Date?
    private(set) var accumulated: TimeInterval = 0
    /// Each finished lap's own duration, oldest first.
    private(set) var laps: [TimeInterval] = []
    private(set) var lapStartElapsed: TimeInterval = 0

    var isRunning: Bool { return startedAt != nil }
    var hasStarted: Bool { return isRunning || accumulated > 0 }

    func elapsed(at now: Date) -> TimeInterval {
        let running = startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return accumulated + running
    }

    func currentLap(at now: Date) -> TimeInterval { return max(0, elapsed(at: now) - lapStartElapsed) }

    var bestLap: TimeInterval? { return laps.min() }

    mutating func start(at now: Date) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    mutating func pause(at now: Date) {
        guard let s = startedAt else { return }
        accumulated += max(0, now.timeIntervalSince(s))
        startedAt = nil
    }

    mutating func lap(at now: Date) {
        guard isRunning else { return }
        let e = elapsed(at: now)
        laps.append(max(0, e - lapStartElapsed))
        lapStartElapsed = e
    }

    mutating func reset() { self = RideTimer() }

    static func format(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00.0" }
        let tenths = Int((t * 10).rounded(.down))
        let h = tenths / 36000
        let m = (tenths / 600) % 60
        let s = (tenths / 10) % 60
        let d = tenths % 10
        return h > 0 ? String(format: "%ld:%02ld:%02ld.%ld", h, m, s, d) : String(format: "%ld:%02ld.%ld", m, s, d)
    }
}

// MARK: - Maintenance reminders

struct MaintenanceItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var icon: String = "wrench.and.screwdriver"
    /// Distance interval in km (nil = no distance rule).
    var everyKm: Double?
    /// Time interval in days (nil = no time rule).
    var everyDays: Int?
    var lastDone: Date
    /// Estimated distance on this scooter when it was last done.
    var kmAtLastDone: Double = 0
}

enum MaintenanceDue: String, Equatable { case ok, soon, due }

enum MaintenanceMath {
    static let soonFraction = 0.85

    /// How far through its interval an item is (1.0 = due). The larger of distance and time.
    static func progress(_ i: MaintenanceItem, totalKm: Double, now: Date) -> Double {
        var p = 0.0
        if let k = i.everyKm, k > 0, totalKm.isFinite {
            p = max(p, max(0, totalKm - i.kmAtLastDone) / k)
        }
        if let d = i.everyDays, d > 0 {
            p = max(p, max(0, now.timeIntervalSince(i.lastDone)) / (Double(d) * 86400))
        }
        return p.isFinite ? p : 0
    }

    static func status(_ i: MaintenanceItem, totalKm: Double, now: Date) -> MaintenanceDue {
        let p = progress(i, totalKm: totalKm, now: now)
        if p >= 1 { return .due }
        if p >= soonFraction { return .soon }
        return .ok
    }

    static func markDone(_ i: MaintenanceItem, totalKm: Double, now: Date) -> MaintenanceItem {
        var c = i
        c.lastDone = now
        c.kmAtLastDone = totalKm.isFinite ? totalKm : 0
        return c
    }

    /// What's left, in words ("120 mi or 12 days left", "due now").
    static func remaining(_ i: MaintenanceItem, totalKm: Double, now: Date, mph: Bool) -> String {
        var parts: [String] = []
        if let k = i.everyKm, k > 0 {
            let left = k - max(0, totalKm - i.kmAtLastDone)
            if left > 0 { parts.append(mph ? String(format: "%.0f mi", Units.kmToMiles(left)) : String(format: "%.0f km", left)) }
        }
        if let d = i.everyDays, d > 0 {
            let left = Double(d) - max(0, now.timeIntervalSince(i.lastDone)) / 86400
            if left > 0 { parts.append("\(Int(left.rounded(.up))) day" + (Int(left.rounded(.up)) == 1 ? "" : "s")) }
        }
        if status(i, totalKm: totalKm, now: now) == .due || parts.isEmpty { return "due now" }
        return parts.joined(separator: " or ") + " left"
    }

    /// Starting list for a new scooter.
    static func defaults(now: Date, totalKm: Double = 0) -> [MaintenanceItem] {
        return [
            MaintenanceItem(name: "Check tire pressure", icon: "circle.circle", everyKm: Units.milesToKm(100), everyDays: 14, lastDone: now, kmAtLastDone: totalKm),
            MaintenanceItem(name: "Check brakes", icon: "exclamationmark.octagon", everyKm: Units.milesToKm(200), everyDays: 30, lastDone: now, kmAtLastDone: totalKm),
            MaintenanceItem(name: "Tighten bolts and stem", icon: "wrench.and.screwdriver", everyKm: Units.milesToKm(300), everyDays: 60, lastDone: now, kmAtLastDone: totalKm),
        ]
    }
}

// MARK: - Lifetime ride totals

struct RideTotals: Equatable {
    var rides = 0
    var distanceKm = 0.0
    var movingTime: TimeInterval = 0
    var maxKmh = 0.0
    var longestKm = 0.0

    /// Distance over moving time (0 when there is no moving time).
    var avgKmh: Double { return movingTime > 0 ? distanceKm / (movingTime / 3600) : 0 }
}

enum RideTotalsMath {
    static func totals(_ trips: [Trip]) -> RideTotals {
        var t = RideTotals()
        for trip in trips {
            let s = TripMath.stats(trip.samples)
            guard s.validSamples > 0 else { continue }
            t.rides += 1
            if s.distanceKm.isFinite { t.distanceKm += s.distanceKm; t.longestKm = max(t.longestKm, s.distanceKm) }
            if s.movingTime.isFinite { t.movingTime += s.movingTime }
            if s.maxKmh.isFinite { t.maxKmh = max(t.maxKmh, s.maxKmh) }
        }
        return t
    }
}

// MARK: - Garage vehicle + controller types

enum VehicleType: String, Codable, CaseIterable, Identifiable {
    case escooter, ebike
    var id: String { rawValue }
    var label: String { return self == .ebike ? "E-bike" : "E-scooter" }
    var icon: String { return self == .ebike ? "bicycle" : "scooter" }
}

enum ControllerType: String, Codable, CaseIterable, Identifiable {
    case joyhis365, zydtech, ninebot, fardriver, kukirin, unknown
    var id: String { rawValue }

    var label: String {
        switch self {
        case .joyhis365: return "Joyhis / 365"
        case .zydtech: return "Zydtech (Volpam, Hiboy)"
        case .ninebot: return "Ninebot / Segway / Xiaomi"
        case .fardriver: return "Fardriver"
        case .kukirin: return "KuKirin (G2 / G4)"
        case .unknown: return "Unknown"
        }
    }

    /// The adapter this controller type uses.
    var adapterID: String {
        switch self {
        case .joyhis365: return Joyhis365Adapter.adapterID
        case .zydtech: return VolpamAdapter.adapterID
        case .ninebot: return NinebotAdapter.adapterID
        case .fardriver: return FardriverAdapter.adapterID
        case .kukirin: return KukirinAdapter.adapterID
        case .unknown: return GenericReadOnlyAdapter.adapterID
        }
    }

    /// Experimental / unknown controllers show live data only until a capture.
    var readOnlyUntilCapture: Bool {
        switch self {
        case .ninebot, .fardriver, .kukirin, .unknown: return true
        case .joyhis365, .zydtech: return false
        }
    }

    var note: String {
        switch self {
        case .joyhis365: return "Controls verified on the J078 from captures."
        case .zydtech: return "Speed limit verified on the Volpam. Other Zydtech models are unverified."
        case .ninebot: return "Experimental, untested on hardware: live data. Plain M365: KERS, cruise and tail light; Max G30: cruise, each confirmed and read back. Everything else stays read-only."
        case .fardriver: return "Experimental and read-only: live data only (volts, amps, motor speed, faults). HackTheScoot never writes to a motor controller. Needs a capture to unlock anything more."
        case .kukirin: return "Experimental, untested on hardware: live data only (G2: speed, volts, rpm, mode; G4: mode). Nothing is ever written to a KuKirin."
        case .unknown: return "Live data and the packet logger only. Needs a capture to unlock controls."
        }
    }

    /// Best guess from a compatibility-database entry's adapter id.
    static func from(compatAdapter: String?) -> ControllerType {
        switch compatAdapter {
        case "joyhis365": return .joyhis365
        case "zydtech365": return .zydtech
        case "ninebot", "xiaomi365": return .ninebot
        case "fardriver": return .fardriver
        case "kukirin": return .kukirin
        default: return .unknown
        }
    }
}
