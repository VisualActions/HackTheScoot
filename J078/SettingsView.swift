import SwiftUI
import UniformTypeIdentifiers

/// v4.0.1 "More" tab: the scooter list, look, app extras and tools in one place.
struct MoreView: View {
    @ObservedObject var ble: BLEManager
    @EnvironmentObject var themes: ThemeStore
    var chooseScooter: () -> Void
    @AppStorage(Keys.keepAwake) private var keepAwake = true
    @AppStorage(Keys.soundOn) private var soundOn = true
    @AppStorage(Keys.unitsSwapped) private var unitsSwapped = false
    @AppStorage(Keys.startSwapped) private var startSwapped = false
    @AppStorage(Keys.showDashControls) private var showDashControls = true
    @AppStorage(Keys.gaugeMaxAuto) private var gaugeMaxAuto = true
    @AppStorage(Keys.gaugeMax) private var gaugeMax = 30.0
    @ObservedObject var garage = GarageStore.shared
    @ObservedObject var store = StoreManager.shared
    @ObservedObject var rideHub = RideHub.shared

    var body: some View {
        NavigationView {
            List {
                Section("Scooter") {
                    NavigationLink { GarageView(ble: ble) } label: {
                        HStack(spacing: 12) {
                            if let a = garage.active { ScooterAvatar(scooter: a, size: 30) } else { Image(systemName: "car.2.fill") }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Garage")
                                Text(garage.active.map { "Active: \($0.name)" } ?? "Add your scooters").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(garage.scooters.count)").foregroundColor(.secondary)
                        }
                    }
                    NavigationLink { ConnectView(ble: ble) } label: {
                        HStack {
                            Label("Connect and my scooters", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            Text(ble.isActive ? (ble.isSimulating ? "Simulator" : ble.connectedName) : "").foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    Toggle(isOn: $ble.autoReconnect) { Label("Auto-connect", systemImage: "arrow.triangle.2.circlepath") }
                    Button(action: chooseScooter) { Label("Choose scooter model", systemImage: "scooter") }
                }
                Section("Ride") {
                    NavigationLink { SpeedAlertSettingsView() } label: {
                        HStack {
                            Label("Speed alert", systemImage: "bell.badge")
                            Spacer()
                            Text(rideHub.alertOn ? UnitPref.speed(rideHub.alertKmh, mph: UnitPref.mph(themes)) : "Off").foregroundColor(.secondary)
                        }
                    }
                    NavigationLink { RideTimerView() } label: { Label("Ride timer and laps", systemImage: "stopwatch") }
                    NavigationLink { RideStatsView(trips: TripManager.sharedForMore) } label: { Label("Ride stats", systemImage: "chart.line.uptrend.xyaxis") }
                    NavigationLink { ParkedSpotView(ble: ble) } label: { Label("Last parked here", systemImage: "mappin.and.ellipse") }
                }
                Section("Dashboard") {
                    NavigationLink { ThemeEditorView() } label: { Label("Theme and colors", systemImage: "paintpalette") }
                    NavigationLink { DashboardDesignerView() } label: { Label("Dashboard designer", systemImage: "square.grid.2x2") }
                    Toggle(isOn: $showDashControls) { Label("Mode buttons on the dashboard", systemImage: "hand.tap") }
                    Toggle(isOn: $keepAwake) { Label("Keep screen on", systemImage: "sun.max") }
                    Toggle(isOn: $gaugeMaxAuto) { Label("Gauge max: auto", systemImage: "gauge") }
                    if !gaugeMaxAuto {
                        Stepper(value: $gaugeMax, in: 10...80, step: 5) { Text("Gauge max: \(safeInt(gaugeMax))") }
                    }
                }
                Section(header: Text("HackTheScoot Pro"), footer: Text(Billing.testMode ? "Test mode: nothing here charges real money." : "")) {
                    NavigationLink { PaywallView() } label: {
                        HStack {
                            Label("Pro", systemImage: "star.circle")
                            Spacer()
                            Text(store.tier.name + (store.isTestUnlocked ? " (test)" : "")).foregroundColor(.secondary)
                        }
                    }
                    NavigationLink { TripAnalyticsView(trips: TripManager.sharedForMore) } label: { proLabel("Trip analytics", "chart.bar.xaxis", .tripAnalytics) }
                    NavigationLink { LogAnalysisView(ble: ble) } label: { proLabel("Log analysis", "waveform.path.ecg", .extendedLogAnalysis) }
                    NavigationLink { FrameDiffView() } label: { proLabel("Frame compare", "rectangle.split.2x1", .protocolWorkspace) }
                }
                Section("App") {
                    NavigationLink { AppSettingsView() } label: { Label("App settings (units, accent, haptics, icon)", systemImage: "gearshape") }
                    NavigationLink { HelpView() } label: { Label("Help and FAQ", systemImage: "questionmark.circle") }
                    Button { NotificationCenter.default.post(name: .hackTheScootShowOnboarding, object: nil) } label: { Label("Show the intro again", systemImage: "hand.wave") }
                    NavigationLink { StartupStudioView() } label: { Label("Startup Studio", systemImage: "sparkles") }
                    NavigationLink { FeedbackSettingsView() } label: { Label("Haptics and sounds", systemImage: "waveform") }
                    Toggle(isOn: $soundOn) { Label("Sound when a scooter connects", systemImage: "speaker.wave.2") }
                }
                Section(header: Text("J078 unverified mappings"), footer: Text("If mph and km/h (or zero and kick start) come out backwards on your scooter, flip these.")) {
                    Toggle("Swap units value", isOn: $unitsSwapped)
                    Toggle("Swap start-mode value", isOn: $startSwapped)
                }
                Section("Tools") {
                    NavigationLink { DiagnosticsView(ble: ble) } label: { Label("Diagnostics", systemImage: "stethoscope") }
                    NavigationLink { DevLabView(ble: ble) } label: { Label("Developer Lab", systemImage: "terminal") }
                    NavigationLink { LogPage(ble: ble) } label: { Label("Packet log", systemImage: "list.bullet.rectangle") }
                    NavigationLink { PacketLoggerView(ble: ble) } label: { Label("Packet logger (record a capture)", systemImage: "record.circle") }
                    NavigationLink { DeveloperSettingsView() } label: { Label("Developer settings (test unlock)", systemImage: "hammer") }
                }
                Section(header: Text("About"), footer: Text("Trips, logs and settings stay on this phone unless you export them. Nothing is uploaded.")) {
                    HStack(spacing: 12) {
                        LogoView().frame(width: 44, height: 44)
                        VStack(alignment: .leading) {
                            Text("HackTheScoot").font(.headline)
                            Text("v\(AppInfo.version) beta").foregroundColor(.secondary)
                        }
                    }
                    NavigationLink("What works (evidence)") { EvidenceView() }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
        }
        .navigationViewStyle(.stack)
    }
}

private extension MoreView {
    func proLabel(_ title: String, _ icon: String, _ f: ProFeature) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if !store.allows(f) { Image(systemName: "lock.fill").font(.caption).foregroundColor(.secondary) }
        }
    }
}

enum AppInfo {
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "4"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
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
            ProThemesSection()
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


/// v4.1: the Pro theme pack, shown under the free presets.
struct ProThemesSection: View {
    @EnvironmentObject var themes: ThemeStore
    @ObservedObject var store = StoreManager.shared
    var body: some View {
        Section(header: Text("Pro themes"), footer: Text(store.allows(.premiumThemes) ? "Part of Pro." : "Six extra looks with Pro. The presets above are free.")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(DashTheme.proPresets, id: \.name) { p in
                        Button {
                            if store.allows(.premiumThemes) { themes.theme = p }
                        } label: {
                            HStack(spacing: 4) {
                                if !store.allows(.premiumThemes) { Image(systemName: "lock.fill").font(.caption2) }
                                Text(p.name)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Color(hex: p.accent).opacity(0.25)))
                        }
                        .disabled(!store.allows(.premiumThemes))
                    }
                }
            }
            if !store.allows(.premiumThemes) {
                NavigationLink { PaywallView(highlight: .premiumThemes) } label: { Text("See Pro") }
            }
        }
    }
}
