import Foundation
import CoreBluetooth

// J078 protocol, decoded on Nov 9 2026 from Credence's own Bluetooth captures
// (iPhone sysdiagnose, the 365 app talking to his J078). Things marked
// VERIFIED were seen on his scooter. Things marked UNVERIFIED are best guesses.
//
// v4: this file is Foundation + CoreBluetooth only (no SwiftUI), so the unit
// tests compile it directly. Every parser checks the length before it reads a
// byte, and every frame the app can send has a safety level (see CommandSafety).

// MARK: - Gears

enum Gear: Int, CaseIterable, Identifiable, Codable {
    case walk = 0, eco, drive, sport

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .walk: return "Walk"
        case .eco: return "Eco"
        case .drive: return "Drive"
        case .sport: return "Sport"
        }
    }

    /// Value for the gear command BD BE AB 05 [v]. VERIFIED.
    var setValue: UInt8 {
        switch self {
        case .walk: return 0x04
        case .eco: return 0x01
        case .drive: return 0x02
        case .sport: return 0x03
        }
    }

    /// Byte the app echoes in its 500 ms keep-alive BD BE AB [x] FF. VERIFIED.
    var keepAliveByte: UInt8 {
        switch self {
        case .eco: return 0xA0
        case .drive: return 0xA1
        case .sport: return 0xA2
        case .walk: return 0xA3
        }
    }

    /// Gear byte (index 5) in the status frame. VERIFIED.
    var statusCode: UInt8 {
        switch self {
        case .walk: return 0x08
        case .eco: return 0x10
        case .drive: return 0x20
        case .sport: return 0x40
        }
    }

    /// Gear byte in the speed-limit write BD BE AB [x] [kmh] and its ack DB EB BA [x] [kmh].
    /// Same byte as the keep-alive. A2 (sport) VERIFIED on Nov 9 (A2 1D, A2 1F).
    /// A0 eco / A1 drive / A3 walk follow the keep-alive pattern: UNVERIFIED (experimental).
    var limitByte: UInt8 { return keepAliveByte }

    /// true only for the gear whose speed-limit write was seen in his capture.
    var limitWriteVerified: Bool { return self == .sport }

    static func fromLimitByte(_ b: UInt8) -> Gear? {
        return Gear.allCases.first { $0.limitByte == b }
    }

    static func fromStatus(_ b: UInt8) -> Gear? {
        return Gear.allCases.first { $0.statusCode == b }
    }

    /// The x in the short reply DB EB BA [x] [kmh]: 0A eco, 1A drive, 2A sport, 3A walk.
    static func fromLimitCode(_ x: UInt8) -> Gear? {
        switch x >> 4 {
        case 0: return .eco
        case 1: return .drive
        case 2: return .sport
        case 3: return .walk
        default: return nil
        }
    }

    /// Limits his scooter reported on Nov 9 (km/h). VERIFIED: = 4 / 8 / 11 / 19 mph.
    /// Top speeds from his wheel-lift test on Nov 9 (mph). VERIFIED.
    var capturedTopMph: Int {
        switch self {
        case .walk: return 4
        case .eco: return 8
        case .drive: return 11
        case .sport: return 19
        }
    }

    /// mph for a km/h limit: the scooter's own mph table when it matches the capture.
    static func mph(for gear: Gear, kmh: Int) -> Int {
        if kmh == gear.capturedLimitKmh { return gear.capturedTopMph }
        return Int((Double(kmh) * Units.mphPerKmh).rounded())
    }

    /// The limits his scooter reported on Nov 9 (km/h). VERIFIED (= 4 / 8 / 11 / 19 mph).
    var capturedLimitKmh: Int {
        switch self {
        case .walk: return 6
        case .eco: return 12
        case .drive: return 18
        case .sport: return 31
        }
    }

    /// v4: the factory (stock) maximum is the ceiling for every speed-limit write.
    /// Credence's v4 spec: "Keep speed limits within documented factory values."
    /// The only documented values are the ones his scooter reported, so they are the caps.
    /// (Nov 9 15:23: the 365 app asked sport = 32 and the scooter itself kept 31.)
    var factoryMaxKmh: Int { return capturedLimitKmh }

    /// Lowest limit the app will ask for. Walk is fixed at its factory 6 km/h.
    var minLimitKmh: Int {
        switch self {
        case .walk: return 6
        default: return 6
        }
    }

    var limitRange: ClosedRange<Int> { return minLimitKmh...factoryMaxKmh }

    /// Walk has nothing to adjust (min == max), so its slider is hidden.
    var limitAdjustable: Bool { return minLimitKmh < factoryMaxKmh }
}

