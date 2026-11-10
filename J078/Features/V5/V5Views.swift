import SwiftUI
import UniformTypeIdentifiers

// v5.0 screens: compatibility checker, vehicle info, faults, battery/range estimate,
// backup/restore, what's new, legal (DRAFT), and the app log. All free.

// MARK: - Compatibility checker (free, spec phase 4)

struct CompatCheckerView: View {
    @State private var query = ""
    private var results: [CompatEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return CompatSeed.all }
        return CompatSeed.all.filter { ($0.manufacturer + " " + $0.model + " " + $0.note + " " + ($0.adapter ?? "")).lowercased().contains(q) }
    }

    var body: some View {
        List {
            Section(footer: Text("Compatibility database v\(CompatSeed.dbVersion). A brand being listed doesn't mean it can be controlled: only what has evidence from a real capture is. Nothing here is \"Full Support\" yet because nothing has passed every hardware test.")) {
                ForEach(results) { e in
                    NavigationLink { CompatDetailView(entry: e) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.displayName).font(.subheadline.weight(.semibold))
                            Text(e.level.rawValue).font(.caption).foregroundColor(CompatDetailView.color(e.level))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if results.isEmpty {
                    Text("Not in the database yet. It would start as read-only, and a capture can change that.").foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Brand or model")
        .navigationTitle("Compatibility")
    }
}

struct CompatDetailView: View {
    let entry: CompatEntry
    static func color(_ l: CompatibilityLevel) -> Color {
        switch l {
        case .full: return .green
        case .partial: return .blue
        case .diagnosticsOnly: return .teal
        case .experimental: return .orange
        case .unsupported: return .secondary
        }
    }
    var body: some View {
        List {
            Section {
                row("Manufacturer", entry.manufacturer)
                row("Model", entry.model)
                row("Support", entry.level.rawValue)
                row("Controller family", ControllerType.from(compatAdapter: entry.adapter).label)
            } footer: { Text(entry.level.blurb) }
            Section("Notes") { Text(entry.note).font(.subheadline) }
            Section(footer: Text("Speed settings stay at what the scooter itself accepts. HackTheScoot never flashes firmware.")) {
                row("Writes", entry.level == .partial || entry.level == .full ? "Only the verified ones" : "None (read-only)")
            }
            if entry.level != .partial && entry.level != .full, let b = BLEManager.current {
                Section { NavigationLink { CaptureGuideView(ble: b) } label: { Label("Help unlock it (capture tutorial)", systemImage: "lock.open") } }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.model)
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) { Text(k); Spacer(); Text(v).foregroundColor(.secondary).multilineTextAlignment(.trailing) }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Vehicle info / firmware (read-only)

struct VehicleInfoView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var garage = GarageStore.shared

    var body: some View {
        List {
            Section(header: Text("Connected vehicle"), footer: Text(ble.isActive ? ble.adapter.level.blurb : "Connect to see what the vehicle reports.")) {
                row("Name", ble.isActive ? (ble.isSimulating ? "Simulator" : ble.connectedName) : "Not connected")
                row("Adapter", ble.adapter.displayName)
                row("Support level", ble.adapter.level.rawValue)
                row("Identified by", "\(ble.matchConfidence)")
                row("Signal", ble.rssi.map { "\($0) dBm" } ?? "--")
            }
            Section(header: Text("Firmware and hardware"), footer: Text("Read from the standard Bluetooth Device Information service, if the vehicle has one. Reading never changes anything. The J078 and Volpam protocols don't report a firmware version, so it shows here only if the Bluetooth module shares it. Serial numbers are hidden.")) {
                let keys = ["Manufacturer", "Model number", "Firmware revision", "Hardware revision", "Software revision", "Serial number", "System ID"]
                ForEach(keys, id: \.self) { k in row(k, ble.deviceInfo[k] ?? "--") }
                Button { ble.readDeviceInfo() } label: { Label("Read device info", systemImage: "arrow.down.doc") }
                    .disabled(!ble.isActive || ble.isSimulating)
            }
            Section("Bluetooth services") {
                if ble.serviceList.isEmpty { Text("--").foregroundColor(.secondary) }
                ForEach(ble.serviceList, id: \.self) { s in Text(ServiceID.short(s)).font(.footnote.monospaced()) }
                row("Characteristics", "\(ble.characteristicsInfo.count)")
            }
            if let a = garage.active {
                Section("In your Garage") {
                    row("Vehicle", a.name)
                    row("Type", a.vehicleType.label)
                    row("Controller", a.controllerType.label)
                    row("Database entry", a.compat.displayName)
                }
            }
            Section("App") {
                row("HackTheScoot", AppInfo.version)
                row("Compatibility database", CompatSeed.dbVersion)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Vehicle info")
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) { Text(k); Spacer(); Text(v).foregroundColor(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled) }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Fault explanations

struct FaultListView: View {
    var body: some View {
        List {
            Section(header: Text("Fardriver controllers"), footer: Text(FaultCatalog.source)) {
                ForEach(FaultCatalog.fardriver) { f in
                    NavigationLink { FaultDetailView(fault: f) } label: {
                        HStack {
                            Text(f.title)
                            Spacer()
                            Text(f.severity.rawValue).font(.caption).foregroundColor(FaultDetailView.color(f.severity))
                        }
                    }
                }
            }
            Section(header: Text("Joyhis J078 and Volpam"), footer: Text("No fault codes have been decoded from these yet, so none are shown. HackTheScoot never makes one up.")) {
                Label("Nothing decoded yet", systemImage: "questionmark.circle").foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fault explanations")
    }
}

struct FaultDetailView: View {
    let fault: FaultInfo
    static func color(_ s: FaultInfo.Severity) -> Color {
        switch s { case .stop: return .red; case .check: return .orange; case .info: return .secondary }
    }
    var body: some View {
        List {
            Section {
                Label(fault.severity.rawValue, systemImage: fault.severity == .stop ? "hand.raised.fill" : "exclamationmark.triangle")
                    .foregroundColor(FaultDetailView.color(fault.severity))
            }
            Section("What it usually means") { Text(fault.meaning) }
            Section("What to do") { Text(fault.whatToDo) }
            Section(footer: Text(FaultCatalog.source)) { EmptyView() }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(fault.title)
    }
}

// MARK: - Battery and range ESTIMATE

struct BatteryRangeView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var garage = GarageStore.shared
    @EnvironmentObject var themes: ThemeStore
    @AppStorage("range.packNominal") private var packNominal = 48
    @AppStorage("range.manualPercent") private var manualPercent = 80.0
    @State private var fullRange: Double = 25

    private var mph: Bool { UnitPref.mph(themes) }
    private var rangeKey: String { "range.full." + (garage.activeID?.uuidString ?? "none") }

    /// Where the battery number comes from, best first.
    private var battery: (pct: Double, source: String) {
        if let f = ble.fardriver, let s = f.socPercent { return (Double(s), "Fardriver charge (unverified)") }
        if let f = ble.fardriver, let v = f.volts, let p = BatteryEstimate.percent(packVolts: v, nominal: packNominal) {
            return (Double(p), String(format: "estimated from %.1f V on a %d V pack", v, packNominal))
        }
        if let n = ble.ninebot, let b = n.batteryPercent { return (Double(b), "Ninebot battery (unverified)") }
        return (manualPercent, "the number you set below")
    }

    var body: some View {
        let b = battery
        let mode = ble.status?.gear?.name ?? ble.volpamStatus?.mode?.name
        let km = RangeEstimate.kmLeft(fullRangeKm: fullRange, batteryPercent: b.pct, mode: mode)
        List {
            Section(footer: Text("ESTIMATED. Wind, hills, weight, temperature and battery age all change real range a lot. Don't count on the last few miles.")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("About \(UnitPref.distance(km, mph: mph)) left").font(.title2.weight(.bold))
                    Text("Battery \(Int(b.pct.rounded()))%, from \(b.source)\(mode.map { ", \($0) mode" } ?? "")").font(.footnote).foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
            Section(header: Text("Full-charge range"), footer: Text("How far this vehicle goes on a full charge for you (the box number is usually optimistic). Saved per Garage vehicle.")) {
                Stepper(value: $fullRange, in: 5...200, step: mph ? Units.milesToKm(1) : 1) {
                    Text("Full charge: \(UnitPref.distance(fullRange, mph: mph))")
                }
                .onChange(of: fullRange) { UserDefaults.standard.set($0, forKey: rangeKey) }
            }
            Section(header: Text("Battery"), footer: Text("The J078 and Volpam battery readings aren't verified yet, so set it from the scooter's own display. Fardriver packs: pick the pack voltage so the volts can be turned into an estimated %.")) {
                VStack(alignment: .leading) {
                    Text("Battery now (manual): \(Int(manualPercent))%")
                    Slider(value: $manualPercent, in: 0...100, step: 5).accessibilityLabel("Battery percent")
                }
                Picker("Pack voltage", selection: $packNominal) {
                    ForEach(BatteryEstimate.packs.map { $0.nominal }, id: \.self) { n in Text("\(n) V").tag(n) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Battery and range")
        .onAppear {
            let v = UserDefaults.standard.double(forKey: rangeKey)
            fullRange = v > 0 ? v : 25
        }
    }
}

// MARK: - Backup / restore

struct BackupView: View {
    @EnvironmentObject var themes: ThemeStore
    @State private var includeTrips = true
    @State private var file: URL?
    @State private var importing = false
    @State private var pending: BackupBundle?
    @State private var message: String?

    var body: some View {
        Form {
            Section(header: Text("Back up"), footer: Text("One JSON file with your settings, Garage (names, models, colors, notes), maintenance, themes and layouts. Photos, passwords, PINs and the Pro test unlock are never included.")) {
                Toggle("Include trips (and GPS routes)", isOn: $includeTrips)
                Button { file = makeFile() } label: { Label("Make a backup file", systemImage: "externaldrive.badge.plus") }
                if let u = file { ShareLink(item: u) { Label("Save or share \(u.lastPathComponent)", systemImage: "square.and.arrow.up") } }
            }
            Section(header: Text("Restore"), footer: Text("Settings from the file replace the ones here. Trips are added, never deleted.")) {
                Button { importing = true } label: { Label("Restore from a backup file...", systemImage: "externaldrive.badge.checkmark") }
                if let p = pending {
                    Text("Backup from HackTheScoot \(p.appVersion), \(p.created.formatted(date: .abbreviated, time: .shortened)): \(p.settings.count) settings, \(p.trips?.count ?? 0) trips.")
                        .font(.footnote)
                    Button("Restore it now") { apply(p) }
                    Button("Cancel", role: .cancel) { pending = nil }
                }
                if let m = message { Text(m).font(.footnote).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Backup and restore")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            guard case .success(let url) = r else { message = "Restore cancelled"; return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: url) else { message = "Couldn't read the file"; return }
            switch BackupBundle.decode(d) {
            case .success(let b): pending = b; message = nil
            case .failure(let e): message = "Can't restore: \(e)"
            }
        }
    }

    private func makeFile() -> URL? {
        let trips = includeTrips ? TripManager.sharedForMore.trips : nil
        let b = BackupBundle.make(from: UserDefaults.standard.dictionaryRepresentation(), trips: trips, appVersion: AppInfo.version)
        guard let d = b.encoded() else { message = "Couldn't make the file"; return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("HackTheScoot-backup-\(f.string(from: Date())).json")
        do { try d.write(to: u); message = "Backup ready: \(b.settings.count) settings\(trips.map { ", \($0.count) trips" } ?? "")."; return u }
        catch { message = "Couldn't save: \(error.localizedDescription)"; return nil }
    }

    private func apply(_ b: BackupBundle) {
        for (k, v) in b.settings where BackupBundle.isAllowed(k) { UserDefaults.standard.set(v.plist, forKey: k) }
        var added = 0
        if let t = b.trips { added = TripManager.sharedForMore.importTrips(t) }
        GarageStore.shared.reload()
        MaintenanceStore.shared.reload()
        themes.reload()
        pending = nil
        message = "Restored \(b.settings.count) settings\(b.trips == nil ? "" : " and added \(added) trips"). Some settings apply the next time you open the app."
        AppJournal.shared.note("backup restored: \(b.settings.count) settings, \(added) trips")
    }
}

// MARK: - What's new

struct WhatsNewView: View {
    var onDone: (() -> Void)? = nil
    var body: some View {
        List {
            Section(header: Text("HackTheScoot \(WhatsNew.version)")) {
                ForEach(Array(WhatsNew.items.enumerated()), id: \.offset) { _, i in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: i.icon).font(.title3).frame(width: 30).foregroundColor(.accentColor).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.title).font(.subheadline.weight(.semibold))
                            Text(i.detail).font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
            Section(footer: Text("Nothing was removed or capped. Everything from 4.2 is still here. The full list is in CHANGELOG.md on GitHub.")) {
                if let d = onDone { Button("Got it") { d() }.frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("What's new")
        .onAppear { UserDefaults.standard.set(WhatsNew.version, forKey: WhatsNew.seenKey) }
    }
}

// MARK: - Privacy policy, terms (DRAFT) and open-source credits

struct LegalDocView: View {
    enum Doc { case privacy, terms, licenses }
    let doc: Doc

    private var title: String {
        switch doc { case .privacy: return "Privacy policy"; case .terms: return "Terms of use"; case .licenses: return "Open-source credits" }
    }

    private var sections: [(String, String)] {
        switch doc {
        case .privacy: return LegalText.privacy
        case .terms: return LegalText.terms
        case .licenses: return LegalText.licenses
        }
    }

    var body: some View {
        List {
            if doc != .licenses {
                Section {
                    Label("DRAFT: not final. It needs an adult (the publisher) and a legal review before HackTheScoot is published.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundColor(.orange)
                }
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, s in
                Section(s.0) { Text(s.1).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
    }
}

enum LegalText {
    static let privacy: [(String, String)] = [
        ("The short version", "Scooter Bluetooth data stays on your phone. There are no ads, no tracking and no data selling. This beta has no accounts and sends nothing to any server."),
        ("Who we are", "HackTheScoot's publisher (to be filled in: the adult account holder or a company), with a contact email (to be filled in)."),
        ("Data kept only on your phone", "Bluetooth packets and logs, trips and ride stats, optional GPS routes (only if you turn them on), your parked spot (only if you turn it on), themes, settings and your Garage. None of it is uploaded. It leaves your phone only when you export or share a file yourself."),
        ("Location", "Used only if you turn on GPS routes or \"last parked here\", and only while the app is open. Never uploaded."),
        ("Captures you send", "A capture is a file you choose to share (GitHub, email, AirDrop). Captures can contain a vehicle password: the app masks the ones it can recognise, and you should check before posting publicly. GitHub issues are public."),
        ("Payments", "This beta is in TEST mode: no real money. When real payments exist, Apple handles App Store purchases and Stripe handles web purchases. We never see card numbers."),
        ("Crash logs", "Kept on your phone only (More > App log). Shared only if you share them."),
        ("Children", "Not directed at children under 13. (Wording to be set at legal review.)"),
        ("Your rights", "Everything is on your phone, so deleting the app deletes it. If accounts or sync are added later, this policy will say how to get, fix or delete your data (GDPR / CCPA)."),
        ("Changes and contact", "We'll update this page if anything changes. Contact: to be filled in."),
    ]

    static let terms: [(String, String)] = [
        ("Safety first", "Ride legally and wear a helmet. Don't use the app while riding: the dashboard is for a quick glance on a mounted phone."),
        ("What the app does and doesn't do", "HackTheScoot doesn't flash firmware or modify controllers. Speed settings are sent only to vehicles with verified commands, and the vehicle can still refuse or clamp them. Settings above stock sit behind a warning, and riding faster than your local law allows is on you."),
        ("Compatibility is information, not a promise", "Support levels (Full, Partial, Diagnostics Only, Experimental, Unsupported) describe the evidence we have. Experimental and unknown vehicles are read-only."),
        ("Not affiliated", "We're not affiliated with Joyhis, Volpam, Segway-Ninebot, Xiaomi, Fardriver, Minimotors, KuKirin or any other brand. Names are used only to say what works."),
        ("Warranty", "Using third-party apps may affect your vehicle maker's warranty. Check with them."),
        ("Subscriptions", "Pro is TEST MODE in this beta. Real prices, trial and renewal terms, cancellation and refunds will be written here before anything is sold. Safety, fault warnings, controls and compatibility info stay free."),
        ("Acceptable use", "Only connect to vehicles you own or have permission to use."),
        ("No warranty", "The app is provided as is. Liability limits: to be set at legal review."),
        ("Contact", "To be filled in."),
    ]

    static let licenses: [(String, String)] = [
        ("HackTheScoot", "Our own code. Protocol work decoded from Credence's own Bluetooth captures. No vendor code is included."),
        ("Fardriver notes", "jackhumbert/fardriver-controllers, MIT License, Copyright (c) Jack Humbert. Used for facts (frame layout, address table, CRC parameters, field names). No code copied."),
        ("Segway-Ninebot BLE protocol docs", "by NootNooot, Apache-2.0 (nootnooot.codeberg.page/segway-ninebot-ble). Used for facts (frame format, checksum, registers). No code copied."),
        ("Not used", "No code from scooterhacking repositories (NinebotCrypto is AGPL, most others have no license)."),
        ("Apple", "Apple's public Bluetooth logging profile and sysdiagnose instructions are linked, not copied."),
    ]
}

// MARK: - App log (crash-safe journal)

struct AppLogView: View {
    @State private var text = AppJournal.shared.journalText()
    @State private var crashed = AppJournal.shared.lastSessionEndedUnexpectedly

    var body: some View {
        List {
            if crashed {
                Section(footer: Text("If it happened while riding or connecting, share this log so it can be fixed.")) {
                    Label("Last time, HackTheScoot closed unexpectedly.", systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Button("Dismiss") { AppJournal.shared.dismissCrashNotice(); crashed = false }
                }
            }
            Section(footer: Text("A small log of what the app did (connects, phases, captures), saved as it happens so it survives a crash. On this phone only, passwords masked.")) {
                ShareLink(item: AppJournal.shared.journalURL) { Label("Share the app log", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { AppJournal.shared.clearJournal(); text = "" } label: { Label("Clear", systemImage: "trash") }
            }
            Section("Latest") {
                let lines = text.split(separator: "\n").suffix(150).reversed()
                if lines.isEmpty { Text("Empty").foregroundColor(.secondary) }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Text(String(l)).font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("App log")
    }
}
