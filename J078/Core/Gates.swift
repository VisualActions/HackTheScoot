import Foundation

// MARK: - Park / password gate (v4 fix)
//
// v3 could send "park" after the password step TIMED OUT. v4: park is only sent
// after the scooter actually answered DB EB CA CA FF to the password we sent in
// this same session. A timeout, a wrong-password reply, a disconnect or a new
// session all close the gate.

struct ParkGate: Equatable {
    enum State: Equatable {
        case idle
        case waiting(sentAt: Date)
        case verified(at: Date)
        case wrongPassword
        case timedOut
    }

    private(set) var state: State = .idle
    var timeout: TimeInterval = 2.5
    /// A verified password stays good for this long (the 365 app sends it right before park).
    var validFor: TimeInterval = 30

    mutating func passwordSent(at t: Date) { state = .waiting(sentAt: t) }

    /// Feed every decoded reply. Returns true when this reply changed the state.
    @discardableResult
    mutating func reply(_ incoming: J078Incoming, at t: Date) -> Bool {
        guard case .waiting = state else { return false }
        switch incoming {
        case .passwordOK: state = .verified(at: t); return true
        case .passwordWrong: state = .wrongPassword; return true
        default: return false
        }
    }

    mutating func tick(now: Date) {
        if case .waiting(let s) = state, now.timeIntervalSince(s) > timeout { state = .timedOut }
        if case .verified(let v) = state, now.timeIntervalSince(v) > validFor { state = .idle }
    }

    mutating func reset() { state = .idle }

    func mayPark(now: Date) -> Bool {
        if case .verified(let v) = state { return now.timeIntervalSince(v) <= validFor }
        return false
    }

    var text: String {
        switch state {
        case .idle: return "not sent yet"
        case .waiting: return "waiting for the scooter..."
        case .verified: return "password OK (scooter replied DB EB CA CA FF)"
        case .wrongPassword: return "wrong password, park NOT sent"
        case .timedOut: return "no answer from the scooter, park NOT sent"
        }
    }
}

// MARK: - Write guard
//
// The ONE place a byte can leave the phone. BLEManager asks it before every
// CoreBluetooth write. In simulation / replay nothing ever passes, whatever the
// caller wants, and every decision is recorded (tests read the record).

final class WriteGuard {
    struct Attempt: Equatable {
        let bytes: [UInt8]
        let channel: String
        let allowed: Bool
        let reason: String
    }

    var source: DataSource = .none
    var channelReady = false
    var advancedUnlocked = false
    private(set) var attempts: [Attempt] = []
    private(set) var sentCount = 0
    var keepHistory = 200

    func decide(_ bytes: [UInt8], channel: String, safety: CommandSafety,
                origin: WriteOrigin, userConfirmed: Bool = false) -> CommandGate.Decision {
        var d = CommandGate.check(source: source, safety: safety, origin: origin,
                                  channelReady: channelReady, userConfirmed: userConfirmed,
                                  advancedUnlocked: advancedUnlocked)
        if J078Safety.neverWriteCharacteristics.contains(channel.uppercased()) {
            d = .deny("this characteristic is never written (firmware / identity)")
        }
        let reason: String
        switch d {
        case .allow: reason = "ok"; sentCount += 1
        case .deny(let r): reason = r
        }
        attempts.append(Attempt(bytes: bytes, channel: channel, allowed: d == .allow, reason: reason))
        if attempts.count > keepHistory { attempts.removeFirst(attempts.count - keepHistory) }
        return d
    }
}

