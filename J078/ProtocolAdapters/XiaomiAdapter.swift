import Foundation

// MARK: - Xiaomi M365 family (v5.1, EXPERIMENTAL, UNTESTED ON HARDWARE)
//
// Matched by name ("MIScooter...") on the standard Nordic UART service. The session itself
// (plain M365 first, then plain Ninebot, then pairing for the Ninebot-encrypted models) is
// NBXDriver. Writes are NOT in the capability model: the only ones are the three
// experimental M365 (plain) settings in NBXSetting, behind a read, a confirmation and a
// read-back. Every other model stays read-only.

struct XiaomiM365Adapter: ProtocolAdapter {
    static let adapterID = "xiaomi365"
    static let nordicUART = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    let id = XiaomiM365Adapter.adapterID
    let displayName = "Xiaomi M365 family"
    let family = "Xiaomi 55 AA (plain M365) or Ninebot Encryption2 (Pro, Pro 2, 1S, Essential)"
    let level = CompatibilityLevel.experimental
    let factoryMaxKmh: Int? = 25
    let capabilities: [Capability: Evidence] = [
        .liveSpeed: .unverified,
        .battery: .unverified,
        .odometer: .unverified,
        .firmwareVersion: .unverified,
        .faultCodes: .unverified,
        .temperature: .unverified,
    ]
    let evidenceNotes = [
        "Experimental, untested on hardware.",
        "Plain M365 (old Bluetooth firmware): live data, plus experimental KERS, cruise and tail light (read first, confirm, write, read back).",
        "M365 Pro, Pro 2, 1S, Essential: HackTheScoot's own clean-room Ninebot pairing (Apache-2.0 spec), read-only.",
        "M365 on the newer Xiaomi login: not supported (the only public code is AGPL).",
    ]

    func match(name: String?, serviceIDs: [String]) -> MatchConfidence {
        let n = (name ?? "").lowercased()
        let hasName = n.hasPrefix("miscooter") || n.hasPrefix("mi scooter") || n.contains("xiaomi") || n.hasPrefix("mi electric")
        let hasNUS = serviceIDs.contains { $0.uppercased() == XiaomiM365Adapter.nordicUART }
        switch (hasNUS, hasName) {
        case (true, true): return .servicesAndName
        // The Nordic UART service alone is used by lots of devices (and the name alone can
        // be anything): never enough on its own to be more than a name match.
        case (false, true): return .nameOnly
        default: return .none
        }
    }
}
