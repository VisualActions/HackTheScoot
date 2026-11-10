import Foundation

/// Offline helpers for the Developer Lab: decode pasted hex, read exported logs,
/// and compare two captures. Nothing here touches Bluetooth.
enum CaptureTools {

    static func parseHex(_ text: String) -> [UInt8]? {
        let cleaned = text.uppercased()
            .replacingOccurrences(of: "0X", with: "")
            .filter { "0123456789ABCDEF".contains($0) }
        guard !cleaned.isEmpty, cleaned.count % 2 == 0, cleaned.count <= 512 else { return nil }
        var out: [UInt8] = []
        var i = cleaned.startIndex
        while i < cleaned.endIndex {
            let j = cleaned.index(i, offsetBy: 2)
            guard let b = UInt8(cleaned[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }

    /// Explains one frame: tries J078 (scrambled air bytes, or already-decoded) and Volpam.
    static func explain(_ bytes: [UInt8]) -> [String] {
        var out: [String] = []
        let asAir = J078Incoming.parse(raw: bytes)
        if case .rejected = asAir {} else { out.append("J078 (air bytes, unscrambled): " + describe(asAir)) }
        let asDecoded = J078Incoming.parse(raw: Proto.encode(bytes))
        if case .rejected = asDecoded {} else { out.append("J078 (already decoded): " + describe(asDecoded)) }
        if bytes.count >= 3, bytes[0] == 0xBD, bytes[1] == 0xBE {
            out.append("J078 app->scooter (decoded): " + Proto.txLabel(bytes) + " [" + J078Safety.classify(decoded: bytes, scrambled: true).label + "]")
        }
        let air = Proto.decode(bytes)
        if air.count >= 3, air[0] == 0xBD, air[1] == 0xBE {
            out.append("J078 app->scooter (air): " + Proto.txLabel(air) + " [" + J078Safety.classify(decoded: air, scrambled: true).label + "]")
        }
        let v = VolpamProto.parse(bytes)
        if case .rejected(let why) = v {
            if bytes.first == 0xAC || bytes.first == 0x01 { out.append("Volpam: rejected (\(why))") }
        } else {
            out.append("Volpam: \(v)")
        }
        if bytes.count >= 4 && VolpamProto.crcOK(bytes) { out.append("CRC16-Modbus: OK") }
        if out.isEmpty { out.append("Not recognised. Unscrambled: " + Proto.hex(air)) }
        return out
    }

    static func describe(_ i: J078Incoming) -> String {
        switch i {
        case .status(let s): return Proto.label(s.decoded)
        case .limitAck(let g, let k): return "speed-limit ack: \(g.name) = \(k) km/h"
        case .limitReport(let g, let k): return "limit report: \(g.name) = \(k) km/h"
        case .passwordOK: return "password OK"
        case .passwordWrong: return "password WRONG"
        case .otherReply(let t): return String(format: "DB EB %02X reply (not in the map)", t)
        case .rejected(let w): return "rejected: \(w)"
        }
    }

    struct LogLine: Equatable {
        var time: String
        var dir: String
        var channel: String
        var air: [UInt8]
    }

    /// Reads a HackTheScoot exported log ("HH:mm:ss.SSS RX 6E400003 air: .. | dec: .. | note").
    static func parseExportedLog(_ text: String) -> [LogLine] {
        var out: [LogLine] = []
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            let parts = line.components(separatedBy: " ")
            guard parts.count >= 4, parts[1] == "RX" || parts[1] == "TX" else { continue }
            guard let r = line.range(of: "air: ") else { continue }
            var rest = String(line[r.upperBound...])
            if let bar = rest.range(of: " |") { rest = String(rest[..<bar.lowerBound]) }
            guard let bytes = parseHex(rest) else { continue }
            out.append(LogLine(time: parts[0], dir: parts[1], channel: parts[2], air: bytes))
        }
        return out
    }

    /// A frame "type" key for comparing captures (first 3-4 bytes after unscrambling).
    static func typeKey(_ l: LogLine) -> String {
        if l.channel.hasPrefix("6E40") {
            let d = Proto.decode(l.air)
            if let s = Proto.parseStatus(d) { return "\(l.dir) status \(s.gear?.name ?? "?")" }
            return "\(l.dir) " + Proto.hex(Array(d.prefix(4)))
        }
        return "\(l.dir) \(l.channel) " + Proto.hex(Array(l.air.prefix(3)))
    }

    struct Comparison: Equatable {
        var onlyInA: [String: Int]
        var onlyInB: [String: Int]
        var inBoth: [String: (Int, Int)]
        static func == (a: Comparison, b: Comparison) -> Bool {
            return a.onlyInA == b.onlyInA && a.onlyInB == b.onlyInB && a.inBoth.keys.sorted() == b.inBoth.keys.sorted()
        }
    }

    static func compare(_ a: [LogLine], _ b: [LogLine]) -> Comparison {
        var ca: [String: Int] = [:], cb: [String: Int] = [:]
        for l in a { ca[typeKey(l), default: 0] += 1 }
        for l in b { cb[typeKey(l), default: 0] += 1 }
        var onlyA: [String: Int] = [:], onlyB: [String: Int] = [:], both: [String: (Int, Int)] = [:]
        for (k, v) in ca { if let w = cb[k] { both[k] = (v, w) } else { onlyA[k] = v } }
        for (k, v) in cb where ca[k] == nil { onlyB[k] = v }
        return Comparison(onlyInA: onlyA, onlyInB: onlyB, inBoth: both)
    }

    /// Protocol self-tests the app can run on the phone (Developer Lab).
    static func selfTests() -> [(String, Bool)] {
        var r: [(String, Bool)] = []
        r.append(("scramble round trip, all 256 bytes", Proto.scrambleSelfTestOK))
        r.append(("scramble is a permutation (256 distinct outputs)", Set((0...255).map { Proto.encodeByte(UInt8($0)) }).count == 256))
        r.append(("Volpam CRC reproduces all 7 captured feature frames",
                  VolpamProto.capturedFeatureFrames.allSatisfy { VolpamProto.withCRC(Array($0.dropLast(2))) == $0 }))
        r.append(("Volpam CRC reproduces all 3 captured speed writes",
                  VolpamProto.capturedSpeedWrites.allSatisfy { VolpamProto.withCRC(Array($0.dropLast(2))) == $0 }))
        r.append(("speed-limit write refuses above factory (sport 32)", Proto.setLimit(.sport, kmh: 32) == nil))
        r.append(("empty / short / long frames are rejected",
                  [[], [0x01], [UInt8](repeating: 0, count: 90)].allSatisfy { if case .rejected = J078Incoming.parse(raw: $0) { return true } else { return false } }))
        r.append(("simulation can never pass the write gate",
                  CommandGate.check(source: .simulation, safety: .verified, origin: .control, channelReady: true, userConfirmed: true, advancedUnlocked: true) != .allow))
        return r
    }
}
