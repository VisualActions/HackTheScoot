import XCTest

/// v4.2 logic: Fardriver + Ninebot read-only parsers, speed alert, ride timer,
/// maintenance reminders, ride totals and the Garage's new vehicle fields.
final class FardriverTests: XCTestCase {

    // Frames built with the public project's own CRC tables (in Python), so these check
    // that our bitwise CRC really matches theirs.
    let e8: [UInt8] = [0xAA, 0x81, 0xD5, 0x02, 0x00, 0x00, 0x29, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC7, 0x91]
    let e2: [UInt8] = [0xAA, 0x80, 0x09, 0x00, 0x02, 0x80, 0x40, 0x00, 0xB0, 0x04, 0x00, 0x00, 0x00, 0x00, 0xF1, 0xB8]
    let f4: [UInt8] = [0xAA, 0xB5, 0x3C, 0x00, 0x00, 0x55, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1C, 0x9E]

    func testCRCMatchesThePublicTables() {
        for f in [e8, e2, f4] {
            let (a, b) = FardriverProto.crc(Array(f[0..<14]))
            XCTAssertEqual(a, f[14]); XCTAssertEqual(b, f[15])
        }
        XCTAssertEqual(FardriverProto.makeFrame(id: 1, data: Array(e8[2..<14])), e8)
    }

    func testParsesVoltsAmpsSpeedFaultsAndCharge() {
        var t = FardriverTelemetry()
        for f in [e8, e2, f4] {
            guard case .frame(let fr) = FardriverProto.parse(f) else { return XCTFail("frame rejected") }
            t.apply(fr)
        }
        XCTAssertEqual(t.volts ?? 0, 72.5, accuracy: 0.001)
        XCTAssertEqual(t.amps ?? 0, 10.25, accuracy: 0.001)
        XCTAssertEqual(t.watts ?? 0, 72.5 * 10.25, accuracy: 0.01)
        XCTAssertEqual(t.motorSpeedRaw, 1200)
        XCTAssertEqual(t.gear, 2)
        XCTAssertEqual(t.forward, true)
        XCTAssertEqual(t.faults?.active, ["Throttle error"])
        XCTAssertEqual(t.faults?.brake, true)
        XCTAssertEqual(t.motorTempC, 60)
        XCTAssertEqual(t.socPercent, 85)
        XCTAssertEqual(t.validFrames, 3)
    }

    func testRejectsBadFrames() {
        var bad = e8; bad[5] ^= 0x01
        XCTAssertEqual(FardriverProto.parse(bad), .rejected("CRC mismatch"))
        XCTAssertEqual(FardriverProto.parse(Array(e8.prefix(15))), .rejected("length 15, want 16"))
        var noHeader = e8; noHeader[0] = 0x55
        XCTAssertEqual(FardriverProto.parse(noHeader), .rejected("no AA header"))
    }

    func testStreamReassemblesSplitAndJoinedNotifications() {
        var s = FardriverStream()
        let joined = [0x00, 0x13] + e8 + e2 + f4
        // split into 20-byte notifications, the BLE default
        var frames = 0
        var i = 0
        while i < joined.count {
            frames += s.feed(Array(joined[i..<min(i + 20, joined.count)])).count
            i += 20
        }
        XCTAssertEqual(frames, 3)
        XCTAssertEqual(s.telemetry.volts ?? 0, 72.5, accuracy: 0.001)
        XCTAssertEqual(s.feed([]).count, 0)
    }

    func testAdapterIsReadOnlyAndNeedsMoreThanFFE0() {
        let a = FardriverAdapter()
        XCTAssertEqual(a.level, .experimental)
        XCTAssertTrue(Capability.allCases.filter { $0.isWrite }.allSatisfy { !a.canWrite($0) && !a.canWriteExperimentally($0) })
        XCTAssertEqual(a.match(name: "HMSoft", serviceIDs: ["FFE0"]), .none, "a bare FFE0 serial module isn't a Fardriver")
        XCTAssertEqual(a.match(name: "FARDRIVER-72", serviceIDs: ["FFE0"]), .servicesAndName)
        XCTAssertEqual(a.match(name: "Fardriver", serviceIDs: []), .nameOnly)
        let (best, _) = AdapterRegistry.best(name: "FarDriver ND", serviceIDs: ["0000FFE0-0000-1000-8000-00805F9B34FB"])
        XCTAssertEqual(best.id, FardriverAdapter.adapterID)
        XCTAssertEqual(AdapterRegistry.kind(for: best), .unknown, "listen-only path, never the J078/Volpam write paths")
    }
}

final class NinebotTests: XCTestCase {

