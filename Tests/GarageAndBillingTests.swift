import XCTest

final class GarageTests: XCTestCase {

    func testSeedHasTheJ078AndDadsVolpam() {
        let g = GarageState.seeded()
        XCTAssertEqual(g.scooters.count, 2)
        XCTAssertEqual(g.scooters[0].compatID, "joyhis-j078")
        XCTAssertEqual(g.scooters[0].kind, .j078)
        XCTAssertEqual(g.scooters[1].compatID, "volpam-dad")
        XCTAssertEqual(g.scooters[1].kind, .volpam)
        XCTAssertEqual(g.active?.id, g.scooters[0].id)
        XCTAssertEqual(g.scooters[0].compat.level, .partial)
        XCTAssertEqual(g.scooters[1].compat.level, .partial)
    }

    func testCompatSeedMatchesTheResearchDatabase() {
        XCTAssertEqual(CompatSeed.entries.count, 10)   // 4.2 added the Fardriver ND entry; 5.1 added M365 Pro and KuKirin G2
        XCTAssertEqual(CompatSeed.find("hiboy-s2-pro").level, .experimental)
        XCTAssertEqual(CompatSeed.find("dualtron-ey4").level, .unsupported)
        XCTAssertEqual(CompatSeed.find("nope").id, "other")
        XCTAssertFalse(CompatSeed.entries.contains { $0.level == .full }, "nothing is full support yet")
        XCTAssertEqual(CompatSeed.bestMatch(for: .j078).id, "joyhis-j078")
        XCTAssertEqual(CompatSeed.bestMatch(for: .volpam).id, "volpam-dad")
        XCTAssertEqual(CompatSeed.bestMatch(for: .unknown).id, "other")
    }

    func testSwitchAddRemove() {
        var g = GarageState.seeded()
        let v = g.scooters[1].id
        g.setActive(v)
        XCTAssertEqual(g.active?.id, v)
        g.setActive(UUID())                       // unknown id is ignored
        XCTAssertEqual(g.active?.id, v)
        g.add(GarageScooter(name: "Hiboy", compatID: "hiboy-s2-pro"))
        XCTAssertEqual(g.scooters.count, 3)
        XCTAssertEqual(g.active?.name, "Hiboy")
        g.remove(g.active!.id)
        XCTAssertEqual(g.scooters.count, 2)
        XCTAssertNotNil(g.active, "removing the active one falls back to another scooter")
    }

    func testConnectingLinksTheRightScooterAndNeverMixes() {
        var g = GarageState.seeded()
        let j = g.scooters[0].id, v = g.scooters[1].id
        let jBLE = UUID(), vBLE = UUID(), other = UUID()

        // J078 connects while the J078 is active: links to it
        XCTAssertEqual(g.linkConnected(bleID: jBLE, name: "365_scooter", kind: .j078), j)
        // the Volpam connects: links to the Volpam entry and makes it active
        XCTAssertEqual(g.linkConnected(bleID: vBLE, name: "VOLPAM", kind: .volpam), v)
        XCTAssertEqual(g.active?.id, v)
        // the J078 again: found by its Bluetooth id
        XCTAssertEqual(g.linkConnected(bleID: jBLE, name: "365_scooter", kind: .j078), j)
        XCTAssertEqual(g.active?.id, j)
        // an unknown device never gets linked to a garage scooter
        XCTAssertNil(g.linkConnected(bleID: other, name: "Mystery", kind: .unknown))
        XCTAssertEqual(g.active?.id, j)
        // a second J078 with no free J078 entry: not guessed onto the first one
        XCTAssertNil(g.linkConnected(bleID: other, name: "365_scooter", kind: .j078))
        XCTAssertEqual(g.scooters.first { $0.id == j }?.bleID, jBLE)
    }

    func testStatsStayOnTheirScooterAndTopSpeedOnlyGoesUp() {
        var g = GarageState.seeded()
        let j = g.scooters[0].id, v = g.scooters[1].id
        g.recordStats(LastStats(at: Date(), topKmh: 30, mode: "Sport"), for: j)
        g.recordStats(LastStats(at: Date(), topKmh: 20, mode: "Eco"), for: j)
        XCTAssertEqual(g.scooters.first { $0.id == j }?.lastStats?.topKmh, 30)
        XCTAssertEqual(g.scooters.first { $0.id == j }?.lastStats?.mode, "Eco")
        XCTAssertNil(g.scooters.first { $0.id == v }?.lastStats)
        g.recordStats(LastStats(at: Date(), topKmh: .nan), for: v)
        XCTAssertEqual(g.scooters.first { $0.id == v }?.lastStats?.topKmh, 0)
    }

