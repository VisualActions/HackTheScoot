import XCTest

final class FakeTimer: CancellableTimer {
    var cancelled = false
    let block: () -> Void
    init(_ b: @escaping () -> Void) { block = b }
    func cancel() { cancelled = true }
}

final class FakeScheduler: TimerScheduler {
    var made: [FakeTimer] = []
    func schedule(every interval: TimeInterval, _ block: @escaping () -> Void) -> CancellableTimer {
        let t = FakeTimer(block); made.append(t); return t
    }
}

final class SessionTimerTests: XCTestCase {
    func testNoDuplicateHeartbeat() {
        let s = FakeScheduler(); let timers = SessionTimers(scheduler: s)
        var n = 0
        timers.start("keepalive", every: 0.5) { n += 1 }
        timers.start("keepalive", every: 0.5) { n += 100 }
        XCTAssertEqual(timers.count, 1)
        XCTAssertTrue(s.made[0].cancelled, "starting the same name again replaces the old timer")
        s.made[1].block()
        XCTAssertEqual(n, 100)
    }

    func testDisconnectStopsEverything() {
        let s = FakeScheduler(); let timers = SessionTimers(scheduler: s)
        timers.start("keepalive", every: 0.5) {}
        timers.start("hello", every: 3) {}
        timers.start("rssi", every: 2) {}
        timers.newSession()
        XCTAssertEqual(timers.count, 0)
        XCTAssertTrue(s.made.allSatisfy { $0.cancelled })
    }

    func testOldSessionTickIsIgnored() {
        let s = FakeScheduler(); let timers = SessionTimers(scheduler: s)
        var fired = 0
        timers.start("keepalive", every: 0.5) { fired += 1 }
        let old = s.made[0]
        timers.newSession()
        old.block()   // a late tick from the dead session
        XCTAssertEqual(fired, 0)
    }
}

final class ReconnectTests: XCTestCase {
    func testBackoffAndReset() {
        var p = ReconnectPolicy()
        XCTAssertEqual(p.onDisconnect(userRequested: false, bluetoothOn: true), .reconnect(attempt: 1, delay: 0.5))
        XCTAssertEqual(p.onDisconnect(userRequested: false, bluetoothOn: true), .reconnect(attempt: 2, delay: 1))
        XCTAssertEqual(p.onDisconnect(userRequested: false, bluetoothOn: true), .reconnect(attempt: 3, delay: 2))
        for _ in 0..<5 { _ = p.onDisconnect(userRequested: false, bluetoothOn: true) }
        if case .reconnect(_, let d) = p.onDisconnect(userRequested: false, bluetoothOn: true) { XCTAssertEqual(d, 5) } else { XCTFail() }
        p.onConnected()
        XCTAssertEqual(p.onDisconnect(userRequested: false, bluetoothOn: true), .reconnect(attempt: 1, delay: 0.5))
    }

    func testUserDisconnectAndOffNeverReconnect() {
        var p = ReconnectPolicy()
        if case .reconnect = p.onDisconnect(userRequested: true, bluetoothOn: true) { XCTFail() }
        if case .reconnect = p.onDisconnect(userRequested: false, bluetoothOn: false) { XCTFail() }
        p.enabled = false
        if case .reconnect = p.onDisconnect(userRequested: false, bluetoothOn: true) { XCTFail() }
    }

    func testMaxAttempts() {
        var p = ReconnectPolicy(); p.maxAttempts = 2
        _ = p.onDisconnect(userRequested: false, bluetoothOn: true)
        _ = p.onDisconnect(userRequested: false, bluetoothOn: true)
        if case .reconnect = p.onDisconnect(userRequested: false, bluetoothOn: true) { XCTFail() }
    }

    func testPhaseGatesCommands() {
        XCTAssertFalse(ConnectionPhase.discovering.canSendCommands)
        XCTAssertFalse(ConnectionPhase.subscribing.canSendCommands)
        XCTAssertFalse(ConnectionPhase.reconnecting(attempt: 1).canSendCommands)
        XCTAssertTrue(ConnectionPhase.ready.canSendCommands)
    }

