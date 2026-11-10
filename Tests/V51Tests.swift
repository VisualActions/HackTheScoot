import XCTest

/// v5.1 logic: KuKirin parser, the clean-room Ninebot Encryption2, the Xiaomi / Ninebot
/// session driver (with a fake radio and fake time), its safety gate and the error codes.
/// The crypto vectors were made with an independent Python implementation of the same
/// Apache-2.0 spec, so these check the Swift matches the spec as we read it. They do NOT
/// prove a real scooter agrees: that is untested on hardware.

enum NBVectors {
    static let name = "NBScooter1234"
    static let auth: [UInt8] = (0x10...0x1F).map { UInt8($0) }
    static let password: [UInt8] = (0xA0...0xAF).map { UInt8($0) }
    static let serial: [UInt8] = Array("N4GSD1234C5678".utf8)
    static let k0: [UInt8] = [0x4C, 0x27, 0x0A, 0x9C, 0x4A, 0xD5, 0xDA, 0x25, 0x36, 0x39, 0x5B, 0x5E, 0x46, 0xBA, 0x9C, 0x21]
    static let pre_fw: [UInt8] = [0x5A, 0xA5, 0x00, 0x4B, 0xC6, 0x8F, 0xDB, 0x00, 0x00, 0x45, 0xFF, 0x00, 0x00]
    static let pre_z: [UInt8] = [0x5A, 0xA5, 0x00, 0x27, 0x71, 0x95, 0x4E, 0x00, 0x00, 0x45, 0xFF, 0x00, 0x00]
    static let k1: [UInt8] = [0x7A, 0xD7, 0x49, 0x34, 0xF3, 0x57, 0xC1, 0xA3, 0x0D, 0x83, 0x7F, 0x83, 0x24, 0x73, 0x2A, 0x87]
    static let setp: [UInt8] = [0x5A, 0xA5, 0x10, 0x6C, 0x64, 0xB3, 0xC9, 0x14, 0x61, 0xEF, 0xFD, 0xAA, 0xB5, 0xCF, 0x2B, 0x68, 0x35, 0x0B, 0x0E, 0x74, 0xAE, 0x65, 0x75, 0xD7, 0x38, 0xBC, 0x9C, 0x00, 0x02]
    static let k2: [UInt8] = [0x48, 0xC4, 0x23, 0x03, 0x97, 0x2B, 0xDD, 0x35, 0x69, 0x6C, 0xE9, 0x51, 0x18, 0x02, 0x12, 0x09]
    static let authFrame: [UInt8] = [0x5A, 0xA5, 0x0E, 0xEE, 0x53, 0xD5, 0x26, 0x2A, 0xA5, 0xCC, 0x2B, 0x1F, 0xE6, 0x67, 0xE3, 0xAC, 0xEA, 0x77, 0x7E, 0x09, 0xB6, 0x80, 0xFE, 0x5F, 0xF1, 0x00, 0x03]
    static let rd: [UInt8] = [0x5A, 0xA5, 0x01, 0x08, 0xE5, 0xD3, 0xAE, 0xB8, 0x14, 0xC4, 0x8D, 0x3F, 0x00, 0x04]
    static let r_pre: [UInt8] = [0x5A, 0xA5, 0x1E, 0x54, 0xD9, 0x8F, 0xDB, 0x25, 0x51, 0xE8, 0x5E, 0xD4, 0xC1, 0x79, 0x9E, 0x99, 0x5D, 0xA4, 0xAB, 0x69, 0xFA, 0xCA, 0xC4, 0x7B, 0x74, 0xBD, 0x1E, 0x84, 0xE5, 0x5D, 0xBA, 0xB5, 0x07, 0x8B, 0x86, 0x42, 0xDF, 0x00, 0x00, 0x86, 0xFA, 0x00, 0x00]
    static let r_set: [UInt8] = [0x5A, 0xA5, 0x00, 0xEB, 0x13, 0x2F, 0x82, 0x54, 0xD9, 0xBE, 0xB9, 0x00, 0x07]
    static let r_auth: [UInt8] = [0x5A, 0xA5, 0x00, 0xF6, 0xD6, 0x4B, 0xA2, 0xB7, 0xCD, 0x97, 0x16, 0x00, 0x08]
    static let r_rd: [UInt8] = [0x5A, 0xA5, 0x02, 0xE2, 0x37, 0xDA, 0xBF, 0x23, 0xCD, 0x0F, 0xDA, 0x86, 0x37, 0x00, 0x09]
}