    func testTripsPerScooter() {
        var g = GarageState.seeded()
        let j = g.scooters[0].id, v = g.scooters[1].id
        _ = g.linkConnected(bleID: UUID(), name: "365_scooter", kind: .j078)
        var t1 = Trip(start: Date(), end: nil, scooterName: "365_scooter", source: "bluetooth"); t1.scooterID = j
        var t2 = Trip(start: Date(), end: nil, scooterName: "VOLPAM", source: "bluetooth"); t2.scooterID = v
        let old = Trip(start: Date(), end: nil, scooterName: "365_scooter", source: "bluetooth")   // pre-4.1, no id
        XCTAssertEqual(g.trips([t1, t2, old], for: j).count, 2)
        XCTAssertEqual(g.trips([t1, t2, old], for: v).count, 1)
    }

    func testOldTripsAndDamagedGarageStillDecode() throws {
        let oldTrip = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","start":0,"scooterName":"365_scooter","source":"bluetooth","samples":[],"interruptions":0}"#
        let t = try JSONDecoder().decode(Trip.self, from: Data(oldTrip.utf8))
        XCTAssertNil(t.scooterID)
        let bad = #"{"scooters":[{"name":123,"compatID":"joyhis-j078"}],"activeID":null}"#
        let g = try JSONDecoder().decode(GarageState.self, from: Data(bad.utf8))
        XCTAssertEqual(g.scooters.count, 1)
        XCTAssertEqual(g.scooters[0].name, "Scooter")
        XCTAssertNotNil(g.active)
        let round = try JSONDecoder().decode(GarageState.self, from: JSONEncoder().encode(GarageState.seeded()))
        XCTAssertEqual(round.scooters.map { $0.name }, ["My J078", "Dad's Volpam"])
    }
}

final class BillingTests: XCTestCase {

    func testTiersAndPricesMatchTheSpec() {
        XCTAssertEqual(Tier.allCases.map { $0.name }, ["Free", "Pro", "Developer"])
        XCTAssertEqual(Billing.proMonthlyPrice, "$3.99")
        XCTAssertEqual(Billing.proYearlyPrice, "$29.99")
        XCTAssertEqual(Billing.yearlySavingPercent, 37)
        XCTAssertTrue(Billing.testMode, "4.1 must stay in test mode")
    }

    func testProductsUnlockPro() {
        XCTAssertEqual(Billing.tier(forProduct: Billing.proMonthlyID), .pro)
        XCTAssertEqual(Billing.tier(forProduct: Billing.proYearlyID), .pro)
        XCTAssertEqual(Billing.tier(forProduct: "something.else"), .free)
        XCTAssertEqual(Billing.effectiveTier(purchased: [], testUnlock: .free), .free)
        XCTAssertEqual(Billing.effectiveTier(purchased: [Billing.proYearlyID], testUnlock: .free), .pro)
        XCTAssertEqual(Billing.effectiveTier(purchased: [], testUnlock: .developer), .developer)
        XCTAssertEqual(Billing.effectiveTier(purchased: [Billing.proMonthlyID], testUnlock: .free), .pro)
    }

    func testFeatureGates() {
        XCTAssertFalse(Billing.allows(.tripAnalytics, tier: .free))
        XCTAssertTrue(Billing.allows(.tripAnalytics, tier: .pro))
        XCTAssertFalse(Billing.allows(.protocolWorkspace, tier: .pro))
        XCTAssertTrue(Billing.allows(.protocolWorkspace, tier: .developer))
        for f in ProFeature.allCases { XCTAssertTrue(Billing.allows(f, tier: .developer)) }
    }

    /// The hard rules: no scooter capability is ever sold, and there is no speed unlock.
    func testNothingSafetyOrControlIsPaywalled() {
        for c in Capability.allCases { XCTAssertEqual(Billing.requiredTier(for: c), .free, c.label) }
        for f in ProFeature.allCases {
            let words = (f.rawValue + " " + f.title + " " + f.detail).lowercased()
            for banned in ["speed limit", "unlock speed", "speed unlock", "top speed", "fault", "safety", "park", "light", "control"] {
                XCTAssertFalse(words.contains(banned), "\(f) mentions \(banned)")
            }
        }
        XCTAssertTrue(Billing.alwaysFree.contains { $0.contains("above-stock") })
        XCTAssertTrue(Billing.alwaysFree.contains { $0.lowercased().contains("fault") })
    }

