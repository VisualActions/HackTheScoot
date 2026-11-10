import SwiftUI
import UIKit

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct DebugView: View {
    @ObservedObject var ble: BLEManager
    var body: some View {
        NavigationStack {
            DevLabView(ble: ble)
        }
    }
}

struct LogPage: View {
    @ObservedObject var ble: BLEManager
    @State private var shareItem: ShareItem?
    @State private var follow = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Keep-alives", isOn: $ble.logKeepAlives)
                Toggle("Every status", isOn: $ble.logEveryStatus)
            }
            .font(.caption)
            .padding(.horizontal)
            ScrollViewReader { proxy in
                List(ble.log) { entry in
                    LogRow(entry: entry)
                        .id(entry.id)
                }
                .listStyle(.plain)
                .onChange(of: ble.log.count) { _ in
                    if follow, let last = ble.log.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button(follow ? "Pause" : "Follow") {
                    follow.toggle()
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("Clear") {
                    ble.clearLog()
                }
                Button {
                    if let url = ble.exportLogFile() {
                        shareItem = ShareItem(url: url)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
    }
}

struct LogRow: View {
    let entry: LogEntry

    private var kindColor: Color {
        switch entry.kind {
        case .rx: return .green
        case .tx: return .orange
        case .info: return .secondary
        case .blocked: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(LogEntry.timeFormatter.string(from: entry.time))
                    .foregroundColor(.secondary)
                Text(entry.kind.rawValue)
                    .bold()
                    .foregroundColor(kindColor)
                Text(entry.channel)
                    .bold()
            }
            .font(.caption2.monospaced())

            if !entry.raw.isEmpty {
                Text("air " + Proto.hex(entry.raw))
                    .font(.caption.monospaced())
                    .foregroundColor(entry.decoded == nil ? .primary : .secondary)
                    .textSelection(.enabled)
            }
            if let d = entry.decoded {
                Text("dec " + Proto.hex(d))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.caption)
                    .foregroundColor(entry.kind == .info ? Color.primary : Color.blue)
            }
        }
        .padding(.vertical, 1)
    }
}

struct StatusBytesPage: View {
    @ObservedObject var ble: BLEManager

    private func meaning(_ i: Int) -> String {
        switch i {
        case 0...3: return "header DB EB FA DB"
        case 4: return "flags: 02 light, 04 park, 10 start mode, 01 units"
        case 5: return "gear: 08 walk, 10 eco, 20 drive, 40 sport"
        case 6: return "unknown (0)"
        case 7: return "speed x10, high byte"
        case 8: return "speed x10, low byte"
        case 10: return "battery %? (UNVERIFIED)"
        case 23...26: return "odometer? (UNVERIFIED)"
        default: return ""
        }
    }

    var body: some View {
        List {
            if let s = ble.status {
                Section("Decoded") {
                    row("Speed", String(format: "%.1f", s.speed) + " (scooter's unit)")
                    row("Gear", s.gear?.name ?? String(format: "unknown %02X", s.gearCode))
                    row("Flags", String(format: "%02X", s.flags) + " light \(s.light ? 1 : 0) park \(s.parked ? 1 : 0) start \(s.startModeBit ? 1 : 0) units \(s.unitsBit ? 1 : 0)")
                    row("Byte 10 (battery? UNVERIFIED, raw)", s.byte10Raw.map { "\($0)" } ?? "--")
                    row("Bytes 23-26 (odometer? UNVERIFIED, raw)", Proto.hex(s.bytes23to26Raw))
                    if let t = ble.lastStatusTime {
                        row("Last status", LogEntry.timeFormatter.string(from: t))
                    }
                }
                Section("All \(s.decoded.count) bytes (decoded)") {
                    ForEach(Array(s.decoded.enumerated()), id: \.offset) { item in
                        HStack(alignment: .top) {
                            Text(String(format: "[%02d]", item.offset)).foregroundColor(.secondary)
                            Text(String(format: "%02X", item.element)).bold()
                            Text(String(format: "%3d", Int(item.element))).foregroundColor(.secondary)
                            Text(meaning(item.offset)).font(.caption).foregroundColor(.secondary)
                        }
                        .font(.caption.monospaced())
                    }
                }
            } else {
                Section {
                    Text("No status frame yet. Connect to the J078 and it shows up here (~15 per second).")
                        .foregroundColor(.secondary)
                }
            }
            Section("Checks") {
                row("Scramble self-test", Proto.scrambleSelfTestOK ? "OK" : "FAILED")
                row("Password reply", ble.passwordState)
                row("Protocol", ble.kind.label)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
            Spacer()
            Text(v).font(.callout.monospaced()).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

/// UIKit share sheet (save the .txt to Files, AirDrop it, etc.).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