final class KukirinTests: XCTestCase {
    /// Our own frames, laid out like the published G2 observations.
    func g2Main(volts100: Int, rpm: Int, kmh: UInt8, motor: Bool) -> [UInt8] {
        var f = [UInt8](repeating: 0, count: 20)
        f[0] = 0x27; f[1] = 0x22
        f[4] = UInt8(volts100 & 0xFF); f[5] = UInt8(volts100 >> 8)
        f[10] = UInt8(rpm & 0xFF); f[11] = UInt8(rpm >> 8)
        f[12] = kmh
        f[18] = motor ? 0x42 : 0x40
        return f
    }

    func testG2LiveData() {
        var t = KukirinTelemetry(model: .g2)
        t.feed([UInt8](repeating: 0xFF, count: 20))
        XCTAssertEqual(t.ignoredFrames, 1, "the first all-FF block is ignored")
        t.feed(g2Main(volts100: 4815, rpm: 512, kmh: 23, motor: true))
        XCTAssertEqual(t.batteryVolts ?? 0, 48.15, accuracy: 0.001)
        XCTAssertEqual(t.motorRpm, 512)
        XCTAssertEqual(t.speedKmh, 23)
        XCTAssertEqual(t.motorActive, true)
        var m = [UInt8](repeating: 0, count: 20); m[0] = 0xF2; m[1] = 0xB0; m[3] = 0x14
        t.feed(m)
        XCTAssertEqual(t.rideMode, "Sport")
        m[3] = 0x19; t.feed(m); XCTAssertEqual(t.rideMode, "Race")
        m[3] = 0x0F; t.feed(m); XCTAssertEqual(t.rideMode, "Eco")
        m[3] = 0x33; t.feed(m); XCTAssertEqual(t.rideMode, "Eco", "unknown codes don't change the mode")
        XCTAssertEqual(t.validFrames, 5)
    }

    func testG2RejectsNonsense() {
        var t = KukirinTelemetry(model: .g2)
        t.feed(g2Main(volts100: 999, rpm: 50_000, kmh: 200, motor: false))   // 9.99 V, crazy rpm / speed
        XCTAssertNil(t.batteryVolts)
        XCTAssertNil(t.motorRpm)
        XCTAssertNil(t.speedKmh)
        t.feed([0x27]); t.feed([]); t.feed([UInt8](repeating: 0x27, count: 100))
        XCTAssertEqual(t.g2MainFrames, 1)
    }

    func testG4Mode() {
        var t = KukirinTelemetry(model: KukirinProto.model(fromName: "G4-8812"))
        XCTAssertEqual(t.model, .g4)
        t.feed([0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00])
        XCTAssertEqual(t.rideMode, "Sport")
        t.feed([0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x01])    // gate byte not 0: ignored
        XCTAssertEqual(t.rideMode, "Sport")
        t.feed([0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00])
        XCTAssertEqual(t.rideMode, "Race")
        XCTAssertNil(t.speedKmh, "the G4 publishes mode only")
    }

