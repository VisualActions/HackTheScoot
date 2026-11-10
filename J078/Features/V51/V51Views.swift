import SwiftUI

// MARK: - v5.1 screens (EXPERIMENTAL, UNTESTED ON HARDWARE). Everything here is free.

/// The label every new 5.1 feature carries.
struct ExperimentalBadge: View {
    var body: some View {
        Label("Experimental, untested on hardware", systemImage: "flask")
            .font(.caption.weight(.semibold))
            .foregroundColor(.orange)
            .accessibilityLabel("Experimental, untested on hardware")
    }
}

struct KukirinLiveSection: View {
    let t: KukirinTelemetry
    var body: some View {
        Section(header: Text("KuKirin \(t.model.rawValue) live data"),
                footer: Text("Read-only: HackTheScoot never writes to a KuKirin. Decoded from public observations (bancada-g2 for the G2, maksdoner for the G4). Values are unverified until someone checks them against the dashboard.")) {
            ExperimentalBadge()
            if t.model != .g4 {
                row("Speed", t.speedKmh.map { "\($0) km/h" } ?? "--")
                row("Battery", t.batteryVolts.map { String(format: "%.2f V", $0) } ?? "--")
                row("Motor", t.motorRpm.map { "\($0) rpm" + ((t.motorActive ?? false) ? " (running)" : "") } ?? "--")
            }
            row("Ride mode", t.rideMode ?? "--")
            row("Frames decoded / ignored", "\(t.validFrames) / \(t.ignoredFrames)")
            if t.validFrames == 0 {
                Text("Nothing decoded yet. Some KuKirin model years have no working Bluetooth. If the official app works but this stays empty, a capture helps.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary).monospacedDigit() }
            .accessibilityElement(children: .combine)
    }
}

struct NBXLiveSection: View {
    @ObservedObject var ble: BLEManager
    @State private var confirmPair = false

    private var d: NBXDriver { ble.nbx }
    private var t: NBXTelemetry { ble.nbx.telemetry }
    private var xiaomi: Bool { ble.nbx.family == .xiaomi }

    var body: some View {
        Section(header: Text(xiaomi ? "Xiaomi live data" : "Ninebot live data"),
                footer: Text("HackTheScoot asks the scooter for these values (reads only). Units come from public docs and are unverified on your scooter.")) {
            ExperimentalBadge()
            Label(d.stageText, systemImage: stageIcon).font(.subheadline)
            if canPair {
                Button { confirmPair = true } label: { Label("Pair with this scooter", systemImage: "key.horizontal") }
                    .accessibilityHint("Asks the scooter to pair. You press its power button once.")
            }
            if d.mode != nil {
                Group {
                    row("Speed", t.speedKmh.map { String(format: "%.1f km/h", $0) } ?? "--")
                    row("Battery", t.batteryPercent.map { "\($0) %" } ?? "--")
                    row("Odometer", t.odometerKm.map { String(format: "%.1f km", $0) } ?? "--")
                    row("Trip", t.tripKm.map { String(format: "%.2f km", $0) } ?? "--")
                    row("Range (unverified)", t.rangeKm.map { String(format: "%.1f km", $0) } ?? "--")
                    row("Frame temperature", t.frameTempC.map { String(format: "%.1f °C", $0) } ?? "--")
                    row("Controller firmware", t.escFirmware ?? "--")
                }
                if !xiaomi {
                    row("Bluetooth firmware", t.bleFirmware ?? "--")
                    row("Battery firmware", t.bmsFirmware ?? "--")
                }
                if let e = t.errorCode, let f = FaultCatalog.explainCode(e, xiaomi: xiaomi) {
                    NavigationLink { FaultDetailView(fault: f, sourceText: FaultCatalog.scooterCodeSource) } label: {
                        Label("Error \(e): \(f.title)", systemImage: "exclamationmark.triangle.fill").foregroundColor(.red)
                    }
                } else {
                    row("Error code", t.errorCode.map { $0 == 0 ? "none" : "\($0)" } ?? "--")
                }
                if let w = t.warningCode, w != 0 { row("Warning code", "\(w)") }
                NavigationLink { NBXControlsView(ble: ble) } label: {
                    Label(d.allowedSettings.isEmpty ? "Settings (read-only on this scooter)" : "Experimental settings", systemImage: "slider.horizontal.3")
                }
            }
            NavigationLink { ScooterErrorCodesView() } label: { Label("Ninebot and Xiaomi error codes", systemImage: "list.number") }
        }
        .alert("Pair with this scooter?", isPresented: $confirmPair) {
            Button("Pair") { ble.nbxStartPairing() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Experimental, untested on hardware. HackTheScoot uses its own pairing code. When asked, press the scooter's power button once. The official app may ask you to pair again afterwards. Nothing else on the scooter changes.")
        }
    }

    private var canPair: Bool {
        switch d.stage {
        case .needsPairing: return true
        default: return false
        }
    }

    private var stageIcon: String {
        switch d.stage {
        case .live: return "dot.radiowaves.left.and.right"
        case .pairing: return "key.horizontal"
        case .unsupported: return "xmark.octagon"
        case .needsPairing: return "lock"
        default: return "hourglass"
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary).monospacedDigit() }
            .accessibilityElement(children: .combine)
    }
}

/// The only Xiaomi / Ninebot writes: read first, confirm, write once, read back.
struct NBXControlsView: View {
    @ObservedObject var ble: BLEManager
    @State private var pending: (setting: NBXSetting, value: UInt16, label: String)?
    @State private var showConfirm = false
    @State private var message: String?

    private var d: NBXDriver { ble.nbx }

    var body: some View {
        List {
            Section(footer: Text("Each change reads the current value first, only works while the scooter stands still, asks you, sends one message, then reads the value back to check. Firmware, lock, power-off, PIN, serial, speed-limit and battery commands are never sent.")) {
                ExperimentalBadge()
                Text("These settings are built from public documentation and have not been tried on a real scooter. They should work, but they might not.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            if d.allowedSettings.isEmpty {
                Section(footer: Text(readOnlyReason)) {
                    Label("Read-only on this scooter", systemImage: "lock.shield")
                }
            }
            ForEach(d.allowedSettings) { s in
                Section(header: Text(s.title)) {
                    HStack { Text("Scooter reports"); Spacer(); Text(s.label(for: d.telemetry.setting(s))).foregroundColor(.secondary) }
                        .accessibilityElement(children: .combine)
                    ForEach(s.options, id: \.value) { o in
                        Button {
                            pending = (s, o.value, o.label)
                            showConfirm = true
                        } label: {
                            HStack {
                                Text(o.label)
                                Spacer()
                                if d.telemetry.setting(s) == Int(o.value) { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                            }
                        }
                        .disabled(d.telemetry.setting(s) == nil)
                    }
                }
            }
            if let m = message ?? d.lastWriteResult {
                Section("Last change") { Text(m).font(.footnote) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Experimental settings")
        .alert("Change this setting?", isPresented: $showConfirm) {
            Button("Send it") {
                if let p = pending { message = ble.nbxWrite(p.setting, value: p.value) }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("Experimental, untested on hardware. \(pending?.setting.title ?? "") -> \(pending?.label ?? ""). Only while standing still. HackTheScoot reads it back to check.")
        }
    }

    private var readOnlyReason: String {
        if d.mode == nil { return "Not connected to a live session yet." }
        if d.family == .xiaomi { return "Encrypted Xiaomi models (Pro, Pro 2, 1S, Essential) are read-only for now. A capture of the Mi Home app would show their settings." }
        return "Nothing is writable on this scooter yet."
    }
}

struct ScooterErrorCodesView: View {
    var body: some View {
        List {
            Section(header: Text("Ninebot ES / Max (G30)"), footer: Text(FaultCatalog.scooterCodeSource)) {
                ForEach(FaultCatalog.ninebot) { f in codeRow(f) }
            }
            Section(header: Text("Xiaomi M365 family")) {
                ForEach(FaultCatalog.xiaomi) { f in codeRow(f) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Scooter error codes")
    }

    private func codeRow(_ f: FaultInfo) -> some View {
        NavigationLink { FaultDetailView(fault: f, sourceText: FaultCatalog.scooterCodeSource) } label: {
            HStack {
                Text(f.title)
                Spacer()
                Text(f.severity.rawValue).font(.caption).foregroundColor(FaultDetailView.color(f.severity))
            }
        }
    }
}

/// Capture guide / compatibility: what's known per brand right now.
struct BrandStatusSection: View {
    var body: some View {
        Section(header: Text("What's known so far"), footer: Text("Experimental means untested on hardware. A capture from your official app is what turns a guess into a verified control.")) {
            ForEach(BrandStatusList.all) { b in
                VStack(alignment: .leading, spacing: 3) {
                    Text(b.brand).font(.subheadline.weight(.semibold))
                    Text(b.status).font(.footnote)
                    Text("A capture would add: " + b.needsCapture).font(.footnote).foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