// MARK: - Scooter kinds (auto-detected)

enum ScooterKind: String, Codable, CaseIterable, Identifiable {
    case j078      // 365_scooter, service 6E400001-0000-1000-8000-00805F9B34FB, scrambled BD BE frames
    case volpam    // v1 path: F1F0 / F2F0 services, A5 02 FD 5A heartbeat on F1F1
    case nusOther  // a standard Nordic UART device (6E400001-B5A3-...), protocol unknown
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .j078: return "J078 (365 app protocol)"
        case .volpam: return "Volpam / F1F1 (v1 path)"
        case .nusOther: return "Other UART scooter (log only)"
        case .unknown: return "Unknown (log only)"
        }
    }

    var short: String {
        switch self {
        case .j078: return "J078"
        case .volpam: return "Volpam"
        case .nusOther: return "UART"
        case .unknown: return "?"
        }
    }
}

// MARK: - Live status

struct ScooterStatus: Equatable {
    /// Unscrambled bytes, kept whole so nothing is lost.
    var decoded: [UInt8]
    /// Bytes exactly as they came over the air (nil for frames that never had an air form).
    var raw: [UInt8]? = nil
    var flags: UInt8
    var gearCode: UInt8
    var gear: Gear?
    var speedTenths: Int

    var light: Bool { flags & 0x02 != 0 }        // VERIFIED
    var parked: Bool { flags & 0x04 != 0 }       // VERIFIED
    var startModeBit: Bool { flags & 0x10 != 0 } // VERIFIED it follows cmd 07; meaning UNVERIFIED
    var unitsBit: Bool { flags & 0x01 != 0 }     // VERIFIED it follows cmd 01; meaning UNVERIFIED
    /// Live speed in the scooter's CURRENT display unit (mph while it is set to mile). VERIFIED.
    var speed: Double { Double(speedTenths) / 10.0 }

    /// Any byte, bounds-checked.
    func byte(_ i: Int) -> UInt8? { return i >= 0 && i < decoded.count ? decoded[i] : nil }

    /// Byte 10 read 0x64 (100) in every capture. It MIGHT be battery %, but it never
    /// moved, so v4 does not show it as a battery value. Raw only (Developer Lab).
    var byte10Raw: UInt8? { return byte(10) }

    /// Bytes 23-26 (D0 97 01 00 in every capture). Might be an odometer, never seen
    /// changing, unit unknown. Raw only. v4 shows "unavailable" for the odometer.
    var bytes23to26Raw: [UInt8] { decoded.count >= 27 ? Array(decoded[23...26]) : [] }
}

/// Data we have NOT been able to verify. The UI uses this to say "unavailable"
/// instead of showing a guess as a fact.
enum UnverifiedData: String, CaseIterable {
    case battery = "Battery %"
    case odometer = "Odometer"
    case firmware = "Firmware version"
    case errors = "Error codes"
    case temperature = "Motor / controller temperature"
    case voltage = "Battery voltage"

    var why: String {
        switch self {
        case .battery: return "Status byte 10 read 100 in every capture and never moved. Not proven to be battery."
        case .odometer: return "Bytes 23-26 never changed in any capture; unit unknown."
        case .firmware: return "No firmware/version reply has been captured from the J078."
        case .errors: return "The 365 app has a fault-code reply (DB EB 20 B0) but none was ever captured."
        case .temperature: return "No temperature field has been identified."
        case .voltage: return "No voltage field has been identified."
        }
    }
}