    func testFrameShapeAndChecksum() {
        // Protocol 2 read request shape: 5A A5 LEN 3E TARGET CMD INDEX payload, then the
        // inverted sum of LEN..payload, low byte first (0x130 -> 0xFECF -> CF FE).
        let f = NinebotProto.makeFrame(target: 0x20, cmd: 0x01, index: 0xB0, payload: [0x20])
        XCTAssertEqual(f, [0x5A, 0xA5, 0x01, 0x3E, 0x20, 0x01, 0xB0, 0x20, 0xCF, 0xFE])
        guard case .frame(let fr) = NinebotProto.parse(f) else { return XCTFail("rejected") }
        XCTAssertEqual(fr.index, 0xB0)
        XCTAssertEqual(fr.payload, [0x20])
        // the docs' 15-bit form is accepted too
        var f15 = f; f15[9] = 0x7E
        if case .rejected = NinebotProto.parse(f15) { XCTFail("15-bit checksum form should be accepted") }
    }

    func testDecodesSpeedBatteryOdometerFromReadReplies() {
        var t = NinebotTelemetry()
        t.feed(NinebotProto.makeFrame(target: 0x01, cmd: 0x04, index: 0x26, payload: [0xC8, 0x00]))        // 20.0 km/h
        t.feed(NinebotProto.makeFrame(target: 0x01, cmd: 0x04, index: 0xB5, payload: [0x4B, 0x00]))        // 75 %
        t.feed(NinebotProto.makeFrame(target: 0x01, cmd: 0x04, index: 0xB7, payload: [0x10, 0x27, 0x00, 0x00])) // 10.000 km
        XCTAssertEqual(t.speedKmh ?? 0, 20.0, accuracy: 0.001)
        XCTAssertEqual(t.batteryPercent, 75)
        XCTAssertEqual(t.odometerKm ?? 0, 10.0, accuracy: 0.001)
        XCTAssertEqual(t.validFrames, 3)
    }

    func testOtherBoardsAndEncryptedFramesAreNotDecoded() {
        var t = NinebotTelemetry()
        t.feed(NinebotProto.makeFrame(target: 0x07, cmd: 0x04, index: 0x26, payload: [0xC8, 0x00]))   // a BMS register 0x26
        XCTAssertNil(t.speedKmh)
        t.feed([0x5A, 0xA5, 0x01] + [UInt8](repeating: 0x11, count: 11))                              // LEN + 13 = encrypted
        XCTAssertEqual(t.encryptedFrames, 1)
        var bad = NinebotProto.makeFrame(target: 0x01, cmd: 0x04, index: 0x26, payload: [0xC8, 0x00]); bad[7] = 0x01
        t.feed(bad)
        XCTAssertEqual(t.rejectedFrames, 1)
    }

