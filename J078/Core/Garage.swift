import Foundation

/// The last numbers we saw from one scooter. Kept per scooter so two scooters never mix.
struct LastStats: Codable, Equatable {
    var at: Date
    var topKmh: Double = 0
    var mode: String? = nil
    var limitsKmh: [String: Int] = [:]
    var connection: String = "bluetooth"
}

/// One scooter in the Garage.
struct GarageScooter: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// CompatSeed id ("joyhis-j078", "volpam-dad", ... or "other").
    var compatID: String
    var colorHex: String = "#0A84FF"
    /// File name of the photo inside Documents/garage, nil = use the color.
    var photoFile: String? = nil
    var notes: String = ""
    /// The phone's Bluetooth identifier for this scooter, once it has connected here.
    var bleID: UUID? = nil
    var bleName: String? = nil
    var lastConnected: Date? = nil
    var lastStats: LastStats? = nil
    var created: Date = Date()

    var compat: CompatEntry { return CompatSeed.find(compatID) }
    var kind: ScooterKind { return compat.kind }

    enum CodingKeys: String, CodingKey {
        case id, name, compatID, colorHex, photoFile, notes, bleID, bleName, lastConnected, lastStats, created
    }

    init(id: UUID = UUID(), name: String, compatID: String, colorHex: String = "#0A84FF", notes: String = "") {
        self.id = id
        self.name = name
        self.compatID = compatID
        self.colorHex = colorHex
        self.notes = notes
    }

    /// Tolerant decoding: a damaged field falls back instead of losing the whole garage.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = ((try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        name = String((((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "Scooter").prefix(40))
        compatID = ((try? c.decodeIfPresent(String.self, forKey: .compatID)) ?? nil) ?? "other"
        colorHex = ((try? c.decodeIfPresent(String.self, forKey: .colorHex)) ?? nil) ?? "#0A84FF"
        photoFile = (try? c.decodeIfPresent(String.self, forKey: .photoFile)) ?? nil
        notes = ((try? c.decodeIfPresent(String.self, forKey: .notes)) ?? nil) ?? ""
        bleID = (try? c.decodeIfPresent(UUID.self, forKey: .bleID)) ?? nil
        bleName = (try? c.decodeIfPresent(String.self, forKey: .bleName)) ?? nil
        lastConnected = (try? c.decodeIfPresent(Date.self, forKey: .lastConnected)) ?? nil
        lastStats = (try? c.decodeIfPresent(LastStats.self, forKey: .lastStats)) ?? nil
        created = ((try? c.decodeIfPresent(Date.self, forKey: .created)) ?? nil) ?? Date()
    }
}

/// Pure Garage rules (unit-tested). The store just persists what these return.
struct GarageState: Codable, Equatable {
    var scooters: [GarageScooter] = []
    var activeID: UUID? = nil

    /// First launch: his J078 and his dad's Volpam.
    static func seeded() -> GarageState {
        let j = GarageScooter(name: "My J078", compatID: "joyhis-j078", colorHex: "#0A84FF")
        let v = GarageScooter(name: "Dad's Volpam", compatID: "volpam-dad", colorHex: "#FF9F0A")
        return GarageState(scooters: [j, v], activeID: j.id)
    }

    var active: GarageScooter? {
        if let a = activeID, let s = scooters.first(where: { $0.id == a }) { return s }
        return scooters.first
    }

    mutating func add(_ s: GarageScooter, makeActive: Bool = true) {
        scooters.append(s)
        if makeActive || activeID == nil { activeID = s.id }
    }

    mutating func remove(_ id: UUID) {
        scooters.removeAll { $0.id == id }
        if activeID == id { activeID = scooters.first?.id }
    }

    mutating func setActive(_ id: UUID) {
        if scooters.contains(where: { $0.id == id }) { activeID = id }
    }

    mutating func update(_ s: GarageScooter) {
        if let i = scooters.firstIndex(where: { $0.id == s.id }) { scooters[i] = s }
    }

    /// A scooter connected over Bluetooth. Returns the garage scooter it belongs to:
    /// 1. one already linked to this Bluetooth id;
    /// 2. else the active scooter, if it is not linked yet and its model uses this protocol;
    /// 3. else any unlinked scooter whose model uses this protocol;
    /// 4. else nil (the app offers "Add to Garage", it never guesses across protocols).
    /// The scooter it returns becomes active, so trips and stats land on the right one.
    @discardableResult
    mutating func linkConnected(bleID: UUID, name: String, kind: ScooterKind, at now: Date = Date()) -> UUID? {
        var target: Int? = scooters.firstIndex { $0.bleID == bleID }
        if target == nil, kind != .unknown, kind != .nusOther {
            if let a = active, a.bleID == nil, a.kind == kind { target = scooters.firstIndex { $0.id == a.id } }
            if target == nil { target = scooters.firstIndex { $0.bleID == nil && $0.kind == kind } }
        }
        guard let i = target else { return nil }
        scooters[i].bleID = bleID
        scooters[i].bleName = name
        scooters[i].lastConnected = now
        activeID = scooters[i].id
        return scooters[i].id
    }

    mutating func unlink(_ id: UUID) {
        if let i = scooters.firstIndex(where: { $0.id == id }) {
            scooters[i].bleID = nil
            scooters[i].bleName = nil
        }
    }

    mutating func recordStats(_ stats: LastStats, for id: UUID) {
        guard let i = scooters.firstIndex(where: { $0.id == id }) else { return }
        var s = stats
        // top speed is "highest ever seen" for this scooter
        s.topKmh = max(stats.topKmh.isFinite ? stats.topKmh : 0, scooters[i].lastStats?.topKmh ?? 0)
        scooters[i].lastStats = s
    }

    /// Trips that belong to one scooter. Trips from before 4.1 have no scooter id and
    /// are matched by the Bluetooth name they were recorded with.
    func trips(_ all: [Trip], for id: UUID) -> [Trip] {
        guard let s = scooters.first(where: { $0.id == id }) else { return [] }
        return all.filter { t in
            if let sid = t.scooterID { return sid == id }
            if let n = s.bleName, !n.isEmpty { return t.scooterName == n }
            return false
        }
    }
}
