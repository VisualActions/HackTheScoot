import XCTest

final class ScrambleTests: XCTestCase {
    func testRoundTripAll256() {
        for v in 0...255 {
            let b = UInt8(v)
            XCTAssertEqual(Proto.decodeByte(Proto.encodeByte(b)), b, "round trip failed for \(v)")
            XCTAssertEqual(Proto.encodeByte(Proto.decodeByte(b)), b, "inverse round trip failed for \(v)")
        }
    }

    func testScrambleIsPermutation() {
        let outs = Set((0...255).map { Proto.encodeByte(UInt8($0)) })
        XCTAssertEqual(outs.count, 256)
        XCTAssertTrue(Proto.scrambleSelfTestOK)
    }

    func testArrayEncodeDecode() {
        let frame: [UInt8] = [0xBD, 0xBE, 0xAB, 0xA2, 0x1F]
        XCTAssertEqual(Proto.decode(Proto.encode(frame)), frame)
        XCTAssertNotEqual(Proto.encode(frame), frame)
    }
}

final class PacketParsingTests: XCTestCase {
    func status(flags: UInt8 = 0x11, gear: UInt8 = 0x40, speedTenths: Int = 190, count: Int = 29) -> [UInt8] {
        var d = [UInt8](repeating: 0, count: count)
        d[0] = 0xDB; d[1] = 0xEB; d[2] = 0xFA; d[3] = 0xDB
        if count > 4 { d[4] = flags }
        if count > 5 { d[5] = gear }
        if count > 8 { d[7] = UInt8(speedTenths >> 8); d[8] = UInt8(speedTenths & 0xFF) }
        if count > 10 { d[10] = 0x64 }
        return d
    }

    func testStatusValues() {
        let s = Proto.parseStatus(status(flags: 0x11 | 0x02 | 0x04, gear: 0x40, speedTenths: 190))
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.gear, .sport)
        XCTAssertEqual(s?.speed ?? -1, 19.0, accuracy: 0.001)
        XCTAssertEqual(s?.light, true)
        XCTAssertEqual(s?.parked, true)
        XCTAssertEqual(s?.unitsBit, true)
        XCTAssertEqual(s?.startModeBit, true)
    }

    func testGearCodes() {
        XCTAssertEqual(Proto.parseStatus(status(gear: 0x08))?.gear, .walk)
        XCTAssertEqual(Proto.parseStatus(status(gear: 0x10))?.gear, .eco)
        XCTAssertEqual(Proto.parseStatus(status(gear: 0x20))?.gear, .drive)
        XCTAssertNil(Proto.parseStatus(status(gear: 0x33))?.gear)
    }

    func testStatusFromAirBytesKeepsRaw() {
        let air = Proto.encode(status())
        guard case .status(let s) = J078Incoming.parse(raw: air) else { return XCTFail("not parsed") }
        XCTAssertEqual(s.raw, air)
        XCTAssertEqual(s.decoded, status())
    }

    func testBatteryAndOdometerAreRawOnly() {
        let s = Proto.parseStatus(status())!
        XCTAssertEqual(s.byte10Raw, 0x64)
        XCTAssertEqual(UnverifiedData.allCases.count, 6)
    }

    func testRejectsShortLongAndJunk() {
        for bad: [UInt8] in [[], [0x01], [0xDB, 0xEB], [UInt8](repeating: 0x55, count: 65), [0x00, 0x01, 0x02, 0x03, 0x04]] {
            if case .rejected = J078Incoming.parse(raw: bad) {} else { XCTFail("accepted junk \(bad)") }
        }
        // truncated status (header ok, too short for speed)
        let trunc = Proto.encode([0xDB, 0xEB, 0xFA, 0xDB, 0x11])
        if case .rejected = J078Incoming.parse(raw: trunc) {} else { XCTFail("accepted truncated status") }
        XCTAssertNil(Proto.parseStatus([0xDB, 0xEB, 0xFA, 0xDB, 0x11, 0x40, 0, 0]))
    }

    func testEveryLengthNeverCrashes() {
        for n in 0...70 {
            var b = [UInt8](repeating: 0, count: n)
            if n > 0 { b[0] = Proto.encodeByte(0xDB) }
            if n > 1 { b[1] = Proto.encodeByte(0xEB) }
            if n > 2 { b[2] = Proto.encodeByte(0xFA) }
            if n > 3 { b[3] = Proto.encodeByte(0xDB) }
            _ = J078Incoming.parse(raw: b)
            _ = VolpamProto.parse(b)
            _ = CaptureTools.explain(b)
        }
    }

    func testPasswordReplies() {
        XCTAssertEqual(J078Incoming.parse(raw: Proto.encode([0xDB, 0xEB, 0xCA, 0xCA, 0xFF])), .passwordOK)
        XCTAssertEqual(J078Incoming.parse(raw: Proto.encode([0xDB, 0xEB, 0xCA, 0xCA, 0xAA])), .passwordWrong)
        XCTAssertFalse(Proto.isPasswordOK([0xDB, 0xEB, 0xCA, 0xCA]))
    }

    func testPasswordFrame() {
        XCTAssertEqual(Proto.password("000000"), [0xBD, 0xBE, 0xAC, 0xAC, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30])
        XCTAssertEqual(J078Safety.classify(decoded: Proto.password("123456"), scrambled: true), .verified)
    }
}

