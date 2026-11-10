import Foundation
import SwiftUI
import UIKit
import CoreLocation
import AudioToolbox

// MARK: - Units everywhere

/// One place for "mph or km/h" on the new 4.2 screens. Follows the same setting as the
/// dashboard (the theme's units), so More > Units changes every screen at once.
enum UnitPref {
    static func mph(_ themes: ThemeStore) -> Bool { return themes.theme.units != "kmh" }
    static func speed(_ kmh: Double, mph: Bool) -> String {
        let v = kmh.isFinite ? kmh : 0
        return mph ? String(format: "%.1f mph", Units.kmhToMph(v)) : String(format: "%.1f km/h", v)
    }
    static func distance(_ km: Double, mph: Bool) -> String {
        let v = km.isFinite ? km : 0
        return mph ? String(format: "%.2f mi", Units.kmToMiles(v)) : String(format: "%.2f km", v)
    }
}

// MARK: - Haptics master switch

enum HapticsPref {
    static let key = "fb.haptics.master"
    static var on: Bool { return UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

// MARK: - Ride hub: speed alert + ride timer, fed by every live sample

final class RideHub: ObservableObject {
    static let shared = RideHub()

    static let alertOnKey = "speedAlert.on"
    static let alertKmhKey = "speedAlert.kmh"
    static let alertSoundKey = "speedAlert.sound"
    static let alertHapticKey = "speedAlert.haptic"

    @Published var alertOn: Bool { didSet { UserDefaults.standard.set(alertOn, forKey: RideHub.alertOnKey); logic.reset() } }
    @Published var alertKmh: Double { didSet { UserDefaults.standard.set(alertKmh, forKey: RideHub.alertKmhKey); logic.thresholdKmh = alertKmh; logic.reset() } }
    @Published var alertSound: Bool { didSet { UserDefaults.standard.set(alertSound, forKey: RideHub.alertSoundKey) } }
    @Published var alertHaptic: Bool { didSet { UserDefaults.standard.set(alertHaptic, forKey: RideHub.alertHapticKey) } }
    @Published private(set) var alertsThisSession = 0
    @Published private(set) var lastAlertAt: Date?
    @Published private(set) var lastKmh: Double = 0

    @Published var timer = RideTimer()

    private var logic: SpeedAlertLogic

    init() {
        let ud = UserDefaults.standard
        let k = ud.object(forKey: RideHub.alertKmhKey) as? Double ?? 32.0   // ~20 mph
        alertOn = ud.object(forKey: RideHub.alertOnKey) as? Bool ?? false
        alertKmh = (k.isFinite && k >= 3 && k <= 120) ? k : 32.0
        alertSound = ud.object(forKey: RideHub.alertSoundKey) as? Bool ?? true
        alertHaptic = ud.object(forKey: RideHub.alertHapticKey) as? Bool ?? true
        logic = SpeedAlertLogic(thresholdKmh: (k.isFinite && k >= 3 && k <= 120) ? k : 32.0)
    }

    /// Every live speed sample (real or simulated), in km/h.
    func sample(kmh: Double, at now: Date = Date()) {
        guard kmh.isFinite else { return }
        lastKmh = kmh
        guard alertOn else { return }
        if logic.sample(kmh: kmh, at: now) {
            alertsThisSession += 1
            lastAlertAt = now
            fireAlert()
        }
    }

    func fireAlert() {
        DispatchQueue.main.async {
            if self.alertHaptic && HapticsPref.on {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            }
            if self.alertSound { AudioServicesPlaySystemSound(1005) }
        }
    }
}

// MARK: - Last parked here (opt-in, when-in-use only)

struct ParkedSpot: Codable, Equatable {
    var lat: Double
    var lon: Double
    var accuracy: Double
    var at: Date
    var scooterName: String
}

final class ParkedSpotStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = ParkedSpotStore()
    static let enabledKey = "parked.enabled"
    static let spotKey = "parked.spot"

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: ParkedSpotStore.enabledKey)
            if enabled { requestPermission() }
        }
    }
    @Published private(set) var spot: ParkedSpot?
    @Published private(set) var authStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastError: String?

    private var manager: CLLocationManager?
    private var pendingName = "Scooter"

    override init() {
        enabled = UserDefaults.standard.bool(forKey: ParkedSpotStore.enabledKey)
        if let d = UserDefaults.standard.data(forKey: ParkedSpotStore.spotKey) {
            spot = try? JSONDecoder().decode(ParkedSpot.self, from: d)
        }
        super.init()
    }

    private func lm() -> CLLocationManager {
        if let m = manager { return m }
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager = m
        authStatus = m.authorizationStatus
        return m
    }

    var authorized: Bool { return authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways }

    func requestPermission() {
        let m = lm()
        if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() }
    }

    /// Called when the scooter parks or the link drops. Does nothing unless opted in.
    func noteParked(scooterName: String) {
        guard enabled else { return }
        let m = lm()
        guard authorized else { return }
        pendingName = scooterName.isEmpty ? "Scooter" : scooterName
        m.requestLocation()
    }

    func saveNow(scooterName: String) {
        guard enabled else { return }
        let m = lm()
        if !authorized { requestPermission(); return }
        pendingName = scooterName.isEmpty ? "Scooter" : scooterName
        m.requestLocation()
    }

    func clear() {
        spot = nil
        UserDefaults.standard.removeObject(forKey: ParkedSpotStore.spotKey)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { self.authStatus = manager.authorizationStatus }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        let s = ParkedSpot(lat: l.coordinate.latitude, lon: l.coordinate.longitude, accuracy: l.horizontalAccuracy, at: Date(), scooterName: pendingName)
        DispatchQueue.main.async {
            self.spot = s
            self.lastError = nil
            if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: ParkedSpotStore.spotKey) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.lastError = error.localizedDescription }
    }

    var mapsURL: URL? {
        guard let s = spot else { return nil }
        return URL(string: String(format: "http://maps.apple.com/?ll=%.6f,%.6f&q=%@", s.lat, s.lon, "Parked%20scooter"))
    }
}

