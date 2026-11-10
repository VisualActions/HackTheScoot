import XCTest
import SwiftUI
import UIKit
@testable import J078

/// v5.1: every new screen and section opens without crashing (portrait and landscape,
/// dark and light), with nothing connected and with mock KuKirin / Xiaomi / Ninebot data.
/// The mock sessions use a fake radio: nothing is sent anywhere.
final class NewScreenTests51: XCTestCase {

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

    private func reply(_ idx: UInt8, _ v: Int) -> [UInt8] {
        return NBXFrames.m365(addr: 0x23, cmd: 0x01, index: idx, payload: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }

    /// A BLEManager whose Xiaomi session is live on a fake radio (nothing connected, nothing sent).
    private func mockXiaomi() -> BLEManager {
        let ble = BLEManager()
        var sent = 0
        ble.nbx.send = { _ in sent += 1; return true }
        let t0 = Date()
        ble.nbx.start(family: .xiaomi, bleName: "MIScooter0000", deviceKey: "screen-test", now: t0)
        ble.nbx.tick(now: t0)
        let regs: [(UInt8, Int)] = [(0xB4, 76), (0xB5, 0), (0xB7, 123_456), (0x3E, 215), (0xB0, 14), (0x7B, 1), (0x7C, 0), (0x7D, 2), (0x1A, 0x0134)]
        for (i, v) in regs {
            ble.nbx.receive(reply(i, v), now: t0)
        }
        XCTAssertEqual(ble.nbx.mode, .xiaomiPlain)
        XCTAssertGreaterThan(sent, 0)
        return ble
    }

    func testKukirinLiveData() {
        let ble = BLEManager()
        var g2 = KukirinTelemetry(model: .g2)
        g2.speedKmh = 18; g2.batteryVolts = 49.8; g2.motorRpm = 420; g2.motorActive = true; g2.rideMode = "Sport"; g2.g2MainFrames = 12
        ble.kukirin = g2
        render(List { ReadOnlyLiveView(ble: ble) }, "Read-only screen with KuKirin G2 data")
        render(List { KukirinLiveSection(t: g2) }, "KuKirin G2 section, light", scheme: .light)
        render(List { KukirinLiveSection(t: KukirinTelemetry(model: .g4)) }, "KuKirin G4, nothing decoded yet")
        ble.kukirin = nil
    }

    func testXiaomiLiveSectionAndExperimentalSettings() {
        let ble = mockXiaomi()
        render(List { ReadOnlyLiveView(ble: ble) }, "Read-only screen with a live M365 session")
        render(List { NBXLiveSection(ble: ble) }, "M365 section, light", scheme: .light)
        render(NBXControlsView(ble: ble), "Experimental M365 settings")
        render(NBXControlsView(ble: ble), "Experimental M365 settings, light", scheme: .light)
        XCTAssertNotNil(ble.nbxWrite(.kers, value: 3), "an unknown value is never sent")
        ble.nbx.stop()
    }

    func testNinebotNeedsPairingAndReadOnlyStates() {
        let ble = BLEManager()
        let t0 = Date()
        ble.nbx.start(family: .ninebot, bleName: "NBScooter0000", deviceKey: "screen-test", now: t0)
        render(List { NBXLiveSection(ble: ble) }, "Ninebot probing")
        ble.nbx.tick(now: t0.addingTimeInterval(3.2))
        render(List { ReadOnlyLiveView(ble: ble) }, "Ninebot needs pairing (Pair button)")
        render(NBXControlsView(ble: ble), "Ninebot settings before pairing (read-only)")
        ble.nbx.stop()
        render(NBXControlsView(ble: BLEManager()), "Settings with nothing connected")
    }

    func testErrorCodesAndBrandStatus() {
        render(ScooterErrorCodesView(), "Ninebot and Xiaomi error codes")
        render(ScooterErrorCodesView(), "Error codes, light", scheme: .light)
        for f in FaultCatalog.ninebot.prefix(3) + FaultCatalog.xiaomi.suffix(2) {
            render(FaultDetailView(fault: f, sourceText: FaultCatalog.scooterCodeSource), "Code \(f.id)")
        }
        if let u = FaultCatalog.explainCode(77, xiaomi: false) { render(FaultDetailView(fault: u, sourceText: FaultCatalog.scooterCodeSource), "Unknown code") }
        render(FaultListView(), "Fault list with the Ninebot / Xiaomi link")
        render(List { BrandStatusSection() }, "Brand status")
        render(CaptureGuideView(ble: BLEManager()), "Capture guide with the brand status")
        render(CompatCheckerView(), "Compatibility checker with the brand status")
        for e in CompatSeed.all where e.adapter == "kukirin" || e.adapter == "xiaomi365" || e.adapter == "ninebot" {
            render(CompatDetailView(entry: e), "Compat detail \(e.id)")
        }
        render(WhatsNewView(), "What's new in 5.1")
        render(List { ExperimentalBadge() }, "Experimental badge")
    }
}
