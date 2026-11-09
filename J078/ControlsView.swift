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
                        Label("Speed limits (coming soon)", systemImage: "lock")
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

    var body: some View {
        List {
            Section {
                Text("Coming soon. Changing the limits needs one more Bluetooth capture: if the 365 app has a speed setting, change it once while logging, then send the log. Until that command is seen on your scooter, this app sends nothing here.")
                    .font(.callout)
            }
            Section("Current limits (read only)") {
                ForEach(Gear.allCases) { g in
                    let kmh = ble.limitsKmh[g] ?? g.capturedLimitKmh
                    VStack(alignment: .leading) {
                        HStack {
                            Text(g.name).bold()
                            Spacer()
                            Text("\(Gear.mph(for: g, kmh: kmh)) mph · \(kmh) km/h").monospacedDigit()
                        }
                        Slider(value: .constant(Double(kmh)), in: 0...40, step: 1)
                            .disabled(true)
                    }
                }
            }
        }
        .navigationTitle("Speed limits")
    }
}
