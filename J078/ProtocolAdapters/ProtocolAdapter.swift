import Foundation

// MARK: - Capability model
//
// Every scooter family is described by one adapter. An adapter declares, for every
// capability, how much evidence we have. The UI only shows a control when the
// connected device's adapter says that capability is writable. Unknown devices get
// GenericReadOnly: they can be watched (log, hex), never written to.

enum Capability: String, CaseIterable, Codable, Identifiable {
    case liveSpeed, ridingMode, setRidingMode, light, setLight, park, setPark
    case lock, setLock, units, setUnits, startMode, setStartMode
    case speedLimitRead, speedLimitWrite, battery, odometer, firmwareVersion, faultCodes, temperature

    var id: String { rawValue }

    var label: String {
        switch self {
        case .liveSpeed: return "Live speed"
        case .ridingMode: return "Riding mode (read)"
        case .setRidingMode: return "Change riding mode"
        case .light: return "Light (read)"
        case .setLight: return "Turn light on/off"
        case .park: return "Park state (read)"
        case .setPark: return "Park on/off"
        case .lock: return "Lock state (read)"
        case .setLock: return "Lock / unlock"
        case .units: return "Units (read)"
        case .setUnits: return "Change mph / km/h"
        case .startMode: return "Start mode (read)"
        case .setStartMode: return "Change start mode"
        case .speedLimitRead: return "Speed limit readout"
        case .speedLimitWrite: return "Set speed limit (factory range)"
        case .battery: return "Battery %"
        case .odometer: return "Odometer"
        case .firmwareVersion: return "Firmware version"
        case .faultCodes: return "Fault codes"
        case .temperature: return "Temperatures"
        }
    }

    /// true for capabilities that send something to the scooter.
    var isWrite: Bool {
        switch self {
        case .setRidingMode, .setLight, .setPark, .setLock, .setUnits, .setStartMode, .speedLimitWrite: return true
        default: return false
        }
    }
}

/// How sure we are about one capability on one adapter.
enum Evidence: String, Codable, CaseIterable {
    /// Seen in a real capture AND checked against what the rider saw.
    case verified
    /// Seen on the air, meaning partly guessed. Writes need an explicit confirmation.
    case experimental
    /// Shown as raw bytes only, never as a value (battery / odometer on the J078).
    case unverified
    /// Not available on this device as far as we know.
    case unsupported

    var label: String {
        switch self {
        case .verified: return "Verified"
        case .experimental: return "Experimental"
        case .unverified: return "Unverified"
        case .unsupported: return "Unsupported"
        }
    }
}

/// The five levels from the HackTheScoot plan.
enum CompatibilityLevel: String, Codable, CaseIterable {
    case full = "Full Support"
    case partial = "Partial Support"
    case diagnosticsOnly = "Diagnostics Only"
    case experimental = "Experimental"
    case unsupported = "Unsupported"

    var blurb: String {
        switch self {
        case .full: return "All advertised features passed hardware testing."
        case .partial: return "Only specific features are verified."
        case .diagnosticsOnly: return "Read-only information is available."
        case .experimental: return "Limited research support, no unverified writes."
        case .unsupported: return "No compatible communication method has been established."
        }
    }
}

/// How a device was matched. Advertising names can be changed or spoofed, so a
/// name-only match is never enough to enable writes: the adapter's channels must
/// also be found after connecting.
enum MatchConfidence: Int, Comparable {
    case none = 0, nameOnly = 1, services = 2, servicesAndName = 3
    static func < (a: MatchConfidence, b: MatchConfidence) -> Bool { return a.rawValue < b.rawValue }
}

protocol ProtocolAdapter {
    var id: String { get }
    var displayName: String { get }
    var family: String { get }
    var level: CompatibilityLevel { get }
    var capabilities: [Capability: Evidence] { get }
    /// Evidence lines shown in Diagnostics and the README (capture names, dates).
    var evidenceNotes: [String] { get }
    /// Factory maximum speed limit, km/h, as this adapter knows it (nil = unknown).
    var factoryMaxKmh: Int? { get }
    func match(name: String?, serviceIDs: [String]) -> MatchConfidence
}

extension ProtocolAdapter {
    func evidence(_ c: Capability) -> Evidence { return capabilities[c] ?? .unsupported }