// MARK: - Protocol

enum Proto {

    // Service / characteristics. The J078 uses the 16-bit Bluetooth base form
    // 6e400001-0000-1000-8000-00805f9b34fb, which iOS may show as just "6E400001",
    // so everything is matched by prefix.
    static let j078ServicePrefix = "6E400001"
    static let writePrefix = "6E400002"
    static let notifyPrefix = "6E400003"
    static let baseSuffix = "-0000-1000-8000-00805F9B34FB"
    static let shortIDs = ["F1F0", "F1F1", "F1F2", "F2F0", "F2F1", "F2F2"]
    static let advertisedName = "365_scooter"

    /// Short readable name for a UUID ("F1F1", "6E400003", or the full UUID).
    static func name(for uuid: CBUUID) -> String {
        let s = uuid.uuidString.uppercased()
        for short in shortIDs {
            if s == short || s.hasPrefix("0000" + short + "-") {
                return short
            }
        }
        for prefix in ["6E400001", "6E400002", "6E400003"] {
            if s.hasPrefix(prefix) {
                return prefix
            }
        }
        return s
    }

    /// Kind from the advertisement (before connecting).
    static func guessKind(name: String?, services: [CBUUID]) -> ScooterKind {
        if let n = name, n.lowercased().hasPrefix("365_scooter") {
            return .j078
        }
        return kind(fromServices: services)
    }

    /// Kind from a list of services (advertised or discovered).
    static func kind(fromServices services: [CBUUID]) -> ScooterKind {
        let names = services.map { $0.uuidString.uppercased() }
        if names.contains(where: { $0 == j078ServicePrefix || $0 == j078ServicePrefix + baseSuffix }) {
            return .j078
        }
        if names.contains(where: { $0.hasPrefix(j078ServicePrefix) }) {
            return .nusOther
        }
        let short = services.map { name(for: $0) }
        if short.contains("F1F0") || short.contains("F2F0") || short.contains("F1F1") {
            return .volpam
        }
        return .unknown
    }

    // MARK: Scramble (every 6E400002 / 6E400003 byte except the two raw frames). VERIFIED.

    static func encodeByte(_ b: UInt8) -> UInt8 {
        var x = b &+ 0xA4
        x ^= 0x29
        x = x &+ 0xC7
        x ^= 0x3A
        x ^= 0x7B
        x = x &+ 0xEB
        x ^= 0xDE
        return x
    }

    static func decodeByte(_ b: UInt8) -> UInt8 {
        var x = b ^ 0xDE
        x = x &- 0xEB
        x ^= 0x7B
        x ^= 0x3A
        x = x &- 0xC7
        x ^= 0x29
        x = x &- 0xA4
        return x
    }

    static func encode(_ bytes: [UInt8]) -> [UInt8] { return bytes.map { encodeByte($0) } }
    static func decode(_ bytes: [UInt8]) -> [UInt8] { return bytes.map { decodeByte($0) } }

    /// Self-check: decode(encode(x)) == x for all 256 values.
    static var scrambleSelfTestOK: Bool {
        return (0...255).allSatisfy { decodeByte(encodeByte(UInt8($0))) == UInt8($0) }
    }

    // MARK: Frames app -> scooter

    /// Sent RAW (not scrambled) on connect and every few seconds. VERIFIED.
    static let helloRaw: [UInt8] = [0xBD, 0xBE, 0xAF, 0xFF, 0xFF]
    /// Sent RAW now and then. VERIFIED it is sent; purpose unknown.
    static let pingRaw: [UInt8] = [0xBD, 0xBE, 0xAC, 0xCC, 0xCC]

