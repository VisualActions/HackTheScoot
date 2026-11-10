import Foundation

/// The research compatibility database seed (docs/compat/seed/compat-db.seed.json on
/// the research-docs branch, db 0.1.0), compiled in so the Garage and onboarding work
/// offline. Levels are copied as-is: nothing here is "full" because nothing is.
struct CompatEntry: Identifiable, Equatable {
    let id: String
    let manufacturer: String
    let model: String
    let level: CompatibilityLevel
    /// Adapter id from the research DB (joyhis365 / zydtech365 / ninebot / generic_readonly), nil = none.
    let adapter: String?
    /// Which app protocol path this model uses today.
    let kind: ScooterKind
    let note: String

    var displayName: String { return "\(manufacturer) \(model)" }
}

enum CompatSeed {
    static let dbVersion = "0.1.0"

    static let entries: [CompatEntry] = [
        CompatEntry(id: "joyhis-j078", manufacturer: "Joyhis", model: "J078", level: .partial, adapter: "joyhis365", kind: .j078,
                    note: "365 app protocol. Speed, mode, light, park and speed limits verified from captures. Battery and odometer unverified."),
        CompatEntry(id: "volpam-dad", manufacturer: "VOLPAM", model: "VOLPAM (exact model unverified)", level: .partial, adapter: "zydtech365", kind: .volpam,
                    note: "Zydtech / 365 family. Bluetooth password, heartbeat and speed limit (stock cap) from captures."),
        CompatEntry(id: "hiboy-s2-pro", manufacturer: "Hiboy", model: "S2 Pro", level: .experimental, adapter: "zydtech365", kind: .unknown,
                    note: "Same Zydtech shape as the Volpam per a public writeup. No capture yet, so read-only."),
        CompatEntry(id: "ninebot-max-g30", manufacturer: "Segway-Ninebot", model: "KickScooter Max G30", level: .experimental, adapter: "ninebot", kind: .unknown,
                    note: "v5.1, experimental, untested on hardware: live data (reads only), pairing for encrypted firmware with HackTheScoot's own clean-room code, and one experimental setting, cruise control. Lights, KERS, speed mode and max speed stay off (the sources disagree)."),
        CompatEntry(id: "xiaomi-m365", manufacturer: "Xiaomi", model: "Mi Electric Scooter M365", level: .experimental, adapter: "xiaomi365", kind: .unknown,
                    note: "v5.1, experimental, untested on hardware. Old (plain) Bluetooth firmware: live data plus experimental KERS, cruise and tail light, each read first, confirmed, written once and read back. Newer Xiaomi login firmware: not supported."),
        CompatEntry(id: "xiaomi-m365-pro", manufacturer: "Xiaomi", model: "M365 Pro / Pro 2 / 1S / Essential", level: .experimental, adapter: "xiaomi365", kind: .unknown,
                    note: "v5.1, experimental, untested on hardware: pairs with HackTheScoot's own clean-room Ninebot encryption (press the power button), then live data only. No writes."),
        CompatEntry(id: "fardriver-nd", manufacturer: "Fardriver", model: "ND controller (e-bikes, e-scooters)", level: .experimental, adapter: "fardriver", kind: .unknown,
                    note: "v4.2 read-only adapter from the MIT-licensed public Fardriver notes: volts, amps, motor speed and fault bits, all unverified. Never written to."),
        CompatEntry(id: "kukirin-g2", manufacturer: "KuKirin", model: "G2 (2026)", level: .experimental, adapter: "kukirin", kind: .unknown,
                    note: "v5.1, experimental, untested on hardware: live speed, battery voltage, motor rpm and ride mode, read-only. No KuKirin control command is public, so nothing is ever written."),
        CompatEntry(id: "kukirin-g4", manufacturer: "KuKirin", model: "G4", level: .experimental, adapter: "kukirin", kind: .unknown,
                    note: "v5.1, experimental, untested on hardware: ride mode only, read-only. No KuKirin control command is public, so nothing is ever written."),
        CompatEntry(id: "dualtron-ey4", manufacturer: "Minimotors", model: "Dualtron (EY3 Connect / EY4 / EYA)", level: .unsupported, adapter: nil, kind: .unknown,
                    note: "No public protocol. Unsupported for now.")
    ]

    /// Anything not in the seed.
    static let other = CompatEntry(id: "other", manufacturer: "Other", model: "scooter", level: .diagnosticsOnly, adapter: "generic_readonly",
                                   kind: .unknown, note: "Not in the database yet: log and raw data only.")

    static func find(_ id: String?) -> CompatEntry {
        guard let id = id else { return other }
        return entries.first { $0.id == id } ?? other
    }

    /// The seed entry that matches what the app detected on connect.
    static func bestMatch(for kind: ScooterKind) -> CompatEntry {
        switch kind {
        case .j078: return find("joyhis-j078")
        case .volpam: return find("volpam-dad")
        default: return other
        }
    }

    static var all: [CompatEntry] { return entries + [other] }
}
