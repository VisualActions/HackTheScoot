import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var ble: BLEManager
    @EnvironmentObject var themes: ThemeStore
    var chooseScooter: () -> Void
    @AppStorage(Keys.keepAwake) private var keepAwake = true
    @AppStorage(Keys.soundOn) private var soundOn = true
    @AppStorage(Keys.unitsSwapped) private var unitsSwapped = false
    @AppStorage(Keys.startSwapped) private var startSwapped = false

    var body: some View {
        NavigationView {
            Form {
                Section("Dashboard") {
                    NavigationLink("Theme and colors") { ThemeEditorView() }
                    NavigationLink("Dashboard designer") { DashboardDesignerView() }
                    Toggle("Keep screen awake on the dashboard", isOn: $keepAwake)
                }
                Section("App") {
                    NavigationLink("Startup Studio") { StartupStudioView() }
                    NavigationLink("Haptics and sounds") { FeedbackSettingsView() }
                    Toggle("Sound when a scooter connects", isOn: $soundOn)
                }
                Section("Tools") {
                    NavigationLink("Diagnostics") { DiagnosticsView(ble: ble) }
                    NavigationLink("Developer Lab") { DevLabView(ble: ble) }
                    Button("Choose scooter model...", action: chooseScooter)
                }
                Section(header: Text("J078 unverified mappings"), footer: Text("If mph and km/h (or zero and kick start) come out backwards on your scooter, flip these.")) {
                    Toggle("Swap units value", isOn: $unitsSwapped)
                    Toggle("Swap start-mode value", isOn: $startSwapped)
                }
                Section(header: Text("About"), footer: Text("Trips, logs and settings stay on this phone unless you export them. Nothing is uploaded.")) {
                    HStack { LogoView().frame(width: 44, height: 44); VStack(alignment: .leading) { Text("HackTheScoot").font(.headline); Text("v4 beta").foregroundColor(.secondary) } }
                    NavigationLink("What works (evidence)") { EvidenceView() }
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
    }
}

struct EvidenceView: View {
    var body: some View {
        List {
            ForEach(AdapterRegistry.all.map { $0 as ProtocolAdapter } + [AdapterRegistry.generic], id: \.id) { a in
                Section(header: Text("\(a.displayName) · \(a.level.rawValue)")) {
                    ForEach(Capability.allCases.filter { a.evidence($0) != .unsupported }) { c in
                        HStack { Text(c.label); Spacer(); Text(a.evidence(c).label).foregroundColor(.secondary) }.font(.subheadline)
                    }
                    ForEach(a.evidenceNotes, id: \.self) { Text($0).font(.caption).foregroundColor(.secondary) }
                }
            }
        }
        .navigationTitle("Evidence")
    }
}

struct ThemeEditorView: View {
    @EnvironmentObject var themes: ThemeStore
    @State private var exporting: ShareItem?
    @State private var importing = false
    @State private var importMessage: String?

    private func colorBinding(_ kp: WritableKeyPath<DashTheme, String>) -> Binding<Color> {
        Binding(get: { Color(hex: themes.theme[keyPath: kp]) }, set: { themes.theme[keyPath: kp] = $0.hexString })
    }

    var body: some View {
        Form {
            Section("Presets") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(DashTheme.presets, id: \.name) { p in
                            Button { themes.theme = p } label: {
                                Text(p.name).padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(Color(hex: p.accent).opacity(0.25)))
                            }
                        }
                    }
                }
            }
            Section("Gauge") {
                Picker("Design", selection: $themes.theme.gauge) {
                    Text("Classic").tag("classic"); Text("Digital").tag("digital"); Text("Performance").tag("performance")
                }
                .pickerStyle(.segmented)
                Picker("Font", selection: $themes.theme.font) {
                    Text("Rounded").tag("rounded"); Text("Mono").tag("mono"); Text("Normal").tag("normal")
                }
                VStack(alignment: .leading) {
                    Text("Animation intensity: \(Int(themes.theme.animationIntensity * 100))%")
                    Slider(value: $themes.theme.animationIntensity, in: 0...1)
                }
                Picker("Units", selection: $themes.theme.units) {
                    Text("Scooter's").tag("scooter"); Text("mph").tag("mph"); Text("km/h").tag("kmh")
                }
            }
            Section("Colors") {
                ColorPicker("Accent", selection: colorBinding(\.accent), supportsOpacity: false)
                ColorPicker("Background", selection: colorBinding(\.background), supportsOpacity: false)
                Picker("Background style", selection: $themes.theme.backgroundStyle) {
                    Text("Gradient").tag("gradient"); Text("Solid").tag("solid"); Text("Black").tag("black")
                }
                Picker("Appearance", selection: $themes.theme.appearance) {
                    Text("Dark").tag("dark"); Text("Light").tag("light"); Text("System").tag("system")
                }
            }
            Section(header: Text("Riding mode colors"), footer: Text("Defaults: walk muted white, eco green, drive blue, sport red. A short color sweep plays when the mode changes.")) {
                Toggle("Color the gauge by mode", isOn: $themes.theme.useModeColor)
                ColorPicker("Walk", selection: colorBinding(\.walkColor), supportsOpacity: false)
                ColorPicker("Eco", selection: colorBinding(\.ecoColor), supportsOpacity: false)
                ColorPicker("Drive", selection: colorBinding(\.driveColor), supportsOpacity: false)
                ColorPicker("Sport", selection: colorBinding(\.sportColor), supportsOpacity: false)
                Toggle("Night riding (dim, no flashing)", isOn: $themes.theme.night)
            }
            Section(footer: Text("Theme files hold colors and layout only: no scooter names, IDs, passwords or rides.")) {
                Button("Export theme (JSON)") {
                    if let d = themes.theme.exportJSON() {
                        let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(themes.theme.name.replacingOccurrences(of: " ", with: "-")).hts-theme.json")
                        if (try? d.write(to: u)) != nil { exporting = ShareItem(url: u) }
                    }
                }
                Button("Import theme...") { importing = true }
                if let m = importMessage { Text(m).font(.footnote) }
                Button("Reset to default", role: .destructive) { themes.theme = DashTheme() }
            }
        }
        .navigationTitle("Theme")
        .sheet(item: $exporting) { ShareSheet(items: [$0.url]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            guard case .success(let url) = r else { importMessage = "Import cancelled"; return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: url) else { importMessage = "Couldn't read the file"; return }
            switch DashTheme.importJSON(d) {
            case .success(let t): themes.theme = t; importMessage = "Imported \(t.name). Missing fields got defaults."
            case .failure(let e): importMessage = "Not a HackTheScoot theme (\(e))"
            }
        }
    }
}