// MARK: - Maintenance store (per Garage scooter)

final class MaintenanceStore: ObservableObject {
    static let shared = MaintenanceStore()
    /// Bumped on every change so screens redraw.
    @Published private(set) var revision = 0
    private var cache: [UUID: [MaintenanceItem]] = [:]

    private func key(_ id: UUID) -> String { return "maint." + id.uuidString }

    /// Never publishes (safe to call while a view is drawing).
    func list(for id: UUID, totalKm: Double) -> [MaintenanceItem] {
        if let l = cache[id] { return l }
        if let d = UserDefaults.standard.data(forKey: key(id)), let l = try? JSONDecoder().decode([MaintenanceItem].self, from: d) {
            cache[id] = l
            return l
        }
        let l = MaintenanceMath.defaults(now: Date(), totalKm: totalKm)
        cache[id] = l
        return l
    }

    /// v5.0 restore: forget the cache so lists are re-read.
    func reload() { cache = [:]; revision += 1 }

    func set(_ l: [MaintenanceItem], for id: UUID) {
        cache[id] = l
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: key(id)) }
        revision += 1
    }

    /// Estimated distance on one Garage scooter, from its trips.
    static func totalKm(for id: UUID, trips: [Trip]) -> Double {
        let mine = GarageStore.shared.state.trips(trips, for: id)
        return RideTotalsMath.totals(mine).distanceKm
    }

    func dueCount(for id: UUID, trips: [Trip], now: Date = Date()) -> Int {
        let km = MaintenanceStore.totalKm(for: id, trips: trips)
        return list(for: id, totalKm: km).filter { MaintenanceMath.status($0, totalKm: km, now: now) == .due }.count
    }
}

// MARK: - Packet logger (Developer): record a whole session, then export it

final class PacketRecorder: ObservableObject {
    static let shared = PacketRecorder()
    let maxFrames = 20000

    @Published private(set) var isRecording = false
    @Published private(set) var frames: [LogEntry] = []
    @Published private(set) var startedAt: Date?
    @Published private(set) var stoppedAt: Date?
    @Published private(set) var dropped = 0
    private(set) var deviceLabel = ""
    private weak var ble: BLEManager?
    private var savedFlags: (Bool, Bool)?