    func testAdapterMatchesAndNeverWrites() {
        let a = KukirinAdapter()
        XCTAssertTrue(Capability.allCases.filter { $0.isWrite }.allSatisfy { !a.canWrite($0) && !a.canWriteExperimentally($0) })
        XCTAssertEqual(a.match(name: "G2-0C1F", serviceIDs: ["0000FFF0-0000-1000-8000-00805F9B34FB"]), .servicesAndName)
        XCTAssertEqual(a.match(name: "Thermometer", serviceIDs: ["FFF0"]), .none, "FFF0 alone is a generic service")
        let (best, _) = AdapterRegistry.best(name: "G2-0C1F", serviceIDs: ["FFF0"])
        XCTAssertEqual(best.id, KukirinAdapter.adapterID)
        XCTAssertEqual(AdapterRegistry.kind(for: best), .unknown, "listen-only path")
        let (u, _) = AdapterRegistry.best(name: "uart", serviceIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E"])
        XCTAssertEqual(u.id, GenericReadOnlyAdapter.adapterID, "plain Nordic UART still isn't claimed")
        let (j, _) = AdapterRegistry.best(name: "365_scooter", serviceIDs: ["6E400001-0000-1000-8000-00805F9B34FB"])
        XCTAssertEqual(j.id, Joyhis365Adapter.adapterID, "the J078 is untouched")
        let (v, _) = AdapterRegistry.best(name: nil, serviceIDs: ["F1F0", "F2F0"])
        XCTAssertEqual(v.id, VolpamAdapter.adapterID, "the Volpam is untouched")
    }
}

final class NBEncryption2Tests: XCTestCase {
    func testKeyDerivation() {
        XCTAssertEqual(NBCrypto.deriveKey(Array(NBVectors.name.utf8), nil), NBVectors.k0)
        XCTAssertEqual(NBCrypto.deriveKey(Array(NBVectors.name.utf8), NBVectors.auth), NBVectors.k1)
        XCTAssertEqual(NBCrypto.deriveKey(NBVectors.password, NBVectors.auth), NBVectors.k2)
    }

    func testAESAgainstFIPS197() {
        // FIPS-197 appendix C.1
        let key: [UInt8] = (0x00...0x0F).map { UInt8($0) }
        let pt: [UInt8] = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        XCTAssertEqual(NBCrypto.aesBlock(key: key, pt), [0x69, 0xC4, 0xE0, 0xD8, 0x6A, 0x7B, 0x04, 0x30, 0xD8, 0xCD, 0xB7, 0x80, 0x70, 0xB4, 0xC5, 0x5A])
    }

    func testNonSNAndSNEncrypt() {
        let pre: [UInt8] = [0x5A, 0xA5, 0x00, 0x3E, 0x21, 0x5B, 0x00]
        XCTAssertEqual(NBCrypto.encryptNonSN(key: NBVectors.k0, plain: pre, staticBlock: NBXDriver.gen2StaticBlock), NBVectors.pre_fw)
        XCTAssertEqual(NBCrypto.encryptNonSN(key: NBVectors.k0, plain: pre, staticBlock: [UInt8](repeating: 0, count: 16)), NBVectors.pre_z)
        XCTAssertEqual(NBVectors.pre_fw.count, 13, "PRE_COMM is 13 bytes on the air (spec)")
        let auth: [UInt8] = [0x5A, 0xA5, 0x0E, 0x3E, 0x21, 0x5D, 0x00] + NBVectors.serial
        let a = NBCrypto.encryptSN(key: NBVectors.k2, plain: auth, counter: 3, auth: NBVectors.auth)
        XCTAssertEqual(a, NBVectors.authFrame)
        XCTAssertEqual(a.count, 27, "AUTH is 27 bytes on the air (spec)")
    }

    func testDecryptAndTamper() {
        let r = NBCrypto.decrypt(key: NBVectors.k2, frame: NBVectors.r_rd, auth: NBVectors.auth, staticBlock: [])
        XCTAssertEqual(r, .ok(plain: [0x5A, 0xA5, 0x02, 0x20, 0x3E, 0x04, 0xB5, 0xC8, 0x00], counter: 9))
        var bad = NBVectors.r_rd; bad[5] ^= 0x01
        XCTAssertEqual(NBCrypto.decrypt(key: NBVectors.k2, frame: bad, auth: NBVectors.auth, staticBlock: []), .badMac)
        var badTag = NBVectors.r_rd; badTag[badTag.count - 4] ^= 0x01
        XCTAssertEqual(NBCrypto.decrypt(key: NBVectors.k2, frame: badTag, auth: NBVectors.auth, staticBlock: []), .badMac)
        var badCs = NBVectors.r_pre; badCs[badCs.count - 4] ^= 0x01
        XCTAssertEqual(NBCrypto.decrypt(key: NBVectors.k0, frame: badCs, auth: [], staticBlock: NBXDriver.gen2StaticBlock), .badChecksum)
        XCTAssertEqual(NBCrypto.decrypt(key: NBVectors.k0, frame: [0x5A, 0xA5, 0x05], auth: [], staticBlock: []), .badLength)
        XCTAssertEqual(NBCrypto.decrypt(key: NBVectors.k0, frame: Array(NBVectors.r_pre.dropLast()), auth: [], staticBlock: []), .badLength)
    }

