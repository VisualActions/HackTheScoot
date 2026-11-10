import Foundation

// Volpam (dad's scooter) protocol, decoded from the Nov 9 17:46 sysdiagnose
// (the vendor app talking to the real Volpam, run 17:42:49-17:45:27).
//
// GATT (from the capture's ATT discovery):
//   service F1F0: F1F1 (write)  <- AC feature frames, A5 heartbeats, Modbus frames
//                 F2F1 (notify) -> AC 00 00 status, AC 01 00 limits, 01 03 replies, 5A FA
//   service F2F0: F1F2 (write)  <- Bluetooth password (ASCII "AT+PWD[......]")
//                 F2F2 (notify) -> "OK+PWD:Y"
//
// CRC: CRC16-Modbus (init FFFF, poly A001 reflected), low byte first.
// CONFIRMED: it reproduces the last two bytes of all 25 distinct frames the app
// wrote (441 writes) and of the CRC-carrying notifications, byte-for-byte.
//
// The Bluetooth password is never stored in code, the README or the log:
// the user types it, it lives in the iOS Keychain, and the log shows "AT+PWD[******]".

enum VolpamProto {

    static let writeChar = "F1F1"
    static let passwordChar = "F1F2"
    static let dataNotifyChar = "F2F1"
    static let authNotifyChar = "F2F2"

    // MARK: CRC

