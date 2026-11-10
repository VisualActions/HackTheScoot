import XCTest

/// v5.0 logic: capture tutorial, password masking, ride search, GPS route math,
/// battery / range estimates, fault explanations, what's new, the Stripe test return
/// link, backup / restore and the crash-safe journal.
final class CaptureTutorialTests: XCTestCase {

    func testQuickRouteCoversTheWholeFlowInOrder() {
        let s = CaptureGuide.quickSteps
        XCTAssertEqual(s.map { $0.id }, Array(1...s.count), "steps are numbered in order")
        let all = s.map { $0.title + " " + $0.detail }.joined(separator: " ").lowercased()
        for word in ["packet logger", "connect", "official app", "one thing at a time", "5 seconds", "stop", "share", "github"] {
            XCTAssertTrue(all.contains(word), "quick route mentions \(word)")
        }
        // start the logger comes before connecting, and pressing comes before stopping
        let titles = s.map { $0.title.lowercased() }
        XCTAssertLessThan(titles.firstIndex { $0.contains("packet logger") }!, titles.firstIndex { $0.contains("connect") }!)
        XCTAssertLessThan(titles.firstIndex { $0.contains("press") }!, titles.firstIndex { $0.contains("stop") }!)
    }

    func testAdvancedRouteMatchesApplesSteps() {
        let all = CaptureGuide.sysdiagnoseSteps.map { $0.title + " " + $0.detail }.joined(separator: " ")
        XCTAssertTrue(all.contains("developer.apple.com/bug-reporting/profiles-and-logs/?name=bluetooth"))
        XCTAssertTrue(all.contains("250 milliseconds"), "Apple's press length")
        XCTAssertTrue(all.contains("Analytics Data"))
        XCTAssertTrue(all.contains("stacks-"), "a stacks-only result means it didn't start")
        XCTAssertTrue(all.contains("bluetoothd-hci-latest.pklg"))
        XCTAssertTrue(all.contains("Remove"), "says how to remove the profile")
    }

    func testFunctionsToPressIncludeTheBasics() {
        let f = CaptureGuide.functionsToPress.joined(separator: " ").lowercased()
        for w in ["lights on", "lights off", "mode", "speed limit", "park"] { XCTAssertTrue(f.contains(w), w) }
        XCTAssertGreaterThanOrEqual(CaptureGuide.pauseSeconds, 3)
    }

    func testIssueLinkUsesTheTemplateAndPrefills() {
        let u = CaptureGuide.issueURL(brand: "Hiboy", model: "S2 Pro", controller: "Zydtech", vehicleType: "E-scooter")!.absoluteString
        XCTAssertTrue(u.hasPrefix("https://github.com/VisualActions/HackTheScoot/issues/new?"))
        XCTAssertTrue(u.contains("template=new-vehicle-capture.yml"))
        XCTAssertTrue(u.contains("title=Capture:%20Hiboy%20S2%20Pro"))
        XCTAssertTrue(u.contains("brand=Hiboy"))
        XCTAssertNotNil(CaptureGuide.issueURL(), "works with nothing filled in")
    }

    func testPrivacyNoteWarnsAboutPasswords() {
        XCTAssertTrue(CaptureGuide.privacyNote.lowercased().contains("password"))
        XCTAssertTrue(CaptureGuide.privacyNote.lowercased().contains("publicly"))
    }
}

final class CaptureSanitizerTests: XCTestCase {
    func testMasksATPWDAsText() {
        XCTAssertEqual(CaptureSanitizer.mask("sent AT+PWD[123456] ok"), "sent AT+PWD[******] ok")
        XCTAssertTrue(CaptureSanitizer.looksUnmasked("AT+PWD[123456]"))
        XCTAssertFalse(CaptureSanitizer.looksUnmasked(CaptureSanitizer.mask("AT+PWD[123456]")))
    }

    func testMasksATPWDInHex() {
        let line = "12:00:00.000 TX F1F2 air: 41 54 2B 50 57 44 5B 31 32 33 34 35 36 5D 0D 0A | note"
        let out = CaptureSanitizer.mask(line)
        XCTAssertFalse(out.contains("31 32 33 34 35 36"))
        XCTAssertTrue(out.contains("41 54 2B 50 57 44 5B ** ** ** ** ** ** 5D 0D 0A | note"))
    }

    func testMasksATypedPinAsTextAndAsciiHex() {
        let out = CaptureSanitizer.mask("pin 4321 hex 34 33 32 31 end", pins: ["4321"])
        XCTAssertEqual(out, "pin **** hex ** ** ** ** end")
        XCTAssertEqual(CaptureSanitizer.mask("12", pins: ["12"]), "12", "too-short PINs are ignored (would mask everything)")
    }

