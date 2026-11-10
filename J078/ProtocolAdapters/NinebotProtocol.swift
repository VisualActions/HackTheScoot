import Foundation

// MARK: - Segway-Ninebot (KickScooter Max G30 first)
//
// CLEAN-ROOM, READ-ONLY. Written from the Apache-2.0 "Segway-Ninebot BLE Protocol" docs
// by NootNooot, https://nootnooot.codeberg.page/segway-ninebot-ble/ (frame formats,
// checksum, command reference). No code copied from scooterhacking's repos
// (NinebotCrypto is AGPL; most others have no license).
//
// Protocol 2 frame: 5A A5 | LEN | 3E | TARGET | CMD | INDEX | payload(LEN) | cs lo, cs hi
// Read replies use CMD 0x04. Current production firmware wraps this in AES
// ("Encryption2"), which needs a handshake = writes, so it stays off here.
//
// A Ninebot only answers when asked, and asking is a write, so on most scooters this
// adapter will see nothing until a real capture confirms the read request. Writes stay
// off until then.

enum NinebotProto {
    static let service = "6E400001-0000-0000-006E-696E65626F74"
    static let btID: UInt8 = 0x3E
    static let cmdReadResponse: UInt8 = 0x04
    static let boardDIS: UInt8 = 0x01

    /// Checksum per the docs: inverted sum of LEN..end of payload. The docs print a 15-bit
    /// mask; classic M365 tools use 16 bits, so both are accepted.
    static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        let total = bytes.reduce(0) { $0 + Int($1) }
        return UInt16(~total & 0xFFFF)
    }

    struct Frame: Equatable {
        let target: UInt8
        let cmd: UInt8
        let index: UInt8
        let payload: [UInt8]
    }

    enum Parsed: Equatable {
        case frame(Frame)
        case encrypted
        case rejected(String)
    }

    static func parse(_ b: [UInt8]) -> Parsed {
        guard b.count >= 9 else { return .rejected("too short") }
        guard b[0] == 0x5A, b[1] == 0xA5 else { return .rejected("no 5A A5 header") }
        let len = Int(b[2])
        if b.count == len + 13 { return .encrypted }          // Encryption2: plaintext + 6 bytes
        guard b.count == len + 9 else { return .rejected("length \(b.count) doesn't match LEN \(len)") }
        guard b[3] == btID else { return .rejected("BT_ID isn't 3E") }
        let cs = checksum(b[2..<(7 + len)])
        let got = UInt16(b[7 + len]) | (UInt16(b[8 + len]) << 8)
        guard got == cs || got == (cs & 0x7FFF) else { return .rejected("checksum mismatch") }
        return .frame(Frame(target: b[4], cmd: b[5], index: b[6], payload: Array(b[7..<(7 + len)])))
    }

    /// Builds a valid Protocol 2 frame (tests and the offline decoder; never sent).
    static func makeFrame(target: UInt8, cmd: UInt8, index: UInt8, payload: [UInt8]) -> [UInt8] {
        var f: [UInt8] = [0x5A, 0xA5, UInt8(payload.count), btID, target, cmd, index] + payload
        let cs = checksum(f[2...])
        f += [UInt8(cs & 0xFF), UInt8(cs >> 8)]
        return f
    }
}

struct NinebotTelemetry: Equatable {
    var speedKmh: Double?
    var batteryPercent: Int?
    var odometerKm: Double?
    var rangeKm: Double?
    var validFrames = 0
    var encryptedFrames = 0
    var rejectedFrames = 0

    mutating func apply(_ f: NinebotProto.Frame) {
        validFrames += 1
        guard f.cmd == NinebotProto.cmdReadResponse, f.target == NinebotProto.boardDIS else { return }
        let p = f.payload
        func u16(_ i: Int) -> Int? { return p.count >= i + 2 ? Int(p[i]) | (Int(p[i + 1]) << 8) : nil }
        func u32(_ i: Int) -> Int? {
            guard p.count >= i + 4 else { return nil }
            return Int(p[i]) | (Int(p[i + 1]) << 8) | (Int(p[i + 2]) << 16) | (Int(p[i + 3]) << 24)
        }
        switch f.index {
        case 0x26: if let v = u16(0) { speedKmh = Double(Int16(truncatingIfNeeded: v)) / 10.0 }
        case 0xB5: if let v = u16(0), (0...100).contains(v) { batteryPercent = v }
        case 0xB7: if let v = u32(0) { odometerKm = Double(v) / 1000.0 }
        case 0x25: if let v = u16(0) { rangeKm = Double(v) / 10.0 }
        default: break
        }
    }

    mutating func feed(_ bytes: [UInt8]) {
        switch NinebotProto.parse(bytes) {
        case .frame(let f): apply(f)
        case .encrypted: encryptedFrames += 1
        case .rejected: rejectedFrames += 1
        }
    }
}

struct NinebotAdapter: ProtocolAdapter {
    static let adapterID = "ninebot"
    let id = NinebotAdapter.adapterID
    let displayName = "Ninebot / Segway (Max G30)"
    let family = "Segway-Ninebot BLE (Protocol 2 / Encryption2), read-only"
    let level = CompatibilityLevel.experimental
    let factoryMaxKmh: Int? = 30
    let capabilities: [Capability: Evidence] = [
        .liveSpeed: .unverified,
        .battery: .unverified,
        .odometer: .unverified,
    ]
    let evidenceNotes = [
        "Clean-room from the Apache-2.0 NootNooot Segway-Ninebot BLE docs (frames, checksum, registers).",
        "No capture from a real G30 yet: read-only, writes off.",
        "Most Ninebots only answer when asked (a write), and new firmware is encrypted, so live data may stay empty until a capture.",
    ]

    func match(name: String?, serviceIDs: [String]) -> MatchConfidence {
        let hasService = serviceIDs.contains { $0.uppercased() == NinebotProto.service }
        let n = (name ?? "").lowercased()
        let hasName = n.contains("ninebot") || n.hasPrefix("nbscooter") || n.hasPrefix("miscooter") || n.hasPrefix("segway")
        switch (hasService, hasName) {
        case (true, true): return .servicesAndName
        case (true, false): return .services
        case (false, true): return .nameOnly
        default: return .none
        }
    }
}
