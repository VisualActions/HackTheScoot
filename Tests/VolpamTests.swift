import XCTest

final class VolpamCRCTests: XCTestCase {
    // Every distinct frame the vendor app wrote in the Nov 9 17:46 capture.
    let captured: [String] = [
        "AC 00 0A 62 06 0C 12 23 3E B6", "AC 00 0A E2 06 0C 12 23 3F 68", "AC 00 0A E6 06 0C 12 23 CE A8",
        "AC 00 0A E3 06 0C 12 23 02 A8", "AC 00 0A E1 06 0C 12 23 7B 68", "AC 00 0A A2 06 0C 12 23 3E A7",
        "AC 00 0A C2 06 0C 12 23 BE AF",
        "01 07 00 00 00 04 B5 C9", "01 07 00 08 00 04 34 0B", "01 07 00 10 00 04 B4 0C", "01 07 00 18 00 04 35 CE",
        "01 07 00 20 00 04 B4 03", "01 07 00 28 00 04 35 C1", "01 07 00 30 00 04 B5 C6", "01 07 00 38 00 04 34 04",
        "01 07 00 40 00 04 B4 1D", "01 07 00 48 00 04 35 DF",
        "01 03 00 00 00 05 85 C9", "01 03 00 09 00 04 94 0B", "01 03 00 13 00 01 75 CF", "01 03 00 17 00 01 34 0E",
        "01 03 00 20 00 02 C5 C1",
        "01 10 00 20 00 01 02 01 54 A1 5F", "01 10 00 20 00 01 02 01 65 60 8B", "01 10 00 20 00 01 02 01 75 61 47",
    ]

    func testCRCReproducesEveryCapturedFrameByteForByte() {
        XCTAssertEqual(captured.count, 25)
        for s in captured {
            let f = CaptureTools.parseHex(s)!
            XCTAssertEqual(VolpamProto.withCRC(Array(f.dropLast(2))), f, "CRC mismatch for \(s)")
            XCTAssertTrue(VolpamProto.crcOK(f))
        }
    }

    func testNotificationCRCs() {
        let status = CaptureTools.parseHex("AC 00 00 01 02 64 00 00 00 00 01 97 00 06 0B 00 00 00 00 03 57 08 62 66 CE")!
        XCTAssertTrue(VolpamProto.crcOK(status))
        let limits = CaptureTools.parseHex("AC 01 00 06 0C 12 23 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 EA 6D")!
        XCTAssertTrue(VolpamProto.crcOK(limits))
        XCTAssertEqual(VolpamProto.parse(limits), .limits([6, 12, 18, 35]))
        guard case .status(let s) = VolpamProto.parse(status) else { return XCTFail() }
        XCTAssertEqual(s.mode, .sport)
        XCTAssertFalse(s.light)
        XCTAssertTrue(s.unlocked)
    }

    func testBuildersMatchCapture() {
        XCTAssertEqual(VolpamProto.speedLimitWrite(tenthsKmh: 340), VolpamProto.capturedSpeedWrites[0])
        XCTAssertNil(VolpamProto.speedLimitWrite(tenthsKmh: 357), "above the 35 km/h factory limit")
        XCTAssertNil(VolpamProto.speedLimitWrite(tenthsKmh: 373))
        XCTAssertNil(VolpamProto.speedLimitWrite(tenthsKmh: 10))
        let base = VolpamProto.Features(unlocked: true, mph: true, zeroStart: true, light: false, mode: .sport)
        XCTAssertEqual(VolpamProto.featureFrame(base, limits: [6, 12, 18, 35]), VolpamProto.capturedFeatureFrames[1])
        var lock = base; lock.unlocked = false
        XCTAssertEqual(VolpamProto.featureFrame(lock, limits: [6, 12, 18, 35]), VolpamProto.capturedFeatureFrames[0])
        var light = base; light.light = true
        XCTAssertEqual(VolpamProto.featureFrame(light, limits: [6, 12, 18, 35]), VolpamProto.capturedFeatureFrames[2])
        var eco = base; eco.mode = .eco
        XCTAssertEqual(VolpamProto.featureFrame(eco, limits: [6, 12, 18, 35]), VolpamProto.capturedFeatureFrames[3])
        var drive = base; drive.mode = .drive
        XCTAssertEqual(VolpamProto.featureFrame(drive, limits: [6, 12, 18, 35]), VolpamProto.capturedFeatureFrames[4])
        XCTAssertNil(VolpamProto.featureFrame(base, limits: [6, 12, 18, 40]), "never raise a limit above factory")
        XCTAssertNil(VolpamProto.featureFrame(base, limits: [6, 12, 18]))
    }

    func testPasswordFrameAndReplies() {
        XCTAssertNil(VolpamProto.passwordFrame("12345"))
        XCTAssertNil(VolpamProto.passwordFrame("abcdef"))
        XCTAssertEqual(VolpamProto.passwordFrame("123456")?.count, 14)
        XCTAssertEqual(VolpamProto.parse(Array("OK+PWD:Y".utf8)), .passwordOK)
        XCTAssertFalse(VolpamProto.passwordMask.contains("1"))
    }

    func testSafety() {
        XCTAssertEqual(VolpamProto.safety(of: VolpamProto.heartbeat, to: "F1F1"), .verified)
        XCTAssertEqual(VolpamProto.safety(of: VolpamProto.capturedSpeedWrites[0], to: "F1F1"), .verified)
        XCTAssertEqual(VolpamProto.safety(of: VolpamProto.capturedSpeedWrites[2], to: "F1F1"), .blocked, "37.3 km/h is above factory")
        XCTAssertEqual(VolpamProto.safety(of: VolpamProto.capturedFeatureFrames[0], to: "F1F1"), .experimental)
        var badCRC = VolpamProto.capturedFeatureFrames[0]; badCRC[9] ^= 0xFF
        XCTAssertEqual(VolpamProto.safety(of: badCRC, to: "F1F1"), .blocked)
        XCTAssertEqual(VolpamProto.safety(of: [0x01, 0x02, 0x03], to: "2A25"), .blocked)
    }

    func testRejectsBadCRCAndLengths() {
        var s = CaptureTools.parseHex("AC 01 00 06 0C 12 23 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 EA 6D")!
        s[5] = 0x99
        if case .rejected = VolpamProto.parse(s) {} else { XCTFail("bad CRC accepted") }
        if case .rejected = VolpamProto.parse([0xAC, 0x00]) {} else { XCTFail("short accepted") }
        XCTAssertEqual(VolpamProto.parse(CaptureTools.parseHex("5A FA FF 03 0A 0A 22 A5 AF")!), .sportLimit(0x22))
        XCTAssertEqual(VolpamProto.parse(CaptureTools.parseHex("5A FA FF 03 0A 0A 22 00 A5 AF")!), .rejected("not in the map"))
    }
}
