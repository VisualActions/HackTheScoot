import SwiftUI

/// Health indicator built ONLY from things we can actually observe.
enum DiagnosticHealth {
    case good, warning, problem, idle
    static func evaluate(phase: ConnectionPhase, lastRx: Date?, rejected: Int, rssi: Int?, simulated: Bool, now: Date) -> (DiagnosticHealth, [String]) {
        var notes: [String] = []
        guard phase.isLinked || simulated else { return (.idle, ["Not connected"]) }
        var h = DiagnosticHealth.good
        if let t = lastRx {
            let age = now.timeIntervalSince(t)
            if age > 3 { h = .problem; notes.append(String(format: "No data for %.0f s", age)) }
        } else {
            h = .warning; notes.append("No data received yet")
        }
        if !simulated, let r = rssi, r < -85 { if h == .good { h = .warning }; notes.append("Weak signal (\(r) dBm)") }
        if rejected > 0 { notes.append("\(rejected) malformed packet(s) rejected safely") }
        if notes.isEmpty { notes.append("Receiving data normally") }
        return (h, notes)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var ble: BLEManager
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let (health, notes) = DiagnosticHealth.evaluate(phase: ble.phase, lastRx: ble.lastRxTime, rejected: ble.rejectedFrames,
                                                        rssi: ble.rssi, simulated: ble.isSimulating, now: now)
        List {
            Section("Status") {
                HStack {
                    Circle().fill(color(health)).frame(width: 14, height: 14)
                    Text(title(health)).font(.headline)
                    if ble.isSimulating { Spacer(); Text("SIMULATED").font(.caption.weight(.heavy)).foregroundColor(.purple) }
                }
                ForEach(notes, id: \.self) { Text($0).font(.footnote).foregroundColor(.secondary) }
            }
            Section("Connection") {
                row("State", ble.phase.label)
                row("Signal", ble.isSimulating ? "n/a (simulated)" : SignalStrength.from(rssi: ble.rssi).rawValue + (ble.rssi.map { " · \($0) dBm" } ?? ""))
                row("Packets / s", String(format: "%.1f", ble.rxPerSecond))
                row("Last data", ble.lastRxTime.map { String(format: "%.1f s ago", now.timeIntervalSince($0)) } ?? "never")
                row("Interruptions", "\(ble.interruptions)")
                row("Rejected packets", "\(ble.rejectedFrames)")
            }
            Section("Device") {
                row("Name", ble.connectedName.isEmpty ? "--" : ble.connectedName)
                row("Detected model", ble.adapter.displayName)
                row("Protocol family", ble.adapter.family)
                row("Compatibility", ble.adapter.level.rawValue)
                row("Firmware version", "Unavailable (no version reply is known)")
                row("Riding mode", ble.status?.gear?.name ?? ble.volpamStatus?.mode.map { $0.name + " (experimental)" } ?? "--")
                row("Error flags", "None confirmed (no fault reply has been captured)")
            }
            Section("Not shown on purpose") {
                ForEach(UnverifiedData.allCases, id: \.self) { u in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(u.rawValue + ": unavailable").font(.subheadline)
                        Text(u.why).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Section("Latest status packet") {
                if let s = ble.status {
                    Text(Proto.hex(s.decoded)).font(.caption.monospaced()).textSelection(.enabled)
                    Text(Proto.label(s.decoded)).font(.caption)
                } else if let v = ble.volpamStatus {
                    Text(Proto.hex(v.raw)).font(.caption.monospaced()).textSelection(.enabled)
                } else {
                    Text("none yet").foregroundColor(.secondary)
                }
            }
            Section("Services and characteristics") {
                if ble.characteristicsInfo.isEmpty { Text("none").foregroundColor(.secondary) }
                ForEach(ble.characteristicsInfo, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
            }
            Section("What this adapter knows") {
                ForEach(Capability.allCases) { c in
                    HStack {
                        Text(c.label).font(.subheadline)
                        Spacer()
                        Text(ble.adapter.evidence(c).label).font(.caption.weight(.semibold)).foregroundColor(evColor(ble.adapter.evidence(c)))
                    }
                }
                ForEach(ble.adapter.evidenceNotes, id: \.self) { Text($0).font(.caption).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Diagnostics")
        .onReceive(tick) { now = $0 }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) { Text(k); Spacer(); Text(v).foregroundColor(.secondary).multilineTextAlignment(.trailing) }
            .font(.subheadline)
    }
    private func color(_ h: DiagnosticHealth) -> Color {
        switch h { case .good: return .green; case .warning: return .yellow; case .problem: return .red; case .idle: return .gray }
    }
    private func title(_ h: DiagnosticHealth) -> String {
        switch h { case .good: return "Healthy link"; case .warning: return "Check"; case .problem: return "Link problem"; case .idle: return "Idle" }
    }
    private func evColor(_ e: Evidence) -> Color {
        switch e { case .verified: return .green; case .experimental: return .orange; case .unverified: return .yellow; case .unsupported: return .secondary }
    }
}