    enum Cmd {
        static let light: UInt8 = 0x00      // 01 on / 00 off. VERIFIED
        static let units: UInt8 = 0x01      // 00 / 01. UNVERIFIED which is km vs mile
        static let park: UInt8 = 0x02       // 01 on / 00 off. VERIFIED
        static let gear: UInt8 = 0x05       // see Gear.setValue. VERIFIED
        static let startMode: UInt8 = 0x07  // 00 / 01. UNVERIFIED which is zero vs glide
    }

    /// Decoded form; encode() before writing.
    static func command(_ cmd: UInt8, _ value: UInt8) -> [UInt8] {
        return [0xBD, 0xBE, 0xAB, cmd, value]
    }

    /// 500 ms keep-alive echoing the current gear (decoded form). VERIFIED.
    static func keepAlive(_ gear: Gear) -> [UInt8] {
        return [0xBD, 0xBE, 0xAB, gear.keepAliveByte, 0xFF]
    }

    /// BD BE AC AC + 6 ASCII digits (decoded form). The 365 app sent "000000"
    /// right before park; the reply DB EB CA CA FF = OK. VERIFIED.
    static func password(_ pin: String) -> [UInt8] {
        var digits = Array(pin.utf8.filter { $0 >= 0x30 && $0 <= 0x39 }.prefix(6))
        while digits.count < 6 { digits.append(0x30) }
        return [0xBD, 0xBE, 0xAC, 0xAC] + digits
    }

    // MARK: Frames scooter -> app (decoded)

    /// Status frames were 29 bytes in every capture. Anything shorter than 9 cannot
    /// hold the speed; anything over 64 is not a status frame.
    static let statusMinLength = 9
    static let statusMaxLength = 64

    static func parseStatus(_ d: [UInt8]) -> ScooterStatus? {
        guard d.count >= statusMinLength, d.count <= statusMaxLength,
              d[0] == 0xDB, d[1] == 0xEB, d[2] == 0xFA, d[3] == 0xDB else { return nil }
        let speed = (Int(d[7]) << 8) | Int(d[8])   // big-endian, x10. VERIFIED (byte 8; byte 7 stayed 0)
        return ScooterStatus(decoded: d, flags: d[4], gearCode: d[5], gear: Gear.fromStatus(d[5]), speedTenths: speed)
    }

    /// DB EB BA [x] [kmh] = that gear's speed limit in km/h. VERIFIED.
    static func parseLimit(_ d: [UInt8]) -> (Gear, Int)? {
        guard d.count >= 5, d.count <= 20, d[0] == 0xDB, d[1] == 0xEB, d[2] == 0xBA,
              d[3] & 0x0F == 0x0A, let g = Gear.fromLimitCode(d[3]) else { return nil }
        return (g, Int(d[4]))
    }

    /// Speed-limit write (decoded form): BD BE AB [gear byte] [kmh]. VERIFIED for sport (A2).
    /// v4: returns nil (nothing to send) when the value is outside the factory range.
    /// There is no above-stock unlock any more.
    static func setLimit(_ gear: Gear, kmh: Int) -> [UInt8]? {
        guard gear.limitRange.contains(kmh) else { return nil }
        return [0xBD, 0xBE, 0xAB, gear.limitByte, UInt8(kmh)]
    }

    /// Ack to a speed-limit write: DB EB BA [gear byte] [kmh the scooter actually set]. VERIFIED (A2).
    /// Nov 9 15:23: the 365 app asked A2 20 (32 km/h), the scooter acked A2 1F (kept 31).
    static func parseLimitAck(_ d: [UInt8]) -> (Gear, Int)? {
        guard d.count >= 5, d.count <= 20, d[0] == 0xDB, d[1] == 0xEB, d[2] == 0xBA, let g = Gear.fromLimitByte(d[3]) else { return nil }
        return (g, Int(d[4]))
    }

    /// Exactly DB EB CA CA FF. VERIFIED. This is the ONLY thing that unlocks park.
    static func isPasswordOK(_ d: [UInt8]) -> Bool {
        return d.count >= 5 && d.count <= 8 && d[0] == 0xDB && d[1] == 0xEB && d[2] == 0xCA && d[3] == 0xCA && d[4] == 0xFF
    }