struct DashboardDesignerView: View {
    @EnvironmentObject var themes: ThemeStore
    @State private var name = ""
    var body: some View {
        List {
            Section(header: Text("Tiles (drag to reorder)"), footer: Text("Battery and odometer tiles show \"unavailable\" until there is evidence for them.")) {
                ForEach(themes.theme.tiles, id: \.self) { t in Text(DashTile(rawValue: t)?.title ?? t) }
                    .onMove { themes.theme.tiles.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { themes.theme.tiles.remove(atOffsets: $0) }
                let missing = DashTile.allCases.filter { !themes.theme.tiles.contains($0.rawValue) }
                if !missing.isEmpty {
                    Menu("Add tile") { ForEach(missing) { t in Button(t.title) { themes.theme.tiles.append(t.rawValue) } } }
                }
            }
            Section("Layout") {
                Picker("Layout", selection: $themes.theme.layout) {
                    Text("Standard").tag("standard"); Text("Minimal").tag("minimal"); Text("Focus (gauge only)").tag("focus")
                }
            }
            Section("Saved layouts") {
                HStack {
                    TextField("Name", text: $name)
                    Button("Save") {
                        var t = themes.theme
                        t.name = name.isEmpty ? "Layout \(themes.layouts.items.count + 1)" : String(name.prefix(40))
                        themes.layouts.save(t); name = ""
                    }
                }
                ForEach(themes.layouts.items, id: \.name) { t in
                    Button(t.name) { themes.theme = t }
                }
                .onDelete { themes.layouts.items.remove(atOffsets: $0) }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Designer")
    }
}

struct FeedbackSettingsView: View {
    @State private var refresh = 0
    var body: some View {
        Form {
            ForEach(Feedback.Event.allCases) { e in
                Section(e.rawValue) {
                    Toggle("Haptic", isOn: Binding(get: { Feedback.shared.hapticOn(e) }, set: { UserDefaults.standard.set($0, forKey: e.hapticKey); refresh += 1 }))
                    Toggle("Sound", isOn: Binding(get: { Feedback.shared.soundOn(e) }, set: { UserDefaults.standard.set($0, forKey: e.soundKey); refresh += 1 }))
                }
            }
        }
        .id(refresh)
        .navigationTitle("Haptics and sounds")
    }
}
