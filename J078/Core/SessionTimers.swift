import Foundation

/// Something that can be cancelled (a Timer, or a fake one in tests).
protocol CancellableTimer: AnyObject {
    func cancel()
}

/// Makes repeating timers. The app uses RunLoopScheduler; tests use a fake.
protocol TimerScheduler {
    func schedule(every interval: TimeInterval, _ block: @escaping () -> Void) -> CancellableTimer
}

final class RunLoopTimerBox: CancellableTimer {
    private var timer: Timer?
    init(_ t: Timer) { timer = t }
    func cancel() { timer?.invalidate(); timer = nil }
}

struct RunLoopScheduler: TimerScheduler {
    func schedule(every interval: TimeInterval, _ block: @escaping () -> Void) -> CancellableTimer {
        let t = Timer(timeInterval: interval, repeats: true) { _ in block() }
        RunLoop.main.add(t, forMode: .common)   // keeps firing while a list scrolls
        return RunLoopTimerBox(t)
    }
}

/// Owns every repeating timer of one Bluetooth session.
/// - one timer per name: starting a name that is running replaces it (no duplicate heartbeats)
/// - cancelAll() stops everything at once (called the moment the scooter disconnects)
/// - every timer carries the session id it was started for; a tick from an old session is ignored
final class SessionTimers {
    private let scheduler: TimerScheduler
    private var timers: [String: CancellableTimer] = [:]
    private(set) var sessionID: Int = 0

    init(scheduler: TimerScheduler = RunLoopScheduler()) {
        self.scheduler = scheduler
    }

    var activeNames: [String] { return timers.keys.sorted() }
    var count: Int { return timers.count }
    func isRunning(_ name: String) -> Bool { return timers[name] != nil }

    /// A new session: every old timer is cancelled and old ticks become no-ops.
    @discardableResult
    func newSession() -> Int {
        cancelAll()
        sessionID += 1
        return sessionID
    }

    func start(_ name: String, every interval: TimeInterval, _ block: @escaping () -> Void) {
        timers[name]?.cancel()
        let sid = sessionID
        timers[name] = scheduler.schedule(every: interval) { [weak self] in
            guard let self = self, self.sessionID == sid, self.timers[name] != nil else { return }
            block()
        }
    }

    func stop(_ name: String) {
        timers[name]?.cancel()
        timers[name] = nil
    }

    func cancelAll() {
        for (_, t) in timers { t.cancel() }
        timers.removeAll()
    }
}