final class SpeedLimitTests: XCTestCase {
    func testCapturedWritesAndFactoryCap() {
        XCTAssertEqual(Proto.setLimit(.sport, kmh: 29), [0xBD, 0xBE, 0xAB, 0xA2, 0x1D])
        XCTAssertEqual(Proto.setLimit(.sport, kmh: 31), [0xBD, 0xBE, 0xAB, 0xA2, 0x1F])
        // v4.0.1: v3's above-stock range (6...45 km/h) is back, behind the UI warning.
        XCTAssertEqual(Proto.setLimit(.sport, kmh: 32), [0xBD, 0xBE, 0xAB, 0xA2, 0x20])
        XCTAssertEqual(Proto.setLimit(.sport, kmh: 45), [0xBD, 0xBE, 0xAB, 0xA2, 0x2D])
        XCTAssertEqual(Proto.setLimit(.eco, kmh: 13), [0xBD, 0xBE, 0xAB, 0xA0, 0x0D])
        XCTAssertNil(Proto.setLimit(.sport, kmh: 46), "never above 45 km/h")
        XCTAssertNil(Proto.setLimit(.sport, kmh: 5), "never below 6 km/h")
        XCTAssertEqual(Gear.sport.factoryMaxKmh, 31)
        XCTAssertFalse(Gear.walk.limitAdjustable)
    }

    /// The v4.0.0 Controls crash: walk's stock range is 6...6, and a SwiftUI Slider with
    /// equal bounds crashes. Every slider range the app builds must be at least 1 wide.
    func testSliderRangesAreNeverZeroWidth() {
        for g in Gear.allCases {
            for above in [false, true] {
                let r = g.sliderRange(aboveStock: above)
                XCTAssertLessThan(r.lowerBound, r.upperBound, "\(g.name) aboveStock=\(above)")
            }
            XCTAssertEqual(g.sliderRange(aboveStock: true), 6...45)
        }
    }

    func testAckParsing() {
        // Nov 9 15:23: asked 32, scooter acked A2 1F (kept 31)
        let ack = Proto.encode([0xDB, 0xEB, 0xBA, 0xA2, 0x1F])
        XCTAssertEqual(J078Incoming.parse(raw: ack), .limitAck(.sport, 31))
        let report = Proto.encode([0xDB, 0xEB, 0xBA, 0x2A, 0x1F])
        XCTAssertEqual(J078Incoming.parse(raw: report), .limitReport(.sport, 31))
        XCTAssertEqual(J078Incoming.parse(raw: Proto.encode([0xDB, 0xEB, 0xBA, 0x0A, 0x0C])), .limitReport(.eco, 12))
    }

    func testOutcome() {
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(LimitOutcome.evaluate(requested: nil, acked: nil, sentAt: nil, now: t0), .notSent)
        XCTAssertEqual(LimitOutcome.evaluate(requested: 29, acked: nil, sentAt: t0, now: t0.addingTimeInterval(1)), .waiting(requested: 29))
        XCTAssertEqual(LimitOutcome.evaluate(requested: 29, acked: nil, sentAt: t0, now: t0.addingTimeInterval(5)), .noAck(requested: 29))
        XCTAssertEqual(LimitOutcome.evaluate(requested: 29, acked: 29, sentAt: t0, now: t0), .accepted(29))
        XCTAssertEqual(LimitOutcome.evaluate(requested: 30, acked: 31, sentAt: t0, now: t0), .declined(requested: 30, kept: 31))
    }