    static func crc16(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in data {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    static func withCRC(_ body: [UInt8]) -> [UInt8] {
        let c = crc16(body)
        return body + [UInt8(c & 0xFF), UInt8(c >> 8)]
    }

    static func crcOK(_ frame: [UInt8]) -> Bool {
        guard frame.count >= 4 else { return false }
        let body = Array(frame[0..<(frame.count - 2)])
        let c = crc16(body)
        return frame[frame.count - 2] == UInt8(c & 0xFF) && frame[frame.count - 1] == UInt8(c >> 8)
    }

    // MARK: Session frames (sent by the vendor app, VERIFIED on the air)

    static let sessionStart: [UInt8] = [0xA5, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5A]
    static let heartbeat: [UInt8] = [0xA5, 0x02, 0xFD, 0x5A]
    static let settingsHeartbeat: [UInt8] = [0xA5, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x5A]
    static let heartbeatInterval: TimeInterval = 0.5

    /// ASCII "AT+PWD[" + 6 digits + "]". Returns nil unless it is exactly 6 digits.
    static func passwordFrame(_ pin: String) -> [UInt8]? {
        let digits = Array(pin.utf8)
        guard digits.count == 6, digits.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return Array("AT+PWD[".utf8) + digits + Array("]".utf8)
    }

    static let passwordMask = "AT+PWD[******]"

    /// "OK+PWD:Y" came back on F2F2 right after the password. VERIFIED.
    static func isPasswordOK(_ b: [UInt8]) -> Bool {
        guard b.count >= 8, b.count <= 20 else { return false }
        return Array(b.prefix(8)) == Array("OK+PWD:Y".utf8)
    }

    /// "OK+PWD:N" is a GUESS at the failure reply (never captured). Anything that
    /// is not exactly OK+PWD:Y counts as not signed in anyway.
    static func isPasswordRejected(_ b: [UInt8]) -> Bool {
        guard b.count >= 8, b.count <= 20 else { return false }
        return Array(b.prefix(7)) == Array("OK+PWD:".utf8) && b[7] != 0x59
    }

    // MARK: Speed limit (Modbus write, register 0x0020, value = km/h x 10)

    static let speedRegister: UInt8 = 0x20
    /// Factory sport limit his dad's Volpam reported (AC 01 00 byte 6 = 0x23 = 35 km/h).
    static let factoryMaxTenths = 350
    static let minTenths = 60

    /// The three writes in the capture, all reproduced byte-for-byte in the tests.
    static let capturedSpeedWrites: [[UInt8]] = [
        [0x01, 0x10, 0x00, 0x20, 0x00, 0x01, 0x02, 0x01, 0x54, 0xA1, 0x5F], // 34.0 -> accepted (34)
        [0x01, 0x10, 0x00, 0x20, 0x00, 0x01, 0x02, 0x01, 0x65, 0x60, 0x8B], // 35.7 -> clamped to 35
        [0x01, 0x10, 0x00, 0x20, 0x00, 0x01, 0x02, 0x01, 0x75, 0x61, 0x47], // 37.3 -> declined, stayed 35
    ]

    /// nil when outside 6.0...35.0 km/h (no above-factory writes, ever).
    static func speedLimitWrite(tenthsKmh: Int) -> [UInt8]? {
        guard tenthsKmh >= minTenths, tenthsKmh <= factoryMaxTenths else { return nil }
        let v = UInt16(tenthsKmh)
        return withCRC([0x01, 0x10, 0x00, speedRegister, 0x00, 0x01, 0x02, UInt8(v >> 8), UInt8(v & 0xFF)])
    }

    // MARK: Feature frame AC 00 0A [flags] [walk] [eco] [drive] [sport] crc  (EXPERIMENTAL)
    //
    // Bit meanings come from the ORDER of his button presses lined up against
    // the frames AND the status echo (byte 22 / byte 21). They are not proven on screen.

    enum Flag {
        static let unlocked: UInt8 = 0x80   // 0x62 sent on "lock", 0xE2 on "unlock"
        static let unitsBit: UInt8 = 0x40   // cleared on the "km/h" tap -> set = mph (guess)
        static let startBit: UInt8 = 0x20   // cleared on "glide start" -> set = zero start (guess)
        static let light: UInt8 = 0x04      // 0xE6 on "light on"
        static let gearMask: UInt8 = 0x03   // 3 = eco, 1 = drive, 2 = sport (from his order)
    }

    enum Mode: Int, CaseIterable, Codable {
        case eco = 0, drive = 1, sport = 2    // index as the status frame reports it (byte 4)

        var name: String {
            switch self {
            case .eco: return "Eco"
            case .drive: return "Drive"
            case .sport: return "Sport"
            }
        }

        /// Low two bits in the feature frame the vendor app wrote.
        var writeBits: UInt8 {
            switch self {
            case .eco: return 0x03
            case .drive: return 0x01
            case .sport: return 0x02
            }
        }
    }

    /// The seven feature frames in the capture (all CRC-reproduced in the tests).
    static let capturedFeatureFrames: [[UInt8]] = [
        [0xAC, 0x00, 0x0A, 0x62, 0x06, 0x0C, 0x12, 0x23, 0x3E, 0xB6],
        [0xAC, 0x00, 0x0A, 0xE2, 0x06, 0x0C, 0x12, 0x23, 0x3F, 0x68],
        [0xAC, 0x00, 0x0A, 0xE6, 0x06, 0x0C, 0x12, 0x23, 0xCE, 0xA8],
        [0xAC, 0x00, 0x0A, 0xE3, 0x06, 0x0C, 0x12, 0x23, 0x02, 0xA8],
        [0xAC, 0x00, 0x0A, 0xE1, 0x06, 0x0C, 0x12, 0x23, 0x7B, 0x68],
        [0xAC, 0x00, 0x0A, 0xA2, 0x06, 0x0C, 0x12, 0x23, 0x3E, 0xA7],
        [0xAC, 0x00, 0x0A, 0xC2, 0x06, 0x0C, 0x12, 0x23, 0xBE, 0xAF],
    ]

    struct Features: Equatable {
        var unlocked: Bool
        var mph: Bool
        var zeroStart: Bool
        var light: Bool
        var mode: Mode

        var flags: UInt8 {
            var f: UInt8 = 0
            if unlocked { f |= Flag.unlocked }
            if mph { f |= Flag.unitsBit }
            if zeroStart { f |= Flag.startBit }
            if light { f |= Flag.light }
            return f | mode.writeBits
        }
    }

    /// limits = [walk, eco, drive, sport] in km/h, exactly as the scooter last reported them,
    /// so the frame never changes a limit. Every limit must be within the factory values.
    static func featureFrame(_ f: Features, limits: [UInt8]) -> [UInt8]? {
        guard limits.count == 4 else { return nil }
        let caps: [UInt8] = [6, 12, 18, 35]
        for i in 0..<4 where limits[i] == 0 || limits[i] > caps[i] { return nil }
        return withCRC([0xAC, 0x00, 0x0A, f.flags] + limits)
    }

    // MARK: Incoming (F2F1)

    struct Status: Equatable {
        let raw: [UInt8]
        let modeIndex: UInt8          // byte 4: 0/1/2 followed eco/drive/sport writes 10 of 10 times
        let flagsEcho: UInt8          // byte 22: same bits as the feature frame, minus "unlocked"
        let lockByte: UInt8           // byte 21: bit 0x08 cleared on lock, set on unlock
        var mode: Mode? { Mode(rawValue: Int(modeIndex)) }
        var light: Bool { flagsEcho & Flag.light != 0 }
        var unlocked: Bool { lockByte & 0x08 != 0 }
        var unitsBit: Bool { flagsEcho & Flag.unitsBit != 0 }
        var startBit: Bool { flagsEcho & Flag.startBit != 0 }
        /// Bytes 13-14 moved while the wheel spun. NOT shown as speed: the unit is unknown.
        var motionRaw: Int { Int(raw[13]) << 8 | Int(raw[14]) }
        /// Byte 5 was 0x64 (100) the whole time. Not shown as battery.
        var byte5Raw: UInt8 { raw[5] }
    }

    enum Incoming: Equatable {
        case status(Status)
        case limits([UInt8])          // [walk, eco, drive, sport] km/h. VERIFIED (sport went 35 -> 34 after the 34.0 write)
        case sportLimit(Int)          // 5A FA FF 03 0A 0A [sport] A5 AF (9 bytes). VERIFIED
        case register(reg: UInt8, value: [UInt8])
        case passwordOK
        case passwordRejected
        case rejected(String)
    }

    static func parse(_ b: [UInt8]) -> Incoming {
        if b.isEmpty { return .rejected("empty") }
        if b.count > 40 { return .rejected("too long (\(b.count) bytes)") }
        if isPasswordOK(b) { return .passwordOK }
        if isPasswordRejected(b) { return .passwordRejected }
        if b.count == 9, b[0] == 0x5A, b[1] == 0xFA, b[7] == 0xA5, b[8] == 0xAF {
            return .sportLimit(Int(b[6]))
        }
        if b.count >= 3, b[0] == 0xAC {
            guard crcOK(b) else { return .rejected("AC frame with a bad CRC") }
            if b[1] == 0x00, b[2] == 0x00 {
                guard b.count == 25 else { return .rejected("status with a bad length (\(b.count))") }
                return .status(Status(raw: b, modeIndex: b[4], flagsEcho: b[22], lockByte: b[21]))
            }
            if b[1] == 0x01, b[2] == 0x00 {
                guard b.count == 25 else { return .rejected("limits with a bad length (\(b.count))") }
                return .limits(Array(b[3...6]))
            }
            return .rejected(String(format: "AC %02X %02X not in the map", b[1], b[2]))
        }
        if b.count >= 7, b[0] == 0x01, b[1] == 0x03 {
            guard crcOK(b) else { return .rejected("Modbus reply with a bad CRC") }
            let n = Int(b[4])
            guard 5 + n + 2 == b.count else { return .rejected("Modbus reply with a bad length") }
            return .register(reg: b[3], value: Array(b[5..<(5 + n)]))
        }
        return .rejected("not in the map")
    }

    static func safety(of frame: [UInt8], to char: String) -> CommandSafety {
        if char == passwordChar { return frame.starts(with: Array("AT+PWD[".utf8)) && frame.count == 14 ? .verified : .blocked }
        guard char == writeChar else { return .blocked }
        if frame == heartbeat || frame == sessionStart || frame == settingsHeartbeat { return .verified }
        guard crcOK(frame) else { return .blocked }
        if frame.count == 11, Array(frame.prefix(7)) == [0x01, 0x10, 0x00, speedRegister, 0x00, 0x01, 0x02] {
            let v = Int(frame[7]) << 8 | Int(frame[8])
            return (v >= minTenths && v <= factoryMaxTenths) ? .verified : .blocked
        }
        if frame.count == 10, frame[0] == 0xAC, frame[1] == 0x00, frame[2] == 0x0A { return .experimental }
        if frame.count == 8, frame[0] == 0x01, frame[1] == 0x03 || frame[1] == 0x07 { return .experimental } // reads
        return .blocked
    }
}
