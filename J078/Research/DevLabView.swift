import SwiftUI

struct DevLabView: View {
    @ObservedObject var ble: BLEManager
    @State private var share: ShareItem?
    @State private var askAdvanced = false

    var body: some View {
        List {
            Section(header: Text("Mode"), footer: Text("Read-only is the default: nothing you do on these pages writes to the scooter. Manual sending needs the advanced warning, and each send is classified: unknown, firmware or bootloader frames are always blocked.")) {
                HStack {
                    Text(ble.advancedWritesUnlocked ? "Manual writes UNLOCKED" : "Read-only").font(.headline)
                        .foregroundColor(ble.advancedWritesUnlocked ? .orange : .green)
                    Spacer()
                    if ble.advancedWritesUnlocked {
                        Button("Lock") { ble.advancedWritesUnlocked = false }
                    } else {
                        Button("Unlock...") { askAdvanced = true }
                    }
                }
            }
            Section("Live") {
                NavigationLink("Packet monitor (search)") { PacketMonitorView(ble: ble) }
                NavigationLink("Status byte inspector") { StatusBytesPage(ble: ble) }
                NavigationLink("Characteristics / UUIDs") { UUIDListView(ble: ble) }
                Toggle("Log keep-alives", isOn: $ble.logKeepAlives)
                Toggle("Log every status frame", isOn: $ble.logEveryStatus)
                Button("Export log") { if let u = ble.exportLogFile() { share = ShareItem(url: u) } }
                Button("Clear log", role: .destructive) { ble.clearLog() }
            }
            Section("Offline tools") {
                NavigationLink("Packet decoder") { DecoderView() }
                NavigationLink("Compare two captures") { CompareView() }
                NavigationLink("Protocol self-tests") { SelfTestView() }
                NavigationLink("LCD startup research") { LCDResearchView() }
            }
            Section(header: Text("Device identification (read-only)"), footer: Text("Forcing a protocol only changes how incoming bytes are read. Controls still need that protocol's own channels to be found.")) {
                Picker("Read as", selection: Binding(get: { ble.kind }, set: { ble.setKind($0) })) {
                    ForEach(ScooterKind.allCases) { k in Text(k.label).tag(k) }
                }
                .disabled(!ble.phase.isLinked)
            }
            Section("Advanced (writes)") {
                NavigationLink("Terminal") { TerminalView(ble: ble) }.disabled(!ble.advancedWritesUnlocked)
                NavigationLink("Explore a byte") { ExperimentalView(ble: ble) }.disabled(!ble.advancedWritesUnlocked)
            }
        }
        .navigationTitle("Developer Lab")
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        .alert("Unlock manual writes?", isPresented: $askAdvanced) {
            Button("I understand, unlock", role: .destructive) { ble.advancedWritesUnlocked = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Manual frames can change scooter settings. Only verified frames and experimental frames you confirm are sent; unknown, firmware and bootloader frames are always blocked. No fuzzing, no scanning. Do this standing still.")
        }
    }
}

struct PacketMonitorView: View {
    @ObservedObject var ble: BLEManager
    @State private var query = ""
    @State private var dir = "all"
    var body: some View {
        let rows = ble.log.suffix(1500).filter { e in
            (dir == "all" || e.kind.rawValue == dir) && e.matches(query)
        }
        VStack(spacing: 0) {
            Picker("", selection: $dir) {
                Text("All").tag("all"); Text("RX").tag("RX"); Text("TX").tag("TX"); Text("Blocked").tag("XX")
            }
            .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 6)
            List(rows.reversed()) { e in LogRow(entry: e) }
                .listStyle(.plain)
        }
        .searchable(text: $query, prompt: "hex bytes, channel or note")
        .navigationTitle("Packets (\(rows.count))")
    }
}

struct UUIDListView: View {
    @ObservedObject var ble: BLEManager
    var body: some View {
        List {
            Section("Services") { ForEach(ble.serviceList, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) } }
            Section("Characteristics") { ForEach(ble.characteristicsInfo, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) } }
            Section("Writable") { Text(ble.writableNames.joined(separator: ", ")).font(.caption.monospaced()) }
        }
        .navigationTitle("UUIDs")
    }
}