    static func isPasswordWrong(_ d: [UInt8]) -> Bool {
        return d.count >= 5 && d.count <= 8 && d[0] == 0xDB && d[1] == 0xEB && d[2] == 0xCA && d[3] == 0xCA && d[4] == 0xAA
    }

    /// Label for a decoded J078 frame, for the log.
    static func label(_ d: [UInt8]) -> String {
        if let s = parseStatus(d) {
            let g = s.gear?.name ?? String(format: "?%02X", s.gearCode)
            let sp = String(format: "%.1f", s.speed)
            let fl = String(format: "%02X", s.flags)
            return "status: \(g), speed \(sp), light \(s.light ? "on" : "off"), park \(s.parked ? "on" : "off"), flags \(fl)"
        }
        if let ack = parseLimitAck(d) {
            return "speed limit ack: \(ack.0.name) set to \(ack.1) km/h"
        }
        if let lim = parseLimit(d) {
            return "limit: \(lim.0.name) = \(lim.1) km/h"
        }
        if isPasswordOK(d) { return "password OK" }
        if isPasswordWrong(d) { return "password WRONG" }
        if d.count >= 3 && d[0] == 0xDB && d[1] == 0xEB {
            return String(format: "DB EB %02X reply (not in the map yet)", d[2])
        }
        return ""
    }

    /// Label for a decoded frame the app sends.
    static func txLabel(_ d: [UInt8]) -> String {
        guard d.count >= 5, d[0] == 0xBD, d[1] == 0xBE else { return "" }
        if d[2] == 0xAC && d.count >= 10 && d[3] == 0xAC { return "password" }
        guard d[2] == 0xAB else { return "" }
        switch d[3] {
        case Cmd.light: return d[4] == 1 ? "light on" : "light off"
        case Cmd.park: return d[4] == 1 ? "park on" : "park off"
        case Cmd.units: return String(format: "units %02X", d[4])
        case Cmd.startMode: return String(format: "start mode %02X", d[4])
        case Cmd.gear:
            let g = Gear.allCases.first { $0.setValue == d[4] }
            return "gear " + (g?.name ?? "?")
        case 0xA0...0xA3:
            if d[4] == 0xFF { return "keep-alive" }
            let g = Gear.fromLimitByte(d[3])
            return "set speed limit \(g?.name ?? "?") = \(d[4]) km/h"
        default: return ""
        }
    }

    // MARK: Volpam / F1F1 (v1 path, from the vendor app, UNVERIFIED on a real Volpam)

    static let volpamHeartbeat: [UInt8] = [0xA5, 0x02, 0xFD, 0x5A]
    static let volpamHeartbeatInterval: TimeInterval = 0.5

    /// CRC16-Modbus (init FFFF, poly A001 reflected). v4: CONFIRMED on the Volpam,
    /// it reproduces all 25 distinct frames in the 17:46 capture byte-for-byte.
    static func crc16Modbus(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in data {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc = crc >> 1
                }
            }
        }
        return crc
    }

    static func rawHints(_ b: [UInt8]) -> String {
        var hints: [String] = []
        if b.count >= 4, b[0] == 0xA5, b[b.count - 1] == 0x5A {
            hints.append(String(format: "A5 frame, cmd %02X", b[1]))
        }
        if b.count >= 5 {
            let body = Array(b[0..<(b.count - 2)])
            let crc = crc16Modbus(body)
            if b[b.count - 2] == UInt8(crc & 0xFF) && b[b.count - 1] == UInt8(crc >> 8) {
                hints.append("CRC16-Modbus OK")
            }
        }
        return hints.joined(separator: ", ")
    }

    // MARK: Helpers

    static func hex(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func kmhToMph(_ v: Double) -> Double { return Units.kmhToMph(v) }

    // MARK: Volpam
    // The Volpam protocol (CRC16-Modbus framed, F1F1 / F2F1) lives in VolpamProtocol.swift.
}
