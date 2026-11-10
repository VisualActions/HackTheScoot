import Foundation

// MARK: - Command safety (v4)
//
// Every frame the app can put on the air has a level. Normal controls only use
// .verified frames. .experimental frames are never sent automatically: only from
// a screen that says "experimental" and only after the user confirms. .blocked
// frames are never sent, whatever the user types.

enum CommandSafety: String, Codable, CaseIterable {
    /// Seen in Credence's own captures AND the scooter's reaction was seen.
    case verified
    /// Built from the capture pattern, never seen on the air exactly like this,
    /// or seen but its meaning is a guess. Manual + confirmed only.
    case experimental
    /// Never transmitted (firmware / bootloader / flash / serial-number / unknown family).
    case blocked

    var label: String {
        switch self {
        case .verified: return "VERIFIED"
        case .experimental: return "EXPERIMENTAL"
        case .blocked: return "BLOCKED"
        }
    }
}

/// Where a write came from. Used by the gate and the log.
enum WriteOrigin: String {
    case session        // hello / keep-alive / ping that the 365 app itself sends
    case control        // a button the user tapped on a normal screen
    case experimental   // an "experimental" button, after confirmation
    case manual         // Developer Lab terminal, after the advanced warning
}

/// What the app is connected to right now. Simulation and replay never write.
enum DataSource: String, Codable {
    case none
    case bluetooth
    case simulation
    case replay

    var isSimulated: Bool { return self == .simulation || self == .replay }
}

/// The one gate every BLE write passes through.
struct CommandGate {
    enum Decision: Equatable {
        case allow
        case deny(String)
    }

    /// Pure decision, unit-tested.
    static func check(source: DataSource,
                      safety: CommandSafety,
                      origin: WriteOrigin,
                      channelReady: Bool,
                      userConfirmed: Bool,
                      advancedUnlocked: Bool) -> Decision {
        switch source {
        case .simulation: return .deny("simulation mode never sends Bluetooth commands")
        case .replay: return .deny("trip replay never sends Bluetooth commands")
        case .none: return .deny("not connected")
        case .bluetooth: break
        }
        guard channelReady else { return .deny("Bluetooth channel not ready yet (notifications not confirmed)") }
        switch safety {
        case .blocked:
            return .deny("blocked: this frame is never sent")
        case .verified:
            return .allow
        case .experimental:
            switch origin {
            case .session, .control:
                return .deny("experimental frames are never sent automatically or from normal controls")
            case .experimental:
                return userConfirmed ? .allow : .deny("needs your confirmation")
            case .manual:
                return (userConfirmed && advancedUnlocked) ? .allow : .deny("needs the advanced-writes warning accepted and a confirmation")
            }
        }
    }
}

// MARK: - J078 frame classification

enum J078Safety {
    /// Characteristics that must never be written (2A25 = serial number string, DFU services).
    static let neverWriteCharacteristics: Set<String> = ["2A25", "2A26", "2A27", "2A28", "FE59", "00001530", "8EC90001"]

    /// Safety level of a DECODED frame headed to 6E400002 (or a raw frame when scrambled == false).
    static func classify(decoded d: [UInt8], scrambled: Bool) -> CommandSafety {
        if !scrambled {
            if d == Proto.helloRaw || d == Proto.pingRaw { return .verified }
            return .blocked
        }
        guard d.count >= 5, d[0] == 0xBD, d[1] == 0xBE else { return .blocked }
        switch d[2] {
        case 0xAB:
            guard d.count == 5 else { return .blocked }
            let cmd = d[3], v = d[4]
            switch cmd {
            case Proto.Cmd.light, Proto.Cmd.park:
                return (v == 0x00 || v == 0x01) ? .verified : .experimental
            case Proto.Cmd.gear:
                return Gear.allCases.contains(where: { $0.setValue == v }) ? .verified : .experimental
            case Proto.Cmd.units, Proto.Cmd.startMode:
                // The command is verified (the flag bit follows it); which value means
                // which mode is not, so the app labels it but the frame itself is real.
                return (v == 0x00 || v == 0x01) ? .verified : .experimental
            case 0xA0...0xA3:
                if v == 0xFF { return .verified }                      // keep-alive
                guard let g = Gear.fromLimitByte(cmd) else { return .blocked }
                guard g.fullRange.contains(Int(v)) else { return .blocked }   // outside 6...45: never
                // Sport inside its stock range is the write seen in his capture. Above stock
                // (v3's unlock) and the other modes go out only after the user confirmed.
                if g.limitWriteVerified && g.limitRange.contains(Int(v)) { return .verified }
                return .experimental
            default:
                return .experimental
            }
        case 0xAC:
            // Only the 6-digit password frame is known in the AC family.
            if d.count == 10, d[3] == 0xAC, d[4...].allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) { return .verified }
            return .blocked
        default:
            // AF FF FF is the raw hello; any other family (possible firmware / boot) is blocked.
            return .blocked
        }
    }
}

// MARK: - Incoming J078 frames

enum J078Incoming: Equatable {
    case status(ScooterStatus)
    case limitAck(Gear, Int)
    case limitReport(Gear, Int)
    case passwordOK
    case passwordWrong
    case otherReply(UInt8)
    case rejected(String)

    /// Decodes and classifies one notification. Never crashes on short / long / junk input.
    static func parse(raw: [UInt8]) -> J078Incoming {
        if raw.isEmpty { return .rejected("empty frame") }
        if raw.count > 64 { return .rejected("too long (\(raw.count) bytes)") }
        let d = Proto.decode(raw)
        if d.count < 3 { return .rejected("too short (\(d.count) bytes)") }
        guard d[0] == 0xDB, d[1] == 0xEB else { return .rejected("not a DB EB frame") }
        if d[2] == 0xFA {
            if var s = Proto.parseStatus(d) {
                s.raw = raw
                return .status(s)
            }
            return .rejected("status frame with a bad length or header (\(d.count) bytes)")
        }
        if let a = Proto.parseLimitAck(d) { return .limitAck(a.0, a.1) }
        if let l = Proto.parseLimit(d) { return .limitReport(l.0, l.1) }
        if Proto.isPasswordOK(d) { return .passwordOK }
        if Proto.isPasswordWrong(d) { return .passwordWrong }
        return .otherReply(d[2])
    }
}

// MARK: - Speed-limit outcome

/// What we can honestly say about a speed-limit write. BLE write success is NOT acceptance.
enum LimitOutcome: Equatable {
    case notSent
    case waiting(requested: Int)
    case accepted(Int)
    case declined(requested: Int, kept: Int)
    case noAck(requested: Int)

    static func evaluate(requested: Int?, acked: Int?, sentAt: Date?, now: Date, timeout: TimeInterval = 3) -> LimitOutcome {
        guard let req = requested else { return .notSent }
        if let a = acked {
            return a == req ? .accepted(a) : .declined(requested: req, kept: a)
        }
        if let t = sentAt, now.timeIntervalSince(t) > timeout { return .noAck(requested: req) }
        return .waiting(requested: req)
    }

    var text: String {
        switch self {
        case .notSent: return "not sent yet"
        case .waiting(let r): return "asked \(r) km/h, waiting for the scooter's answer..."
        case .accepted(let a): return "scooter accepted \(a) km/h"
        case .declined(let r, let k): return "scooter declined \(r), kept \(k) km/h"
        case .noAck(let r): return "asked \(r) km/h, no answer from the scooter (not applied as far as we know)"
        }
    }
}
