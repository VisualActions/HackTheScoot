import SwiftUI

struct ControlsView: View {
    @ObservedObject var ble: BLEManager
    @AppStorage(Keys.unitsSwapped) private var unitsSwapped = false
    @AppStorage(Keys.startSwapped) private var startSwapped = false
    @AppStorage(Keys.password) private var password = "000000"

    private var startIsZero: Bool? {
        guard let s = ble.status else { return nil }
        return Mapping.startIsZero(flagBit: s.startModeBit, swapped: startSwapped)
    }

    private var isMile: Bool? {
        guard let s = ble.status else { return nil }
        return Mapping.unitsIsMile(flagBit: s.unitsBit, swapped: unitsSwapped)
    }

    var body: some View {
        NavigationStack {
            List {
                if !ble.canControl {
                    Section {
                        Text(ble.connected == nil ? "Connect to your J078 first (Connect tab)." :
                                "Connected device isn't using the J078 protocol, so controls are off. Debug tab shows its packets.")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Lights and park") {
                    Toggle(isOn: Binding(get: { ble.status?.light ?? false },
                                         set: { ble.setLight($0) })) {
                        Label("Front light", systemImage: "lightbulb.fill")
                    }
                    Toggle(isOn: Binding(get: { ble.status?.parked ?? false },
                                         set: { ble.setPark($0, pin: password) })) {
                        Label(ble.busy ?? "Park", systemImage: "parkingsign.circle.fill")
                    }
                    .disabled(ble.busy != nil)
                    Text("Park sends the password first (like the 365 app). Password reply: \(ble.passwordState)")
                        .font(.caption).foregroundColor(.secondary)
                }
                .disabled(!ble.canControl)

                Section("Mode") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Gear.allCases) { g in
                            let on = ble.status?.gear == g
                            Button {
                                ble.setGear(g)
                            } label: {
                                HStack {
                                    Image(systemName: g.icon)
                                    Text(g.name).bold()
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(on ? g.color : Color.white.opacity(0.08))
                                .foregroundColor(on ? .black : .white)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .disabled(!ble.canControl)

                Section {
                    HStack(spacing: 10) {
                        choice("Zero start", selected: startIsZero == true) {
                            ble.setStartMode(value: Mapping.startValue(zero: true, swapped: startSwapped), label: "zero start")
                        }
                        choice("Glide / kick start", selected: startIsZero == false) {
                            ble.setStartMode(value: Mapping.startValue(zero: false, swapped: startSwapped), label: "glide start")
                        }
                    }
                    Toggle("Swap (if these are backwards)", isOn: $startSwapped)
                    Text("Sends BD BE AB 07 \(String(format: "%02X", Mapping.startValue(zero: true, swapped: startSwapped))) for zero start, 07 \(String(format: "%02X", Mapping.startValue(zero: false, swapped: startSwapped))) for glide.")
                        .font(.caption.monospaced()).foregroundColor(.secondary)
                } header: {
                    Text("Start mode (UNVERIFIED which is which)")
                }
                .disabled(!ble.canControl)

                Section {
                    HStack(spacing: 10) {
                        choice("mph", selected: isMile == true) {
                            ble.setUnits(value: Mapping.unitsValue(mile: true, swapped: unitsSwapped), label: "mile")
                        }
                        choice("km/h", selected: isMile == false) {
                            ble.setUnits(value: Mapping.unitsValue(mile: false, swapped: unitsSwapped), label: "km")
                        }
                    }
                    Toggle("Swap (if these are backwards)", isOn: $unitsSwapped)
                    Text("Sends BD BE AB 01 \(String(format: "%02X", Mapping.unitsValue(mile: true, swapped: unitsSwapped))) for mph, 01 \(String(format: "%02X", Mapping.unitsValue(mile: false, swapped: unitsSwapped))) for km/h.")
                        .font(.caption.monospaced()).foregroundColor(.secondary)
                } header: {
                    Text("Units (UNVERIFIED, likely 01 = mile)")
                }
                .disabled(!ble.canControl)

                Section("Top speed per mode") {
                    TopSpeedsList(ble: ble)
                    NavigationLink {
                        SpeedLimitsView(ble: ble)
                    } label: {
                        Label("Set speed limits", systemImage: "speedometer")
                    }
                }
            }
            .navigationTitle("Controls")
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .bold()
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.accentColor : Color.white.opacity(0.08))
                .foregroundColor(.white)
                .cornerRadius(10)
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
                Image(systemName: g.icon).foregroundColor(g.color).frame(width: 24)
                Text(g.name).bold()
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Gear.mph(for: g, kmh: kmh)) mph · \(kmh) km/h")
                        .font(.body.monospacedDigit())
                    Text(ble.limitsLive.contains(g) ? "live from scooter" : "from Nov 9 capture")
                        .font(.caption2).foregroundColor(.secondary)
                    if let seen = ble.topSeen[g], seen > 0 {
                        Text("fastest seen now: " + String(format: "%.1f", seen))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct SpeedLimitsView: View {
    @ObservedObject var ble: BLEManager
    @AppStorage(Keys.aboveStockAccepted) private var aboveStockAccepted = false
    @AppStorage("chosenModel") private var chosenModel = ""
    @State private var showWarning = false

    private var isVolpam: Bool {
        if ble.connected != nil { return ble.kind == .volpam }
        return chosenModel == "volpam"
    }

    var body: some View {
        List {
            if isVolpam {
                Section {
                    Label("Needs a capture from the Volpam", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text("The Volpam uses its own code, and its speed-limit command hasn't been captured yet, so this app sends nothing to it here. To add it: turn on Bluetooth logging, change the speed in the Volpam's own app, do the 3-button capture and send it.")
                        .font(.callout).foregroundColor(.secondary)
                }
            } else {
                Section {
                    Text("Pick a speed and tap Set. The app sends one command only when you tap Set, nothing automatic, no retries. Under each mode you see what the scooter actually accepted (from its reply).")
                        .font(.callout)
                    Text("Above your stock limit may be refused: on Nov 9 the 365 app asked for 32 km/h in Sport and the scooter answered 31 (kept 19 mph).")
                        .font(.caption).foregroundColor(.orange)
                    if !ble.canControl {
                        Text(ble.connected == nil ? "Connect to your J078 first (Connect tab)." : "This device isn't on the J078 protocol, so nothing is sent.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section {
                    if aboveStockAccepted {
                        Label("Above-stock speeds unlocked", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Button("Lock back to stock") { aboveStockAccepted = false }
                    } else {
                        Button {
                            showWarning = true
                        } label: {
                            Label("Allow speeds above stock...", systemImage: "lock.open")
                        }
                        Text("Until you accept the warning, each slider stops at that mode's stock limit.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } header: {
                    Text("Above stock")
                }

                ForEach([Gear.sport, Gear.drive, Gear.eco, Gear.walk]) { g in
                    SpeedLimitRow(ble: ble, gear: g, aboveStock: aboveStockAccepted)
                }
            }
        }
        .navigationTitle("Speed limits")
        .alert("Above your normal limit", isPresented: $showWarning) {
            Button("I understand", role: .destructive) { aboveStockAccepted = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SpeedLimitText.warning)
        }
    }
}

enum SpeedLimitText {
    static let warning = "Speeds above your scooter's normal limit may be declined by the scooter. Running too high can overheat or damage the motor, controller or battery, and is less safe. Wear a helmet. I understand."
    static let minKmh = 6
    static let maxKmh = 45

    static func both(_ kmh: Int, _ gear: Gear) -> String {
        return "\(Gear.mph(for: gear, kmh: kmh)) mph · \(kmh) km/h"
    }
}

struct SpeedLimitRow: View {
    @ObservedObject var ble: BLEManager
    let gear: Gear
    let aboveStock: Bool
    @State private var want: Double = -1

    private var stock: Int { gear.capturedLimitKmh }
    private var current: Int { ble.limitsKmh[gear] ?? stock }
    private var top: Int { aboveStock ? SpeedLimitText.maxKmh : max(stock, SpeedLimitText.minKmh) }
    private var wantKmh: Int {
        let v = want < 0 ? current : Int(want.rounded())
        return min(max(v, SpeedLimitText.minKmh), top)
    }

    var body: some View {
        Section {
            HStack {
                Image(systemName: gear.icon).foregroundColor(gear.color)
                Text(gear.name).bold()
                Spacer()
                Text(gear.limitWriteVerified ? "verified" : "experimental")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(gear.limitWriteVerified ? Color.green.opacity(0.25) : Color.orange.opacity(0.25))
                    .cornerRadius(6)
            }
            Text("Scooter now: " + SpeedLimitText.both(current, gear) + (ble.limitsLive.contains(gear) ? " (live)" : " (Nov 9 capture)"))
                .font(.caption.monospacedDigit()).foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(SpeedLimitText.both(wantKmh, gear))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundColor(wantKmh > stock ? .orange : .primary)
                    Spacer()
                    Button("Set") {
                        ble.setSpeedLimit(gear, kmh: wantKmh)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(gear.color)
                    .disabled(!ble.canControl)
                }
                Slider(value: Binding(get: { Double(wantKmh) }, set: { want = $0 }),
                       in: Double(SpeedLimitText.minKmh)...Double(max(top, SpeedLimitText.minKmh + 1)), step: 1)
                    .tint(gear.color)
                    .disabled(top <= SpeedLimitText.minKmh)
                HStack {
                    Text("\(SpeedLimitText.minKmh) km/h").font(.caption2)
                    Spacer()
                    Text("stock \(stock) km/h").font(.caption2)
                    Spacer()
                    Text("\(top) km/h").font(.caption2)
                }
                .foregroundColor(.secondary)
                if wantKmh > stock {
                    Text("Above stock: the scooter may refuse it.")
                        .font(.caption).foregroundColor(.orange)
                }
            }

            if let asked = ble.limitRequested[gear] {
                ResultLine(gear: gear, asked: asked, accepted: ble.limitAccepted[gear])
            }
        } footer: {
            if !gear.limitWriteVerified {
                Text("Experimental: the \(gear.name) code (BD BE AB \(String(format: "%02X", gear.limitByte)) [km/h]) follows the pattern, it wasn't seen in your capture. Sport (A2) is the checked one.")
            }
        }
    }
}

struct ResultLine: View {
    let gear: Gear
    let asked: Int
    let accepted: Int?
    private var experimental: Bool { !gear.limitWriteVerified }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Asked: " + SpeedLimitText.both(asked, gear))
                .font(.callout.monospacedDigit())
            if let got = accepted {
                Text("Scooter accepted: " + SpeedLimitText.both(got, gear))
                    .font(.callout.bold().monospacedDigit())
                    .foregroundColor(got == asked ? .green : .orange)
                if got != asked {
                    Text("scooter declined, kept \(Gear.mph(for: gear, kmh: got)) mph")
                        .font(.callout.bold())
                        .foregroundColor(.red)
                }
            } else {
                Text(experimental ? "No answer from the scooter yet. If none comes, this mode's code may be wrong." : "Waiting for the scooter's answer...")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
