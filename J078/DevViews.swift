import SwiftUI

/// Hex text -> bytes. Accepts "BD BE AB 00 01", "bdbeab0001", "0xBD,0xBE".
func parseHex(_ text: String) -> [UInt8]? {
    var s = text.uppercased()
    for junk in ["0X", ",", ":", "-", " ", "\n", "\t"] {
        s = s.replacingOccurrences(of: junk, with: junk == "0X" ? "" : "")
    }
    guard !s.isEmpty, s.count % 2 == 0 else { return nil }
    var out: [UInt8] = []
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
        out.append(b)
        i = j
    }
    return out
}

// MARK: - Terminal

struct TerminalView: View {
    @ObservedObject var ble: BLEManager
    @State private var input = ""
    @State private var scramble = true
    @State private var target = Proto.writePrefix
    @State private var history: [String] = []
    @State private var message = ""

    private let help = """
    type hex bytes and tap Send, e.g. BD BE AB 00 01
    Scramble ON = J078 frame (encoded like the 365 app). OFF = raw bytes.
    shortcuts: light on | light off | park on | park off | gear walk|eco|drive|sport | pw | hello | clear
    """

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        Text(help).foregroundColor(.gray)
                        ForEach(ble.log.suffix(400)) { e in
                            Text(line(e))
                                .foregroundColor(e.kind == .tx ? .orange : (e.kind == .rx ? .green : .gray))
                                .id(e.id)
                        }
                    }
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(Color.black)
                .onChange(of: ble.log.count) { _ in
                    if let last = ble.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            VStack(spacing: 6) {
                HStack {
                    Toggle("Scramble", isOn: $scramble).fixedSize()
                    Spacer()
                    Picker("To", selection: $target) {
                        ForEach(targets, id: \.self) { n in Text(n).tag(n) }
                    }
                }
                HStack {
                    Text(">").foregroundColor(.green)
                    TextField("BD BE AB 00 01", text: $input)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onSubmit(send)
                    Button("Send", action: send).buttonStyle(.borderedProminent)
                }
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundColor(.yellow)
                }
                if !history.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(history.suffix(8).reversed()), id: \.self) { h in
                                Button(h) { input = h }
                                    .font(.caption2.monospaced())
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(white: 0.1))
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var targets: [String] {
        var t = ble.writableNames
        if !t.contains(Proto.writePrefix) { t.insert(Proto.writePrefix, at: 0) }
        return t
    }

    private func line(_ e: LogEntry) -> String {
        var s = "\(LogEntry.timeFormatter.string(from: e.time)) \(e.kind.rawValue) \(e.channel) "
        if let d = e.decoded { s += Proto.hex(d) + "  (air " + Proto.hex(e.raw) + ")" }
        else if !e.raw.isEmpty { s += Proto.hex(e.raw) }
        if !e.note.isEmpty { s += "  " + e.note.replacingOccurrences(of: "\n", with: " / ") }
        return s
    }

    private func send() {
        let cmd = input.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        message = ""
        let lower = cmd.lowercased()
        let pin = UserDefaults.standard.string(forKey: Keys.password) ?? "000000"
        switch lower {
        case "clear": ble.clearLog()
        case "light on": ble.setLight(true)
        case "light off": ble.setLight(false)
        case "park on": ble.setPark(true, pin: pin)
        case "park off": ble.setPark(false, pin: pin)
        case "pw": ble.sendManual(Proto.password(pin), scramble: true, to: Proto.writePrefix, source: "terminal")
        case "hello": ble.sendManual(Proto.helloRaw, scramble: false, to: Proto.writePrefix, source: "terminal")
        default:
            if lower.hasPrefix("gear "), let g = Gear.allCases.first(where: { $0.name.lowercased() == String(lower.dropFirst(5)) }) {
                ble.setGear(g)
            } else if let bytes = parseHex(cmd) {
                if !ble.sendManual(bytes, scramble: scramble, to: target, source: "terminal") {
                    message = "not sent: connect first"
                }
            } else {
                message = "not hex (need pairs like BD BE AB 00 01) or a shortcut"
                return
            }
        }
        history.removeAll { $0 == cmd }
        history.append(cmd)
        input = ""
    }
}

// MARK: - Experimental: command explorer

struct ExperimentalView: View {
    @ObservedObject var ble: BLEManager
    @State private var cmd = 0x08
    @State private var value = 0x01
    @State private var before: [UInt8]?
    @State private var sentAt: Date?

