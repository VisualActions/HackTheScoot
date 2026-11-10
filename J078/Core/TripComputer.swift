import Foundation

/// One real speed sample, stored in km/h so every trip uses one unit.
struct TripSample: Codable, Equatable {
    var t: TimeInterval        // seconds since the trip started
    var kmh: Double
    var mode: String?          // "Walk", "Eco", "Drive", "Sport" or nil
}

struct Trip: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var start: Date
    var end: Date?
    var scooterName: String
    var source: String                  // "bluetooth" or "simulation"
    var samples: [TripSample] = []
    var interruptions: Int = 0
    /// Optional route, only when the user turned GPS on. Never uploaded.
    var route: [RoutePoint]? = nil
    /// v4.1: which Garage scooter this ride belongs to (nil for rides from before 4.1).
    var scooterID: UUID? = nil

    struct RoutePoint: Codable, Equatable {
        var t: TimeInterval
        var lat: Double
        var lon: Double
    }

    var duration: TimeInterval {
        let last = samples.last?.t ?? 0
        if let e = end { return max(last, e.timeIntervalSince(start)) }
        return last
    }

    var stats: TripStats { return TripMath.stats(samples) }
}

struct TripStats: Equatable {
    var maxKmh: Double = 0
    var avgMovingKmh: Double = 0
    var distanceKm: Double = 0
    var movingTime: TimeInterval = 0
    var timeInMode: [String: TimeInterval] = [:]
    var validSamples: Int = 0
    var rejectedSamples: Int = 0
}

/// Pure trip math (unit-tested).
enum TripMath {
    /// Samples further apart than this are a gap (lost connection): no distance is invented across it.
    static let maxGap: TimeInterval = 2.0
    /// Faster than this is a corrupt sample, not a ride.
    static let maxPlausibleKmh: Double = 80
    static let movingThresholdKmh: Double = 0.5

    static func isValid(_ s: TripSample) -> Bool {
        return s.kmh.isFinite && s.kmh >= 0 && s.kmh <= maxPlausibleKmh && s.t.isFinite && s.t >= 0
    }

    /// ESTIMATED distance: trapezoid integration of valid samples, skipping gaps.
    /// It is not a scooter odometer and the UI says "estimated".
    static func stats(_ all: [TripSample]) -> TripStats {
        var st = TripStats()
        let samples = all.filter(isValid).sorted { $0.t < $1.t }
        st.validSamples = samples.count
        st.rejectedSamples = all.count - samples.count
        st.maxKmh = samples.map { $0.kmh }.max() ?? 0
        guard samples.count >= 2 else { return st }
        for i in 1..<samples.count {
            let a = samples[i - 1], b = samples[i]
            let dt = b.t - a.t
            guard dt > 0, dt <= maxGap else { continue }
            let v = (a.kmh + b.kmh) / 2
            st.distanceKm += v * dt / 3600
            if v > movingThresholdKmh { st.movingTime += dt }
            if let m = a.mode { st.timeInMode[m, default: 0] += dt }
        }
        st.avgMovingKmh = st.movingTime > 0 ? st.distanceKm / (st.movingTime / 3600) : 0
        return st
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Plain-text summary for sharing. Speeds in the unit the user picked.
    static func summary(_ trip: Trip, mph: Bool) -> String {
        let s = trip.stats
        let conv: (Double) -> Double = { mph ? Units.kmhToMph($0) : $0 }
        let su = mph ? "mph" : "km/h", du = mph ? "mi" : "km"
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        var lines = [
            "HackTheScoot ride - \(df.string(from: trip.start))",
            "Scooter: \(trip.scooterName)" + (trip.source == "simulation" ? " (SIMULATED)" : ""),
            "Duration: \(format(trip.duration))",
            String(format: "Distance (estimated from speed, not an odometer): %.2f %@", conv(s.distanceKm), du),
            String(format: "Max speed: %.1f %@", conv(s.maxKmh), su),
            String(format: "Average moving speed: %.1f %@", conv(s.avgMovingKmh), su),
            "Connection interruptions: \(trip.interruptions)",
        ]
        for (m, t) in s.timeInMode.sorted(by: { $0.key < $1.key }) {
            lines.append("Time in \(m): \(format(t))")
        }
        return lines.joined(separator: "\n")
    }
}

/// Decides when a trip starts and ends from live data (unit-tested, no timers inside).
struct TripDetector {
    var startKmh: Double = 2.0
    var endAfterStill: TimeInterval = 90
    var endAfterLost: TimeInterval = 180

    enum Event: Equatable { case none, start, end }

    private(set) var active = false
    private var lastMoving: Date?
    private var lostSince: Date?

    mutating func sample(kmh: Double, at t: Date) -> Event {
        lostSince = nil
        if kmh >= startKmh { lastMoving = t }
        if !active {
            if kmh >= startKmh { active = true; return .start }
            return .none
        }
        if let m = lastMoving, t.timeIntervalSince(m) > endAfterStill { active = false; return .end }
        return .none
    }

    mutating func connectionLost(at t: Date) { if lostSince == nil { lostSince = t } }

    mutating func tick(now: Date) -> Event {
        guard active else { return .none }
        if let l = lostSince, now.timeIntervalSince(l) > endAfterLost { active = false; return .end }
        if lostSince == nil, let m = lastMoving, now.timeIntervalSince(m) > endAfterStill { active = false; return .end }
        return .none
    }

    mutating func forceEnd() -> Event {
        guard active else { return .none }
        active = false
        return .end
    }
}

/// Trips saved as one JSON file in Application Support. Local only.
final class TripStore {
    let url: URL

    init(directory: URL? = nil) {
        let dir = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("trips.json")
    }

    func load() -> [Trip] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([Trip].self, from: d)) ?? []
    }

    func save(_ trips: [Trip]) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(trips) {
            try? d.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}