    func testSessionCounterStartsAtTwo() {
        var s = NBCryptoSession(bleName: NBVectors.name, staticBlock: NBXDriver.gen2StaticBlock)
        XCTAssertFalse(s.snMode)
        XCTAssertEqual(s.encrypt([0x5A, 0xA5, 0x00, 0x3E, 0x21, 0x5B, 0x00]), NBVectors.pre_fw)
        s.startSN(auth: NBVectors.auth)
        s.key2 = NBVectors.auth
        let setPwd: [UInt8] = [0x5A, 0xA5, 0x10, 0x3E, 0x21, 0x5C, 0x00] + NBVectors.password
        XCTAssertEqual(s.encrypt(setPwd), NBVectors.setp)
        XCTAssertEqual(s.counter, 2)
    }
}

final class NBXFrameAndSafetyTests: XCTestCase {
    func testChecksumsMatchTheDocs() {
        // Ninebot ES protocol worked example: 5A A5 01 3D 20 01 3E 02 -> 60 FF
        let example: [UInt8] = [0x01, 0x3D, 0x20, 0x01, 0x3E, 0x02]
        XCTAssertEqual(NBXFrames.checksum(example[...]), 0xFF60)
        XCTAssertEqual(NBXFrames.m365Read(index: 0xB5, length: 2), [0x55, 0xAA, 0x03, 0x20, 0x01, 0xB5, 0x02, 0x24, 0xFF])
        let r = NBXFrames.parseM365(NBXFrames.m365(addr: 0x23, cmd: 0x01, index: 0xB4, payload: [0x50, 0x00]))
        XCTAssertEqual(r, NBXFrames.Reply(source: 0x23, cmd: 0x01, index: 0xB4, data: [0x50, 0x00]))
        var bad = NBXFrames.m365Read(index: 0xB5, length: 2); bad[7] ^= 0x10
        XCTAssertNil(NBXFrames.parseM365(bad))
        let p2 = NBXFrames.p2WithChecksum([0x5A, 0xA5, 0x02, 0x20, 0x3E, 0x04, 0xB4, 0x50, 0x00])
        XCTAssertEqual(NBXFrames.parseP2Unencrypted(p2), NBXFrames.Reply(source: 0x20, cmd: 0x04, index: 0xB4, data: [0x50, 0x00]))
    }