    private let known: [Int: String] = [
        0x00: "front light (VERIFIED)",
        0x01: "units (UNVERIFIED 00/01)",
        0x02: "park (VERIFIED, needs password first)",
        0x05: "gear 01-04 (VERIFIED)",
        0x07: "start mode (UNVERIFIED 00/01)"
    ]

    private var frame: [UInt8] { Proto.command(UInt8(cmd), UInt8(value)) }

    var body: some View {
        List {
            Section {
                Text("Try one command at a time and watch what the scooter does. Unknown commands might change a setting, do nothing, or do something weird. Do it parked or with the wheel off the ground. Nothing here sends by itself.")
                    .font(.footnote)
            }
            Section("Command  BD BE AB [cmd] [value]") {
                Stepper(value: $cmd, in: 0...255) {
                    HStack {
                        Text("cmd").foregroundColor(.secondary)
                        Text(String(format: "%02X", cmd)).font(.body.monospaced().bold())
                        Text(known[cmd] ?? "unknown").font(.caption).foregroundColor(known[cmd] == nil ? .orange : .green)
                    }
                }
                Stepper(value: $value, in: 0...255) {
                    HStack {
                        Text("value").foregroundColor(.secondary)
                        Text(String(format: "%02X", value)).font(.body.monospaced().bold())
                    }
                }
                Text("decoded " + Proto.hex(frame)).font(.caption.monospaced())
                Text("on air  " + Proto.hex(Proto.encode(frame))).font(.caption.monospaced()).foregroundColor(.secondary)
                Button("Send once") {
                    before = ble.status?.decoded
                    sentAt = Date()
                    ble.sendManual(frame, scramble: true, to: Proto.writePrefix, source: "experiment")
                }
                .disabled(!ble.canControl)
            }
            Section("What changed in the status since Send") {
                if let b = before, let now = ble.status?.decoded, let t = sentAt {
                    let diffs = Array(zip(b, now).enumerated()).filter { $0.element.0 != $0.element.1 && $0.offset != 7 && $0.offset != 8 }
                    Text("sent at \(LogEntry.timeFormatter.string(from: t))").font(.caption).foregroundColor(.secondary)
                    if diffs.isEmpty {
                        Text("no status bytes changed (speed ignored)").foregroundColor(.secondary)
                    }
                    ForEach(diffs, id: \.offset) { d in
                        Text(String(format: "byte [%02d]: %02X -> %02X", d.offset, d.element.0, d.element.1))
                            .font(.callout.monospaced())
                    }
                    Button("Reset") { before = nil; sentAt = nil }
                } else {
                    Text("Send something to compare.").foregroundColor(.secondary)
                }
            }
            Section("Ideas to try") {
                Text("• cmd 03, 04, 06, 08+ with value 00 / 01 (lights? cruise? screen?)\n• value 02+ on known commands\n• If something works, export the log in Debug and send it, and it gets a real button.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Experimental")
    }
}

// MARK: - DJI-style "choose your scooter"

struct ScooterModel: Identifiable {
    let id: String
    let name: String
    let detail: String
    let kind: ScooterKind
    let icon: String
    let ready: Bool
}

enum ScooterModels {
    static let all: [ScooterModel] = [
        ScooterModel(id: "j078", name: "Joyhis J078", detail: "365 app · shows up as 365_scooter · full controls", kind: .j078, icon: "scooter", ready: true),
        ScooterModel(id: "volpam", name: "Volpam", detail: "F1F1 heartbeat path from v1 · log + heartbeat", kind: .volpam, icon: "bolt.car", ready: true),
        ScooterModel(id: "other", name: "Other scooter", detail: "Max Shot and others · log only for now, send a capture to add it", kind: .unknown, icon: "questionmark.circle", ready: false)
    ]

    static func find(_ id: String) -> ScooterModel? {
        return all.first { $0.id == id }
    }
}

struct ChooseScooterView: View {
    @AppStorage("chosenModel") private var chosenModel = ""
    var onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Which scooter do you have?")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .padding(.top, 30)
                Text("You can change this later in Settings. The app still auto-detects when it connects.")
                    .font(.callout).foregroundColor(.secondary)
                ForEach(ScooterModels.all) { m in
                    Button {
                        chosenModel = m.id
                        onDone()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: m.icon)
                                .font(.system(size: 34))
                                .frame(width: 60, height: 60)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(14)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.name).font(.title3.bold())
                                Text(m.detail).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: chosenModel == m.id ? "checkmark.circle.fill" : "chevron.right")
                                .foregroundColor(chosenModel == m.id ? .green : .secondary)
                        }
                        .padding()
                        .background(Color.white.opacity(chosenModel == m.id ? 0.14 : 0.06))
                        .cornerRadius(18)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}
