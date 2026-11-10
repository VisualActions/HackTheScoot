import XCTest
import SwiftUI
import UIKit
@testable import J078

/// v4.2: every new screen opens without crashing, with a simulated J078, with nothing
/// connected, and (for the read-only adapters) with mock Fardriver / Ninebot data.
final class NewScreenTests42: XCTestCase {

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

    private func render<V: View>(_ view: V, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let host = UIHostingController(rootView: NavigationView { view }.navigationViewStyle(.stack).environmentObject(ThemeStore()).preferredColorScheme(.dark))
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

    private func simulatedScooter(_ scenario: ScooterSimulator.Scenario = .cityRide) -> BLEManager {
        let ble = BLEManager()
        ble.startSimulation(scenario)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        return ble
    }

    private func sampleTrip() -> Trip {
        var samples: [TripSample] = []
        for i in 0...90 { samples.append(TripSample(t: Double(i), kmh: Double(10 + (i % 15)), mode: i < 45 ? "Drive" : "Sport")) }
        return Trip(start: Date().addingTimeInterval(-600), end: Date().addingTimeInterval(-510), scooterName: "My J078", source: "simulation", samples: samples)
    }

    func testRideScreensWithASimulatedJ078() {
        let ble = simulatedScooter()
        let trips = TripManager()
        render(RideStatsView(trips: trips), "Ride stats")
        render(SpeedAlertSettingsView(), "Speed alert")
        RideHub.shared.alertOn = true
        RideHub.shared.alertKmh = 8
        RideHub.shared.sample(kmh: 12)
        render(SpeedAlertSettingsView(), "Speed alert, fired once")
        RideHub.shared.alertOn = false
        render(RideTimerView(), "Ride timer, stopped")
        RideHub.shared.timer.start(at: Date().addingTimeInterval(-90))
        RideHub.shared.timer.lap(at: Date().addingTimeInterval(-30))
        render(RideTimerView(), "Ride timer, running with a lap")
        RideHub.shared.timer.reset()
        render(QuickActionsSheet(ble: ble, close: {}), "Quick actions, simulated J078")
        render(ParkedSpotView(ble: ble), "Last parked here")
        render(DashboardView(ble: ble, trips: trips, openConnect: {}), "Dashboard with quick-actions button")
        ble.stopSimulation()
    }

    @MainActor
    func testShareCardAndMaintenance() {
        let trip = sampleTrip()
        render(RideShareCard(trip: trip, mph: true, accent: .orange), "Share card (mph)")
        render(RideShareCard(trip: trip, mph: false, accent: .blue), "Share card (km/h)")
        render(ShareCardView(trip: trip), "Share card screen")
        let url = ShareCardRenderer.render(trip: trip, mph: true, accent: .orange)
        XCTAssertNotNil(url, "the share image renders to a PNG")
        if let u = url { XCTAssertGreaterThan((try? Data(contentsOf: u))?.count ?? 0, 1000) }
        let trips = TripManager()
        let id = GarageStore.shared.scooters.first?.id ?? UUID()
        render(MaintenanceView(scooterID: id, trips: trips), "Maintenance")
        render(MaintenanceView(scooterID: UUID(), trips: trips), "Maintenance, unknown vehicle")
    }

    func testAppScreensDisconnected() {
        let ble = BLEManager()
        render(HelpView(), "Help / FAQ")
        render(AppSettingsView(), "App settings")
        render(PacketLoggerView(ble: ble), "Packet logger, idle")
        render(QuickActionsSheet(ble: ble, close: {}), "Quick actions, nothing connected")
        render(ParkedSpotView(ble: ble), "Last parked, nothing connected")
        render(MoreView(ble: ble, chooseScooter: {}), "More with the 4.2 sections")
    }

    func testPacketLoggerRecordsFrames() {
        let ble = simulatedScooter()
        PacketRecorder.shared.start(ble: ble)
        XCTAssertTrue(ble.logEveryStatus, "the logger records every frame while it runs")
        ble.info("test line")
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        render(PacketLoggerView(ble: ble), "Packet logger, recording")
        PacketRecorder.shared.stop()
        XCTAssertGreaterThan(PacketRecorder.shared.frames.count, 0)
        XCTAssertNotNil(PacketRecorder.shared.exportURL())
        render(PacketLoggerView(ble: ble), "Packet logger, stopped with frames")
        ble.stopSimulation()
    }

    func testReadOnlyVehiclesShowLiveDataOnly() {
        let ble = BLEManager()
        var f = FardriverTelemetry()
        f.volts = 72.4; f.amps = 12.5; f.motorSpeedRaw = 1500; f.gear = 2; f.socPercent = 80; f.motorTempC = 41
        f.faults = FardriverFaults(raw4: 0x02, raw5: 0x80)
        f.validFrames = 40
        ble.fardriver = f
        var n = NinebotTelemetry()
        n.speedKmh = 18.2; n.batteryPercent = 64; n.validFrames = 3
        ble.ninebot = n
        render(List { ReadOnlyLiveView(ble: ble) }, "Read-only live view, mock Fardriver + Ninebot")
        render(ControlsView(ble: ble), "Controls, nothing connected")
        render(ConnectView(ble: ble), "Connect list")
        XCTAssertFalse(ble.canControl, "a read-only vehicle never gets controls")
    }

    func testGarageAddVehicleAndEbikeDetail() {
        let ble = BLEManager()
        render(AddScooterView(done: {}), "Add vehicle (e-bike / controller)")
        render(GarageView(ble: ble), "Garage")
        let before = GarageStore.shared.scooters.count
        GarageStore.shared.add(name: "Test e-bike", compatID: "fardriver-nd", colorHex: "#FF9F0A", vehicleType: .ebike, controller: .fardriver)
        guard let e = GarageStore.shared.scooters.last, GarageStore.shared.scooters.count == before + 1 else { return XCTFail("not added") }
        XCTAssertTrue(e.readOnlyUntilCapture)
        render(GarageDetailView(ble: ble, scooterID: e.id), "Garage detail, Fardriver e-bike")
        GarageStore.shared.remove(e.id)
    }
}
