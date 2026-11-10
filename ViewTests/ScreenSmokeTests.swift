import XCTest
import SwiftUI
import UIKit
@testable import J078

/// Builds and lays out every screen in a real window, with a simulated scooter, so
/// a SwiftUI crash on open (a zero-width Slider, a missing EnvironmentObject, a bad
/// range, a NaN to Int) fails CI instead of crashing on the phone.
/// v4.0.0 crashed on Controls: the Walk speed-limit slider had a 6...6 range.
final class ScreenSmokeTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("j078", forKey: "chosenModel")
        UserDefaults.standard.set(false, forKey: "startup.enabled")
        UserDefaults.standard.set(true, forKey: Onboarding.doneKey)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Puts the view on screen, lays it out and lets SwiftUI run a few frames.
    private func render<V: View>(_ view: V, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let host = UIHostingController(rootView: view.environmentObject(ThemeStore()).preferredColorScheme(.dark))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view, name, file: file, line: line)
        // landscape too (the dashboard has its own landscape layout)
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
    }

    private func simulatedScooter(_ scenario: ScooterSimulator.Scenario = .cityRide) -> BLEManager {
        let ble = BLEManager()
        ble.startSimulation(scenario)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))   // a few simulated status frames
        return ble
    }

    func testEveryTabWithASimulatedJ078() {
        let ble = simulatedScooter()
        XCTAssertEqual(ble.kind, .j078)
        XCTAssertTrue(ble.canControl, "simulated J078 should unlock the controls")
        let trips = TripManager()
        render(DashboardView(ble: ble, trips: trips, openConnect: {}), "Dashboard")
        render(ControlsView(ble: ble), "Controls")
        render(TripsView(trips: trips, ble: ble), "Trips")
        render(MoreView(ble: ble, chooseScooter: {}), "More")
        render(RootView(ble: ble, trips: trips), "Root tab bar")
        ble.stopSimulation()
    }

    func testEveryTabDisconnected() {
        let ble = BLEManager()
        let trips = TripManager()
        render(DashboardView(ble: ble, trips: trips, openConnect: {}), "Dashboard (no scooter)")
        render(ControlsView(ble: ble), "Controls (no scooter)")
        render(TripsView(trips: trips, ble: ble), "Trips (no scooter)")
        render(MoreView(ble: ble, chooseScooter: {}), "More (no scooter)")
    }

    /// The exact v4.0.0 crash: every speed-limit row, stock and above-stock, every mode.
    func testSpeedLimitScreensNeverBuildAZeroWidthSlider() {
        let ble = simulatedScooter(.idle)
        for above in [false, true] {
            UserDefaults.standard.set(above, forKey: Keys.aboveStockAccepted)
            render(NavigationView { SpeedLimitsView(ble: ble) }, "Speed limits aboveStock=\(above)")
            for g in Gear.allCases {
                render(List { SpeedLimitRow(ble: ble, gear: g, aboveStock: above) }, "\(g.name) row aboveStock=\(above)")
            }
        }
        UserDefaults.standard.set(false, forKey: Keys.aboveStockAccepted)
        ble.stopSimulation()
    }

    func testControlsForVolpamAndUnknownDevices() {
        let ble = BLEManager()
        ble.kind = .volpam
        render(ControlsView(ble: ble), "Controls (Volpam)")
        render(NavigationView { VolpamExperimentalView(ble: ble) }, "Volpam experimental")
        ble.kind = .unknown
        render(ControlsView(ble: ble), "Controls (unknown)")
    }

    func testEveryModeOnTheDashboard() {
        let ble = simulatedScooter(.modeTour)
        let trips = TripManager()
        for g in Gear.allCases {
            ble.setGear(g)          // simulator only: never Bluetooth
            render(DashboardView(ble: ble, trips: trips, openConnect: {}), "Dashboard in \(g.name)")
        }
        ble.stopSimulation()
    }

    func testEveryGaugeStyleAndPreset() {
        let ble = simulatedScooter(.sportRun)
        let trips = TripManager()
        for p in DashTheme.presets {
            let store = ThemeStore()
            store.theme = p
            let host = UIHostingController(rootView: DashboardView(ble: ble, trips: trips, openConnect: {}).environmentObject(store))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        // NaN / infinity never reach an Int conversion
        for v in [Double.nan, .infinity, -.infinity, 1e300, -5] {
            let m = GaugeModel(speed: v, maxSpeed: v, unit: "mph", color: .blue, accent: .blue, font: .default,
                               stale: false, simulated: false, intensity: 0.5, night: false)
            for style in ["classic", "digital", "performance"] {
                render(AnyGauge(style: style, m: m).frame(width: 300, height: 300), "gauge \(style) \(v)")
            }
        }
        ble.stopSimulation()
    }

    func testMoreScreens() {
        let ble = simulatedScooter(.idle)
        render(NavigationView { ConnectView(ble: ble) }, "Connect")
        render(NavigationView { DiagnosticsView(ble: ble) }, "Diagnostics")
        render(NavigationView { DevLabView(ble: ble) }, "Developer Lab")
        render(NavigationView { LogPage(ble: ble) }, "Packet log")
        render(NavigationView { StartupStudioView() }, "Startup Studio")
        render(NavigationView { ThemeEditorView() }, "Theme editor")
        render(NavigationView { DashboardDesignerView() }, "Designer")
        render(NavigationView { FeedbackSettingsView() }, "Haptics")
        render(NavigationView { EvidenceView() }, "Evidence")
        render(NavigationView { TerminalView(ble: ble) }, "Terminal")
        render(NavigationView { ExperimentalView(ble: ble) }, "Explorer")
        render(NavigationView { StatusBytesPage(ble: ble) }, "Status bytes")
        render(ChooseScooterView(onDone: {}), "Choose scooter")
        render(StartupOverlay(text: "HACKTHESCOOT", theme: "neon", duration: 1) {}, "Startup overlay")
        ble.stopSimulation()
    }
}