    func testOnlyTheAgreedWritesAreAllowed() {
        func c(_ m: NBXMode, _ cmd: UInt8, _ idx: UInt8, _ d: [UInt8], target: UInt8 = 0x20) -> CommandSafety {
            return NBXSafety.classify(mode: m, cmd: cmd, target: target, index: idx, data: d)
        }
        // reads
        XCTAssertEqual(c(.xiaomiPlain, 0x01, 0xB5, [2]), .verified)
        XCTAssertEqual(c(.ninebotEncrypted, 0x01, 0xB4, [2]), .verified)
        XCTAssertEqual(c(.xiaomiPlain, 0x01, 0x10, [14]), .blocked, "serial isn't read either")
        XCTAssertEqual(c(.xiaomiPlain, 0x01, 0x17, [6]), .blocked, "the PIN is never read")
        // the three M365 settings, only their agreed values
        XCTAssertEqual(c(.xiaomiPlain, 0x03, 0x7B, [2, 0]), .experimental)
        XCTAssertEqual(c(.xiaomiPlain, 0x03, 0x7B, [3, 0]), .blocked)
        XCTAssertEqual(c(.xiaomiPlain, 0x03, 0x7C, [1, 0]), .experimental)
        XCTAssertEqual(c(.xiaomiPlain, 0x03, 0x7D, [2, 0]), .experimental)
        XCTAssertEqual(c(.xiaomiPlain, 0x03, 0x7D, [1, 0]), .blocked)
        // G30: cruise only
        XCTAssertEqual(c(.ninebotEncrypted, 0x03, 0x7C, [1]), .experimental)
        XCTAssertEqual(c(.ninebotPlain, 0x03, 0x7C, [0]), .experimental)
        for idx: UInt8 in [0x7B, 0x7D, 0x75, 0x90, 0x80, 0x81] { XCTAssertEqual(c(.ninebotEncrypted, 0x03, idx, [1]), .blocked, "G30 0x\(String(idx, radix: 16))") }
        // encrypted Xiaomi models: no writes at all
        XCTAssertEqual(c(.xiaomiEncrypted, 0x03, 0x7C, [1, 0]), .blocked)
        // never: firmware, power, lock, PIN, serial, limits, battery, IoT heartbeat
        for cmd: UInt8 in [0x07, 0x08, 0x09, 0x0A, 0x0B, 0x50, 0x55, 0x57, 0x64] {
            for m in [NBXMode.xiaomiPlain, .ninebotPlain, .ninebotEncrypted, .xiaomiEncrypted] { XCTAssertEqual(c(m, cmd, 0x00, []), .blocked) }
        }
        for idx: UInt8 in [0x10, 0x17, 0x3F, 0x70, 0x71, 0x77, 0x78, 0x79, 0x90, 0x93, 0x74, 0x75] {
            for m in [NBXMode.xiaomiPlain, .ninebotPlain, .ninebotEncrypted] {
                XCTAssertEqual(c(m, 0x03, idx, [1, 0]), .blocked)
                XCTAssertEqual(c(m, 0x02, idx, [1, 0]), .blocked)
            }
        }
        XCTAssertEqual(c(.xiaomiPlain, 0x03, 0x7C, [1, 0], target: 0x22), .blocked, "nothing is ever written to the battery")
        XCTAssertEqual(c(.ninebotPlain, 0x5C, 0x00, Array(repeating: 0, count: 16)), .blocked, "no pairing frames on a plain session")
        XCTAssertFalse(NBXSafety.standingStill(nil), "unknown speed = not standing still")
        XCTAssertFalse(NBXSafety.standingStill(4))
        XCTAssertTrue(NBXSafety.standingStill(0))
    }
}

final class NBXDriverTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    var sent: [NBXDriver.Outgoing] = []
    var saved: [UInt8]?

    func driver(_ family: NBXDriver.Family) -> NBXDriver {
        let d = NBXDriver()
        d.send = { [unowned self] o in self.sent.append(o); return true }
        d.makePassword = { NBVectors.password }
        d.savePassword = { [unowned self] pw, _ in self.saved = pw }
        d.start(family: family, bleName: NBVectors.name, deviceKey: "test", now: t0)
        return d
    }

