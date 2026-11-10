import Foundation

/// Where the Bluetooth connection is. Shown to the user and used to gate writes.
enum ConnectionPhase: Equatable {
    case idle
    case scanning
    case connecting
    case discovering
    case subscribing         // waiting for the notify subscription to be CONFIRMED
    case authenticating      // Volpam: waiting for OK+PWD
    case synchronizing       // subscribed, waiting for the first valid status frame
    case ready
    case reconnecting(attempt: Int)
    case disconnected(reason: String)
    case bluetoothOff

    var label: String {
        switch self {
        case .idle: return "Not connected"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .discovering: return "Discovering services"
        case .subscribing: return "Subscribing"
        case .authenticating: return "Signing in"
        case .synchronizing: return "Synchronizing"
        case .ready: return "Connected"
        case .reconnecting(let n): return n > 1 ? "Reconnecting (try \(n))" : "Reconnecting"
        case .disconnected(let r): return r.isEmpty ? "Disconnected" : "Disconnected: \(r)"
        case .bluetoothOff: return "Bluetooth off"
        }
    }

    /// Writes that need an answer (password, park, limits) only go out here.
    var canSendCommands: Bool { return self == .ready || self == .synchronizing }
    var isLinked: Bool {
        switch self {
        case .discovering, .subscribing, .authenticating, .synchronizing, .ready: return true
        default: return false
        }
    }
}

/// Pure reconnect policy (unit-tested). iOS keeps a pending connect() alive with no
/// timeout, so the policy only decides WHETHER to keep trying and how to label it.
struct ReconnectPolicy {
    var enabled: Bool = true
    var maxAttempts: Int = 0           // 0 = keep trying while the app is allowed to run
    private(set) var attempt: Int = 0

    enum Action: Equatable {
        case reconnect(attempt: Int, delay: TimeInterval)
        case giveUp(String)
    }

    mutating func onDisconnect(userRequested: Bool, bluetoothOn: Bool) -> Action {
        if userRequested { attempt = 0; return .giveUp("you disconnected") }
        if !enabled { attempt = 0; return .giveUp("auto-reconnect is off") }
        if !bluetoothOn { return .giveUp("Bluetooth is off") }
        attempt += 1
        if maxAttempts > 0 && attempt > maxAttempts { return .giveUp("gave up after \(maxAttempts) tries") }
        // short backoff: 0.5, 1, 2, 4, 5, 5 ... seconds before re-issuing connect()
        let delay = min(5.0, 0.5 * pow(2.0, Double(attempt - 1)))
        return .reconnect(attempt: attempt, delay: delay)
    }

    mutating func onConnected() { attempt = 0 }
}

/// Signal strength words for an RSSI in dBm.
enum SignalStrength: String {
    case excellent = "Excellent", good = "Good", fair = "Fair", weak = "Weak", none = "No signal"

    static func from(rssi: Int?) -> SignalStrength {
        guard let r = rssi, r < 0, r > -127 else { return .none }
        if r >= -60 { return .excellent }
        if r >= -70 { return .good }
        if r >= -82 { return .fair }
        return .weak
    }

    var bars: Int {
        switch self {
        case .excellent: return 4
        case .good: return 3
        case .fair: return 2
        case .weak: return 1
        case .none: return 0
        }
    }
}

/// Counts frames per second over a sliding window (diagnostics).
struct RateMeter {
    private(set) var stamps: [Date] = []
    var window: TimeInterval = 3

    mutating func tick(_ t: Date) {
        stamps.append(t)
        trim(t)
    }

    mutating func trim(_ now: Date) {
        let cut = now.addingTimeInterval(-window)
        if let i = stamps.firstIndex(where: { $0 >= cut }) {
            if i > 0 { stamps.removeFirst(i) }
        } else {
            stamps.removeAll()
        }
    }

    func rate(now: Date) -> Double {
        let cut = now.addingTimeInterval(-window)
        let n = stamps.filter { $0 >= cut }.count
        return Double(n) / window
    }
}
