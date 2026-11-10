import Foundation

/// Offline J078 simulator. It builds REAL-format status frames (scrambled, the way
/// they come over the air) so the whole app, including the parser, runs on them.
/// It has no reference to Bluetooth: it cannot send anything. Every frame it makes
/// is tagged simulated by the app.
final class ScooterSimulator {

    enum Scenario: String, CaseIterable, Identifiable {
        case idle = "Parked, idle"
        case connecting = "Connecting"
        case cityRide = "City ride"
        case sportRun = "Sport run"
        case modeTour = "Mode tour"
        case disconnect = "Disconnect + reconnect"
        case malformed = "Malformed packets"

        var id: String { rawValue }
        var blurb: String {
            switch self {
            case .idle: return "Standing still, light off, status every 100 ms."
            case .connecting: return "Silence for 2 s, then the limit reports, then status."
            case .cityRide: return "Eco and drive, stops and starts."
            case .sportRun: return "Accelerates to the sport limit and back."
            case .modeTour: return "Walk, eco, drive, sport, 6 s each."
            case .disconnect: return "Rides, drops the link for 4 s, comes back."
            case .malformed: return "Mixes in short, long and garbage frames (the parser must reject them)."
            }
        }
    }

    struct State: Equatable {
        var gear: Gear = .eco
        var speedMph: Double = 0
        var light = false
        var parked = false
        var mile = true
        var zeroStart = true
    }

    private(set) var state = State()
    private(set) var t: TimeInterval = 0
    private(set) var scenario: Scenario
    private var targetMph: Double = 0
    private var rng: UInt64
    private(set) var linkUp = true

    init(scenario: Scenario = .cityRide, seed: UInt64 = 42) {
        self.scenario = scenario
        self.rng = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        if scenario == .sportRun { state.gear = .sport }
        if scenario == .idle { state.parked = true }
    }

    private func rand() -> Double {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Double(rng % 10_000) / 10_000.0
    }

    /// The simulator's version of a control tap (light, gear...). Changes the
    /// simulated scooter only; never reaches Bluetooth.
    func apply(light: Bool? = nil, gear: Gear? = nil, parked: Bool? = nil, mile: Bool? = nil, zeroStart: Bool? = nil) {
        if let v = light { state.light = v }
        if let g = gear { state.gear = g }
        if let p = parked { state.parked = p; if p { state.speedMph = 0 } }
        if let m = mile { state.mile = m }
        if let z = zeroStart { state.zeroStart = z }
    }

    private var pending: [[UInt8]] = []
    private(set) var limitKmh: [Gear: Int] = [:]

    /// A decoded J078 command frame, as the app would have sent it. Changes the
    /// simulated scooter only. Speed-limit writes are acked the way the real one
    /// does: clamped to the factory value (32 asked -> 31 kept on sport).
    func applyCommand(_ d: [UInt8]) {
        guard d.count == 5, d[0] == 0xBD, d[1] == 0xBE, d[2] == 0xAB else { return }
        let v = d[4]
        switch d[3] {
        case Proto.Cmd.light: apply(light: v == 1)
        case Proto.Cmd.park: apply(parked: v == 1)
        case Proto.Cmd.units: apply(mile: v == 1)
        case Proto.Cmd.startMode: apply(zeroStart: v == 1)
        case Proto.Cmd.gear:
            if let g = Gear.allCases.first(where: { $0.setValue == v }) { apply(gear: g) }
        case 0xA0...0xA3:
            guard v != 0xFF, let g = Gear.fromLimitByte(d[3]) else { return }
            let kept = min(Int(v), g.factoryMaxKmh)
            limitKmh[g] = kept
            pending.append(Proto.encode([0xDB, 0xEB, 0xBA, d[3], UInt8(kept)]))
        default: break
        }
    }

    func capMph(_ g: Gear) -> Double { return Double(g.capturedTopMph) }

