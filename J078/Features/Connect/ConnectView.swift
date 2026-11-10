import SwiftUI

struct ConnectView: View {
    @ObservedObject var ble: BLEManager
    @EnvironmentObject var themes: ThemeStore

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        ConnectionPill(ble: ble)
                        Spacer()
                        Text(ble.bluetoothState).font(.caption).foregroundColor(.secondary)
                    }
                    if ble.isActive {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ble.connectedName.isEmpty ? "Device" : ble.connectedName).font(.headline)
                            Text("\(ble.adapter.displayName) · \(ble.adapter.level.rawValue)").font(.subheadline).foregroundColor(.secondary)
                            Text(ble.adapter.level.blurb).font(.caption).foregroundColor(.secondary)
                        }
                        Button(ble.isSimulating ? "Stop simulator" : "Disconnect", role: .destructive) { ble.disconnect() }
                    }
                    Toggle("Auto-reconnect", isOn: $ble.autoReconnect)
                }

                if !ble.savedScooters.isEmpty {
                    Section("Saved") {
                        ForEach(ble.savedScooters) { s in
                            Button { ble.connectSaved(s) } label: {
                                VStack(alignment: .leading) {
                                    Text(s.name)
                                    Text("\(s.kind.short) · last \(s.lastConnected.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .swipeActions { Button("Forget", role: .destructive) { ble.forget(s) } }
                        }
                    }
                }

                Section(header: Text("Nearby"), footer: Text("Names can be changed or spoofed, so a name alone never enables controls: the scooter's own Bluetooth services have to match after connecting.")) {
                    HStack {
                        Button(ble.isScanning ? "Stop scan" : "Scan") { ble.isScanning ? ble.stopScan() : ble.startScan() }
                            .buttonStyle(.borderedProminent).tint(themes.accent)
                        Spacer()
                        Toggle("Likely scooters only", isOn: $ble.showOnlyScooters).labelsHidden()
                        Text("Scooters only").font(.caption)
                    }
                    if ble.isScanning && ble.visibleDevices.isEmpty {
                        HStack { ProgressView(); Text("Looking...").foregroundColor(.secondary) }
                    }
                    ForEach(ble.visibleDevices) { d in
                        Button { ble.connect(d) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).foregroundColor(.primary)
                                    Text(d.confidence == .none ? "Unknown, read-only" : "Likely \(d.adapterName) (\(confidenceText(d.confidence)))")
                                        .font(.caption).foregroundColor(d.confidence == .none ? .secondary : .green)
                                }
                                Spacer()
                                SignalBars(bars: SignalStrength.from(rssi: d.rssi).bars)
                                Text("\(d.rssi)").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text("Offline simulator"), footer: Text("Plays real-format J078 packets through the real parser, clearly marked SIMULATED. Simulation never sends Bluetooth commands.")) {
                    ForEach(ScooterSimulator.Scenario.allCases) { sc in
                        Button { ble.startSimulation(sc) } label: {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(sc.rawValue)
                                    if ble.simulationScenario == sc { Spacer(); Text("RUNNING").font(.caption2.weight(.heavy)).foregroundColor(.purple) }
                                }
                                Text(sc.blurb).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connect")
        }
        .navigationViewStyle(.stack)
    }

    private func confidenceText(_ c: MatchConfidence) -> String {
        switch c {
        case .servicesAndName: return "services + name"
        case .services: return "services"
        case .nameOnly: return "name only, unconfirmed"
        case .none: return "no match"
        }
    }
}