    func start(ble: BLEManager) {
        frames = []
        dropped = 0
        startedAt = Date()
        stoppedAt = nil
        self.ble = ble
        deviceLabel = "\(ble.connectedName.isEmpty ? "(no device)" : ble.connectedName) · adapter \(ble.adapter.displayName) · \(ble.source.rawValue)"
        // record EVERY frame while the logger runs (keep-alives and repeated status too)
        savedFlags = (ble.logKeepAlives, ble.logEveryStatus)
        ble.logKeepAlives = true
        ble.logEveryStatus = true
        isRecording = true
        marks = 0
        // v5.0: written to disk as it records, so a crash doesn't lose the capture
        AppJournal.shared.beginCapture(header: headerLines().joined(separator: "\n"))
        AppJournal.shared.note("capture started: \(deviceLabel)")
    }

    /// v5.0: "I pressed ..." markers, so whoever reads the capture knows what each change was.
    @Published private(set) var marks = 0
    /// PINs the rider typed to mask in the export (kept in memory only, never saved).
    var extraPins: [String] = []

    func mark(_ label: String) {
        guard isRecording else { return }
        marks += 1
        let text = "MARK #\(marks): pressed \(label) in the official app"
        if let b = ble { b.info(text) } else {
            record(LogEntry(time: Date(), kind: .info, channel: "--", raw: [], decoded: nil, note: text))
        }
    }

    private func headerLines() -> [String] {
        return ["HackTheScoot \(AppInfo.version) packet capture",
                "device: \(deviceLabel)",
                "started: \(startedAt.map { "\($0)" } ?? "-")",
                "passwords are masked in this file (check before posting publicly)",
                ""]
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        stoppedAt = Date()
        if let b = ble, let f = savedFlags {
            b.logKeepAlives = f.0
            b.logEveryStatus = f.1
        }
        savedFlags = nil
        let stamp = Int((startedAt ?? Date()).timeIntervalSince1970)
        savedFile = AppJournal.shared.finishCapture(footer: "stopped: \(stoppedAt.map { "\($0)" } ?? "-")  frames: \(frames.count)  marks: \(marks)", stamp: stamp)
        AppJournal.shared.note("capture stopped: \(frames.count) frames")
    }

    /// v5.0: the copy saved on this phone (Application Support/logs), kept for the last 10.
    @Published private(set) var savedFile: URL?

    /// BLEManager calls this for every log line (passwords are already masked there).
    func record(_ e: LogEntry) {
        guard isRecording else { return }
        if frames.count >= maxFrames { dropped += 1; return }
        frames.append(e)
        AppJournal.shared.appendCapture(e.exportLine)
    }

    var rxCount: Int { return frames.filter { $0.kind == .rx }.count }
    var txCount: Int { return frames.filter { $0.kind == .tx }.count }

    func exportText() -> String {
        var lines = ["HackTheScoot \(AppInfo.version) packet capture",
                     "device: \(deviceLabel)",
                     "started: \(startedAt.map { "\($0)" } ?? "-")  stopped: \(stoppedAt.map { "\($0)" } ?? "still recording")",
                     "frames: \(frames.count) (rx \(rxCount), tx \(txCount))\(dropped > 0 ? ", \(dropped) over the limit not kept" : ""), marks: \(marks)",
                     "passwords are masked in this file",
                     ""]
        lines += frames.map { $0.exportLine }
        return CaptureSanitizer.mask(lines.joined(separator: "\n"), pins: extraPins)
    }

    func exportURL() -> URL? {
        let stamp = Int((startedAt ?? Date()).timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hackthescoot-capture-\(stamp).txt")
        do { try exportText().write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}

// MARK: - Alternate app icons

enum AppIcons {
    struct Choice: Identifiable, Equatable {
        let id: String          // "" = primary
        let name: String
        let preview: String     // hex colour for the swatch
    }
    static let choices: [Choice] = [
        Choice(id: "", name: "Classic", preview: "#00E5FF"),
        Choice(id: "AppIcon-Ember", name: "Ember", preview: "#FF6A1A"),
        Choice(id: "AppIcon-Mono", name: "Mono", preview: "#E5E5EA"),
        Choice(id: "AppIcon-Lime", name: "Lime", preview: "#9CFF2E"),
    ]

    static var supported: Bool { return UIApplication.shared.supportsAlternateIcons }
    static var current: String { return UIApplication.shared.alternateIconName ?? "" }

    static func set(_ id: String, done: @escaping (String?) -> Void) {
        guard supported else { done("This phone doesn't allow icon changes."); return }
        UIApplication.shared.setAlternateIconName(id.isEmpty ? nil : id) { err in
            DispatchQueue.main.async { done(err?.localizedDescription) }
        }
    }
}