    /// Advance by dt seconds. Returns the over-the-air frames produced (may be empty).
    func step(dt: TimeInterval) -> [[UInt8]] {
        t += dt
        var out: [[UInt8]] = []
        switch scenario {
        case .idle:
            targetMph = 0
        case .connecting:
            if t < 2 { return [] }
            if t - dt < 2 { out += limitReports() }
            targetMph = 0
        case .cityRide:
            let phase = t.truncatingRemainder(dividingBy: 40)
            state.gear = phase < 20 ? .eco : .drive
            targetMph = (phase.truncatingRemainder(dividingBy: 20) < 14) ? capMph(state.gear) * (0.75 + 0.2 * rand()) : 0
        case .sportRun:
            state.gear = .sport
            let phase = t.truncatingRemainder(dividingBy: 30)
            targetMph = phase < 18 ? capMph(.sport) : 0
        case .modeTour:
            let i = Int(t / 6) % 4
            state.gear = [Gear.walk, .eco, .drive, .sport][i]
            targetMph = capMph(state.gear)
        case .disconnect:
            let phase = t.truncatingRemainder(dividingBy: 20)
            linkUp = !(phase > 10 && phase < 14)
            targetMph = capMph(.drive) * 0.8
            state.gear = .drive
        case .malformed:
            targetMph = capMph(.eco) * 0.6
            let r = rand()
            if r < 0.15 { out.append([0x12]) }                                   // too short
            else if r < 0.25 { out.append([UInt8](repeating: 0xAA, count: 80)) } // too long
            else if r < 0.35 { out.append(Proto.encode([0xDB, 0xEB, 0xFA, 0xDB, 0x11])) } // truncated status
            else if r < 0.42 { out.append([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]) }    // garbage
        }
        if state.parked { targetMph = 0 }
        let cap = capMph(state.gear)
        targetMph = min(targetMph, cap)
        // smooth physics-ish response, 1 decimal like the real scooter
        let accel = targetMph > state.speedMph ? 6.0 : 9.0  // mph per second
        let delta = targetMph - state.speedMph
        let stepMph = max(-accel * dt, min(accel * dt, delta))
        state.speedMph = max(0, min(cap, state.speedMph + stepMph))
        guard linkUp else { return [] }
        out += pending
        pending.removeAll()
        out.append(statusFrame())
        if Int(t * 2) != Int((t - dt) * 2) {        // ~ every 500 ms, like the real one
            out.append(Proto.encode([0xDB, 0xEB, 0xBA, limitCode(state.gear), UInt8(limitKmh[state.gear] ?? state.gear.capturedLimitKmh)]))
        }
        return out
    }

    func limitCode(_ g: Gear) -> UInt8 {
        switch g {
        case .eco: return 0x0A
        case .drive: return 0x1A
        case .sport: return 0x2A
        case .walk: return 0x3A
        }
    }

    func limitReports() -> [[UInt8]] {
        return Gear.allCases.map { Proto.encode([0xDB, 0xEB, 0xBA, limitCode($0), UInt8($0.capturedLimitKmh)]) }
    }

    /// A 29-byte status frame in the real layout, scrambled.
    func statusFrame() -> [UInt8] {
        var d = [UInt8](repeating: 0, count: 29)
        d[0] = 0xDB; d[1] = 0xEB; d[2] = 0xFA; d[3] = 0xDB
        var f: UInt8 = 0
        if state.mile { f |= 0x01 }
        if state.light { f |= 0x02 }
        if state.parked { f |= 0x04 }
        if state.zeroStart { f |= 0x10 }
        d[4] = f
        d[5] = state.gear.statusCode
        let shown = state.mile ? state.speedMph : Units.mphToKmh(state.speedMph)
        let tenths = Int((shown * 10).rounded())
        d[7] = UInt8((tenths >> 8) & 0xFF)
        d[8] = UInt8(tenths & 0xFF)
        d[10] = 0x64
        d[23] = 0xD0; d[24] = 0x97; d[25] = 0x01; d[26] = 0x00; d[27] = 0x05; d[28] = 0x05
        return Proto.encode(d)
    }
}
