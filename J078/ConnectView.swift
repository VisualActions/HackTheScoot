import SwiftUI

struct ConnectView: View {
    @ObservedObject var ble: BLEManager
    @AppStorage("chosenModel") private var chosenModel = ""

    private var chosen: ScooterModel? { ScooterModels.find(chosenModel) }

    /// The chosen model's devices first, then other scooters, then everything else.
    private var sortedDevices: [FoundDevice] {
        let list = ble.visibleDevices
        guard let k = chosen?.kind, k != .unknown else { return list }
        return list.filter { $0.kind == k } + list.filter { $0.kind != k }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    if let m = chosen {
                        Label("Looking for: \(m.name)", systemImage: m.icon)
                    }
                    Text(ble.bluetoothState)
                    Text(ble.connectionStatus)
                    Toggle("Auto-connect to my last scooter", isOn: $ble.autoReconnect)
                }

                if ble.connected != nil {
                    connectedSection
                } else {
                    if !ble.savedScooters.isEmpty {
                        savedSection
                    }
                    scanSection
                    devicesSection
                }

                Section {
                    Text("Works with: J078 (shows up as \"365_scooter\", no pairing), the Volpam / F1F1 scooters from v1 (heartbeat path), and anything else in log-only mode. The app picks the protocol by name and Bluetooth service; you can change it by hand after connecting. Close the 365 app first, the scooter may only allow one connection.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Connect")
        }
    }

    private var connectedSection: some View {
        Group {
            Section("Connected") {
                HStack {
                    Text(ble.connectedName).font(.headline)
                    Spacer()
                    Text(ble.kind.short).foregroundColor(.secondary)
                }
                Picker("Protocol", selection: Binding(get: { ble.kind }, set: { ble.setKind($0) })) {
                    ForEach(ScooterKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                if ble.kind == .j078 {
                    Text(ble.j078Ready ? "J078 channel ready, keep-alive running" : "Looking for the J078 channel...")
                        .foregroundColor(ble.j078Ready ? .green : .orange)
                }
                Button("Disconnect", role: .destructive) {
                    ble.disconnect()
                }
            }
            if ble.kind == .volpam || ble.hasF1F1 {
                Section("Volpam / F1F1 (v1 path)") {
                    Toggle("Heartbeat (A5 02 FD 5A on F1F1)", isOn: Binding(
                        get: { ble.volpamHeartbeatOn },
                        set: { ble.setVolpamHeartbeat($0) }
                    ))
                    .disabled(!ble.hasF1F1)
                    Text("Heartbeats sent: \(ble.volpamHeartbeatsSent)")
                    Text("From reading the vendor app, not checked on a real Volpam yet. Watch the Debug log for replies.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Section("Services and characteristics") {
                if ble.characteristicsInfo.isEmpty {
                    Text("Discovering...").foregroundColor(.secondary)
                }
                ForEach(Array(ble.characteristicsInfo.enumerated()), id: \.offset) { item in
                    Text(item.element).font(.caption.monospaced())
                }
            }
        }
    }

    private var savedSection: some View {
        Section("My scooters") {
            ForEach(ble.savedScooters) { s in
                Button {
                    ble.connectSaved(s)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.name).font(.headline)
                            Text(s.kind.label).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "bolt.horizontal.circle")
                    }
                }
                .foregroundColor(.primary)
                .swipeActions {
                    Button("Forget", role: .destructive) { ble.forget(s) }
                }
            }
        }
    }

    private var scanSection: some View {
        Section("Scan") {
            Toggle("Only show scooters", isOn: $ble.showOnlyScooters)
            Button(ble.isScanning ? "Stop scan" : "Start scan") {
                if ble.isScanning {
                    ble.stopScan()
                } else {
                    ble.startScan()
                }
            }
            if ble.connectionStatus.hasPrefix("Connecting") {
                Button("Cancel connecting", role: .cancel) {
                    ble.disconnect()
                }
            }
        }
    }

    private var devicesSection: some View {
        Section("Devices (\(sortedDevices.count))") {
            ForEach(sortedDevices) { d in
                Button {
                    ble.connect(d)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(d.name).font(.headline)
                            if d.kind != .unknown {
                                Text(d.kind.short)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(d.kind == .j078 ? Color.green.opacity(0.3) : Color.blue.opacity(0.3))
                                    .cornerRadius(6)
                            }
                            Spacer()
                            Text("\(d.rssi) dBm").font(.caption).foregroundColor(.secondary)
                        }
                        if !d.advertisedServices.isEmpty {
                            Text("Services: " + d.advertisedServices.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        }
    }
}