    func testSignalWords() {
        XCTAssertEqual(SignalStrength.from(rssi: -50), .excellent)
        XCTAssertEqual(SignalStrength.from(rssi: -90), .weak)
        XCTAssertEqual(SignalStrength.from(rssi: nil), .none)
        XCTAssertEqual(SignalStrength.from(rssi: 127), .none)
    }
}

final class ParkGateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testTimeoutNeverParks() {
        var g = ParkGate()
        g.passwordSent(at: t0)
        g.tick(now: t0.addingTimeInterval(5))
        XCTAssertEqual(g.state, .timedOut)
        XCTAssertFalse(g.mayPark(now: t0.addingTimeInterval(5)))
        // a late OK after the timeout does not open the gate
        XCTAssertFalse(g.reply(.passwordOK, at: t0.addingTimeInterval(6)))
        XCTAssertFalse(g.mayPark(now: t0.addingTimeInterval(6)))
    }

    func testOnlyRealOKParks() {
        var g = ParkGate()
        XCTAssertFalse(g.mayPark(now: t0))
        g.passwordSent(at: t0)
        XCTAssertFalse(g.reply(.otherReply(0xBA), at: t0))
        XCTAssertFalse(g.mayPark(now: t0))
        XCTAssertTrue(g.reply(J078Incoming.parse(raw: Proto.encode([0xDB, 0xEB, 0xCA, 0xCA, 0xFF])), at: t0.addingTimeInterval(0.2)))
        XCTAssertTrue(g.mayPark(now: t0.addingTimeInterval(1)))
        XCTAssertFalse(g.mayPark(now: t0.addingTimeInterval(60)), "a verified password expires")
    }

    func testWrongPasswordAndReset() {
        var g = ParkGate()
        g.passwordSent(at: t0)
        g.reply(.passwordWrong, at: t0)
        XCTAssertFalse(g.mayPark(now: t0))
        g.passwordSent(at: t0); g.reply(.passwordOK, at: t0)
        g.reset()   // disconnect
        XCTAssertFalse(g.mayPark(now: t0))
    }
}

final class SimulationIsolationTests: XCTestCase {
    func testWriteGuardNeverPassesInSimulation() {
        let w = WriteGuard()
        w.source = .simulation; w.channelReady = true; w.advancedUnlocked = true
        for origin in [WriteOrigin.session, .control, .experimental, .manual] {
            XCTAssertNotEqual(w.decide([0x01], channel: "6E400002", safety: .verified, origin: origin, userConfirmed: true), .allow)
        }
        w.source = .replay
        XCTAssertNotEqual(w.decide([0x01], channel: "6E400002", safety: .verified, origin: .control, userConfirmed: true), .allow)
        XCTAssertEqual(w.sentCount, 0)
    }

    func testSimulatorFramesGoThroughTheRealParser() {
        let sim = ScooterSimulator(scenario: .sportRun, seed: 7)
        var statuses = 0, maxSpeed = 0.0
        for _ in 0..<100 {
            for f in sim.step(dt: 0.1) {
                if case .status(let s) = J078Incoming.parse(raw: f) { statuses += 1; maxSpeed = max(maxSpeed, s.speed) }
            }
        }
        XCTAssertGreaterThan(statuses, 50)
        XCTAssertLessThanOrEqual(maxSpeed, 19.0, "never above the sport cap")
    }

    func testMalformedScenarioIsRejectedSafely() {
        let sim = ScooterSimulator(scenario: .malformed, seed: 3)
        var rejected = 0
        for _ in 0..<300 { for f in sim.step(dt: 0.1) { if case .rejected = J078Incoming.parse(raw: f) { rejected += 1 } } }
        XCTAssertGreaterThan(rejected, 0)
    }