struct DecoderView: View {
    @State private var text = "F7 5C 1A 28 9E 90 E7"
    var body: some View {
        Form {
            Section(footer: Text("Paste bytes exactly as they came over the air. Nothing is sent.")) {
                TextEditor(text: $text).font(.body.monospaced()).frame(minHeight: 90)
            }
            Section("Decoded") {
                if let b = CaptureTools.parseHex(text) {
                    ForEach(Array(CaptureTools.explain(b).enumerated()), id: \.offset) { Text($0.element).font(.footnote.monospaced()).textSelection(.enabled) }
                } else {
                    Text("Not valid hex").foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Decoder")
    }
}

struct CompareView: View {
    @State private var a = ""
    @State private var b = ""
    var body: some View {
        Form {
            Section("Capture A (exported log text)") { TextEditor(text: $a).font(.caption.monospaced()).frame(minHeight: 80) }
            Section("Capture B") { TextEditor(text: $b).font(.caption.monospaced()).frame(minHeight: 80) }
            let ca = CaptureTools.parseExportedLog(a), cb = CaptureTools.parseExportedLog(b)
            let c = CaptureTools.compare(ca, cb)
            Section("Result: \(ca.count) vs \(cb.count) frames") {
                ForEach(c.onlyInA.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in Text("only A: \(k) ×\(v)").font(.caption.monospaced()) }
                ForEach(c.onlyInB.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in Text("only B: \(k) ×\(v)").font(.caption.monospaced()) }
                ForEach(c.inBoth.keys.sorted(), id: \.self) { k in Text("both: \(k) ×\(c.inBoth[k]!.0)/\(c.inBoth[k]!.1)").font(.caption.monospaced()).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Compare")
    }
}

struct SelfTestView: View {
    var body: some View {
        List(Array(CaptureTools.selfTests().enumerated()), id: \.offset) { _, t in
            HStack {
                Image(systemName: t.1 ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundColor(t.1 ? .green : .red)
                Text(t.0).font(.subheadline)
            }
        }
        .navigationTitle("Self-tests")
    }
}

/// Research only: a phone-side model of the J078 LCD. Nothing here is sent.
struct LCDResearchView: View {
    @State private var on = Set<Int>()
    @State private var digit = 8
    var body: some View {
        List {
            Section(footer: Text("Our original goal was a custom startup on the J078's own LCD. What we know: the 365 app never sent anything that changes the LCD in any capture, the display and controller look like one unit on the same Bluetooth link, and no firmware-update or bootloader path has been identified. HackTheScoot does NOT send display, firmware, flash or bootloader commands, and won't until a recoverable update path is proven on spare hardware.")) {
                Text("Status: research only").font(.headline)
            }
            Section(header: Text("Segment simulator (approximate)"), footer: Text("A generic 7-segment model, not a measured copy of the J078's segment shapes. Tap segments to sketch a frame.")) {
                SevenSegment(on: $on).frame(height: 160)
                HStack {
                    Stepper("Show \(digit)", value: $digit, in: 0...9)
                        .onChange(of: digit) { d in on = SevenSegment.segments(for: d) }
                    Button("Clear") { on = [] }
                }
            }
            Section("Open questions") {
                Text("Does the dashboard have its own programmable MCU? Unknown (needs a teardown photo of the display board).")
                Text("Is there a recoverable firmware update mechanism? None found in the 365 app or the captures.")
                Text("Next safe step: photograph the display PCB chips; no writes.")
            }
            .font(.footnote)
        }
        .navigationTitle("LCD research")
    }
}

struct SevenSegment: View {
    @Binding var on: Set<Int>
    static func segments(for d: Int) -> Set<Int> {
        let map: [[Int]] = [[0,1,2,4,5,6],[2,5],[0,2,3,4,6],[0,2,3,5,6],[1,2,3,5],[0,1,3,5,6],[0,1,3,4,5,6],[0,2,5],[0,1,2,3,4,5,6],[0,1,2,3,5,6]]
        return Set(map[max(0, min(9, d))])
    }
    var body: some View {
        GeometryReader { g in
            let w = min(g.size.width, g.size.height * 0.6), h = w * 1.6, t = w * 0.14
            let x0 = (g.size.width - w) / 2
            let rects: [CGRect] = [
                CGRect(x: x0 + t, y: 0, width: w - 2 * t, height: t),
                CGRect(x: x0, y: t, width: t, height: h / 2 - 1.5 * t),
                CGRect(x: x0 + w - t, y: t, width: t, height: h / 2 - 1.5 * t),
                CGRect(x: x0 + t, y: h / 2 - t / 2, width: w - 2 * t, height: t),
                CGRect(x: x0, y: h / 2 + t / 2, width: t, height: h / 2 - 1.5 * t),
                CGRect(x: x0 + w - t, y: h / 2 + t / 2, width: t, height: h / 2 - 1.5 * t),
                CGRect(x: x0 + t, y: h - t, width: w - 2 * t, height: t),
            ]
            ZStack(alignment: .topLeading) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: t / 2)
                        .fill(on.contains(i) ? Color.cyan : Color.secondary.opacity(0.15))
                        .frame(width: rects[i].width, height: rects[i].height)
                        .offset(x: rects[i].minX, y: rects[i].minY)
                        .onTapGesture { if on.contains(i) { on.remove(i) } else { on.insert(i) } }
                }
            }
        }
    }
}
