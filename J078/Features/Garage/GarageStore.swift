import SwiftUI
import UIKit

/// The Garage: every scooter you own, each with its own name, model, look, notes,
/// last-known stats and trips. Stored on this phone only (UserDefaults + photos in
/// Documents/garage). A singleton so no screen can open without it.
final class GarageStore: ObservableObject {
    static let shared = GarageStore()

    @Published private(set) var state: GarageState

    private let key = "garage.v1"
    private var timer: Timer?
    private weak var ble: BLEManager?

    init(defaults: UserDefaults = .standard) {
        if let d = defaults.data(forKey: key), let s = try? JSONDecoder().decode(GarageState.self, from: d), !s.scooters.isEmpty {
            state = s
        } else {
            state = GarageState.seeded()
        }
        save()
    }

    /// v5.0 restore: re-read the Garage after a backup was imported.
    func reload(defaults: UserDefaults = .standard) {
        if let d = defaults.data(forKey: key), let s = try? JSONDecoder().decode(GarageState.self, from: d), !s.scooters.isEmpty {
            state = s
            save()
        }
    }

    var scooters: [GarageScooter] { return state.scooters }
    var active: GarageScooter? { return state.active }
    var activeID: UUID? { return state.active?.id }

    private func save() {
        if let d = try? JSONEncoder().encode(state) { UserDefaults.standard.set(d, forKey: key) }
        UserDefaults.standard.set(state.active?.bleID?.uuidString, forKey: "garage.activeBLEID")
    }

    private func mutate(_ f: (inout GarageState) -> Void) {
        var s = state
        f(&s)
        state = s
        save()
    }

    // MARK: Edits

    func add(name: String, compatID: String, colorHex: String, vehicleType: VehicleType = .escooter, controller: ControllerType? = nil) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate { $0.add(GarageScooter(name: n.isEmpty ? "Scooter" : String(n.prefix(40)), compatID: compatID, colorHex: colorHex,
                                      vehicleType: vehicleType, controller: controller)) }
    }

    func update(_ s: GarageScooter) { mutate { $0.update(s) } }

    func remove(_ id: UUID) {
        if let f = state.scooters.first(where: { $0.id == id })?.photoFile { try? FileManager.default.removeItem(at: GarageStore.photoURL(f)) }
        mutate { $0.remove(id) }
    }

    func unlink(_ id: UUID) { mutate { $0.unlink(id) } }

    /// Switch the active scooter and (when auto-connect is on) connect to it.
    func setActive(_ id: UUID) {
        guard id != state.activeID else { return }
        mutate { $0.setActive(id) }
        if let b = ble, b.autoReconnect, !b.isSimulating { _ = b.connectPreferred() }
    }

    /// Links the scooter that is connected right now to a garage entry.
    func linkCurrent(to id: UUID) {
        guard let b = ble, let p = b.connected else { return }
        mutate { st in
            // a Bluetooth id belongs to one garage scooter only
            for i in st.scooters.indices where st.scooters[i].bleID == p.identifier { st.scooters[i].bleID = nil }
            if let i = st.scooters.firstIndex(where: { $0.id == id }) {
                st.scooters[i].bleID = p.identifier
                st.scooters[i].bleName = b.connectedName
                st.scooters[i].lastConnected = Date()
            }
            st.setActive(id)
        }
    }

    /// The connected scooter is not in the garage: add it.
    func addCurrent() {
        guard let b = ble, let p = b.connected else { return }
        let compat = CompatSeed.bestMatch(for: b.kind)
        var s = GarageScooter(name: b.connectedName.isEmpty ? "Scooter" : String(b.connectedName.prefix(40)), compatID: compat.id, colorHex: "#64D2FF")
        s.bleID = p.identifier
        s.bleName = b.connectedName
        s.lastConnected = Date()
        mutate { $0.add(s) }
    }

    /// Is the scooter on the air right now an unlinked one?
    var connectedButUnlinked: Bool {
        guard let b = ble, !b.isSimulating, b.phase.isLinked, let p = b.connected else { return false }
        return !state.scooters.contains { $0.bleID == p.identifier }
    }

    func isConnected(_ s: GarageScooter) -> Bool {
        guard let b = ble, !b.isSimulating, b.phase.isLinked, let id = s.bleID else { return false }
        return b.connected?.identifier == id
    }

    // MARK: Photos

    static var photoDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("garage", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func photoURL(_ file: String) -> URL { return photoDir.appendingPathComponent(file) }

    func setPhoto(_ data: Data?, for id: UUID) {
        guard var s = state.scooters.first(where: { $0.id == id }) else { return }
        if let old = s.photoFile { try? FileManager.default.removeItem(at: GarageStore.photoURL(old)) }
        s.photoFile = nil
        if let data = data, let img = UIImage(data: data) {
            let side: CGFloat = 600
            let scale = min(1, side / max(img.size.width, img.size.height, 1))
            let size = CGSize(width: max(1, img.size.width * scale), height: max(1, img.size.height * scale))
            let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
            if let jpg = small.jpegData(compressionQuality: 0.8) {
                let name = "\(id.uuidString)-\(Int(Date().timeIntervalSince1970)).jpg"
                if (try? jpg.write(to: GarageStore.photoURL(name))) != nil { s.photoFile = name }
            }
        }
        update(s)
    }

    func photo(_ s: GarageScooter) -> UIImage? {
        guard let f = s.photoFile else { return nil }
        return UIImage(contentsOfFile: GarageStore.photoURL(f).path)
    }

    // MARK: Bluetooth

    func attach(_ b: BLEManager) {
        ble = b
        b.preferredScooterID = { [weak self] in self?.state.active?.bleID }
        b.adapterHint = { [weak self] id in
            guard let st = self?.state else { return nil }
            if let s = st.scooters.first(where: { $0.bleID == id }) { return s.controllerType.adapterID }
            if let a = st.active, a.bleID == nil, a.controllerType == .fardriver || a.controllerType == .ninebot || a.controllerType == .kukirin { return a.controllerType.adapterID }
            return nil
        }
        b.onConnected = { [weak self] id, name, kind in
            self?.mutate { _ = $0.linkConnected(bleID: id, name: name, kind: kind) }
        }
        timer?.invalidate()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.snapshot() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Every 5 s while a real scooter is connected: remember its numbers on ITS garage entry.
    private func snapshot() {
        guard let b = ble, !b.isSimulating, b.phase.isLinked, let p = b.connected else { return }
        var target = state.scooters.first { $0.bleID == p.identifier }?.id
        if target == nil, b.kind == .j078 || b.kind == .volpam {
            // the scooter was identified after connect (e.g. promoted to J078 by its status frame)
            mutate { _ = $0.linkConnected(bleID: p.identifier, name: b.connectedName, kind: b.kind) }
            target = state.scooters.first { $0.bleID == p.identifier }?.id
        }
        guard let id = target else { return }
        var st = LastStats(at: Date())
        if let s = b.status {
            let mile = Mapping.unitsIsMile(flagBit: s.unitsBit, swapped: UserDefaults.standard.bool(forKey: Keys.unitsSwapped))
            st.topKmh = SpeedDisplay.toKmh(b.tripMax, scooterIsMile: mile)
            st.mode = s.gear?.name
        }
        for (g, v) in b.limitsKmh where b.kind == .j078 { st.limitsKmh[g.name] = v }
        if let i = state.scooters.firstIndex(where: { $0.id == id }) {
            var s = state
            s.recordStats(st, for: id)
            s.scooters[i].lastConnected = Date()
            state = s
            save()
        }
    }
}
