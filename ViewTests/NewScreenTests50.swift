import XCTest
import SwiftUI
import UIKit
@testable import J078

/// v5.0: every new screen opens without crashing (portrait and landscape), with nothing
/// connected, with a simulated J078, and with mock read-only (Fardriver / Ninebot) data.
final class NewScreenTests50: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("j078", forKey: "chosenModel")
        UserDefaults.standard.set(false, forKey: "startup.enabled")
        UserDefaults.standard.set(true, forKey: Onboarding.doneKey)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    override func tearDown() {
        PacketRecorder.shared.stop()
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func render<V: View>(_ view: V, _ name: String, scheme: ColorScheme = .dark, file: StaticString = #filePath, line: UInt = #line) {
        let host = UIHostingController(rootView: NavigationView { view }.navigationViewStyle(.stack).environmentObject(ThemeStore()).preferredColorScheme(scheme))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view, name, file: file, line: line)
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
    }

    private func simulatedScooter() -> BLEManager {
        let ble = BLEManager()
        ble.startSimulation(.cityRide)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        return ble
    }

    private func tripWithRoute() -> Trip {
        var samples: [TripSample] = []
        for i in 0...90 { samples.append(TripSample(t: Double(i), kmh: Double(10 + (i % 15)), mode: "Drive")) }
        var t = Trip(start: Date().addingTimeInterval(-600), end: Date().addingTimeInterval(-510), scooterName: "My J078", source: "bluetooth", samples: samples)
        t.route = (0..<30).map { Trip.RoutePoint(t: Double($0), lat: 40.7128 + Double($0) * 0.0004, lon: -74.0060 + Double($0) * 0.0003) }
        return t
    }

    func testCaptureTutorialEverywhere() {
        let ble = BLEManager()
        render(CaptureGuideView(ble: ble), "Capture tutorial, nothing connected")
        render(CaptureSendView(ble: ble), "Send a capture, no capture yet")
        render(HelpView(ble: ble), "Help with the capture link")
        render(List { ReadOnlyLiveView(ble: ble) }, "Read-only vehicle screen with the tutorial link")
        render(ConnectView(ble: ble), "Connect with 'already connected' finder")
        XCTAssertEqual(ble.findConnectedToThisPhone(), 0, "no Bluetooth on the simulator: finds nothing, no crash")
        let sim = simulatedScooter()
        render(CaptureGuideView(ble: sim), "Capture tutorial, simulated J078")
        sim.stopSimulation()
    }

    func testPacketLoggerMarksAndSend() {
        let ble = simulatedScooter()
        render(PacketLoggerView(ble: ble), "Packet logger idle")
        PacketRecorder.shared.start(ble: ble)
        PacketRecorder.shared.mark("Lights on")
        PacketRecorder.shared.mark("Lights off")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(PacketRecorder.shared.marks, 2)
        XCTAssertTrue(PacketRecorder.shared.frames.contains { $0.note.contains("MARK #1: pressed Lights on") })
        render(PacketLoggerView(ble: ble), "Packet logger recording with marks")
        render(CaptureSendView(ble: ble), "Send while still recording")
        PacketRecorder.shared.extraPins = ["98765"]
        ble.info("test pin 98765")
        PacketRecorder.shared.stop()
        XCTAssertNotNil(PacketRecorder.shared.savedFile, "saved on the phone as it recorded")
        XCTAssertTrue(PacketRecorder.shared.frames.contains { $0.note.contains("98765") }, "the line was recorded")
        XCTAssertFalse(PacketRecorder.shared.exportText().contains("98765"), "and the typed PIN is masked in the export")
        render(CaptureSendView(ble: ble), "Send a finished capture")
        render(PacketLoggerView(ble: ble), "Packet logger stopped")
        PacketRecorder.shared.extraPins = []
        ble.stopSimulation()
    }

    func testCompatibilityFaultsAndInfo() {
        render(CompatCheckerView(), "Compatibility checker")
        for e in CompatSeed.all { render(CompatDetailView(entry: e), "Compat detail \(e.id)") }
        render(FaultListView(), "Fault list")
        for f in FaultCatalog.fardriver.prefix(3) { render(FaultDetailView(fault: f), "Fault \(f.id)") }
        render(FaultDetailView(fault: FaultCatalog.explain("Unknown 7")), "Unknown fault")
        let ble = BLEManager()
        render(VehicleInfoView(ble: ble), "Vehicle info, disconnected")
        ble.deviceInfo = ["Firmware revision": "1.2.3", "Manufacturer": "Test", "Serial number": "(hidden: 8 characters)"]
        render(VehicleInfoView(ble: ble), "Vehicle info with device info")
        let sim = simulatedScooter()
        render(VehicleInfoView(ble: sim), "Vehicle info, simulated")
        sim.stopSimulation()
    }

    func testBatteryRange() {
        let ble = BLEManager()
        render(BatteryRangeView(ble: ble), "Battery and range, manual")
        var f = FardriverTelemetry()
        f.volts = 72.4; f.amps = 5; f.validFrames = 10
        ble.fardriver = f
        render(BatteryRangeView(ble: ble), "Battery and range from Fardriver volts")
        f.socPercent = 55
        ble.fardriver = f
        render(BatteryRangeView(ble: ble), "Battery and range from Fardriver charge")
        var n = NinebotTelemetry(); n.batteryPercent = 40
        ble.fardriver = nil; ble.ninebot = n
        render(BatteryRangeView(ble: ble), "Battery and range from Ninebot")
        let sim = simulatedScooter()
        render(BatteryRangeView(ble: sim), "Battery and range, simulated J078")
        sim.stopSimulation()
    }

    func testBackupWhatsNewLegalAndLog() {
        _ = GarageStore.shared
        render(BackupView(), "Backup and restore")
        UserDefaults.standard.set("do-not-copy", forKey: "volpam.password.test")
        let b = BackupBundle.make(from: UserDefaults.standard.dictionaryRepresentation(), trips: nil, appVersion: AppInfo.version)
        XCTAssertNil(b.settings["volpam.password.test"])
        XCTAssertFalse(b.settings.keys.contains { $0.lowercased().contains("password") || $0.hasPrefix("premium") })
        XCTAssertNotNil(b.settings["garage.v1"], "the Garage is in the backup")
        UserDefaults.standard.removeObject(forKey: "volpam.password.test")
        render(WhatsNewView(onDone: {}), "What's new")
        render(WhatsNewView(), "What's new from More")
        render(LegalDocView(doc: .privacy), "Privacy policy draft")
        render(LegalDocView(doc: .terms), "Terms draft")
        render(LegalDocView(doc: .licenses), "Open-source credits")
        AppJournal.shared.note("screen test")
        render(AppLogView(), "App log")
    }

    func testTripsSearchRouteAndAppearance() {
        let ble = BLEManager()
        let trips = TripManager()
        let saved = trips.trips
        trips.trips = [tripWithRoute()] + saved
        render(TripsView(trips: trips, ble: ble), "Trips with search and filters")
        render(TripDetailView(trip: tripWithRoute(), mph: true, trips: trips), "Ride with a GPS route map")
        var noRoute = tripWithRoute(); noRoute.route = nil
        render(TripDetailView(trip: noRoute, mph: false, trips: trips), "Ride without a route")
        render(Form { RouteSettingsSection() }, "GPS route setting")
        render(AppSettingsView(), "App settings with appearance and routes")
        render(AppSettingsView(), "App settings in light mode", scheme: .light)
        render(MoreView(ble: ble, chooseScooter: {}), "More with the 5.0 sections")
        render(MoreView(ble: ble, chooseScooter: {}), "More in light mode", scheme: .light)
        trips.trips = saved
    }

    func testDashboardStillOpensWithVoiceOverLabels() {
        let ble = simulatedScooter()
        render(DashboardView(ble: ble, trips: TripManager(), openConnect: {}), "Dashboard (VoiceOver value)")
        ble.stopSimulation()
    }

    func testStripeReturnLinkOnlyWorksInTestMode() {
        XCTAssertTrue(Billing.testMode, "5.0 is still TEST MODE only")
        XCTAssertEqual(ProReturnLink.plan(from: URL(string: "hackthescoot://pro-test?plan=monthly")!), "monthly")
    }
}