    func testSimulatedLimitWriteIsClampedLikeTheReal() {
        let sim = ScooterSimulator(scenario: .idle, seed: 1)
        sim.applyCommand([0xBD, 0xBE, 0xAB, 0xA2, 0x20])  // ask 32
        let acks = sim.step(dt: 0.1).compactMap { f -> Int? in
            if case .limitAck(_, let k) = J078Incoming.parse(raw: f) { return k } else { return nil }
        }
        XCTAssertEqual(acks.first, 31)
    }

    func testGateBasics() {
        let w = WriteGuard()
        w.source = .bluetooth
        XCTAssertNotEqual(w.decide([1], channel: "6E400002", safety: .verified, origin: .control), .allow, "channel not ready")
        w.channelReady = true
        XCTAssertEqual(w.decide([1], channel: "6E400002", safety: .verified, origin: .control), .allow)
        XCTAssertNotEqual(w.decide([1], channel: "6E400002", safety: .experimental, origin: .control), .allow, "never automatic")
        XCTAssertNotEqual(w.decide([1], channel: "6E400002", safety: .experimental, origin: .experimental, userConfirmed: false), .allow)
        XCTAssertEqual(w.decide([1], channel: "6E400002", safety: .experimental, origin: .experimental, userConfirmed: true), .allow)
        XCTAssertNotEqual(w.decide([1], channel: "6E400002", safety: .blocked, origin: .manual, userConfirmed: true), .allow)
        XCTAssertNotEqual(w.decide([1], channel: "2A25", safety: .verified, origin: .control), .allow, "identity / DFU characteristics are never written")
    }
}

final class AdapterTests: XCTestCase {
    func testUnknownDefaultsToReadOnly() {
        let (a, c) = AdapterRegistry.best(name: "Some Speaker", serviceIDs: ["180D", "FEAA"])
        XCTAssertEqual(c, .none)
        XCTAssertEqual(a.id, GenericReadOnlyAdapter.adapterID)
        XCTAssertTrue(Capability.allCases.filter { $0.isWrite }.allSatisfy { !a.canWrite($0) && !a.canWriteExperimentally($0) })
    }

    func testNameAloneIsNotEnough() {
        let (a, c) = AdapterRegistry.best(name: "365_scooter", serviceIDs: [])
        XCTAssertEqual(a.id, Joyhis365Adapter.adapterID)
        XCTAssertEqual(c, .nameOnly)
        let (_, c2) = AdapterRegistry.best(name: "365_scooter", serviceIDs: ["6E400001-0000-1000-8000-00805F9B34FB"])
        XCTAssertEqual(c2, .servicesAndName)
    }

    func testNordicUARTIsNotAJ078() {
        let (a, _) = AdapterRegistry.best(name: "uart", serviceIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E"])
        XCTAssertEqual(a.id, GenericReadOnlyAdapter.adapterID)
    }

    func testVolpamMatchAndCaps() {
        let (a, _) = AdapterRegistry.best(name: nil, serviceIDs: ["F1F0", "F2F0"])
        XCTAssertEqual(a.id, VolpamAdapter.adapterID)
        XCTAssertEqual(a.factoryMaxKmh, 35)
        XCTAssertTrue(a.canWrite(.speedLimitWrite))
        XCTAssertFalse(a.canWrite(.setLight), "feature-frame bits are unverified")
        XCTAssertTrue(a.canWriteExperimentally(.setLight))
    }

    func testJ078Evidence() {
        let a = Joyhis365Adapter()
        XCTAssertEqual(a.level, .partial)
        XCTAssertEqual(a.factoryMaxKmh, 31)
        for c in [Capability.liveSpeed, .setLight, .setPark, .setRidingMode, .speedLimitRead] { XCTAssertEqual(a.evidence(c), .verified, c.rawValue) }
        XCTAssertEqual(a.evidence(.battery), .unverified)
        XCTAssertEqual(a.evidence(.odometer), .unverified)
        XCTAssertFalse(a.canWrite(.setUnits))
        XCTAssertNotEqual(a.level, .full, "nothing is Full without hardware testing")
    }

    func testNoAdapterAdvertisesAboveFactory() {
        XCTAssertNil(Proto.setLimit(.sport, kmh: 32))
        XCTAssertNil(VolpamProto.speedLimitWrite(tenthsKmh: 351))
        XCTAssertNotNil(VolpamProto.speedLimitWrite(tenthsKmh: 350))
    }
}

final class TripTests: XCTestCase {
    func testDistanceAverageAndGaps() {
        // 10 km/h for 36 s = 0.1 km, then a 30 s gap (lost link) that must add nothing
        var s: [TripSample] = (0...36).map { TripSample(t: Double($0), kmh: 10, mode: "Eco") }
        s += (66...102).map { TripSample(t: Double($0), kmh: 10, mode: "Drive") }
        let st = TripMath.stats(s)
        XCTAssertEqual(st.distanceKm, 0.2, accuracy: 0.0001)
        XCTAssertEqual(st.avgMovingKmh, 10, accuracy: 0.0001)
        XCTAssertEqual(st.maxKmh, 10)
        XCTAssertEqual(st.timeInMode["Eco"] ?? 0, 36, accuracy: 0.001)
        XCTAssertEqual(st.timeInMode["Drive"] ?? 0, 36, accuracy: 0.001)
    }

