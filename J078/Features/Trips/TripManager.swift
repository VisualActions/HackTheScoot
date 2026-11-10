import Foundation
import Combine

/// Records trips from live samples (real or simulated) and keeps the history.
/// Local only: trips are a JSON file on this phone, exported only when you share one.
final class TripManager: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var current: Trip?
    @Published var autoRecord: Bool = UserDefaults.standard.object(forKey: "tripAutoRecord") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoRecord, forKey: "tripAutoRecord") }
    }

    private var detector = TripDetector()
    private let store = TripStore()
    private var timer: Timer?
    var scooterName: () -> String = { "Scooter" }

    init() {
        trips = store.load().sorted { $0.start > $1.start }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func attach(_ ble: BLEManager) {
        scooterName = { [weak ble] in ble?.connectedName.isEmpty == false ? ble!.connectedName : "Scooter" }
        ble.onSpeedSample = { [weak self] kmh, mode, simulated in self?.sample(kmh: kmh, mode: mode, simulated: simulated) }
        ble.onLinkLost = { [weak self] in self?.linkLost() }
    }

    func sample(kmh: Double, mode: String?, simulated: Bool, at now: Date = Date()) {
        if var c = current {
            c.samples.append(TripSample(t: now.timeIntervalSince(c.start), kmh: kmh, mode: mode))
            current = c
        }
        guard autoRecord || current != nil else { return }
        switch detector.sample(kmh: kmh, at: now) {
        case .start: begin(simulated: simulated, at: now, first: TripSample(t: 0, kmh: kmh, mode: mode))
        case .end: finish()
        case .none: break
        }
    }

    func linkLost() {
        detector.connectionLost(at: Date())
        if var c = current { c.interruptions += 1; current = c }
    }

    private func tick() {
        if detector.tick(now: Date()) == .end { finish() }
    }

    private func begin(simulated: Bool, at t: Date, first: TripSample) {
        current = Trip(start: t, end: nil, scooterName: scooterName(), source: simulated ? "simulation" : "bluetooth", samples: [first])
        Feedback.shared.fire(.tripStart)
    }

    func finish() {
        _ = detector.forceEnd()
        guard var c = current else { return }
        current = nil
        c.end = Date()
        if c.samples.count >= 5 {
            trips.insert(c, at: 0)
            store.save(trips)
        }
        Feedback.shared.fire(.tripEnd)
    }

    func delete(_ t: Trip) {
        trips.removeAll { $0.id == t.id }
        store.save(trips)
    }

    func clear() {
        trips.removeAll()
        store.save(trips)
    }

    func exportURL(_ t: Trip, mph: Bool) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hackthescoot-ride-\(Int(t.start.timeIntervalSince1970)).txt")
        do { try TripMath.summary(t, mph: mph).write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}
