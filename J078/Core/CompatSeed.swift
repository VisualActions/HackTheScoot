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
                    note: "Ninebot protocol researched, adapter not built yet. Read-only."),
        CompatEntry(id: "xiaomi-m365", manufacturer: "Xiaomi", model: "Mi Electric Scooter M365", level: .experimental, adapter: "ninebot", kind: .unknown,
                    note: "Ninebot-family protocol researched, adapter not built yet. Read-only."),
        CompatEntry(id: "kukirin-g4", manufacturer: "KuKirin", model: "G4", level: .experimental, adapter: "generic_readonly", kind: .unknown,
                    note: "No verified protocol. KuKirin warns against third-party apps, so no writes."),
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
