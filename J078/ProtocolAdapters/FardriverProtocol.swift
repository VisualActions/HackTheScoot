import Foundation

// MARK: - Fardriver (ND-series e-bike / e-scooter motor controllers)
//
// CLEAN-ROOM, READ-ONLY. Written from the public, MIT-licensed protocol notes in
// jackhumbert/fardriver-controllers (README "Serial Protocol" + the field names in
// fardriver.hpp), https://github.com/jackhumbert/fardriver-controllers. No code was
// copied: the CRC below is computed bitwise (CRC-16/MODBUS polynomial 0xA001, start
// value 0x7F3C), which reproduces that project's two lookup tables byte-for-byte.
//
// What the notes say: the controller streams 16-byte frames
//   AA | id(6 bits) flags(2 bits) | 12 data bytes | crc lo, crc hi
// and `id` (< 55) picks which block of six 16-bit words the data is.
// The Bluetooth module forwards the same serial frames (notify on FFE1).
//
// HackTheScoot never writes to a Fardriver: motor-controller settings writes can damage
// hardware. Every value here is "unverified" until someone records a capture from a
// real controller and checks it against the official app.

enum FardriverProto {
    static let magic: UInt8 = 0xAA
    static let frameLength = 16
    static let serviceIDs = ["FFE0", "FFEC"]
    static let notifyChar = "FFE1"

    /// Address of the first 16-bit word in a frame, by id (from the public notes).
    static let addressTable: [UInt8] = [
        0xE2, 0xE8, 0xEE, 0x00, 0x06, 0x0C, 0x12,
        0xE2, 0xE8, 0xEE, 0x18, 0x1E, 0x24, 0x2A,
        0xE2, 0xE8, 0xEE, 0x30, 0x5D, 0x63, 0x69,
        0xE2, 0xE8, 0xEE, 0x7C, 0x82, 0x88, 0x8E,
        0xE2, 0xE8, 0xEE, 0x94, 0x9A, 0xA0, 0xA6,
        0xE2, 0xE8, 0xEE, 0xAC, 0xB2, 0xB8, 0xBE,
        0xE2, 0xE8, 0xEE, 0xC4, 0xCA, 0xD0,
        0xE2, 0xE8, 0xEE, 0xD6, 0xDC, 0xF4, 0xFA,
    ]

    /// CRC over `bytes` (everything except the two CRC bytes). Returns (first, second) byte.
    static func crc(_ bytes: [UInt8]) -> (UInt8, UInt8) {
        var c: UInt16 = 0x7F3C
        for b in bytes {
            c ^= UInt16(b)
            for _ in 0..<8 {
                if c & 1 != 0 { c = (c >> 1) ^ 0xA001 } else { c >>= 1 }
            }
        }
        return (UInt8(c & 0xFF), UInt8(c >> 8))
    }

    struct Frame: Equatable {
        let id: UInt8
        let flags: UInt8
        /// Address of data word 0, nil for ids the notes don't map (>= 55).
        let address: UInt8?
        /// Six little-endian 16-bit words.
        let words: [UInt16]
        let data: [UInt8]
    }

    enum Parsed: Equatable {
        case frame(Frame)
        case rejected(String)
    }

    static func parse(_ b: [UInt8]) -> Parsed {
        guard b.count == frameLength else { return .rejected("length \(b.count), want 16") }
        guard b[0] == magic else { return .rejected("no AA header") }
        let (c0, c1) = crc(Array(b[0..<14]))
        guard b[14] == c0, b[15] == c1 else { return .rejected("CRC mismatch") }
        let id = b[1] & 0x3F
        let flags = b[1] >> 6
        let data = Array(b[2..<14])
        var words: [UInt16] = []
        var i = 0
        while i + 1 < data.count {
            words.append(UInt16(data[i]) | (UInt16(data[i + 1]) << 8))
            i += 2
        }
        let addr: UInt8? = Int(id) < addressTable.count ? addressTable[Int(id)] : nil
        return .frame(Frame(id: id, flags: flags, address: addr, words: words, data: data))
    }

    /// Builds a valid frame (tests and the offline decoder only; never sent anywhere).
    static func makeFrame(id: UInt8, data: [UInt8], flags: UInt8 = 2) -> [UInt8] {
        var d = data
        if d.count < 12 { d += [UInt8](repeating: 0, count: 12 - d.count) }
        var f: [UInt8] = [magic, (flags << 6) | (id & 0x3F)] + Array(d.prefix(12))
        let (a, b) = crc(f)
        f += [a, b]
        return f
    }
}

/// Fault and state bits from the 0xE2 block (names from the public notes).
struct FardriverFaults: Equatable {
    var raw4: UInt8 = 0
    var raw5: UInt8 = 0

    static let names4 = ["Motor hall error", "Throttle error", "Current protection restart", "Phase current surge",
                         "Voltage protection", "Alarm", "Motor over-temperature", "Controller over-temperature"]
    /// Bit 7 of byte 5 is the brake input, not a fault.
    static let names5 = ["Phase current overflow", "Phase zero error", "Phase protection", "Line current zero error",
                         "MOSFET high-side error", "MOSFET low-side error", "Current protection"]