    /// A write is offered on a normal screen only when it is verified.
    func canWrite(_ c: Capability) -> Bool { return c.isWrite && evidence(c) == .verified }

    /// Experimental writes live on the Experimental page behind a confirmation.
    func canWriteExperimentally(_ c: Capability) -> Bool { return c.isWrite && evidence(c) == .experimental }

    var verified: [Capability] { return Capability.allCases.filter { evidence($0) == .verified } }
    var experimental: [Capability] { return Capability.allCases.filter { evidence($0) == .experimental } }
    var unverified: [Capability] { return Capability.allCases.filter { evidence($0) == .unverified } }
    var unsupported: [Capability] { return Capability.allCases.filter { evidence($0) == .unsupported } }
}

/// Normalises a CoreBluetooth UUID string to the short names we match on.
enum ServiceID {
    static func short(_ s: String) -> String {
        let u = s.uppercased()
        if u.count == 4 { return u }
        if u.hasPrefix("0000"), u.hasSuffix("-0000-1000-8000-00805F9B34FB") {
            let i = u.index(u.startIndex, offsetBy: 4)
            let j = u.index(i, offsetBy: 4)
            return String(u[i..<j])
        }
        if u.count >= 8 { return String(u.prefix(8)) }
        return u
    }
}

// MARK: - Registry

enum AdapterRegistry {
    static let all: [ProtocolAdapter] = [Joyhis365Adapter(), VolpamAdapter()]
    static let generic: ProtocolAdapter = GenericReadOnlyAdapter()

    /// Best adapter for what we can see. Anything without a real match is GenericReadOnly.
    static func best(name: String?, serviceIDs: [String]) -> (ProtocolAdapter, MatchConfidence) {
        var best: (ProtocolAdapter, MatchConfidence) = (generic, .none)
        for a in all {
            let c = a.match(name: name, serviceIDs: serviceIDs)
            if c > best.1 { best = (a, c) }
        }
        return best
    }

    static func adapter(for kind: ScooterKind) -> ProtocolAdapter {
        switch kind {
        case .j078: return Joyhis365Adapter()
        case .volpam: return VolpamAdapter()
        case .nusOther, .unknown: return generic
        }
    }

    static func kind(for adapter: ProtocolAdapter) -> ScooterKind {
        switch adapter.id {
        case Joyhis365Adapter.adapterID: return .j078
        case VolpamAdapter.adapterID: return .volpam
        default: return .unknown
        }
    }
}

// MARK: - Joyhis J078 ("365 scooter" app, scrambled BD BE / DB EB frames)

struct Joyhis365Adapter: ProtocolAdapter {
    static let adapterID = "joyhis365"
    let id = Joyhis365Adapter.adapterID
    let displayName = "Joyhis J078"
    let family = "Joyhis / 365 scooter app (scrambled 6E400002/6E400003)"
    let level = CompatibilityLevel.partial
    let factoryMaxKmh: Int? = 31
    let capabilities: [Capability: Evidence] = [
        .liveSpeed: .verified,          // status byte 7-8, x10, checked against his 4/8/11/19 mph
        .ridingMode: .verified,
        .setRidingMode: .verified,      // cmd 05: 04/01/02/03 matched his order exactly
        .light: .verified,
        .setLight: .verified,           // cmd 00
        .park: .verified,
        .setPark: .verified,            // cmd 02, only after DB EB CA CA FF
        .units: .experimental,          // bit follows cmd 01, which value is mph is a guess
        .setUnits: .experimental,
        .startMode: .experimental,      // bit follows cmd 07, which is zero/glide is a guess
        .setStartMode: .experimental,
        .speedLimitRead: .verified,     // DB EB BA, matched 6/12/18/31 km/h
        .speedLimitWrite: .verified,    // sport only (A2); other gears are experimental, see Gear.limitWriteVerified
        .battery: .unverified,          // byte 10 = 100 in every capture
        .odometer: .unverified,         // bytes 23-26 never moved
        .firmwareVersion: .unsupported,
        .faultCodes: .unsupported,
        .temperature: .unsupported,
        .lock: .unsupported,
        .setLock: .unsupported,
    ]
    let evidenceNotes = [
        "Nov 9 13:31 sysdiagnose: commands, status frame, scramble table",
        "Nov 9 14:35 wheel-lift test: live speed x10 matched 4/8/11/19 mph",
        "Nov 9 17:11 + 15:23: speed-limit write BD BE AB A2 [kmh] and its ack; 32 km/h was clamped to 31",
    ]

