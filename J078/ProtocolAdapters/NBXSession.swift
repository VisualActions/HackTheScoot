import Foundation

// MARK: - Xiaomi M365 / Segway-Ninebot sessions (v5.1, EXPERIMENTAL, UNTESTED ON HARDWARE)
//
// Clean-room from published FACTS:
//  - Xiaomi M365 "55 AA" frames and registers: CamiAlfa/M365-BLE-PROTOCOL (facts only,
//    credit Camilo Ruiz) cross-checked with jx-grxf/scooter-tuning-db (CC BY 4.0).
//  - Ninebot "5A A5" frames, the Max G30 register table and pairing: the Apache-2.0
//    NootNooot Segway-Ninebot BLE spec, plus facts from Ninebot's ES protocol PDF.
//  - Checksum: inverted sum of LEN..payload, low 16 bits (checked against the Ninebot
//    PDF's own worked example 5A A5 01 3D 20 01 3E 02 -> 60 FF).
// See ACKNOWLEDGEMENTS.md.
//
// SAFETY (the whole design):
//  - Reads ask for a value and change nothing. Only the registers in NBXSafety.readable.
//  - Writes: ONLY M365 (plain) KERS 0x7B / cruise 0x7C / tail light 0x7D, and Max G30
//    cruise 0x7C. Each one: read the current value first, scooter standing still, the
//    rider confirms, write once, read back to verify.
//  - Everything else is BLOCKED and never leaves the phone: firmware/IAP (07-0B), turn off
//    (0x79), reboot (0x78), engine (0x77), lock/unlock (0x70/0x71), PIN/password (0x17),
//    serial (0x10 writes), speed limit / max speed / max power / speed mode, BMS writes.
//  - We never pretend to be a rental IoT board, so the scooter never starts the IoT
//    heartbeat timer that can lock the motor. Leaving or closing the app changes nothing on
//    the scooter. (See NBXSafety.blockedCommands.)

enum NBXMode: String, Equatable, Codable {
    case xiaomiPlain = "Xiaomi M365 (plain)"
    case ninebotPlain = "Ninebot (plain)"
    case xiaomiEncrypted = "Xiaomi (Ninebot encryption)"
    case ninebotEncrypted = "Ninebot (encrypted)"

    var isXiaomi: Bool { return self == .xiaomiPlain || self == .xiaomiEncrypted }
    var isEncrypted: Bool { return self == .xiaomiEncrypted || self == .ninebotEncrypted }
}

enum NBXFrames {
    static let escAddress: UInt8 = 0x20
    static let phoneID: UInt8 = 0x3E
    static let cmdRead: UInt8 = 0x01
    static let cmdWrite: UInt8 = 0x02
    static let cmdWriteNoReply: UInt8 = 0x03
    static let cmdReadReply: UInt8 = 0x04

    static func checksum(_ b: ArraySlice<UInt8>) -> UInt16 {
        let total = b.reduce(0) { $0 + Int($1) }
        return UInt16(~total & 0xFFFF)
    }

    // Xiaomi "Protocol 1": 55 AA | LEN | ADDR | CMD | INDEX | payload | cs lo, cs hi   (LEN = payload + 2)
    static func m365(addr: UInt8, cmd: UInt8, index: UInt8, payload: [UInt8]) -> [UInt8] {
        var f: [UInt8] = [0x55, 0xAA, UInt8(payload.count + 2), addr, cmd, index] + payload
        let cs = checksum(f[2...])
        f += [UInt8(cs & 0xFF), UInt8(cs >> 8)]
        return f
    }

    static func m365Read(index: UInt8, length: UInt8) -> [UInt8] {
        return m365(addr: escAddress, cmd: cmdRead, index: index, payload: [length])
    }