    var active: [String] {
        var out: [String] = []
        for i in 0..<8 where raw4 & (1 << UInt8(i)) != 0 { out.append(FardriverFaults.names4[i]) }
        for i in 0..<7 where raw5 & (1 << UInt8(i)) != 0 { out.append(FardriverFaults.names5[i]) }
        return out
    }
    var brake: Bool { return raw5 & 0x80 != 0 }
}

/// Live values merged from many frames. Every field is nil until its block has arrived.
struct FardriverTelemetry: Equatable {
    var volts: Double?
    var amps: Double?
    /// "MeasureSpeed" in the public notes, very likely motor RPM. Not converted to a road
    /// speed: that needs the wheel size and pole pairs, so it waits for a capture.
    var motorSpeedRaw: Int?
    var gear: Int?
    var forward: Bool?
    var reverse: Bool?
    var socPercent: Int?
    var motorTempC: Int?
    var faults: FardriverFaults?
    var validFrames = 0
    var rejectedFrames = 0
    var lastAddress: UInt8?

    /// Volts x amps. Computed here, not reported by the controller.
    var watts: Double? {
        guard let v = volts, let a = amps else { return nil }
        return v * a
    }

    mutating func apply(_ f: FardriverProto.Frame) {
        validFrames += 1
        lastAddress = f.address
        guard let addr = f.address else { return }
        let d = f.data
        func i16(_ w: Int) -> Int { return Int(Int16(bitPattern: f.words[w])) }
        switch addr {
        case 0xE2:
            forward = d[0] & 0x01 != 0
            reverse = d[0] & 0x02 != 0
            gear = Int((d[0] >> 2) & 0x03)
            faults = FardriverFaults(raw4: d[2], raw5: d[3])
            motorSpeedRaw = Int(f.words[3])
        case 0xE8:
            volts = Double(i16(0)) / 10.0
            amps = Double(i16(2)) / 4.0
        case 0xF4:
            motorTempC = i16(0)
            let soc = Int(Int8(bitPattern: d[3]))
            socPercent = (0...100).contains(soc) ? soc : nil
        default:
            break
        }
    }
}

/// Reassembles 16-byte frames from Bluetooth notifications, which can split or join them.
struct FardriverStream {
    private(set) var buffer: [UInt8] = []
    var telemetry = FardriverTelemetry()

    /// Feeds raw notification bytes; returns the frames that passed the CRC.
    @discardableResult
    mutating func feed(_ bytes: [UInt8]) -> [FardriverProto.Frame] {
        buffer += bytes
        if buffer.count > 512 { buffer.removeFirst(buffer.count - 512) }
        var out: [FardriverProto.Frame] = []
        while buffer.count >= FardriverProto.frameLength {
            guard let start = buffer.firstIndex(of: FardriverProto.magic) else { buffer.removeAll(); break }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= FardriverProto.frameLength else { break }
            let cand = Array(buffer[0..<FardriverProto.frameLength])
            if case .frame(let f) = FardriverProto.parse(cand) {
                out.append(f)
                telemetry.apply(f)
                buffer.removeFirst(FardriverProto.frameLength)
            } else {
                telemetry.rejectedFrames += 1
                buffer.removeFirst(1)
            }
        }
        return out
    }
}

struct FardriverAdapter: ProtocolAdapter {
    static let adapterID = "fardriver"
    let id = FardriverAdapter.adapterID
    let displayName = "Fardriver controller"
    let family = "Fardriver ND series (e-bike / e-scooter motor controller), read-only"
    let level = CompatibilityLevel.experimental
    let factoryMaxKmh: Int? = nil
    let capabilities: [Capability: Evidence] = [
        .liveSpeed: .unverified,     // motor speed word only, no road speed without wheel size
        .battery: .unverified,       // SOC byte from the public notes
        .faultCodes: .unverified,    // fault bits from the public notes
        .temperature: .unverified,   // motor temperature word
        .ridingMode: .unverified,    // 2-bit gear field
    ]
    let evidenceNotes = [
        "Clean-room from the MIT-licensed public notes in jackhumbert/fardriver-controllers (serial frame format, CRC, field names).",
        "No capture from a real Fardriver yet: every value is unverified.",
        "Read-only forever until a capture: HackTheScoot never writes to a motor controller.",
    ]

    func match(name: String?, serviceIDs: [String]) -> MatchConfidence {
        let ids = Set(serviceIDs.map { ServiceID.short($0) })
        let hasService = FardriverProto.serviceIDs.contains { ids.contains($0) }
        let n = (name ?? "").lowercased()
        let hasName = n.contains("fardriver") || n.hasPrefix("controldm")
        switch (hasService, hasName) {
        case (true, true): return .servicesAndName
        case (false, true): return .nameOnly
        // FFE0 alone is a generic serial module used by lots of gadgets: not enough.
        default: return .none
        }
    }
}