    func testLeavesNormalFramesAlone() {
        let line = "12:00:00.000 RX 6E400003 air: DB EB FA DB 01 02 | status"
        XCTAssertEqual(CaptureSanitizer.mask(line), line)
    }
}

final class TripFilterTests: XCTestCase {
    let v1 = UUID(), v2 = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func trips() -> [Trip] {
        var a = Trip(start: now.addingTimeInterval(-3600), end: now, scooterName: "My J078", source: "bluetooth",
                     samples: [TripSample(t: 0, kmh: 10, mode: "Sport")])
        a.scooterID = v1
        a.route = [Trip.RoutePoint(t: 0, lat: 40, lon: -74), Trip.RoutePoint(t: 5, lat: 40, lon: -74.001)]
        var b = Trip(start: now.addingTimeInterval(-10 * 86400), end: nil, scooterName: "Dad's Volpam", source: "bluetooth",
                     samples: [TripSample(t: 0, kmh: 8, mode: "Eco")])
        b.scooterID = v2
        let c = Trip(start: now.addingTimeInterval(-40 * 86400), end: nil, scooterName: "Simulator", source: "simulation", samples: [])
        return [c, a, b]
    }

    func testNoFilterKeepsEverythingNewestFirst() {
        let r = TripFilter().apply(trips(), now: now)
        XCTAssertEqual(r.map { $0.scooterName }, ["My J078", "Dad's Volpam", "Simulator"])
        XCTAssertFalse(TripFilter().isActive)
    }

    func testSearchVehiclePeriodSourceAndRoute() {
        var f = TripFilter(); f.query = "volpam"
        XCTAssertEqual(f.apply(trips(), now: now).map { $0.scooterName }, ["Dad's Volpam"])
        f = TripFilter(); f.query = "SPORT"
        XCTAssertEqual(f.apply(trips(), now: now).count, 1, "mode names are searchable")
        f = TripFilter(); f.vehicleID = v1
        XCTAssertEqual(f.apply(trips(), now: now).map { $0.scooterName }, ["My J078"])
        f = TripFilter(); f.period = .week
        XCTAssertEqual(f.apply(trips(), now: now).count, 1)
        f = TripFilter(); f.period = .month
        XCTAssertEqual(f.apply(trips(), now: now).count, 2)
        f = TripFilter(); f.source = .simulated
        XCTAssertEqual(f.apply(trips(), now: now).map { $0.scooterName }, ["Simulator"])
        f = TripFilter(); f.source = .real
        XCTAssertEqual(f.apply(trips(), now: now).count, 2)
        f = TripFilter(); f.withRouteOnly = true
        XCTAssertEqual(f.apply(trips(), now: now).map { $0.scooterName }, ["My J078"])
        XCTAssertTrue(f.isActive)
    }
}

final class RouteMathTests: XCTestCase {
    func testDistanceAndGlitchesAndSpacing() {
        let a = Trip.RoutePoint(t: 0, lat: 40, lon: -74)
        let b = Trip.RoutePoint(t: 1, lat: 40, lon: -74.01)
        XCTAssertEqual(RouteMath.km(a, b), 0.852, accuracy: 0.01)
        let c = Trip.RoutePoint(t: 2, lat: 41, lon: -74.01)   // 111 km jump = GPS glitch
        let small = Trip.RoutePoint(t: 1, lat: 40, lon: -74.001)
        XCTAssertEqual(RouteMath.lengthKm([a, small, c]), RouteMath.km(a, small), accuracy: 0.0001)
        XCTAssertEqual(RouteMath.lengthKm([a]), 0)
        XCTAssertFalse(RouteMath.isValid(Trip.RoutePoint(t: 0, lat: 0, lon: 0)), "0,0 is a no-fix point")
        XCTAssertFalse(RouteMath.isValid(Trip.RoutePoint(t: 0, lat: .nan, lon: 1)))
        XCTAssertTrue(RouteMath.shouldKeep(a, after: nil))
        XCTAssertFalse(RouteMath.shouldKeep(Trip.RoutePoint(t: 1, lat: 40.000001, lon: -74), after: a), "under 8 m is skipped")
        XCTAssertTrue(RouteMath.shouldKeep(small, after: a))
        let box = RouteMath.bounds([a, b])!
        XCTAssertEqual(box.minLon, -74.01); XCTAssertEqual(box.maxLon, -74)
        XCTAssertNil(RouteMath.bounds([]))
    }
}