    /// Xiaomi writes are 16-bit little-endian, command 0x03.
    static func m365Write(index: UInt8, value: UInt16) -> [UInt8] {
        return m365(addr: escAddress, cmd: cmdWriteNoReply, index: index, payload: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    struct Reply: Equatable {
        let source: UInt8
        let cmd: UInt8
        let index: UInt8
        let data: [UInt8]
    }

    /// Parses one whole 55 AA frame. nil = not one.
    static func parseM365(_ b: [UInt8]) -> Reply? {
        guard b.count >= 8, b[0] == 0x55, b[1] == 0xAA else { return nil }
        let len = Int(b[2])
        guard len >= 2, b.count == len + 6 else { return nil }
        let cs = checksum(b[2..<(4 + len)])
        let got = UInt16(b[4 + len]) | (UInt16(b[5 + len]) << 8)
        guard got == cs || got == (cs & 0x7FFF) else { return nil }
        return Reply(source: b[3], cmd: b[4], index: b[5], data: Array(b[6..<(4 + len)]))
    }

    // Ninebot "Protocol 2" plaintext: 5A A5 | LEN | 3E | TARGET | CMD | INDEX | payload   (LEN = payload)
    static func p2Plain(target: UInt8, cmd: UInt8, index: UInt8, payload: [UInt8], sync2: UInt8 = 0xA5) -> [UInt8] {
        return [0x5A, sync2, UInt8(payload.count), phoneID, target, cmd, index] + payload
    }

    /// Unencrypted Protocol 2 on the air: the plaintext plus the checksum.
    static func p2WithChecksum(_ plain: [UInt8]) -> [UInt8] {
        let cs = checksum(plain[2...])
        return plain + [UInt8(cs & 0xFF), UInt8(cs >> 8)]
    }

    /// A decrypted (or unencrypted, checksum removed) Protocol 2 frame. Replies carry the
    /// sender at byte 3 and 3E at byte 4; requests carry 3E at byte 3.
    static func parseP2Plain(_ pt: [UInt8]) -> Reply? {
        guard pt.count >= 7, pt[0] == 0x5A, pt[1] == 0xA5 || pt[1] == 0xB5 else { return nil }
        let len = Int(pt[2])
        guard pt.count >= 7 + len else { return nil }
        let src: UInt8 = pt[4] == phoneID ? pt[3] : pt[4]
        return Reply(source: src, cmd: pt[5], index: pt[6], data: Array(pt[7..<(7 + len)]))
    }

    /// An unencrypted Protocol 2 frame with its checksum (LEN + 9 bytes).
    static func parseP2Unencrypted(_ b: [UInt8]) -> Reply? {
        guard b.count >= 9, b[0] == 0x5A, b[1] == 0xA5 else { return nil }
        let len = Int(b[2])
        guard b.count == len + 9 else { return nil }
        let cs = checksum(b[2..<(7 + len)])
        let got = UInt16(b[7 + len]) | (UInt16(b[8 + len]) << 8)
        guard got == cs || got == (cs & 0x7FFF) else { return nil }
        return parseP2Plain(Array(b[0..<(7 + len)]))
    }
}

// MARK: - The settings we allow (and the only writes)

enum NBXSetting: String, CaseIterable, Identifiable, Codable {
    case kers, cruise, tailLight
    var id: String { rawValue }

    var index: UInt8 {
        switch self {
        case .kers: return 0x7B
        case .cruise: return 0x7C
        case .tailLight: return 0x7D
        }
    }

    var title: String {
        switch self {
        case .kers: return "KERS (regen braking)"
        case .cruise: return "Cruise control"
        case .tailLight: return "Tail light"
        }
    }

    /// Values both sources agree on. Nothing else is ever written.
    var options: [(value: UInt16, label: String)] {
        switch self {
        case .kers: return [(0, "Weak"), (1, "Medium"), (2, "Strong")]
        case .cruise: return [(0, "Off"), (1, "On")]
        case .tailLight: return [(0, "Off"), (2, "Always on")]
        }
    }

    func label(for v: Int?) -> String {
        guard let v = v else { return "not read yet" }
        return options.first { Int($0.value) == v }?.label ?? "unknown value \(v)"
    }

    /// Which settings each mode may write (EXPERIMENTAL). Encrypted Xiaomi models and
    /// everything not listed: none.
    static func allowed(in mode: NBXMode?) -> [NBXSetting] {
        switch mode {
        case .xiaomiPlain?: return [.kers, .cruise, .tailLight]
        case .ninebotPlain?, .ninebotEncrypted?: return [.cruise]
        default: return []
        }
    }
}

enum NBXSafety {
    /// Registers we read (reads change nothing).
    static let readable: Set<UInt8> = [0x1A, 0x25, 0x3B, 0x3E, 0x67, 0x68, 0x7B, 0x7C, 0x7D,
                                       0xB0, 0xB4, 0xB5, 0xB7, 0xB9, 0xBA, 0xBE]
    /// Never sent, in any form: firmware/IAP, set BLE name, activate, vehicle actions.
    static let blockedCommands: Set<UInt8> = [0x07, 0x08, 0x09, 0x0A, 0x0B, 0x50, 0x55, 0x57, 0x64]
    /// Never WRITTEN: serial, PIN/password, lock/unlock, pedestrian/engine, reboot, turn off,
    /// speed mode, max speed, speed limit, max power, start speed, e-brake, lights/units.
    static let neverWrite: Set<UInt8> = [0x10, 0x17, 0x3F, 0x70, 0x71, 0x73, 0x74, 0x75, 0x77, 0x78, 0x79,
                                         0x7A, 0x7F, 0x80, 0x81, 0x90, 0x93]
    static let pairingCommands: Set<UInt8> = [0x5B, 0x5C, 0x5D]

    /// Safety of one plaintext request. `.verified` here means "a read or the session's own
    /// handshake read", never a change to the scooter.
    static func classify(mode: NBXMode, cmd: UInt8, target: UInt8, index: UInt8, data: [UInt8]) -> CommandSafety {
        if blockedCommands.contains(cmd) { return .blocked }
        if pairingCommands.contains(cmd) {
            guard mode.isEncrypted else { return .blocked }
            // PRE_COMM only asks for the pairing parameters; SET_PWD / AUTH pair the phone
            // (the rider pressed "Pair" and the scooter's power button).
            return cmd == 0x5B ? .verified : .experimental
        }
        if cmd == NBXFrames.cmdRead {
            guard target == NBXFrames.escAddress, readable.contains(index), data.count == 1, (1...32).contains(data[0]) else { return .blocked }
            return .verified
        }
        if cmd == NBXFrames.cmdWrite || cmd == NBXFrames.cmdWriteNoReply {
            guard target == NBXFrames.escAddress, !neverWrite.contains(index) else { return .blocked }
            guard let s = NBXSetting.allCases.first(where: { $0.index == index }),
                  NBXSetting.allowed(in: mode).contains(s) else { return .blocked }
            guard !data.isEmpty, data.count <= 2 else { return .blocked }
            let v = UInt16(data[0]) | (data.count == 2 ? UInt16(data[1]) << 8 : 0)
            return s.options.contains { $0.value == v } ? .experimental : .blocked
        }
        return .blocked
    }

    /// Classifies a request by its plaintext frame (55 AA or 5A A5 form).
    static func classify(mode: NBXMode, plain f: [UInt8]) -> CommandSafety {
        if f.count >= 7, f[0] == 0x55, f[1] == 0xAA {
            guard mode == .xiaomiPlain, let r = NBXFrames.parseM365(f) else { return .blocked }
            return classify(mode: mode, cmd: r.cmd, target: r.source, index: r.index, data: r.data)
        }
        if f.count >= 7, f[0] == 0x5A, f[1] == 0xA5 || f[1] == 0xB5, f[3] == NBXFrames.phoneID {
            let len = Int(f[2])
            guard f.count == 7 + len else { return .blocked }
            return classify(mode: mode, cmd: f[5], target: f[4], index: f[6], data: Array(f[7...]))
        }
        return .blocked
    }

    static func classifyPairing(target: UInt8, plain f: [UInt8]) -> CommandSafety {
        guard f.count >= 7, f[0] == 0x5A, f[3] == NBXFrames.phoneID, f[4] == target, f[6] == 0x00 else { return .blocked }
        switch f[5] {
        case 0x5B: return f.count == 7 ? .verified : .blocked
        case 0x5C: return f.count == 7 + 16 ? .experimental : .blocked
        case 0x5D: return f.count == 7 + 14 ? .experimental : .blocked
        default: return .blocked
        }
    }

    /// The scooter must be standing still and its speed must be known.
    static func standingStill(_ kmh: Double?) -> Bool {
        guard let k = kmh else { return false }
        return abs(k) < 1.0
    }
}

// MARK: - Live values

struct NBXTelemetry: Equatable {
    var speedKmh: Double?
    var batteryPercent: Int?
    var odometerKm: Double?
    var tripKm: Double?
    var tripSeconds: Int?
    var frameTempC: Double?
    var rangeKm: Double?
    var errorCode: Int?
    var warningCode: Int?
    var escFirmware: String?
    var bleFirmware: String?
    var bmsFirmware: String?
    var settings: [String: Int] = [:]
    var replies = 0

    func setting(_ s: NBXSetting) -> Int? { return settings[s.rawValue] }

    static func version(_ v: Int) -> String {
        return "\((v >> 8) & 0xF).\((v >> 4) & 0xF).\(v & 0xF)"
    }

    mutating func apply(index: UInt8, data d: [UInt8], xiaomi: Bool) {
        func u16() -> Int? { return d.count >= 2 ? Int(d[0]) | (Int(d[1]) << 8) : nil }
        func s16() -> Int? { return u16().map { Int(Int16(truncatingIfNeeded: $0)) } }
        func u32() -> Int? { return d.count >= 4 ? Int(d[0]) | (Int(d[1]) << 8) | (Int(d[2]) << 16) | (Int(d[3]) << 24) : nil }
        replies += 1
        switch index {
        case 0xB0: errorCode = u16()
        case 0xBE: warningCode = u16()
        case 0xB4: if let v = u16(), (0...100).contains(v) { batteryPercent = v }
        case 0xB5:
            // Xiaomi: metres per hour. Ninebot ES/Max: 0.1 km/h.
            if let v = s16() {
                let k = xiaomi ? Double(v) / 1000.0 : Double(v) / 10.0
                if abs(k) <= 90 { speedKmh = k }
            }
        case 0xB7: if let v = u32() { odometerKm = Double(v) / 1000.0 }
        case 0xB9: if let v = u16() { tripKm = Double(v) / 100.0 }        // 10 m units (sources disagree, unverified)
        case 0xBA, 0x3B: if let v = u16() { tripSeconds = v }
        case 0x3E: if let v = s16() { frameTempC = Double(v) / 10.0 }
        case 0x25: if let v = u16() { rangeKm = Double(v) / 100.0 }        // 0.01 km per the M365 source, unverified
        case 0x1A: if let v = u16() { escFirmware = NBXTelemetry.version(v) }
        case 0x68: if let v = u16() { bleFirmware = NBXTelemetry.version(v) }
        case 0x67: if let v = u16() { bmsFirmware = NBXTelemetry.version(v) }
        case 0x7B, 0x7C, 0x7D:
            if let s = NBXSetting.allCases.first(where: { $0.index == index }), let v = u16() ?? d.first.map({ Int($0) }) {
                settings[s.rawValue] = v
            }
        default: replies -= 1
        }
    }
}

// MARK: - The session driver (pure: tests drive it with fake time and a fake radio)

final class NBXDriver {
    enum Family: String { case xiaomi, ninebot }

    enum Stage: Equatable {
        case off
        case probingXiaomi(since: Date)
        case probingNinebot(since: Date)
        case needsPairing(String)
        case pairing(String)
        case live(NBXMode)
        case unsupported(String)
    }

    struct Profile: Equatable {
        let name: String
        let target: UInt8
        let sync2: UInt8
        let gen2Block: Bool
    }

    /// The spec's fixed Gen2 protocol constant ("fw_data"): the non-SN keystream input.
    /// Public, identical on every device, not a key (NootNooot, Encryption page).
    static let gen2StaticBlock: [UInt8] = [0x97, 0xCF, 0xB8, 0x02, 0x84, 0x41, 0x43, 0xDE,
                                           0x56, 0x00, 0x2B, 0x3B, 0x34, 0x78, 0x0A, 0x5D]

    /// Tried in order until one answers PRE_COMM. Older kick scooters pair through the
    /// BLE/dash board 0x21; newer families through 0x04. UNVERIFIED on real scooters.
    static let profiles: [Profile] = [
        Profile(name: "classic (0x21, Gen2)", target: 0x21, sync2: 0xA5, gen2Block: true),
        Profile(name: "classic (0x21, zero block)", target: 0x21, sync2: 0xA5, gen2Block: false),
        Profile(name: "modern (0x04, Gen2)", target: 0x04, sync2: 0xA5, gen2Block: true),
        Profile(name: "modern (0x04, Gen3)", target: 0x04, sync2: 0xB5, gen2Block: false),
    ]

    struct Outgoing {
        let air: [UInt8]
        let plain: [UInt8]
        let safety: CommandSafety
        let origin: WriteOrigin
        let confirmed: Bool
        let note: String
        let logIt: Bool
    }

    // Wiring (BLEManager sets these; tests set fakes).
    var send: (Outgoing) -> Bool = { _ in false }
    var loadPassword: (String) -> [UInt8]? = { _ in nil }
    var savePassword: ([UInt8], String) -> Void = { _, _ in }
    var makePassword: () -> [UInt8] = {
        var g = SystemRandomNumberGenerator()
        return (0..<16).map { _ in UInt8.random(in: 0...255, using: &g) }
    }
    var onChange: () -> Void = {}

    private(set) var family: Family = .ninebot
    private(set) var bleName = ""
    private(set) var deviceKey = ""
    private(set) var stage: Stage = .off { didSet { if stage != oldValue { onChange() } } }
    private(set) var telemetry = NBXTelemetry() { didSet { onChange() } }
    private(set) var lastWriteResult: String?
    private(set) var plainNinebotReplies = 0
    private(set) var encryptedFramesSeen = 0
    private(set) var xiaomiLoginFramesSeen = 0

    var mode: NBXMode? { if case .live(let m) = stage { return m }; return nil }

    /// The experimental settings this session may change. A Xiaomi is only writable on the
    /// plain M365 protocol; encrypted Xiaomi models (Pro, Pro 2, 1S, Essential) stay read-only.
    var allowedSettings: [NBXSetting] {
        guard let m = mode else { return [] }
        if family == .xiaomi && m != .xiaomiPlain { return [] }
        return NBXSetting.allowed(in: m)
    }

    private var buffer: [UInt8] = []
    private var lastRx = Date.distantPast
    private var lastSend = Date.distantPast
    private var pollIndex = 0
    private var onceQueue: [(UInt8, UInt8)] = []
    private var lastAirSent: [UInt8] = []
    // pairing
    private var crypto: NBCryptoSession?
    private var profileIndex = 0
    private var pairStep = 0          // 1 PRE_COMM, 2 SET_PWD, 3 AUTH
    private var stepTries = 0
    private var stepSentAt = Date.distantPast
    private var pairStartedAt = Date.distantPast
    private var password: [UInt8] = []
    private var serial: [UInt8] = []
    private var authParam: [UInt8] = []
    private var usedStoredPassword = false
    // write check
    private var pendingWrite: (setting: NBXSetting, value: UInt16, sentAt: Date, readBack: Bool)?

    static let pollEvery: TimeInterval = 0.25
    static let probeFor: TimeInterval = 3.0

    func start(family: Family, bleName: String, deviceKey: String, now: Date) {
        self.family = family
        self.bleName = bleName
        self.deviceKey = deviceKey
        buffer = []
        telemetry = NBXTelemetry()
        lastWriteResult = nil
        pendingWrite = nil
        crypto = nil
        pairStep = 0
        plainNinebotReplies = 0
        encryptedFramesSeen = 0
        xiaomiLoginFramesSeen = 0
        stage = family == .xiaomi ? .probingXiaomi(since: now) : .probingNinebot(since: now)
    }

    func stop() {
        stage = .off
        buffer = []
        crypto = nil
        pendingWrite = nil
    }

    // MARK: Polling

    private func pollList(_ m: NBXMode) -> [(UInt8, UInt8)] {
        if m.isXiaomi {
            return [(0xB5, 2), (0xB4, 2), (0xB0, 2), (0xB5, 2), (0xB7, 4), (0xB9, 2), (0x3B, 2), (0x3E, 2), (0x25, 2)]
        }
        return [(0xB5, 2), (0xB4, 2), (0xB0, 2), (0xBE, 2), (0xB5, 2), (0xB7, 4), (0xB9, 2), (0xBA, 2), (0x3E, 2), (0x25, 2)]
    }

    private func onceList(_ m: NBXMode) -> [(UInt8, UInt8)] {
        var l: [(UInt8, UInt8)] = [(0x1A, 2)]
        if !m.isXiaomi { l += [(0x68, 2), (0x67, 2)] }
        l += NBXSetting.allowed(in: m).map { ($0.index, 2) }
        return l
    }

    private func readFrame(_ m: NBXMode, index: UInt8, length: UInt8) -> [UInt8] {
        if m == .xiaomiPlain { return NBXFrames.m365Read(index: index, length: length) }
        return NBXFrames.p2Plain(target: NBXFrames.escAddress, cmd: NBXFrames.cmdRead, index: index, payload: [length],
                                 sync2: currentProfile?.sync2 ?? 0xA5)
    }

    private var currentProfile: NBXDriver.Profile? {
        guard crypto != nil, profileIndex < NBXDriver.profiles.count else { return nil }
        return NBXDriver.profiles[profileIndex]
    }

    @discardableResult
    private func transmit(plain: [UInt8], mode m: NBXMode, origin: WriteOrigin, confirmed: Bool, note: String, logIt: Bool) -> Bool {
        let safety: CommandSafety
        if m.isEncrypted, plain.count >= 6, NBXSafety.pairingCommands.contains(plain[5]) {
            safety = NBXSafety.classifyPairing(target: currentProfile?.target ?? 0, plain: plain)
        } else {
            safety = NBXSafety.classify(mode: m, plain: plain)
        }
        guard safety != .blocked else { return false }
        // A Xiaomi on anything but the plain M365 protocol is read-only.
        if safety == .experimental, family == .xiaomi, m != .xiaomiPlain, plain.count >= 6, !NBXSafety.pairingCommands.contains(plain[5]) {
            return false
        }
        let air: [UInt8]
        if m.isEncrypted {
            guard var c = crypto else { return false }
            air = c.encrypt(plain)
            crypto = c
        } else if m == .xiaomiPlain {
            air = plain
        } else {
            air = NBXFrames.p2WithChecksum(plain)
        }
        lastAirSent = air
        return send(Outgoing(air: air, plain: plain, safety: safety, origin: origin, confirmed: confirmed, note: note, logIt: logIt))
    }

    /// Called about every 0.25 s by the Bluetooth manager while connected.
    func tick(now: Date) {
        if now.timeIntervalSince(lastRx) > 0.6 { buffer = [] }
        switch stage {
        case .off, .needsPairing, .unsupported:
            return
        case .probingXiaomi(let since):
            if xiaomiLoginFramesSeen > 0 {
                stage = .unsupported("This Xiaomi uses the newer Xiaomi login. The only public code for it is AGPL, so HackTheScoot can't use it. Read-only listening still works in the Developer Lab.")
                return
            }
            if now.timeIntervalSince(since) > NBXDriver.probeFor {
                stage = .probingNinebot(since: now)
                return
            }
            if now.timeIntervalSince(lastSend) >= 0.5 {
                lastSend = now
                transmit(plain: NBXFrames.m365Read(index: 0xB4, length: 2), mode: .xiaomiPlain, origin: .session, confirmed: false,
                         note: "M365 probe: read battery (plain, read-only)", logIt: true)
            }
        case .probingNinebot(let since):
            if plainNinebotReplies > 0 {
                beginLive(.ninebotPlain, now: now)
                return
            }
            if now.timeIntervalSince(since) > NBXDriver.probeFor {
                stage = .needsPairing(encryptedFramesSeen > 0
                    ? "This scooter answers encrypted. Pair it: tap Pair, then press the scooter's power button when asked."
                    : "No plain answer. It probably needs pairing: tap Pair, then press the scooter's power button when asked.")
                return
            }
            if now.timeIntervalSince(lastSend) >= 0.5 {
                lastSend = now
                transmit(plain: NBXFrames.p2Plain(target: NBXFrames.escAddress, cmd: NBXFrames.cmdRead, index: 0xB4, payload: [2]),
                         mode: .ninebotPlain, origin: .session, confirmed: false, note: "Ninebot probe: read battery (plain, read-only)", logIt: true)
            }
        case .pairing:
            pairTick(now: now)
        case .live(let m):
            checkPendingWrite(now: now, mode: m)
            guard now.timeIntervalSince(lastSend) >= NBXDriver.pollEvery else { return }
            lastSend = now
            let next: (UInt8, UInt8)
            if !onceQueue.isEmpty {
                next = onceQueue.removeFirst()
            } else {
                let l = pollList(m)
                next = l[pollIndex % l.count]
                pollIndex += 1
            }
            transmit(plain: readFrame(m, index: next.0, length: next.1), mode: m, origin: .session, confirmed: false,
                     note: String(format: "read 0x%02X", next.0), logIt: false)
        }
    }

    private func beginLive(_ m: NBXMode, now: Date) {
        pollIndex = 0
        onceQueue = onceList(m)
        stage = .live(m)
    }

    // MARK: Receiving

    func receive(_ bytes: [UInt8], now: Date) {
        if bytes.isEmpty { return }
        if !lastAirSent.isEmpty && bytes == lastAirSent && pairStep > 0 {
            // NootNooot transport notes: some iOS reconnects make the scooter echo our frame.
            stage = .needsPairing("The scooter echoed our message back (an iOS Bluetooth quirk). Disconnect, wait 2 seconds, reconnect and pair again.")
            pairStep = 0
            return
        }
        lastRx = now
        buffer += bytes
        if buffer.count > 512 { buffer = Array(buffer.suffix(256)) }
        var guardCount = 0
        while guardCount < 16, let f = nextFrame() {
            guardCount += 1
            handleFrame(f, now: now)
        }
    }

    /// Cuts one whole frame off the front of the buffer, or nil if more bytes are needed.
    private func nextFrame() -> [UInt8]? {
        while buffer.count >= 2 && !(buffer[0] == 0x55 && (buffer[1] == 0xAA || buffer[1] == 0xAB))
                && !(buffer[0] == 0x5A && (buffer[1] == 0xA5 || buffer[1] == 0xB5)) {
            buffer.removeFirst()
        }
        guard buffer.count >= 3 else { return nil }
        let len = Int(buffer[2])
        if buffer[0] == 0x55 {
            if buffer[1] == 0xAB { xiaomiLoginFramesSeen += 1; buffer.removeFirst(2); return nil }
            let total = len + 6
            guard buffer.count >= total else { return nil }
            let f = Array(buffer[0..<total]); buffer.removeFirst(total); return f
        }
        // 5A A5: plain (LEN + 9) if its checksum is right, else encrypted (LEN + 13).
        if crypto == nil, buffer.count >= len + 9, NBXFrames.parseP2Unencrypted(Array(buffer[0..<(len + 9)])) != nil {
            let f = Array(buffer[0..<(len + 9)]); buffer.removeFirst(len + 9); return f
        }
        let total = len + 13
        guard buffer.count >= total else { return nil }
        let f = Array(buffer[0..<total]); buffer.removeFirst(total); return f
    }

    private func handleFrame(_ f: [UInt8], now: Date) {
        if f[0] == 0x55 {
            guard let r = NBXFrames.parseM365(f) else { return }
            // ESC replies come from 0x23 (the BLE side forwards them).
            guard r.cmd == NBXFrames.cmdRead, r.source == 0x23 || r.source == 0x25 else { return }
            if case .probingXiaomi = stage { beginLive(.xiaomiPlain, now: now) }
            guard case .live(.xiaomiPlain) = stage else { return }
            var t = telemetry
            t.apply(index: r.index, data: r.data, xiaomi: true)
            telemetry = t
            return
        }
        if crypto == nil, let r = NBXFrames.parseP2Unencrypted(f) {
            guard r.cmd == NBXFrames.cmdReadReply else { return }
            plainNinebotReplies += 1
            if case .probingNinebot = stage { beginLive(.ninebotPlain, now: now) }
            guard case .live(let m) = stage, m == .ninebotPlain else { return }
            var t = telemetry
            t.apply(index: r.index, data: r.data, xiaomi: family == .xiaomi)
            telemetry = t
            return
        }
        guard var c = crypto else { encryptedFramesSeen += 1; return }
        let d = c.decrypt(f)
        crypto = c
        guard case .ok(let pt, _) = d, let r = NBXFrames.parseP2Plain(pt) else { return }
        if pairStep > 0 { handlePairReply(r, now: now); return }
        guard case .live(let m) = stage, m.isEncrypted, r.cmd == NBXFrames.cmdReadReply else { return }
        var t = telemetry
        t.apply(index: r.index, data: r.data, xiaomi: m.isXiaomi)
        telemetry = t
    }

    // MARK: Pairing (rider tapped Pair and confirmed)

    var pairingMode: NBXMode { return family == .xiaomi ? .xiaomiEncrypted : .ninebotEncrypted }

    func startPairing(now: Date) {
        switch stage {
        case .needsPairing, .pairing, .probingNinebot, .probingXiaomi: break
        default: return
        }
        profileIndex = 0
        pairStartedAt = now
        beginProfile(now: now)
    }

    private func beginProfile(now: Date) {
        guard profileIndex < NBXDriver.profiles.count else {
            crypto = nil
            pairStep = 0
            stage = .needsPairing("No answer to pairing. This model's encryption may differ from the public spec. A capture with the official app would help (Help unlock your scooter).")
            return
        }
        let p = NBXDriver.profiles[profileIndex]
        crypto = NBCryptoSession(bleName: bleName, staticBlock: p.gen2Block ? NBXDriver.gen2StaticBlock : [UInt8](repeating: 0, count: 16))
        buffer = []
        pairStep = 1
        stepTries = 0
        stepSentAt = .distantPast
        usedStoredPassword = false
        stage = .pairing("Asking the scooter for its pairing details (\(p.name))...")
    }

    private func pairTick(now: Date) {
        guard let p = currentProfile else { return }
        guard now.timeIntervalSince(stepSentAt) >= 2.0 else { return }
        switch pairStep {
        case 1:
            if stepTries >= 3 { profileIndex += 1; beginProfile(now: now); return }
            stepTries += 1
            stepSentAt = now
            transmit(plain: NBXFrames.p2Plain(target: p.target, cmd: 0x5B, index: 0x00, payload: [], sync2: p.sync2), mode: pairingMode,
                     origin: .session, confirmed: false, note: "pairing 1/3: PRE_COMM (asks for pairing details)", logIt: true)
        case 2:
            if now.timeIntervalSince(pairStartedAt) > 75 {
                crypto = nil; pairStep = 0
                stage = .needsPairing("Pairing timed out: the scooter didn't confirm. Try again and press the power button once when asked.")
                return
            }
            stepSentAt = now
            transmit(plain: NBXFrames.p2Plain(target: p.target, cmd: 0x5C, index: 0x00, payload: password, sync2: p.sync2), mode: pairingMode,
                     origin: .experimental, confirmed: true, note: "pairing 2/3: SET_PWD (waiting for the power button)", logIt: true)
        case 3:
            if stepTries >= 3 {
                if usedStoredPassword {
                    // A stored session password that no longer works: pair from scratch.
                    usedStoredPassword = false
                    password = makePassword()
                    pairStep = 2; stepTries = 0
                    stage = .pairing("Press the power button on the scooter once now.")
                    return
                }
                crypto = nil; pairStep = 0
                stage = .needsPairing("The scooter didn't accept the pairing. Try again.")
                return
            }
            stepTries += 1
            stepSentAt = now
            transmit(plain: NBXFrames.p2Plain(target: p.target, cmd: 0x5D, index: 0x00, payload: serial, sync2: p.sync2), mode: pairingMode,
                     origin: .experimental, confirmed: true, note: "pairing 3/3: AUTH", logIt: true)
        default:
            return
        }
    }

    private func handlePairReply(_ r: NBXFrames.Reply, now: Date) {
        guard var c = crypto else { return }
        switch (pairStep, r.cmd) {
        case (1, 0x5B):
            guard r.data.count >= 30 else { return }
            authParam = Array(r.data[0..<16])
            serial = Array(r.data[16..<30])
            c.startSN(auth: authParam)
            if r.index != 0, let stored = loadPassword(deviceKey), stored.count == 16 {
                password = stored
                usedStoredPassword = true
                c.key1 = stored; c.key2 = authParam
                crypto = c
                pairStep = 3; stepTries = 0; stepSentAt = .distantPast
                stage = .pairing("Paired before: checking the saved pairing...")
            } else {
                password = makePassword()
                c.key2 = authParam
                crypto = c
                pairStep = 2; stepTries = 0; stepSentAt = .distantPast
                stage = .pairing("Press the power button on the scooter once now.")
            }
            pairTick(now: now)
        case (2, 0x5C):
            if r.index == 1 {
                c.key1 = password; c.key2 = authParam
                crypto = c
                pairStep = 3; stepTries = 0; stepSentAt = .distantPast
                stage = .pairing("Button press seen. Finishing pairing...")
                pairTick(now: now)
            }
        case (3, 0x5D):
            if r.index == 1 {
                savePassword(password, deviceKey)
                pairStep = 0
                lastAirSent = []
                beginLive(pairingMode, now: now)
            }
        default:
            return
        }
    }

    // MARK: Experimental writes (read -> confirm -> write -> read back)

    /// Returns nil when the write went out, else why it didn't.
    func write(_ s: NBXSetting, value: UInt16, confirmed: Bool, now: Date) -> String? {
        guard case .live(let m) = stage else { return "Not connected to a live session." }
        guard allowedSettings.contains(s) else { return "\(s.title) isn't available on this scooter (read-only)." }
        guard s.options.contains(where: { $0.value == value }) else { return "That value is never sent." }
        guard confirmed else { return "Needs your confirmation." }
        guard telemetry.setting(s) != nil else {
            onceQueue.append((s.index, 2))
            return "Read the current value first (reading it now). Try again in a second."
        }
        guard NBXSafety.standingStill(telemetry.speedKmh) else { return "Only while the scooter is standing still (speed must read 0)." }
        guard pendingWrite == nil else { return "Still checking the last change." }
        let plain: [UInt8]
        if m == .xiaomiPlain {
            plain = NBXFrames.m365Write(index: s.index, value: value)
        } else {
            // Max G30 setCruice per the official app config (NootNooot): write-no-reply, 1 byte.
            plain = NBXFrames.p2Plain(target: NBXFrames.escAddress, cmd: NBXFrames.cmdWriteNoReply, index: s.index, payload: [UInt8(value & 0xFF)],
                                      sync2: currentProfile?.sync2 ?? 0xA5)
        }
        let ok = transmit(plain: plain, mode: m, origin: .experimental, confirmed: true,
                          note: "EXPERIMENTAL write: \(s.title) -> \(s.label(for: Int(value)))", logIt: true)
        guard ok else { return "Not sent (blocked by the safety gate)." }
        lastSend = now
        pendingWrite = (s, value, now, false)
        lastWriteResult = "Sent \(s.title): \(s.label(for: Int(value))). Reading it back..."
        onChange()
        return nil
    }

    private func checkPendingWrite(now: Date, mode m: NBXMode) {
        guard let p = pendingWrite else { return }
        let age = now.timeIntervalSince(p.sentAt)
        if !p.readBack && age >= 0.5 {
            pendingWrite = (p.setting, p.value, p.sentAt, true)
            var t = telemetry
            t.settings[p.setting.rawValue] = nil
            telemetry = t
            onceQueue.insert((p.setting.index, 2), at: 0)
            return
        }
        guard p.readBack else { return }
        if let v = telemetry.setting(p.setting) {
            lastWriteResult = v == Int(p.value)
                ? "The scooter now reports \(p.setting.title): \(p.setting.label(for: v)). Changed (experimental)."
                : "The scooter still reports \(p.setting.label(for: v)). It didn't change."
            pendingWrite = nil
            onChange()
        } else if age > 3.0 {
            lastWriteResult = "No read-back from the scooter, so we can't say it changed."
            pendingWrite = nil
            onChange()
        }
    }

    var stageText: String {
        switch stage {
        case .off: return "Not started"
        case .probingXiaomi: return "Checking for a plain M365 (read-only)..."
        case .probingNinebot: return "Checking for a plain Ninebot (read-only)..."
        case .needsPairing(let s), .pairing(let s), .unsupported(let s): return s
        case .live(let m): return "Live: \(m.rawValue)"
        }
    }
}