    func testInvalidSamplesRejected() {
        let s = [TripSample(t: 0, kmh: 5, mode: nil), TripSample(t: 1, kmh: .nan, mode: nil),
                 TripSample(t: 2, kmh: -3, mode: nil), TripSample(t: 3, kmh: 500, mode: nil), TripSample(t: 4, kmh: 5, mode: nil)]
        let st = TripMath.stats(s)
        XCTAssertEqual(st.rejectedSamples, 3)
        XCTAssertEqual(st.maxKmh, 5)
    }

    func testDetector() {
        var d = TripDetector()
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(d.sample(kmh: 0.5, at: t0), .none)
        XCTAssertEqual(d.sample(kmh: 8, at: t0.addingTimeInterval(1)), .start)
        XCTAssertEqual(d.sample(kmh: 0, at: t0.addingTimeInterval(30)), .none)
        XCTAssertEqual(d.tick(now: t0.addingTimeInterval(200)), .end)
    }

    func testSummaryLabelsEstimateAndSimulation() {
        var t = Trip(start: Date(), end: nil, scooterName: "J078", source: "simulation")
        t.samples = [TripSample(t: 0, kmh: 10, mode: nil), TripSample(t: 1, kmh: 10, mode: nil)]
        let s = TripMath.summary(t, mph: true)
        XCTAssertTrue(s.contains("estimated"))
        XCTAssertTrue(s.contains("SIMULATED"))
    }
}

final class ThemeTests: XCTestCase {
    func testRoundTripAndDefaults() {
        var t = DashTheme(); t.accent = "#123456"; t.gauge = "classic"
        let d = t.exportJSON()!
        XCTAssertEqual(try? DashTheme.importJSON(d).get(), t)
        let partial = #"{"accent":"#ABCDEF","gauge":"nope","tiles":["mode","bogus","mode"]}"#.data(using: .utf8)!
        let p = try! DashTheme.importJSON(partial).get()
        XCTAssertEqual(p.accent, "#ABCDEF")
        XCTAssertEqual(p.gauge, DashTheme().gauge)
        XCTAssertEqual(p.tiles, ["mode"])
    }

    func testRejectsJunkAndPrivateData() {
        XCTAssertEqual(DashTheme.importJSON(Data("hello".utf8)), .failure(.notJSON))
        XCTAssertEqual(DashTheme.importJSON(Data(#"{"kind":"trip"}"#.utf8)), .failure(.wrongKind))
        let json = String(data: DashTheme().exportJSON()!, encoding: .utf8)!
        for word in ["password", "uuid", "identifier", "samples", "route"] { XCTAssertFalse(json.lowercased().contains(word)) }
    }
}
