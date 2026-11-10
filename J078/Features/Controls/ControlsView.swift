import SwiftUI

/// v4.0.1 Controls: everything v3 had (light, park, modes, start mode, units, speed
/// limits with the above-stock warning) plus v4's Volpam controls. No crash paths:
/// every slider goes through SafeSlider and every range is at least 1 km/h wide.
struct ControlsView: View {
    @ObservedObject var ble: BLEManager
    @EnvironmentObject var themes: ThemeStore
    @State private var pin = Keychain.get("parkPIN") ?? "000000"
    @State private var volpamPin = ""
    @State private var volpamSaved = Keychain.get("volpamPassword") != nil
    @AppStorage(Keys.unitsSwapped) private var unitsSwapped = false
    @AppStorage(Keys.startSwapped) private var startSwapped = false

    private var moving: Bool { (ble.status?.speed ?? 0) > 2 }
    private var startIsZero: Bool? {
        guard let s = ble.status else { return nil }
        return Mapping.startIsZero(flagBit: s.startModeBit, swapped: startSwapped)
    }
    private var isMile: Bool? {
        guard let s = ble.status else { return nil }
        return Mapping.unitsIsMile(flagBit: s.unitsBit, swapped: unitsSwapped)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        ConnectionPill(ble: ble)
                        Spacer()
                        Text(ble.isActive ? ble.adapter.displayName : "No scooter").font(.footnote).foregroundColor(.secondary)
                    }
                    if moving {
                        Label("You're moving. Change settings when you stop.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundColor(.orange)
                    }
                }
                switch ble.kind {
                case .volpam: volpamSections
                case .j078: j078Sections
                default:
                    if ble.isActive && !ble.isSimulating {
                        Section("Read-only") {
                            Text(ble.isReadOnlyAdapter
                                 ? "\(ble.adapter.displayName) support is experimental: live data only, nothing is sent."
                                 : "This device isn't identified as a J078 or Volpam, so HackTheScoot only listens. If it is your J078, use More > Developer Lab > Treat as.")
                                .foregroundColor(.secondary)
                        }
                        ReadOnlyLiveView(ble: ble)
                    } else {
                        j078Sections   // shown (disabled) so you can see what's there before connecting
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Controls")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: J078

    @ViewBuilder private var j078Sections: some View {
        if !ble.canControl {
            Section {
                Text(ble.isActive ? "Getting ready... controls unlock when the J078 session is up." : "Connect your J078 first (Dashboard > Connect), or run the simulator.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }

        Section(header: Text("Ride"), footer: Text(ble.isSimulating ? "Simulator: taps change the simulated scooter. Nothing is sent over Bluetooth." : "Each tap sends one command. The switches show what the scooter reports back.")) {
            Toggle(isOn: Binding(get: { ble.status?.light ?? false }, set: { ble.setLight($0) })) {
                Label("Front light", systemImage: "lightbulb.fill")
            }
            Toggle(isOn: Binding(get: { ble.status?.parked ?? false }, set: { ble.setPark($0, pin: pin) })) {
                Label(ble.busy ?? "Park", systemImage: "parkingsign.circle.fill")
            }
            .disabled(ble.busy != nil || pin.count != 6)
            ModeGrid(ble: ble)
        }
        .disabled(!ble.canControl)

        Section(header: Text("Park password"), footer: Text("Park sends this password first, like the 365 app (000000 unless you changed it there). It only parks after the scooter answers OK. Kept in the iOS Keychain. Last reply: \(ble.passwordState)")) {
            SecureField("6 digits", text: $pin)
                .keyboardType(.numberPad)
                .onChange(of: pin) { v in
                    let d = String(v.filter { $0.isNumber }.prefix(6))
                    if d != v { pin = d }
                    if d.count == 6 { Keychain.set(d, for: "parkPIN") }
                }
        }

        Section("Top speed per mode") {
            TopSpeedsList(ble: ble)
            NavigationLink { SpeedLimitsView(ble: ble) } label: {
                Label("Set speed limits", systemImage: "speedometer")
            }
        }

        Section(header: Text("Start mode"), footer: Text("UNVERIFIED which value is which. If the scooter does the opposite, flip Swap.")) {
            HStack(spacing: 10) {
                ChoiceButton(title: "Zero start", selected: startIsZero == true) {
                    ble.setStartMode(value: Mapping.startValue(zero: true, swapped: startSwapped), label: "zero start")
                }
                ChoiceButton(title: "Kick start", selected: startIsZero == false) {
                    ble.setStartMode(value: Mapping.startValue(zero: false, swapped: startSwapped), label: "glide start")
                }
            }
            .disabled(!ble.canControl)
            Toggle("Swap", isOn: $startSwapped)
        }

        Section(header: Text("Units"), footer: Text("UNVERIFIED, likely 01 = mph. Flip Swap if it comes out backwards.")) {
            HStack(spacing: 10) {
                ChoiceButton(title: "mph", selected: isMile == true) {
                    ble.setUnits(value: Mapping.unitsValue(mile: true, swapped: unitsSwapped), label: "mph")
                }
                ChoiceButton(title: "km/h", selected: isMile == false) {
                    ble.setUnits(value: Mapping.unitsValue(mile: false, swapped: unitsSwapped), label: "km/h")
                }
            }
            .disabled(!ble.canControl)
            Toggle("Swap", isOn: $unitsSwapped)
        }
    }

    // MARK: Volpam

    @ViewBuilder private var volpamSections: some View {
        Section(header: Text("Volpam sign-in"), footer: Text("The Volpam's Bluetooth password is typed here once and kept in the iOS Keychain on this phone. It is never shown in the log or exported.")) {
            HStack {
                SecureField(volpamSaved ? "Saved (type to replace)" : "Bluetooth password (6 digits)", text: $volpamPin)
                    .keyboardType(.numberPad)
                Button("Save") {
                    if ble.saveVolpamPassword(volpamPin) { volpamSaved = true; volpamPin = "" }
                }
                .disabled(volpamPin.count != 6)
            }
            Text("Status: \(ble.passwordState)").font(.footnote).foregroundColor(.secondary)
        }
        Section(header: Text("Sport speed limit"), footer: Text("Verified from dad's capture: 34.0 was accepted, 35.7 was clamped to 35, 37.3 was declined. So the factory cap is 35 km/h (21.7 mph) and the slider stops there.")) {
            VolpamLimitRow(ble: ble)
        }
        Section(header: Text("Lights, lock, mode")) {
            NavigationLink("Experimental Volpam controls") { VolpamExperimentalView(ble: ble) }
            Text("The feature-frame bits are lined up from the order you tapped the buttons, not proven. They live on their own page and each send asks first.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }
}

struct ModeGrid: View {
    @ObservedObject var ble: BLEManager
    @EnvironmentObject var themes: ThemeStore
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Gear.allCases) { g in
                let on = ble.status?.gear == g
                Button { ble.setGear(g) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: g.icon)
                        Text(g.name).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? themes.accent : Color.white.opacity(0.08)))
                    .foregroundColor(on ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(g.name) mode")
            }
        }
        .padding(.vertical, 4)
    }
}

struct ChoiceButton: View {
    @EnvironmentObject var themes: ThemeStore
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? themes.accent : Color.white.opacity(0.08)))
                .foregroundColor(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct TopSpeedsList: View {
    @ObservedObject var ble: BLEManager
    var body: some View {
        ForEach(Gear.allCases) { g in
            let kmh = ble.limitsKmh[g] ?? g.capturedLimitKmh
            HStack {
                Image(systemName: g.icon).foregroundColor(.secondary).frame(width: 24)
                Text(g.name)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Gear.mph(for: g, kmh: kmh)) mph · \(kmh) km/h").font(.body.monospacedDigit())
                    Text(ble.limitsLive.contains(g) ? "live from scooter" : "from Nov 9 capture")
                        .font(.caption2).foregroundColor(.secondary)
                    if let seen = ble.topSeen[g], seen.isFinite, seen > 0 {
                        Text("fastest seen now: " + String(format: "%.1f", seen)).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Speed limits (v3 screen, restored)

enum SpeedLimitText {
    static let warning = "Speeds above your scooter's normal limit may be declined by the scooter. Running too high can overheat or damage the motor, controller or battery, and is less safe. Wear a helmet. I understand."
    static func both(_ kmh: Int, _ gear: Gear) -> String { "\(Gear.mph(for: gear, kmh: kmh)) mph · \(kmh) km/h" }
}

struct SpeedLimitsView: View {
    @ObservedObject var ble: BLEManager
    @AppStorage(Keys.aboveStockAccepted) private var aboveStockAccepted = false
    @State private var showWarning = false

    var body: some View {
        List {
            Section {
                Text("Pick a speed and tap Set. One command per tap, nothing automatic, no retries. Under each mode you see what the scooter actually accepted (its reply).")
                    .font(.callout)
                Text("Above stock may be refused: on Nov 9 the 365 app asked 32 km/h in Sport and the scooter answered 31.")
                    .font(.caption).foregroundColor(.orange)
                if !ble.canControl {
                    Text(ble.isActive ? "Not a J078 session, so nothing is sent." : "Connect your J078 first.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Section(header: Text("Above stock")) {
                if aboveStockAccepted {
                    Label("Above-stock speeds unlocked (up to \(Gear.absoluteMaxKmh) km/h)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Button("Lock back to stock") { aboveStockAccepted = false }
                } else {
                    Button { showWarning = true } label: { Label("Allow speeds above stock...", systemImage: "lock.open") }
                    Text("Until you accept the warning, each slider stops at that mode's stock limit.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            ForEach([Gear.sport, Gear.drive, Gear.eco, Gear.walk]) { g in
                SpeedLimitRow(ble: ble, gear: g, aboveStock: aboveStockAccepted)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Speed limits")
        .alert("Above your normal limit", isPresented: $showWarning) {
            Button("I understand", role: .destructive) { aboveStockAccepted = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SpeedLimitText.warning)
        }
    }
}

struct SpeedLimitRow: View {
    @ObservedObject var ble: BLEManager
    @EnvironmentObject var themes: ThemeStore
    let gear: Gear
    let aboveStock: Bool
    @State private var want: Double = -1
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var stock: Int { gear.capturedLimitKmh }
    private var current: Int { ble.limitsKmh[gear] ?? stock }
    private var range: ClosedRange<Int> { gear.sliderRange(aboveStock: aboveStock) }
    private var wantKmh: Int {
        let v = want < 0 ? current : safeInt(want)
        return min(max(v, range.lowerBound), range.upperBound)
    }

    var body: some View {
        Section {
            HStack {
                Image(systemName: gear.icon).foregroundColor(.secondary)
                Text(gear.name).font(.headline)
                Spacer()
                Text(gear.limitWriteVerified ? "verified" : "experimental")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(gear.limitWriteVerified ? Color.green.opacity(0.22) : Color.orange.opacity(0.22)))
            }
            Text("Scooter now: " + SpeedLimitText.both(current, gear) + (ble.limitsLive.contains(gear) ? " (live)" : " (Nov 9 capture)"))
                .font(.caption.monospacedDigit()).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(SpeedLimitText.both(wantKmh, gear))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundColor(wantKmh > stock ? .orange : .primary)
                    Spacer()
                    Button("Set") { ble.setSpeedLimit(gear, kmh: wantKmh, experimentalConfirmed: true) }
                        .buttonStyle(.borderedProminent)
                        .tint(themes.accent)
                        .disabled(!ble.canControl)
                }
                SafeSlider(value: Binding(get: { Double(wantKmh) }, set: { want = $0 }),
                           range: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .tint(themes.accent)
                HStack {
                    Text("\(range.lowerBound) km/h"); Spacer(); Text("stock \(stock)"); Spacer(); Text("\(range.upperBound) km/h")
                }
                .font(.caption2).foregroundColor(.secondary)
                if wantKmh > stock {
                    Text("Above stock: the scooter may refuse it.").font(.caption).foregroundColor(.orange)
                }
            }
            if ble.limitRequested[gear] != nil {
                let o = LimitOutcome.evaluate(requested: ble.limitRequested[gear], acked: ble.limitAccepted[gear],
                                              sentAt: ble.limitSentAt[gear], now: now)
                Text(o.text).font(.callout.monospacedDigit()).foregroundColor(color(o))
            }
        } footer: {
            if !gear.limitWriteVerified {
                Text("Experimental: the \(gear.name) code (BD BE AB \(String(format: "%02X", gear.limitByte)) [km/h]) follows the pattern; only Sport (A2) was seen in your capture.")
            }
        }
        .onReceive(tick) { now = $0 }
    }

    private func color(_ o: LimitOutcome) -> Color {
        switch o {
        case .accepted: return .green
        case .declined, .noAck: return .orange
        default: return .secondary
        }
    }
}

struct VolpamLimitRow: View {
    @ObservedObject var ble: BLEManager
    @State private var tenths: Double = 350
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Slider(value: $tenths, in: Double(VolpamProto.minTenths)...Double(VolpamProto.factoryMaxTenths), step: 1)
                Text(String(format: "%.1f km/h · %.1f mph", tenths / 10, Units.kmhToMph(tenths / 10)))
                    .font(.caption.monospacedDigit()).frame(width: 130, alignment: .trailing)
            }
            HStack {
                Button("Set") { ble.setVolpamSpeedLimit(tenthsKmh: Int(tenths)) }.buttonStyle(.bordered).disabled(!ble.canControlVolpam)
                Spacer()
                Text(LimitOutcome.evaluate(requested: ble.limitRequested[.sport], acked: ble.limitAccepted[.sport],
                                           sentAt: ble.limitSentAt[.sport], now: now).text)
                    .font(.caption).foregroundColor(.secondary)
            }
            Text("Scooter reports: " + (ble.limitsLive.contains(.sport) ? "\(ble.limitsKmh[.sport] ?? 0) km/h" : "--"))
                .font(.footnote).foregroundColor(.secondary)
        }
        .onReceive(tick) { now = $0 }
    }
}

struct VolpamExperimentalView: View {
    @ObservedObject var ble: BLEManager
    @State private var f = VolpamProto.Features(unlocked: true, mph: true, zeroStart: true, light: false, mode: .sport)
    @State private var asking = false
    @State private var result = ""

    var body: some View {
        Form {
            Section(footer: Text("Builds ONE feature frame (AC 00 0A ...) with your current limits copied unchanged and a CRC that matches the vendor app byte-for-byte. Bit meanings are guesses from button order.")) {
                Toggle("Unlocked", isOn: $f.unlocked)
                Toggle("Light", isOn: $f.light)
                Toggle("mph (guess)", isOn: $f.mph)
                Toggle("Zero start (guess)", isOn: $f.zeroStart)
                Picker("Mode", selection: $f.mode) {
                    ForEach(VolpamProto.Mode.allCases, id: \.self) { m in Text(m.name).tag(m) }
                }
            }
            Section("Scooter reports") {
                if let s = ble.volpamStatus {
                    Text("mode index \(s.modeIndex) (\(s.mode?.name ?? "?")), light bit \(s.light ? "on" : "off"), lock bit \(s.unlocked ? "unlocked" : "locked")")
                        .font(.footnote)
                } else {
                    Text("No status yet").foregroundColor(.secondary)
                }
            }
            Section {
                Button("Send once (experimental)") { asking = true }
                    .disabled(!ble.canControlVolpam || ble.volpamLimits == nil)
                if !result.isEmpty { Text(result).font(.footnote) }
            }
        }
        .navigationTitle("Volpam (experimental)")
        .confirmationDialog("Send this experimental frame once?", isPresented: $asking, titleVisibility: .visible) {
            Button("Send once") { result = ble.sendVolpamFeatures(f, confirmed: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only do this with the scooter standing still and the wheel off the ground.")
        }
    }
}