    func testSafetyClassification() {
        XCTAssertEqual(J078Safety.classify(decoded: [0xBD, 0xBE, 0xAB, 0xA2, 0x1F], scrambled: true), .verified)
        XCTAssertEqual(J078Safety.classify(decoded: [0xBD, 0xBE, 0xAB, 0xA0, 0x0A], scrambled: true), .experimental)
        XCTAssertEqual(J078Safety.classify(decoded: [0xBD, 0xBE, 0xAB, 0xA2, 0x20], scrambled: true), .experimental, "above stock needs the confirmation")
        XCTAssertEqual(J078Safety.classify(decoded: [0xBD, 0xBE, 0xAB, 0xA2, 0x2E], scrambled: true), .blocked, "46 km/h is never sent")
        XCTAssertEqual(J078Safety.classify(decoded: [0xBD, 0xBE, 0xAB, 0xA2, 0xFF], scrambled: true), .verified)
        XCTAssertEqual(J078Safety.classify(decoded: [0xBD, 0xBE, 0xAB, 0x00, 0x01], scrambled: true), .verified)
        XCTAssertEqual(J078Safety.classify(decoded: [0xBD, 0xBE, 0xAB, 0x05, 0x09], scrambled: true), .experimental)
        XCTAssertEqual(J078Safety.classify(decoded: [0xBD, 0xBE, 0xEE, 0x00, 0x00], scrambled: true), .blocked, "unknown family (possible firmware) is blocked")
        XCTAssertEqual(J078Safety.classify(decoded: Proto.helloRaw, scrambled: false), .verified)
        XCTAssertEqual(J078Safety.classify(decoded: [0x01, 0x02], scrambled: false), .blocked)
    }
}

final class UnitTests: XCTestCase {
    func testConversions() {
        XCTAssertEqual(Units.kmhToMph(31), 19.26, accuracy: 0.01)
        XCTAssertEqual(Units.mphToKmh(19), 30.58, accuracy: 0.01)
        XCTAssertEqual(Units.mphToKmh(Units.kmhToMph(42)), 42, accuracy: 1e-9)
        XCTAssertEqual(Gear.mph(for: .sport, kmh: 31), 19)
        XCTAssertEqual(Gear.mph(for: .drive, kmh: 18), 11)
        XCTAssertEqual(Gear.mph(for: .sport, kmh: 29), 18)
    }

    func testSpeedDisplay() {
        let a = SpeedDisplay.make(raw: 19, scooterIsMile: true, display: "scooter")
        XCTAssertEqual(a.unit, "mph"); XCTAssertEqual(a.value, 19, accuracy: 1e-9)
        let b = SpeedDisplay.make(raw: 19, scooterIsMile: true, display: "kmh")
        XCTAssertEqual(b.unit, "km/h"); XCTAssertEqual(b.value, 30.58, accuracy: 0.01)
        let c = SpeedDisplay.make(raw: 31, scooterIsMile: false, display: "mph")
        XCTAssertEqual(c.value, 19.26, accuracy: 0.01)
        XCTAssertEqual(SpeedDisplay.toKmh(10, scooterIsMile: true), 16.09, accuracy: 0.01)
    }

    func testInterpolatorNeverOvershoots() {
        var i = SpeedInterpolator()
        let t = Date()
        i.sample(10, at: t)
        var last = 0.0
        for _ in 0..<200 {
            let v = i.step(dt: 1.0 / 60, intensity: 0.8)
            XCTAssertLessThanOrEqual(v, 10.0 + 1e-9)
            XCTAssertGreaterThanOrEqual(v, last - 1e-9)
            last = v
        }
        XCTAssertEqual(last, 10, accuracy: 0.05)
        XCTAssertTrue(i.isStale(now: t.addingTimeInterval(5)))
        XCTAssertFalse(i.isStale(now: t.addingTimeInterval(0.5)))
        var j = SpeedInterpolator(); j.sample(7, at: t)
        XCTAssertEqual(j.step(dt: 0.016, intensity: 0), 7)
    }
}