    func testProThemePackIsNewAndFreePresetsStayFree() {
        let free = Set(DashTheme.presets.map { $0.name })
        let pro = DashTheme.proPresets.map { $0.name }
        XCTAssertEqual(pro.count, 6)
        XCTAssertTrue(Set(pro).isDisjoint(with: free))
        for p in DashTheme.proPresets {
            let back = DashTheme.importJSON(p.exportJSON()!)
            XCTAssertEqual(try? back.get(), p, "\(p.name) survives JSON")
        }
    }
}

final class ProToolsTests: XCTestCase {

    private func trip() -> Trip {
        var t = Trip(start: Date(timeIntervalSince1970: 1_800_000_000), end: nil, scooterName: "365, scooter", source: "bluetooth")
        t.samples = (0..<20).map { TripSample(t: Double($0), kmh: Double($0 % 10) * 3, mode: $0 < 10 ? "Eco" : "Sport") }
        return t
    }

    func testCSV() {
        let csv = TripExport.csv(trip(), mph: false)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 21)
        XCTAssertEqual(lines[0], "time,seconds,speed_kmh,mode,scooter,source")
        XCTAssertTrue(lines[1].hasSuffix(",0.00,0.00,Eco,365  scooter,bluetooth"), String(lines[1]))
    }

    func testGPXOnlyWithARoute() {
        var t = trip()
        XCTAssertNil(TripExport.gpx(t))
        t.route = [Trip.RoutePoint(t: 0, lat: 33.5, lon: -84.1), Trip.RoutePoint(t: 1, lat: .nan, lon: 0)]
        let g = TripExport.gpx(t)!
        XCTAssertTrue(g.contains("<trkpt lat=\"33.500000\" lon=\"-84.100000\">"))
        XCTAssertEqual(g.components(separatedBy: "<trkpt").count - 1, 1, "bad points are skipped")
    }

    func testAnalytics() {
        let a = RideAnalytics.compute([trip(), trip()])
        XCTAssertEqual(a.rides, 2)
        XCTAssertEqual(a.topKmh, 27, accuracy: 0.001)
        XCTAssertGreaterThan(a.distanceKm, 0)
        XCTAssertFalse(a.histogram.isEmpty)
        XCTAssertTrue(a.avgMovingKmh.isFinite)
        XCTAssertEqual(RideAnalytics.compute([]).rides, 0)
        XCTAssertEqual(RideAnalytics.compute([]).avgMovingKmh, 0)
    }

    func testLogAnalysisAndFrameDiff() {
        let t0 = Date()
        let frames = [
            FrameRecord(time: t0, direction: "RX", channel: "6E400003", bytes: [0xDB, 0xEB, 0xBA, 0x2A, 0x1F]),
            FrameRecord(time: t0.addingTimeInterval(0.5), direction: "RX", channel: "6E400003", bytes: [0xDB, 0xEB, 0xBA, 0x2A, 0x1F]),
            FrameRecord(time: t0.addingTimeInterval(1.0), direction: "TX", channel: "6E400002", bytes: [0xBD, 0xBE, 0xAB, 0x00, 0x01]),
            FrameRecord(time: t0.addingTimeInterval(3.0), direction: "XX", channel: "6E400002", bytes: [0x00])
        ]
        let a = LogAnalysis.analyze(frames)
        XCTAssertEqual(a.total, 4)
        XCTAssertEqual(a.blocked, 1)
        XCTAssertEqual(a.span, 3, accuracy: 0.001)
        XCTAssertEqual(a.commands.first?.key, "RX DB EB BA 2A")
        XCTAssertEqual(a.commands.first?.count, 2)
        XCTAssertEqual(LogAnalysis.analyze([]).total, 0)

        XCTAssertEqual(FrameDiff.parseHex("DB eb,0xBA:2a"), [0xDB, 0xEB, 0xBA, 0x2A])
        XCTAssertNil(FrameDiff.parseHex("DBE"))
        XCTAssertNil(FrameDiff.parseHex("ZZ"))
        let d = FrameDiff.compare([1, 2, 3], [1, 9])
        XCTAssertEqual(d.count, 3)
        XCTAssertEqual(d.filter { $0.changed }.map { $0.index }, [1, 2])

        let json = DevExport.json(frames, device: "sim")!
        let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual((obj?["frames"] as? [Any])?.count, 4)
    }
}
