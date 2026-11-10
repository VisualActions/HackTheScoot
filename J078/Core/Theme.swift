import Foundation

/// Everything that makes up a dashboard look. Colors are "#RRGGBB" strings so the
/// struct is pure Foundation (tests + JSON sharing). Contains NO identifiers,
/// scooter names, passwords or ride history, on purpose: it is safe to share.
struct DashTheme: Codable, Equatable {
    var name: String = "HackTheScoot"
    var accent: String = "#00E5FF"
    var background: String = "#05070B"
    var backgroundStyle: String = "gradient"        // solid / gradient / black
    var gauge: String = "performance"               // classic / digital / performance
    var font: String = "rounded"                    // rounded / mono / normal
    var appearance: String = "dark"                 // dark / light / system
    var walkColor: String = "#D9DCE1"               // muted white
    var ecoColor: String = "#2BD96B"                // green
    var driveColor: String = "#2F8CFF"              // blue
    var sportColor: String = "#FF3B3B"              // red
    var animationIntensity: Double = 0.6            // 0 = none ... 1 = smoothest
    var units: String = "scooter"                   // scooter / mph / kmh
    var layout: String = "standard"                 // standard / minimal / focus
    var tiles: [String] = DashTile.defaultOrder.map { $0.rawValue }
    var useModeColor: Bool = true
    var night: Bool = false

    static let schemaVersion = 1

    enum CodingKeys: String, CodingKey {
        case name, accent, background, backgroundStyle, gauge, font, appearance
        case walkColor, ecoColor, driveColor, sportColor, animationIntensity, units, layout, tiles, useModeColor, night
    }

    init() {}

    /// Missing fields fall back to defaults; bad values are replaced by defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DashTheme()
        func color(_ k: CodingKeys, _ def: String) -> String {
            let v = (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil
            return DashTheme.validHex(v) ?? def
        }
        func pick(_ k: CodingKeys, _ allowed: [String], _ def: String) -> String {
            let v = (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil
            return v.flatMap { allowed.contains($0) ? $0 : nil } ?? def
        }
        let n = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? d.name
        name = String(n.prefix(40))
        accent = color(.accent, d.accent)
        background = color(.background, d.background)
        backgroundStyle = pick(.backgroundStyle, ["solid", "gradient", "black"], d.backgroundStyle)
        gauge = pick(.gauge, ["classic", "digital", "performance"], d.gauge)
        font = pick(.font, ["rounded", "mono", "normal"], d.font)
        appearance = pick(.appearance, ["dark", "light", "system"], d.appearance)
        walkColor = color(.walkColor, d.walkColor)
        ecoColor = color(.ecoColor, d.ecoColor)
        driveColor = color(.driveColor, d.driveColor)
        sportColor = color(.sportColor, d.sportColor)
        let ai = ((try? c.decodeIfPresent(Double.self, forKey: .animationIntensity)) ?? nil) ?? d.animationIntensity
        animationIntensity = ai.isFinite ? max(0, min(1, ai)) : d.animationIntensity
        units = pick(.units, ["scooter", "mph", "kmh"], d.units)
        layout = pick(.layout, ["standard", "minimal", "focus"], d.layout)
        let t = ((try? c.decodeIfPresent([String].self, forKey: .tiles)) ?? nil) ?? d.tiles
        let valid = t.filter { DashTile(rawValue: $0) != nil }
        var seen = Set<String>()
        tiles = valid.filter { seen.insert($0).inserted }
        useModeColor = ((try? c.decodeIfPresent(Bool.self, forKey: .useModeColor)) ?? nil) ?? d.useModeColor
        night = ((try? c.decodeIfPresent(Bool.self, forKey: .night)) ?? nil) ?? d.night
    }

    static func validHex(_ s: String?) -> String? {
        guard var v = s?.trimmingCharacters(in: .whitespaces).uppercased() else { return nil }
        if !v.hasPrefix("#") { v = "#" + v }
        guard v.count == 7, UInt32(v.dropFirst(), radix: 16) != nil else { return nil }
        return v
    }

    func modeColor(_ g: Gear) -> String {
        switch g {
        case .walk: return walkColor
        case .eco: return ecoColor
        case .drive: return driveColor
        case .sport: return sportColor
        }
    }

    // MARK: JSON sharing

    struct Envelope: Codable {
        var app = "HackTheScoot"
        var kind = "dashboard-theme"
        var version = DashTheme.schemaVersion
        var theme: DashTheme
    }

    func exportJSON() -> Data? {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(Envelope(theme: self))
    }

    enum ImportError: Error, Equatable { case tooBig, notJSON, wrongKind }

    /// Accepts an envelope or a bare theme object.
    static func importJSON(_ data: Data) -> Result<DashTheme, ImportError> {
        guard data.count <= 64 * 1024 else { return .failure(.tooBig) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.notJSON) }
        if let kind = obj["kind"] as? String, kind != "dashboard-theme" { return .failure(.wrongKind) }
        let dec = JSONDecoder()
        if obj["theme"] != nil, let env = try? dec.decode(Envelope.self, from: data) { return .success(env.theme) }
        if let t = try? dec.decode(DashTheme.self, from: data) { return .success(t) }
        return .failure(.notJSON)
    }

    // MARK: Presets

    static var presets: [DashTheme] {
        var classic = DashTheme(); classic.name = "Classic"; classic.gauge = "classic"; classic.accent = "#FFB020"; classic.backgroundStyle = "black"; classic.font = "normal"
        var digital = DashTheme(); digital.name = "Minimal"; digital.gauge = "digital"; digital.accent = "#FFFFFF"; digital.backgroundStyle = "black"; digital.layout = "minimal"; digital.tiles = ["mode", "trip"]; digital.animationIntensity = 0.3
        var perf = DashTheme(); perf.name = "Performance"; perf.gauge = "performance"; perf.accent = "#FF3B3B"; perf.animationIntensity = 0.8
        var night = DashTheme(); night.name = "Night"; night.night = true; night.gauge = "digital"; night.accent = "#B33A3A"; night.background = "#000000"; night.backgroundStyle = "black"; night.layout = "focus"; night.animationIntensity = 0; night.tiles = ["mode", "limit"]
        night.walkColor = "#6E6E6E"; night.ecoColor = "#3D7A50"; night.driveColor = "#3A5C8C"; night.sportColor = "#8C3030"
        return [DashTheme(), classic, digital, perf, night]
    }
}

/// Information tiles the dashboard can show (Dashboard Designer).
enum DashTile: String, CaseIterable, Codable, Identifiable {
    case mode, limit, trip, tripTime, distance, avg, lightPark, signal, battery, odometer

    var id: String { rawValue }
    static let defaultOrder: [DashTile] = [.mode, .limit, .trip, .tripTime, .distance, .lightPark]

    var title: String {
        switch self {
        case .mode: return "Riding mode"
        case .limit: return "Mode limit"
        case .trip: return "Max this ride"
        case .tripTime: return "Ride time"
        case .distance: return "Distance (est.)"
        case .avg: return "Avg speed"
        case .lightPark: return "Light / Park"
        case .signal: return "Signal"
        case .battery: return "Battery"
        case .odometer: return "Odometer"
        }
    }
}

/// Saved named layouts (Dashboard Designer). Pure, Codable.
struct SavedLayouts: Codable, Equatable {
    var items: [DashTheme] = []
    static let max = 12

    mutating func save(_ t: DashTheme) {
        items.removeAll { $0.name == t.name }
        items.insert(t, at: 0)
        if items.count > SavedLayouts.max { items.removeLast(items.count - SavedLayouts.max) }
    }
}