final class EstimateTests: XCTestCase {
    func testBatteryFromVoltage() {
        XCTAssertEqual(BatteryEstimate.percent(packVolts: 42.0, nominal: 36), 100)
        XCTAssertEqual(BatteryEstimate.percent(packVolts: 30.0, nominal: 36), 0)
        XCTAssertEqual(BatteryEstimate.percent(packVolts: 37.0, nominal: 36), 40)
        XCTAssertEqual(BatteryEstimate.percent(packVolts: 54.6, nominal: 52), 70)
        XCTAssertEqual(BatteryEstimate.percent(packVolts: 90, nominal: 72), 100)
        XCTAssertNil(BatteryEstimate.percent(packVolts: 50, nominal: 50), "unknown pack")
        XCTAssertNil(BatteryEstimate.percent(packVolts: .nan, nominal: 48))
        var last = -1
        for tenth in 300...420 {
            let p = BatteryEstimate.percent(packVolts: Double(tenth) / 10.0 * 13, nominal: 48)!
            XCTAssertGreaterThanOrEqual(p, last, "never goes down as volts go up")
            last = p
        }
    }

    func testRange() {
        XCTAssertEqual(RangeEstimate.kmLeft(fullRangeKm: 25, batteryPercent: 80, mode: "Drive"), 20, accuracy: 0.001)
        XCTAssertEqual(RangeEstimate.kmLeft(fullRangeKm: 25, batteryPercent: 80, mode: "Eco"), 23, accuracy: 0.001)
        XCTAssertEqual(RangeEstimate.kmLeft(fullRangeKm: 25, batteryPercent: 80, mode: "Sport"), 16, accuracy: 0.001)
        XCTAssertEqual(RangeEstimate.kmLeft(fullRangeKm: 25, batteryPercent: 150), 25, accuracy: 0.001)
        XCTAssertEqual(RangeEstimate.kmLeft(fullRangeKm: .nan, batteryPercent: 50), 0)
        XCTAssertEqual(RangeEstimate.kmLeft(fullRangeKm: 25, batteryPercent: -5), 0)
        XCTAssertNil(RangeEstimate.kmPerPercent(distanceKm: 5, percentUsed: 1))
        XCTAssertEqual(RangeEstimate.kmPerPercent(distanceKm: 5, percentUsed: 20) ?? 0, 0.25, accuracy: 0.0001)
    }
}

final class FaultAndMiscTests: XCTestCase {
    func testEveryFardriverFaultHasAnExplanation() {
        for n in FardriverFaults.names4 + FardriverFaults.names5 {
            XCTAssertTrue(FaultCatalog.fardriver.contains { $0.id == n }, "explained: \(n)")
        }
        XCTAssertEqual(FaultCatalog.explain("MOSFET high-side error").severity, .stop)
        let unknown = FaultCatalog.explain("Error 42")
        XCTAssertEqual(unknown.title, "Error 42")
        XCTAssertTrue(unknown.meaning.contains("No explanation"), "never invents a meaning")
    }

    func testWhatsNewShowsOncePerVersion() {
        XCTAssertTrue(WhatsNew.shouldShow(seen: nil, current: "5.0.0"))
        XCTAssertTrue(WhatsNew.shouldShow(seen: "4.2.0", current: "5.0.0"))
        XCTAssertFalse(WhatsNew.shouldShow(seen: "5.0.0", current: "5.0.0"))
        XCTAssertFalse(WhatsNew.shouldShow(seen: "5.1.0", current: "5.0.0"))
        XCTAssertTrue(WhatsNew.shouldShow(seen: "4.10.0", current: "5.0.0"))
        XCTAssertFalse(WhatsNew.items.isEmpty)
    }

    func testStripeTestReturnLink() {
        XCTAssertEqual(ProReturnLink.plan(from: URL(string: "hackthescoot://pro-test?plan=yearly")!), "yearly")
        XCTAssertEqual(ProReturnLink.plan(from: URL(string: "hackthescoot://pro-test")!), "test")
        XCTAssertEqual(ProReturnLink.plan(from: URL(string: "hackthescoot://pro-test?plan=pro_monthly")!), "monthly", "the Stripe link's own plan key")
        XCTAssertEqual(ProReturnLink.plan(from: URL(string: "hackthescoot://pro-test?plan=lifetime")!), "test")
        XCTAssertNil(ProReturnLink.plan(from: URL(string: "https://example.com/pro-test?plan=yearly")!))
        XCTAssertNil(ProReturnLink.plan(from: URL(string: "hackthescoot://something-else")!))
        XCTAssertTrue(ProReturnLink.note.contains("TEST"))
    }
}