    func testAdapterIsReadOnly() {
        let a = NinebotAdapter()
        XCTAssertTrue(Capability.allCases.filter { $0.isWrite }.allSatisfy { !a.canWrite($0) && !a.canWriteExperimentally($0) })
        XCTAssertEqual(a.match(name: nil, serviceIDs: ["6e400001-0000-0000-006e-696e65626f74"]), .services)
        XCTAssertEqual(a.match(name: "uart", serviceIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E"]), .none, "plain Nordic UART isn't claimed")
        // the J078's own service still goes to the J078 adapter
        let (j, _) = AdapterRegistry.best(name: "365_scooter", serviceIDs: ["6E400001-0000-1000-8000-00805F9B34FB"])
        XCTAssertEqual(j.id, Joyhis365Adapter.adapterID)
    }
}

final class RideFeatureTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testSpeedAlertFiresOnceThenRearmsBelowTheLine() {
        var a = SpeedAlertLogic(thresholdKmh: 30)
        XCTAssertFalse(a.sample(kmh: 25, at: t0))
        XCTAssertTrue(a.sample(kmh: 31, at: t0.addingTimeInterval(1)))
        XCTAssertFalse(a.sample(kmh: 33, at: t0.addingTimeInterval(2)), "no repeat while still over")
        XCTAssertFalse(a.sample(kmh: 29.5, at: t0.addingTimeInterval(3)), "hovering just under doesn't re-arm")
        XCTAssertFalse(a.sample(kmh: 31, at: t0.addingTimeInterval(4)))
        XCTAssertFalse(a.sample(kmh: 20, at: t0.addingTimeInterval(5)))
        XCTAssertTrue(a.sample(kmh: 32, at: t0.addingTimeInterval(12)))
        XCTAssertFalse(a.sample(kmh: .nan, at: t0.addingTimeInterval(13)))
        var off = SpeedAlertLogic(thresholdKmh: 0)
        XCTAssertFalse(off.sample(kmh: 50, at: t0))
    }

    func testRideTimerWithLapsAndPause() {
        var r = RideTimer()
        XCTAssertFalse(r.hasStarted)
        r.start(at: t0)
        r.lap(at: t0.addingTimeInterval(60))
        r.lap(at: t0.addingTimeInterval(110))
        XCTAssertEqual(r.laps, [60, 50])
        XCTAssertEqual(r.bestLap, 50)
        r.pause(at: t0.addingTimeInterval(120))
        XCTAssertEqual(r.elapsed(at: t0.addingTimeInterval(500)), 120, "paused time doesn't count")
        r.lap(at: t0.addingTimeInterval(130))
        XCTAssertEqual(r.laps.count, 2, "no lap while paused")
        r.start(at: t0.addingTimeInterval(200))
        XCTAssertEqual(r.elapsed(at: t0.addingTimeInterval(210)), 130)
        XCTAssertEqual(r.currentLap(at: t0.addingTimeInterval(210)), 20)
        r.reset()
        XCTAssertEqual(r, RideTimer())
        XCTAssertEqual(RideTimer.format(75.3), "1:15.3")
        XCTAssertEqual(RideTimer.format(3725), "1:02:05.0")
        XCTAssertEqual(RideTimer.format(.nan), "0:00.0")
    }

    func testMaintenanceDueByDistanceOrDays() {
        let item = MaintenanceItem(name: "Brakes", everyKm: 100, everyDays: 30, lastDone: t0, kmAtLastDone: 50)
        XCTAssertEqual(MaintenanceMath.status(item, totalKm: 60, now: t0.addingTimeInterval(86400)), .ok)
        XCTAssertEqual(MaintenanceMath.status(item, totalKm: 140, now: t0.addingTimeInterval(86400)), .soon)
        XCTAssertEqual(MaintenanceMath.status(item, totalKm: 151, now: t0.addingTimeInterval(86400)), .due)
        XCTAssertEqual(MaintenanceMath.status(item, totalKm: 60, now: t0.addingTimeInterval(31 * 86400)), .due, "days alone make it due")
        let done = MaintenanceMath.markDone(item, totalKm: 151, now: t0.addingTimeInterval(40 * 86400))
        XCTAssertEqual(MaintenanceMath.status(done, totalKm: 151, now: t0.addingTimeInterval(40 * 86400)), .ok)
        XCTAssertEqual(MaintenanceMath.remaining(item, totalKm: 151, now: t0, mph: false), "due now")
        XCTAssertEqual(MaintenanceMath.remaining(item, totalKm: 50, now: t0, mph: false), "100 km or 30 days left")
        XCTAssertEqual(MaintenanceMath.defaults(now: t0).count, 3)
        let data = try? JSONEncoder().encode([item])
        XCTAssertEqual(try? JSONDecoder().decode([MaintenanceItem].self, from: data ?? Data()), [item])
    }

    func testRideTotalsAddUpTrips() {
        var samples: [TripSample] = []
        for i in 0...60 { samples.append(TripSample(t: Double(i), kmh: 36, mode: "Drive")) }   // 60 s at 36 km/h = 0.6 km
        let a = Trip(start: t0, end: t0.addingTimeInterval(60), scooterName: "J078", source: "bluetooth", samples: samples)
        let b = Trip(start: t0, end: t0.addingTimeInterval(60), scooterName: "J078", source: "bluetooth", samples: samples)
        let tot = RideTotalsMath.totals([a, b, Trip(start: t0, end: nil, scooterName: "x", source: "bluetooth", samples: [])])
        XCTAssertEqual(tot.rides, 2)
        XCTAssertEqual(tot.distanceKm, 1.2, accuracy: 0.05)
        XCTAssertEqual(tot.maxKmh, 36, accuracy: 0.01)
        XCTAssertEqual(tot.avgKmh, 36, accuracy: 1.0)
        XCTAssertEqual(RideTotals().avgKmh, 0)
    }

    func testGarageVehicleAndControllerTypes() {
        var s = GarageScooter(name: "Sur-Ron", compatID: "fardriver-nd", vehicleType: .ebike)
        XCTAssertEqual(s.controllerType, .fardriver)
        XCTAssertTrue(s.readOnlyUntilCapture)
        s.controller = .unknown
        XCTAssertEqual(s.controllerType, .unknown)
        let j = GarageScooter(name: "My J078", compatID: "joyhis-j078")
        XCTAssertEqual(j.controllerType, .joyhis365)
        XCTAssertFalse(j.readOnlyUntilCapture)
        XCTAssertEqual(j.vehicleType, .escooter)
        // round trip, and a 4.1 garage (no new fields) still loads
        let data = try? JSONEncoder().encode(s)
        let back = try? JSONDecoder().decode(GarageScooter.self, from: data ?? Data())
        XCTAssertEqual(back?.vehicleType, .ebike)
        XCTAssertEqual(back?.controller, .unknown)
        let old = #"{"id":"7D2A1B9E-1111-4222-8333-944455556666","name":"Dad's Volpam","compatID":"volpam-dad"}"#
        let o = try? JSONDecoder().decode(GarageScooter.self, from: Data(old.utf8))
        XCTAssertEqual(o?.vehicleType, .escooter)
        XCTAssertNil(o?.controller)
        XCTAssertEqual(o?.controllerType, .zydtech)
        XCTAssertEqual(CompatSeed.find("fardriver-nd").level, .experimental)
        XCTAssertTrue(ControllerType.allCases.filter { $0.readOnlyUntilCapture } == [.ninebot, .fardriver, .kukirin, .unknown])
    }
}