    func match(name: String?, serviceIDs: [String]) -> MatchConfidence {
        // The J078 uses the 16-bit-base form of 6E400001 (…-0000-1000-8000-00805F9B34FB),
        // NOT the Nordic UART base. A "real" NUS device is not a J078.
        let hasService = serviceIDs.contains { u in
            let s = u.uppercased()
            return s == "6E400001" || s == "6E400001-0000-1000-8000-00805F9B34FB"
        }
        let hasName = (name ?? "").lowercased().hasPrefix("365_scooter")
        switch (hasService, hasName) {
        case (true, true): return .servicesAndName
        case (true, false): return .services
        case (false, true): return .nameOnly
        default: return .none
        }
    }
}

// MARK: - Zydtech family: Volpam (F1F0/F2F0, CRC16-Modbus frames)

struct VolpamAdapter: ProtocolAdapter {
    static let adapterID = "volpam"
    let id = VolpamAdapter.adapterID
    let displayName = "Volpam (Zydtech family)"
    /// Hiboy S2 Pro and AovoPro / 365GO are reported to use the same Zydtech protocol
    /// (F1F0/F1F1, AT+PWD, AC 00 0A, CRC16-Modbus). Only dad's Volpam is verified from a
    /// capture; those others stay unverified until someone captures one.
    let family = "Zydtech family: F1F1/F2F1 frames, CRC16-Modbus (Volpam verified; Hiboy S2 Pro, AovoPro 365GO unverified)"
    let level = CompatibilityLevel.partial
    let factoryMaxKmh: Int? = 35
    let capabilities: [Capability: Evidence] = [
        .speedLimitRead: .verified,     // 5A FA byte 6 and AC 01 00 limits followed the writes
        .speedLimitWrite: .verified,    // Modbus reg 0x20, km/h x10, CRC reproduced byte-for-byte; capped at 35
        .ridingMode: .experimental,     // status byte 4 followed eco/drive/sport 10 of 10 times, labels from order
        .setRidingMode: .experimental,  // feature-frame bits are guesses from button order
        .light: .experimental,
        .setLight: .experimental,
        .lock: .experimental,
        .setLock: .experimental,
        .units: .experimental,
        .setUnits: .experimental,
        .startMode: .experimental,
        .setStartMode: .experimental,
        .liveSpeed: .unverified,        // bytes 13-14 move with the wheel, unit unknown
        .battery: .unverified,          // byte 5 = 100 the whole run
        .odometer: .unsupported,
        .firmwareVersion: .unsupported,
        .faultCodes: .unsupported,
        .temperature: .unsupported,
        .park: .unsupported,
        .setPark: .unsupported,
    ]
    let evidenceNotes = [
        "Nov 9 17:46 sysdiagnose (dad's Volpam, run 17:42:49-17:45:27)",
        "CRC16-Modbus reproduces all 25 distinct written frames byte-for-byte",
        "Speed limit: 34.0 accepted, 35.7 clamped to 35, 37.3 declined -> factory cap 35 km/h",
        "Feature-frame bits (lock, light, gear, units, start) are lined up from button order only",
    ]

    func match(name: String?, serviceIDs: [String]) -> MatchConfidence {
        let ids = Set(serviceIDs.map { ServiceID.short($0) })
        let hasService = ids.contains("F1F0") || ids.contains("F2F0") || ids.contains("F1F1")
        return hasService ? .services : .none
    }
}

// MARK: - Everything else

struct GenericReadOnlyAdapter: ProtocolAdapter {
    static let adapterID = "generic"
    let id = GenericReadOnlyAdapter.adapterID
    let displayName = "Unknown device"
    let family = "Not identified: read-only"
    let level = CompatibilityLevel.diagnosticsOnly
    let factoryMaxKmh: Int? = nil
    let capabilities: [Capability: Evidence] = [:]
    let evidenceNotes = ["No protocol is known for this device. HackTheScoot only listens and logs; it sends nothing."]
    func match(name: String?, serviceIDs: [String]) -> MatchConfidence { return .none }
}
