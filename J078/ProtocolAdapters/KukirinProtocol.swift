import Foundation

// MARK: - KuKirin G2 (2026) / G4: READ-ONLY live data (v5.1, EXPERIMENTAL, UNTESTED ON HARDWARE)
//
// Clean-room. Written only from published FACTS (byte positions and meanings), never from
// anyone's code:
//  - KuKirin G2 (2026): observations published by joaobenites/bancada-g2 (no licence, so
//    facts only, nothing copied). Service FFF0, notify FFF2, write FFF1 (commands unknown),
//    two alternating 20-byte frames typed by bytes 0-1: 27 22 and F2 B0.
//  - KuKirin G4: observations published by maksdoner/Kukirin-G4-Bluetooth-Control (MIT).
//    Notify FFF2, byte 6 == 0x00 gate, byte 5 = ride mode 01/02/03.
// See ACKNOWLEDGEMENTS.md.
//
// NOTHING is ever written to a KuKirin: no control command is publicly known, and F000FFC0
// is TI's firmware-update (OAD) service, which can brick the module.

enum KukirinProto {
    static let service = "FFF0"
    static let notifyChar = "FFF2"
    /// The write characteristic exists, but no command is known. HackTheScoot never writes it.
    static let writeChar = "FFF1"
    /// TI OAD firmware update. Never written, never subscribed.
    static let oadService = "F000FFC0"

    enum Model: String, Codable, Equatable {
        case g2 = "G2 (2026)"
        case g4 = "G4"
        case unknown = "KuKirin (model not recognised)"
    }

    static func model(fromName name: String?) -> Model {
        let n = (name ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        if n.hasPrefix("G4") || n.contains("KUKIRIN G4") || n.contains("KUKIRING4") { return .g4 }
        if n.hasPrefix("G2") || n.contains("KUKIRIN G2") || n.contains("KUKIRING2") { return .g2 }
        return .unknown
    }

    static func g2Mode(_ b: UInt8) -> String? {
        switch b {
        case 0x0F: return "Eco"
        case 0x14: return "Sport"
        case 0x19: return "Race"
        default: return nil
        }
    }

    static func g4Mode(_ b: UInt8) -> String? {
        switch b {
        case 0x01: return "Eco"
        case 0x02: return "Sport"
        case 0x03: return "Race"
        default: return nil
        }
    }
}

struct KukirinTelemetry: Equatable {
    var model: KukirinProto.Model = .unknown
    var speedKmh: Int?
    var batteryVolts: Double?
    var motorRpm: Int?
    var motorActive: Bool?
    var rideMode: String?
    var g2MainFrames = 0
    var g2ModeFrames = 0
    var g4Frames = 0
    var ignoredFrames = 0

    init(model: KukirinProto.Model = .unknown) { self.model = model }

    var validFrames: Int { return g2MainFrames + g2ModeFrames + g4Frames }

    private static func u16le(_ b: [UInt8], _ i: Int) -> Int? {
        guard b.count >= i + 2 else { return nil }
        return Int(b[i]) | (Int(b[i + 1]) << 8)
    }

    /// One FFF2 notification. Never crashes on short, long or junk input.
    mutating func feed(_ b: [UInt8]) {
        guard b.count >= 2, b.count <= 64 else { ignoredFrames += 1; return }
        if b.allSatisfy({ $0 == 0xFF }) { ignoredFrames += 1; return }      // the first all-FF block
        if b[0] == 0x27, b[1] == 0x22, b.count >= 19 {
            if model == .unknown { model = .g2 }
            g2MainFrames += 1
            if let v = KukirinTelemetry.u16le(b, 4) {
                let volts = Double(v) / 100.0
                if (20.0...100.0).contains(volts) { batteryVolts = volts }
            }
            if let r = KukirinTelemetry.u16le(b, 10), r < 20_000 { motorRpm = r }
            if b[12] <= 90 { speedKmh = Int(b[12]) }
            motorActive = (b[18] & 0x02) != 0
            return
        }
        if b[0] == 0xF2, b[1] == 0xB0, b.count >= 4 {
            if model == .unknown { model = .g2 }
            g2ModeFrames += 1
            if let m = KukirinProto.g2Mode(b[3]) { rideMode = m }
            return
        }
        if model == .g4, b.count >= 7, b[6] == 0x00, let m = KukirinProto.g4Mode(b[5]) {
            g4Frames += 1
            rideMode = m
            return
        }
        ignoredFrames += 1
    }
}

struct KukirinAdapter: ProtocolAdapter {
    static let adapterID = "kukirin"
    let id = KukirinAdapter.adapterID
    let displayName = "KuKirin G2 (2026) / G4"
    let family = "KuKirin FFF0 / FFF2 telemetry, read-only"
    let level = CompatibilityLevel.experimental
    let factoryMaxKmh: Int? = nil
    let capabilities: [Capability: Evidence] = [
        .liveSpeed: .unverified,
        .ridingMode: .unverified,
        .battery: .unverified,
    ]
    let evidenceNotes = [
        "Experimental, untested on hardware. Read-only: HackTheScoot never writes to a KuKirin.",
        "G2 (2026): speed, battery voltage, motor rpm and ride mode, from observations published by joaobenites/bancada-g2 (facts only).",
        "G4: ride mode only, from observations published by maksdoner/Kukirin-G4-Bluetooth-Control (MIT).",
        "No control command is publicly known for any KuKirin. A capture with the official app is how we learn them.",
    ]

    func match(name: String?, serviceIDs: [String]) -> MatchConfidence {
        let hasService = serviceIDs.contains { ServiceID.short($0) == KukirinProto.service }
        let n = (name ?? "").uppercased()
        let hasName = n.contains("KUKIRIN") || n.contains("KUGOO") || KukirinProto.model(fromName: name) != .unknown
        switch (hasService, hasName) {
        case (true, true): return .servicesAndName
        // FFF0 alone is a generic TI service used by lots of gadgets: not enough on its own.
        case (true, false): return .none
        case (false, true): return n.contains("KUKIRIN") || n.contains("KUGOO") ? .nameOnly : .none
        default: return .none
        }
    }
}
