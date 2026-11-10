import SwiftUI

struct ControlsView: View {
    @ObservedObject var ble: BLEManager
    @EnvironmentObject var themes: ThemeStore
    @State private var pin = Keychain.get("parkPIN") ?? "000000"
    @State private var volpamPin = ""
    @State private var volpamSaved = Keychain.get("volpamPassword") != nil
    @State private var confirmExperimental = false
    @AppStorage(Keys.unitsSwapped) private var unitsSwapped = false
    @AppStorage(Keys.startSwapped) private var startSwapped = false

    private var moving: Bool { (ble.status?.speed ?? 0) > 2 }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        ConnectionPill(ble: ble)
                        Spacer()
                        Text(ble.adapter.displayName).font(.footnote).foregroundColor(.secondary)
                    }
                    if moving {
                        Label("You're moving. Controls are locked until you stop.", systemImage: "hand.raised.fill")
                            .foregroundColor(.orange)
                    }
                }
                switch ble.kind {
                case .j078: j078Sections
                case .volpam: volpamSections
                default:
                    Section("Read-only") {
                        Text(ble.isActive ? "This device isn't identified, so HackTheScoot only listens. Nothing is sent."
                                          : "Connect a scooter, or start the simulator in Connect.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(moving)
            .navigationTitle("Controls")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: J078

    @ViewBuilder private var j078Sections: some View {
        Section(header: Text("Verified controls"), footer: Text(ble.isSimulating ? "Simulator: taps change the simulated scooter. Nothing is sent over Bluetooth." : "Each tap sends one verified command. The state below is what the scooter reports back.")) {
            Toggle("Front light", isOn: Binding(get: { ble.status?.light ?? false }, set: { ble.setLight($0) }))
                .disabled(!ble.canControl)
            Picker("Riding mode", selection: Binding(get: { ble.status?.gear ?? .eco }, set: { ble.setGear($0) })) {
                ForEach(Gear.allCases) { g in Text(g.name).tag(g) }
            }
            .pickerStyle(.segmented)
            .disabled(!ble.canControl)
        }
        Section(header: Text("Park"), footer: Text("v4: park is sent only after the scooter answers the password (DB EB CA CA FF). A timeout sends nothing. The PIN is kept in the iOS Keychain.")) {
            SecureField("Park PIN (6 digits)", text: $pin)
                .keyboardType(.numberPad)
                .onChange(of: pin) { v in
                    let d = String(v.filter { $0.isNumber }.prefix(6))
                    if d != v { pin = d }
                    Keychain.set(d, for: "parkPIN")
                }
            HStack {
                Button("Park on") { ble.setPark(true, pin: pin) }.buttonStyle(.borderedProminent)
                Button("Park off") { ble.setPark(false, pin: pin) }.buttonStyle(.bordered)
                Spacer()
                Text((ble.status?.parked ?? false) ? "Parked" : "Not parked").foregroundColor(.secondary)
            }
            .disabled(!ble.canControl || pin.count != 6 || ble.busy != nil)
            Text("Password: \(ble.passwordState)").font(.footnote).foregroundColor(.secondary)
        }
        Section(header: Text("Speed limit (factory range)"), footer: Text("The slider stops at the factory limit for each mode (sport 31 km/h / 19 mph). Above-stock was removed in v4. Sport is verified; walk, eco and drive use the same pattern but are experimental.")) {
            ForEach(Gear.allCases.reversed()) { g in
                LimitRow(ble: ble, gear: g, confirmExperimental: confirmExperimental)
            }
            Toggle("I understand walk/eco/drive limits are experimental", isOn: $confirmExperimental)
                .font(.footnote)
        }
        Section(header: Text("Experimental"), footer: Text("These bits follow the commands, but which value means what is a guess from your captures. Each send asks first.")) {
            ExperimentalButton(title: "Units: mph", detail: "cmd 01 = \(Mapping.unitsValue(mile: true, swapped: unitsSwapped))") {
                ble.setUnits(value: Mapping.unitsValue(mile: true, swapped: unitsSwapped), label: "mph")
            }
            ExperimentalButton(title: "Units: km/h", detail: "cmd 01 = \(Mapping.unitsValue(mile: false, swapped: unitsSwapped))") {
                ble.setUnits(value: Mapping.unitsValue(mile: false, swapped: unitsSwapped), label: "km/h")
            }
            ExperimentalButton(title: "Start: zero", detail: "cmd 07 = \(Mapping.startValue(zero: true, swapped: startSwapped))") {
                ble.setStartMode(value: Mapping.startValue(zero: true, swapped: startSwapped), label: "zero start")
            }
            ExperimentalButton(title: "Start: kick / glide", detail: "cmd 07 = \(Mapping.startValue(zero: false, swapped: startSwapped))") {
                ble.setStartMode(value: Mapping.startValue(zero: false, swapped: startSwapped), label: "glide start")
            }
        }
        .disabled(!ble.canControl)
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

struct ExperimentalButton: View {
    let title: String
    let detail: String
    let action: () -> Void
    @State private var asking = false
    var body: some View {
        Button { asking = true } label: {
            HStack {
                Text(title)
                Spacer()
                Text(detail).font(.caption.monospaced()).foregroundColor(.secondary)
                Text("EXP").font(.caption2.weight(.heavy)).foregroundColor(.orange)
            }
        }
        .confirmationDialog("Send this experimental command once?", isPresented: $asking, titleVisibility: .visible) {
            Button("Send once", action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Which value means what is not proven yet. Watch the scooter and the status readout.")
        }
    }
}

struct LimitRow: View {
    @ObservedObject var ble: BLEManager
    let gear: Gear
    let confirmExperimental: Bool
    @State private var value: Double = 0
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(gear.name).font(.headline)
                if !gear.limitWriteVerified { Text("EXPERIMENTAL").font(.caption2.weight(.heavy)).foregroundColor(.orange) }
                Spacer()
                Text("now: " + current).font(.footnote).foregroundColor(.secondary)
            }
            HStack {
                Slider(value: $value, in: Double(gear.limitRange.lowerBound)...Double(gear.limitRange.upperBound), step: 1)
                Text("\(Int(value)) km/h · \(Gear.mph(for: gear, kmh: Int(value))) mph").font(.caption.monospacedDigit()).frame(width: 118, alignment: .trailing)
            }
            HStack {
                Button("Set") { ble.setSpeedLimit(gear, kmh: Int(value), experimentalConfirmed: confirmExperimental) }
                    .buttonStyle(.bordered)
                    .disabled(!ble.canControl || (!gear.limitWriteVerified && !confirmExperimental))
                Spacer()
                Text(outcome.text).font(.caption).foregroundColor(outcomeColor).multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 4)
        .onAppear { value = Double(min(gear.factoryMaxKmh, ble.limitsKmh[gear] ?? gear.capturedLimitKmh)) }
        .onReceive(tick) { now = $0 }
    }

    private var current: String {
        guard let k = ble.limitsKmh[gear] else { return "--" }
        return ble.limitsLive.contains(gear) ? "\(k) km/h" : "\(k) km/h (not reported yet)"
    }

    private var outcome: LimitOutcome {
        LimitOutcome.evaluate(requested: ble.limitRequested[gear], acked: ble.limitAccepted[gear], sentAt: ble.limitSentAt[gear], now: now)
    }

    private var outcomeColor: Color {
        switch outcome {
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