    func m365Reply(_ idx: UInt8, _ v: Int) -> [UInt8] {
        return NBXFrames.m365(addr: 0x23, cmd: 0x01, index: idx, payload: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }

    override func tearDown() {
        // Whatever happened, nothing dangerous ever left.
        for o in sent {
            XCTAssertNotEqual(o.safety, .blocked)
            if o.plain.first == 0x5A, o.plain.count > 5 { XCTAssertFalse(NBXSafety.blockedCommands.contains(o.plain[5])) }
            if o.plain.first == 0x55, o.plain.count > 5 { XCTAssertTrue(o.plain[4] == 0x01 || [0x7B, 0x7C, 0x7D].contains(o.plain[5])) }
        }
        sent = []
        saved = nil
        super.tearDown()
    }

    func testPlainM365ReadsThenWritesKersAndReadsBack() {
        let d = driver(.xiaomi)
        d.tick(now: t0)
        XCTAssertEqual(sent.last?.air, NBXFrames.m365Read(index: 0xB4, length: 2), "probe = a read")
        d.receive(m365Reply(0xB4, 80), now: t0.addingTimeInterval(0.1))
        XCTAssertEqual(d.mode, .xiaomiPlain)
        XCTAssertEqual(d.telemetry.batteryPercent, 80)
        XCTAssertEqual(d.allowedSettings, [.kers, .cruise, .tailLight])
        // before the current value is read, nothing is written
        XCTAssertNotNil(d.write(.kers, value: 2, confirmed: true, now: t0.addingTimeInterval(0.2)))
        d.receive(m365Reply(0x7B, 1), now: t0.addingTimeInterval(0.3))
        // moving: refused (speed 15 km/h = 15000 m/h)
        d.receive(m365Reply(0xB5, 15000), now: t0.addingTimeInterval(0.3))
        XCTAssertEqual(d.telemetry.speedKmh ?? 0, 15, accuracy: 0.01)
        XCTAssertNotNil(d.write(.kers, value: 2, confirmed: true, now: t0.addingTimeInterval(0.4)))
        d.receive(m365Reply(0xB5, 0), now: t0.addingTimeInterval(0.5))
        XCTAssertNotNil(d.write(.kers, value: 2, confirmed: false, now: t0.addingTimeInterval(0.6)), "needs the confirmation")
        XCTAssertNotNil(d.write(.kers, value: 3, confirmed: true, now: t0.addingTimeInterval(0.6)), "never an unknown value")
        let before = sent.count
        XCTAssertNil(d.write(.kers, value: 2, confirmed: true, now: t0.addingTimeInterval(1.0)))
        XCTAssertEqual(sent.count, before + 1)
        XCTAssertEqual(sent.last?.air, NBXFrames.m365Write(index: 0x7B, value: 2))
        XCTAssertEqual(sent.last?.safety, .experimental)
        XCTAssertEqual(sent.last?.origin, .experimental)
        d.tick(now: t0.addingTimeInterval(1.6))
        XCTAssertEqual(sent.last?.air, NBXFrames.m365Read(index: 0x7B, length: 2), "reads it back")
        d.receive(m365Reply(0x7B, 2), now: t0.addingTimeInterval(1.7))
        d.tick(now: t0.addingTimeInterval(1.8))
        XCTAssertTrue(d.lastWriteResult?.contains("Changed") ?? false, d.lastWriteResult ?? "")
    }

    func testReadBackThatDidntChangeIsReportedHonestly() {
        let d = driver(.xiaomi)
        d.tick(now: t0)
        d.receive(m365Reply(0xB4, 50), now: t0)
        d.receive(m365Reply(0xB5, 0), now: t0)
        d.receive(m365Reply(0x7C, 0), now: t0)
        XCTAssertNil(d.write(.cruise, value: 1, confirmed: true, now: t0.addingTimeInterval(1)))
        d.tick(now: t0.addingTimeInterval(1.6))
        d.receive(m365Reply(0x7C, 0), now: t0.addingTimeInterval(1.7))
        d.tick(now: t0.addingTimeInterval(1.9))
        XCTAssertTrue(d.lastWriteResult?.contains("didn't change") ?? false, d.lastWriteResult ?? "")
    }

    func pairNinebot(_ family: NBXDriver.Family) -> NBXDriver {
        let d = driver(family)
        var t = t0
        if family == .xiaomi { d.tick(now: t); t = t.addingTimeInterval(3.1); d.tick(now: t) }   // M365 probe gives up
        d.tick(now: t)
        t = t.addingTimeInterval(3.1)
        d.tick(now: t)
        guard case .needsPairing = d.stage else { XCTFail("expected needsPairing, got \(d.stage)"); return d }
        d.startPairing(now: t)
        d.tick(now: t.addingTimeInterval(0.1))
        XCTAssertEqual(sent.last?.air, NBVectors.pre_fw, "PRE_COMM as the spec builds it")
        XCTAssertEqual(sent.last?.safety, .verified)
        let pre = sent.count
        d.receive(Array(NBVectors.r_pre[0..<20]), now: t.addingTimeInterval(0.2))     // fragmented like BLE
        XCTAssertEqual(sent.count, pre, "waits for the whole frame")
        d.receive(Array(NBVectors.r_pre[20...]), now: t.addingTimeInterval(0.21))
        XCTAssertEqual(sent.last?.air, NBVectors.setp, "SET_PWD, counter 2")
        XCTAssertEqual(sent.last?.safety, .experimental)
        XCTAssertTrue(d.stageText.contains("power button"))
        d.receive(NBVectors.r_set, now: t.addingTimeInterval(1.0))
        XCTAssertEqual(sent.last?.air, NBVectors.authFrame, "AUTH, counter 3")
        d.receive(NBVectors.r_auth, now: t.addingTimeInterval(1.2))
        XCTAssertEqual(saved, NBVectors.password, "the session password goes to the Keychain hook")
        d.tick(now: t.addingTimeInterval(1.5))
        d.receive(NBVectors.r_rd, now: t.addingTimeInterval(1.6))
        return d
    }

    func testNinebotPairingThenEncryptedReadsAndCruiseOnly() {
        let d = pairNinebot(.ninebot)
        XCTAssertEqual(d.mode, .ninebotEncrypted)
        XCTAssertEqual(d.telemetry.speedKmh ?? -1, 20.0, accuracy: 0.01)
        XCTAssertEqual(d.allowedSettings, [.cruise], "G30: cruise only")
        XCTAssertNotNil(d.write(.kers, value: 1, confirmed: true, now: t0.addingTimeInterval(20)))
    }

    func testEncryptedXiaomiIsReadOnly() {
        let d = pairNinebot(.xiaomi)
        XCTAssertEqual(d.mode, .xiaomiEncrypted)
        XCTAssertEqual(d.allowedSettings, [])
        XCTAssertNotNil(d.write(.cruise, value: 1, confirmed: true, now: t0.addingTimeInterval(20)))
    }

    func testPairingTriesTheNextProfileWhenNobodyAnswers() {
        let d = driver(.ninebot)
        d.tick(now: t0)
        d.tick(now: t0.addingTimeInterval(3.1))
        d.startPairing(now: t0.addingTimeInterval(3.2))
        for i in 0..<5 { d.tick(now: t0.addingTimeInterval(3.3 + Double(i) * 2.1)) }
        XCTAssertEqual(sent.last?.air, NBVectors.pre_z, "second profile: zero block")
        XCTAssertEqual(sent.filter { $0.air == NBVectors.pre_fw }.count, 3, "3 tries on the first profile")
    }

    func testEchoIsDetected() {
        let d = driver(.ninebot)
        d.tick(now: t0)
        d.tick(now: t0.addingTimeInterval(3.1))
        d.startPairing(now: t0.addingTimeInterval(3.2))
        d.tick(now: t0.addingTimeInterval(3.3))
        d.receive(NBVectors.pre_fw, now: t0.addingTimeInterval(3.4))
        guard case .needsPairing(let why) = d.stage else { return XCTFail("\(d.stage)") }
        XCTAssertTrue(why.contains("echoed"))
    }

    func testStopSendsNothingMore() {
        let d = driver(.xiaomi)
        d.stop()
        d.tick(now: t0.addingTimeInterval(1))
        XCTAssertTrue(sent.isEmpty)
    }
}

final class NBErrorCodeTests: XCTestCase {
    func testCodesExplainedWithoutRiskyAdvice() {
        XCTAssertNil(FaultCatalog.explainCode(0, xiaomi: false), "0 = no error")
        XCTAssertTrue(FaultCatalog.explainCode(18, xiaomi: false)?.title.contains("hall") ?? false)
        XCTAssertEqual(FaultCatalog.explainCode(40, xiaomi: true)?.severity, .stop)
        XCTAssertTrue(FaultCatalog.explainCode(99, xiaomi: false)?.meaning.contains("No explanation") ?? false, "never invents one")
        let all = FaultCatalog.ninebot + FaultCatalog.xiaomi
        XCTAssertEqual(Set(all.map { $0.id }).count, all.count)
        for f in all {
            let t = (f.meaning + " " + f.whatToDo).lowercased()
            XCTAssertFalse(t.contains("cfw") || t.contains("serial") || t.contains("st-link") || t.contains("custom firmware"), f.id)
        }
    }

    func testCompatAndControllerTypes() {
        XCTAssertEqual(CompatSeed.find("kukirin-g2").adapter, "kukirin")
        XCTAssertEqual(CompatSeed.find("xiaomi-m365-pro").level, .experimental)
        XCTAssertEqual(ControllerType.from(compatAdapter: "xiaomi365"), .ninebot)
        XCTAssertEqual(ControllerType.from(compatAdapter: "kukirin"), .kukirin)
        XCTAssertTrue(ControllerType.kukirin.readOnlyUntilCapture)
        XCTAssertEqual(ControllerType.kukirin.adapterID, KukirinAdapter.adapterID)
        XCTAssertFalse(CompatSeed.entries.contains { $0.level == .full })
        XCTAssertEqual(WhatsNew.version, "5.1.0")
        XCTAssertFalse(BrandStatusList.all.isEmpty)
    }
}
