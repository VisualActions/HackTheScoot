import XCTest
import SwiftUI
import UIKit
@testable import J078

/// v4.1: every new screen (onboarding, garage, paywall, Pro tools, developer settings)
/// opens without crashing, free and unlocked, with and without a simulated scooter.
final class NewScreenTests41: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("j078", forKey: "chosenModel")
        UserDefaults.standard.set(false, forKey: "startup.enabled")
        UserDefaults.standard.set(true, forKey: Onboarding.doneKey)
        StoreManager.shared.testUnlock = .free
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    override func tearDown() {
        StoreManager.shared.testUnlock = .free
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func render<V: View>(_ view: V, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let host = UIHostingController(rootView: view.environmentObject(ThemeStore()).preferredColorScheme(.dark))
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

    func testOnboardingEveryPage() {
        let ble = simulatedScooter(.idle)
        for p in 0..<OnboardingView.pageCount {
            render(OnboardingView(ble: ble, onFinish: {}, startPage: p), "Onboarding page \(p)")
        }
        let off = BLEManager()
        render(OnboardingView(ble: off, onFinish: {}, startPage: 1), "Onboarding Bluetooth page, no scooter")
        render(OnboardingView(ble: off, onFinish: {}, startPage: 3), "Onboarding find page, no scooter")
        ble.stopSimulation()
    }

    func testRootShowsOnboardingOnFirstLaunch() {
        UserDefaults.standard.set(false, forKey: Onboarding.doneKey)
        let ble = simulatedScooter(.idle)
        render(RootView(ble: ble, trips: TripManager()), "Root with onboarding")
        UserDefaults.standard.set(true, forKey: Onboarding.doneKey)
        ble.stopSimulation()
    }

    func testGarageScreens() {
        let ble = simulatedScooter()
        GarageStore.shared.attach(ble)
        XCTAssertGreaterThanOrEqual(GarageStore.shared.scooters.count, 1)
        render(NavigationView { GarageView(ble: ble) }, "Garage")
        for s in GarageStore.shared.scooters {
            render(NavigationView { GarageDetailView(ble: ble, scooterID: s.id) }, "Garage detail \(s.name)")
            render(List { GarageRow(scooter: s, active: true, connected: false) }, "Garage row \(s.name)")
        }
        render(NavigationView { GarageDetailView(ble: ble, scooterID: UUID()) }, "Garage detail (removed)")
        render(AddScooterView {}, "Add scooter")
        for e in CompatSeed.all { render(CompatBadge(level: e.level), "Badge \(e.id)") }
        ble.stopSimulation()
        let off = BLEManager()
        render(NavigationView { GarageView(ble: off) }, "Garage (no scooter)")
    }

    func testPaywallAndProScreensFreeAndUnlocked() {
        let ble = simulatedScooter()
        let trips = TripManager()
        for t in Tier.allCases {
            StoreManager.shared.testUnlock = t
            render(NavigationView { PaywallView() }, "Paywall \(t.name)")
            render(NavigationView { PaywallView(highlight: .dataExport) }, "Paywall highlight \(t.name)")
            render(NavigationView { DeveloperSettingsView() }, "Developer settings \(t.name)")
            render(NavigationView { TripAnalyticsView(trips: trips) }, "Trip analytics \(t.name)")
            render(NavigationView { LogAnalysisView(ble: ble) }, "Log analysis \(t.name)")
            render(NavigationView { FrameDiffView() }, "Frame compare \(t.name)")
            render(NavigationView { ThemeEditorView() }, "Theme editor \(t.name)")
            render(NavigationView { MoreView(ble: ble, chooseScooter: {}) }, "More \(t.name)")
            for f in ProFeature.allCases { render(NavigationView { ProLockedView(feature: f) }, "Locked \(f)") }
        }
        StoreManager.shared.testUnlock = .free
        ble.stopSimulation()
    }

    func testTripScreensWithProExport() {
        var t = Trip(start: Date(), end: Date().addingTimeInterval(30), scooterName: "Simulated J078", source: "simulation")
        t.samples = (0..<30).map { TripSample(t: Double($0), kmh: Double($0), mode: "Eco") }
        let trips = TripManager()
        for tier in [Tier.free, .pro] {
            StoreManager.shared.testUnlock = tier
            render(NavigationView { TripDetailView(trip: t, mph: true, trips: trips) }, "Trip detail \(tier.name)")
            render(NavigationView { List { TripProExportSection(trip: t, mph: false) } }, "Pro export \(tier.name)")
            render(SpeedHistogram(bands: RideAnalytics.compute([t]).histogram, mph: true).frame(height: 150), "Histogram")
        }
        render(SpeedHistogram(bands: [], mph: true), "Empty histogram")
        StoreManager.shared.testUnlock = .free
    }

    func testEveryProThemeOnTheDashboard() {
        let ble = simulatedScooter(.sportRun)
        let trips = TripManager()
        for p in DashTheme.proPresets {
            let store = ThemeStore()
            store.theme = p
            let host = UIHostingController(rootView: DashboardView(ble: ble, trips: trips, openConnect: {}).environmentObject(store))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            XCTAssertNotNil(host.view, p.name)
        }
        ble.stopSimulation()
    }
}