final class BackupTests: XCTestCase {
    func testOnlyTheAppsOwnSafeSettingsAreCopied() {
        let defaults: [String: Any] = [
            "garage.v1": Data([1, 2, 3]), "keepAwake": true, "gaugeMax": 30.0, "range.full.ABC": 25.0, "tripAutoRecord": false,
            "volpam.password": "secret", "park.pin": "1234", "premium.testUnlockTier": 1, "stripeKey": "x",
            "AppleLanguages": ["en"], "NSSomething": 3, "someOtherApp.value": 9,
        ]
        let b = BackupBundle.make(from: defaults, trips: nil, appVersion: "5.0.0 (8)")
        XCTAssertEqual(Set(b.settings.keys), ["garage.v1", "keepAwake", "gaugeMax", "range.full.ABC", "tripAutoRecord"])
        XCTAssertEqual(b.settings["keepAwake"], .bool(true))
        XCTAssertEqual(b.settings["gaugeMax"], .double(30))
        XCTAssertEqual(b.settings["garage.v1"], .data(Data([1, 2, 3])))
        for blocked in ["volpam.password", "park.pin", "premium.testUnlockTier", "stripeKey"] { XCTAssertFalse(BackupBundle.isAllowed(blocked), blocked) }
    }

    func testRoundTripAndValidation() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let trip = Trip(start: start, end: start.addingTimeInterval(60), scooterName: "My J078", source: "bluetooth",
                        samples: [TripSample(t: 0, kmh: 12, mode: "Drive")])
        var b = BackupBundle.make(from: ["keepAwake": false, "maint.X": Data([9]), "gaugeMax": 25, "chosenModel": "j078"],
                                  trips: [trip], appVersion: "5.0.0", now: start)
        XCTAssertEqual(b.settings["gaugeMax"], .int(25))
        guard let d = b.encoded() else { return XCTFail("encode") }
        guard case .success(let back) = BackupBundle.decode(d) else { return XCTFail("decode") }
        XCTAssertEqual(back, b)

        XCTAssertEqual(BackupBundle.decode(Data("nope".utf8)), .failure(.notJSON))
        XCTAssertEqual(BackupBundle.decode(Data(#"{"format":"other","version":1}"#.utf8)), .failure(.wrongFormat))
        XCTAssertEqual(BackupBundle.decode(Data(#"{"format":"hackthescoot-backup","version":9}"#.utf8)), .failure(.newerVersion(9)))

        // a hand-edited file can't smuggle in a password
        b.settings["volpam.password"] = .string("x")
        guard case .success(let cleaned) = BackupBundle.decode(b.encoded()!) else { return XCTFail("decode 2") }
        XCTAssertNil(cleaned.settings["volpam.password"])
    }

    func testTripsAreMergedNeverReplaced() {
        let s = Date(timeIntervalSince1970: 1_800_000_000)
        let a = Trip(start: s, end: nil, scooterName: "A", source: "bluetooth")
        let b = Trip(start: s.addingTimeInterval(100), end: nil, scooterName: "B", source: "bluetooth")
        let merged = BackupBundle.merge(existing: [a], incoming: [a, b])
        XCTAssertEqual(merged.map { $0.scooterName }, ["B", "A"])
    }
}

final class JournalTests: XCTestCase {
    func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testCaptureIsWrittenAsItRecordsAndMasked() {
        let j = AppJournal(directory: tempDir())
        j.beginCapture(header: "HackTheScoot test capture")
        j.appendCapture("12:00:00.000 RX FFE1 air: AA 81 D5")
        j.appendCapture("12:00:01.000 TX F1F2 note AT+PWD[999999]")
        guard let f = j.finishCapture(footer: "stopped", stamp: 42) else { return XCTFail("no file") }
        let text = (try? String(contentsOf: f, encoding: .utf8)) ?? ""
        XCTAssertTrue(text.contains("AA 81 D5"))
        XCTAssertTrue(text.contains("AT+PWD[******]"))
        XCTAssertFalse(text.contains("999999"))
        XCTAssertTrue(text.hasSuffix("stopped\n"))
        XCTAssertEqual(f.lastPathComponent, "capture-42.txt")
        XCTAssertNil(j.unfinishedCapture)
    }

    func testAnUnfinishedCaptureSurvivesARelaunch() {
        let dir = tempDir()
        let j = AppJournal(directory: dir)
        j.beginCapture(header: "header")
        j.appendCapture("line one")
        _ = j.journalText()            // flush the queue
        let relaunched = AppJournal(directory: dir)
        XCTAssertNotNil(relaunched.unfinishedCapture, "the next launch finds it")
        let r = relaunched.recoverUnfinished()
        XCTAssertNotNil(r)
        XCTAssertNil(relaunched.unfinishedCapture)
    }

    func testJournalNotesAreMaskedAndBounded() {
        let j = AppJournal(directory: tempDir())
        j.note("hello AT+PWD[123456]")
        let t = j.journalText()
        XCTAssertTrue(t.contains("hello AT+PWD[******]"))
        for i in 0..<3000 { j.note(String(repeating: "x", count: 100) + " \(i)") }
        _ = j.journalText()
        let size = (try? FileManager.default.attributesOfItem(atPath: j.journalURL.path)[.size] as? Int) ?? 0
        XCTAssertLessThanOrEqual(size, AppJournal.maxJournalBytes + 1024)
    }
}
