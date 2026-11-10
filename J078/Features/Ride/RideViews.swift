import SwiftUI
import MapKit
import UIKit

// v4.2 screens. Every one of them has a screen test in ViewTests/NewScreenTests42.swift.

// MARK: - Ride stats (free)

struct RideStatsView: View {
    @ObservedObject var trips: TripManager
    @ObservedObject var garage = GarageStore.shared
    @EnvironmentObject var themes: ThemeStore

    private var mph: Bool { UnitPref.mph(themes) }

    var body: some View {
        let all = RideTotalsMath.totals(trips.trips)
        List {
            if let c = trips.current {
                let st = c.stats
                Section(header: Text("This ride"), footer: Text(c.source == "simulation" ? "SIMULATED ride." : "")) {
                    row("Ride time", TripMath.format(Date().timeIntervalSince(c.start)))
                    row("Moving time", TripMath.format(st.movingTime))
                    row("Max speed", UnitPref.speed(st.maxKmh, mph: mph))
                    row("Average (moving)", UnitPref.speed(st.avgMovingKmh, mph: mph))
                    row("Distance (estimated)", UnitPref.distance(st.distanceKm, mph: mph))
                }
            }
            Section(header: Text("All rides"), footer: Text("Distance is ESTIMATED from speed × time between samples (gaps over 2 s are skipped). It is not the scooter's odometer.")) {
                row("Rides", "\(all.rides)")
                row("Distance (estimated)", UnitPref.distance(all.distanceKm, mph: mph))
                row("Moving time", TripMath.format(all.movingTime))
                row("Top speed", UnitPref.speed(all.maxKmh, mph: mph))
                row("Average speed", UnitPref.speed(all.avgKmh, mph: mph))
                row("Longest ride (estimated)", UnitPref.distance(all.longestKm, mph: mph))
            }
            if !garage.scooters.isEmpty {
                Section("Per vehicle") {
                    ForEach(garage.scooters) { s in
                        let t = RideTotalsMath.totals(garage.state.trips(trips.trips, for: s.id))
                        HStack(spacing: 12) {
                            ScooterAvatar(scooter: s, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.subheadline.weight(.semibold))
                                Text("\(t.rides) rides · \(UnitPref.distance(t.distanceKm, mph: mph)) est. · top \(UnitPref.speed(t.maxKmh, mph: mph))")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ride stats")
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary).monospacedDigit() }
    }
}

// MARK: - Speed alert (free)

struct SpeedAlertSettingsView: View {
    @ObservedObject var hub = RideHub.shared
    @EnvironmentObject var themes: ThemeStore
    private var mph: Bool { UnitPref.mph(themes) }

    /// The threshold in the unit on screen, whole numbers.
    private var shownValue: Binding<Int> {
        Binding(get: {
            let v = mph ? Units.kmhToMph(hub.alertKmh) : hub.alertKmh
            return v.isFinite ? Int(v.rounded()) : 20
        }, set: { n in
            let k = mph ? Units.mphToKmh(Double(n)) : Double(n)
            hub.alertKmh = max(3, min(120, k))
        })
    }

    var body: some View {
        Form {
            Section(footer: Text("Your own reminder: the phone buzzes and beeps once when you go over this speed, and again only after you slow down below it. It doesn't change anything on the scooter.")) {
                Toggle(isOn: $hub.alertOn) { Label("Speed alert", systemImage: "bell.badge") }
                Stepper(value: shownValue, in: (mph ? 2 : 3)...(mph ? 70 : 110)) {
                    HStack { Text("Alert over"); Spacer(); Text("\(shownValue.wrappedValue) \(mph ? "mph" : "km/h")").foregroundColor(.secondary).monospacedDigit() }
                }
            }
            Section("How") {
                Toggle("Haptic", isOn: $hub.alertHaptic)
                Toggle("Sound", isOn: $hub.alertSound)
                Button { hub.fireAlert() } label: { Label("Test the alert", systemImage: "play.circle") }
                if !HapticsPref.on { Text("Haptics are off in More > App settings.").font(.footnote).foregroundColor(.secondary) }
            }
            if hub.alertsThisSession > 0 {
                Section("This session") {
                    HStack { Text("Alerts"); Spacer(); Text("\(hub.alertsThisSession)").foregroundColor(.secondary) }
                }
            }
        }
        .navigationTitle("Speed alert")
    }
}

// MARK: - Ride timer with laps (free)

struct RideTimerView: View {
    @ObservedObject var hub = RideHub.shared
    @EnvironmentObject var themes: ThemeStore

    var body: some View {
        VStack(spacing: 18) {
            TimelineView(.periodic(from: Date(), by: 0.1)) { ctx in
                VStack(spacing: 6) {
                    Text(RideTimer.format(hub.timer.elapsed(at: ctx.date)))
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("Lap \(hub.timer.laps.count + 1) · " + RideTimer.format(hub.timer.currentLap(at: ctx.date)))
                        .font(.title3).foregroundColor(.secondary).monospacedDigit()
                }
            }
            .padding(.top, 24)
            HStack(spacing: 14) {
                Button {
                    if hub.timer.isRunning { hub.timer.lap(at: Date()) } else { hub.timer.reset() }
                } label: {
                    Text(hub.timer.isRunning ? "Lap" : "Reset").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.bordered)
                .disabled(!hub.timer.hasStarted)
                Button {
                    if hub.timer.isRunning { hub.timer.pause(at: Date()) } else { hub.timer.start(at: Date()) }
                    if HapticsPref.on { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                } label: {
                    Text(hub.timer.isRunning ? "Pause" : (hub.timer.hasStarted ? "Resume" : "Start")).font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(hub.timer.isRunning ? .orange : themes.accent)
            }
            .padding(.horizontal, DS.pad)
            List {
                ForEach(Array(hub.timer.laps.enumerated().reversed()), id: \.offset) { i, t in
                    HStack {
                        Text("Lap \(i + 1)")
                        if t == hub.timer.bestLap && hub.timer.laps.count > 1 { Text("BEST").font(.caption2.weight(.heavy)).foregroundColor(.green) }
                        Spacer()
                        Text(RideTimer.format(t)).monospacedDigit().foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Ride timer")
    }
}

// MARK: - Share card (free)

struct RideShareCard: View {
    let trip: Trip
    let mph: Bool
    let accent: Color

    var body: some View {
        let s = trip.stats
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("HACKTHESCOOT").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(accent)
                Spacer()
                Text(trip.start.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 14)).foregroundColor(.white.opacity(0.6))
            }
            Text(trip.scooterName).font(.system(size: 22, weight: .semibold)).foregroundColor(.white).lineLimit(1)
            Text(UnitPref.distance(s.distanceKm, mph: mph))
                .font(.system(size: 64, weight: .bold, design: .rounded)).foregroundColor(.white).minimumScaleFactor(0.5).lineLimit(1)
            Text("estimated distance").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            HStack(spacing: 0) {
                cell("TOP", UnitPref.speed(s.maxKmh, mph: mph))
                cell("AVG", UnitPref.speed(s.avgMovingKmh, mph: mph))
                cell("TIME", TripMath.format(s.movingTime))
            }
            if trip.source == "simulation" {
                Text("SIMULATED RIDE").font(.system(size: 12, weight: .bold)).foregroundColor(.purple)
            }
        }
        .padding(28)
        .frame(width: 360)
        .background(
            LinearGradient(colors: [Color(white: 0.10), Color.black], startPoint: .top, endPoint: .bottom)
        )
    }

    private func cell(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5))
            Text(v).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ShareCardRenderer {
    @MainActor
    static func render(trip: Trip, mph: Bool, accent: Color) -> URL? {
        let r = ImageRenderer(content: RideShareCard(trip: trip, mph: mph, accent: accent))
        r.scale = 3
        guard let img = r.uiImage, let png = img.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hackthescoot-ride-\(Int(trip.start.timeIntervalSince1970)).png")
        do { try png.write(to: url); return url } catch { return nil }
    }
}

struct ShareCardView: View {
    let trip: Trip
    @EnvironmentObject var themes: ThemeStore
    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                RideShareCard(trip: trip, mph: UnitPref.mph(themes), accent: themes.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if let u = url {
                    ShareLink(item: u) {
                        Label("Share image", systemImage: "square.and.arrow.up").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themes.accent)
                } else if failed {
                    Text("Couldn't make the image.").foregroundColor(.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding(DS.pad)
        }
        .navigationTitle("Share ride")
        .onAppear { make() }
    }

    private func make() {
        let u = ShareCardRenderer.render(trip: trip, mph: UnitPref.mph(themes), accent: themes.accent)
        url = u
        failed = u == nil
    }
}

// MARK: - Last parked here (free, opt-in)

private struct ParkPin: Identifiable {
    let id = 0
    let coord: CLLocationCoordinate2D
}

struct ParkedSpotView: View {
    @ObservedObject var spots = ParkedSpotStore.shared
    @ObservedObject var ble: BLEManager
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                                   span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))

    var body: some View {
        List {
            Section(footer: Text("Off unless you turn it on. When the scooter parks or turns off while the app is open, the phone saves where you are, using location only while the app is in use. It stays on this phone.")) {
                Toggle(isOn: $spots.enabled) { Label("Remember where I parked", systemImage: "mappin.and.ellipse") }
                if spots.enabled && (spots.authStatus == .denied || spots.authStatus == .restricted) {
                    Text("Location is off for HackTheScoot. Turn it on in iOS Settings > HackTheScoot > Location > While Using.")
                        .font(.footnote).foregroundColor(.orange)
                }
            }
            if let s = spots.spot {
                Section("Last parked") {
                    Map(coordinateRegion: $region, annotationItems: [ParkPin(coord: CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon))]) { p in
                        MapMarker(coordinate: p.coord, tint: .orange)
                    }
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                    .onAppear { region.center = CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon) }
                    Text("\(s.scooterName) · \(s.at.formatted(date: .abbreviated, time: .shortened)) · ±\(Int(s.accuracy.isFinite ? s.accuracy : 0)) m")
                        .font(.footnote).foregroundColor(.secondary)
                    if let u = spots.mapsURL { Link(destination: u) { Label("Directions in Maps", systemImage: "arrow.triangle.turn.up.right.diamond") } }
                    Button("Forget this spot", role: .destructive) { spots.clear() }
                }
            } else {
                Section { Text("No spot saved yet.").foregroundColor(.secondary) }
            }
            if spots.enabled {
                Section {
                    Button { spots.saveNow(scooterName: ble.connectedName) } label: { Label("Save my spot now", systemImage: "location") }
                    if let e = spots.lastError { Text(e).font(.footnote).foregroundColor(.secondary) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Last parked here")
    }
}

// MARK: - Long-press quick actions (free)

struct QuickActionsSheet: View {
    @ObservedObject var ble: BLEManager
    @EnvironmentObject var themes: ThemeStore
    var close: () -> Void

    private var gear: Gear? { ble.status?.gear }
    private var pin: String { Keychain.get("parkPIN") ?? "000000" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick actions").font(.title3.weight(.semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }
                    .accessibilityLabel("Close")
            }
            if (ble.status?.speed ?? 0) > 2 {
                Label("Moving: keep your eyes on the road", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundColor(.orange)
            }
            HStack(spacing: 12) {
                bigButton(title: (ble.status?.light ?? false) ? "Light off" : "Light on",
                          icon: (ble.status?.light ?? false) ? "lightbulb.fill" : "lightbulb",
                          on: ble.status?.light ?? false) { ble.setLight(!(ble.status?.light ?? false)) }
                bigButton(title: (ble.status?.parked ?? false) ? "Unpark" : "Park",
                          icon: "parkingsign.circle.fill",
                          on: ble.status?.parked ?? false) { ble.setPark(!(ble.status?.parked ?? false), pin: pin) }
                    .disabled(ble.busy != nil || pin.count != 6)
            }
            Text("Mode").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
            HStack(spacing: 8) {
                ForEach(Gear.allCases) { g in
                    Button { ble.setGear(g) } label: {
                        Text(g.name).font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(gear == g ? themes.accent : DS.card))
                            .foregroundColor(gear == g ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Switch to \(g.name)")
                }
            }
            if !ble.canControl {
                Text(ble.isActive ? (ble.kind == .volpam ? "Volpam controls are on the Controls tab." : "This vehicle is read-only here.") : "Connect your scooter first.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.pad)
        .disabled(!ble.canControl)
    }

    private func bigButton(title: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? themes.accent.opacity(0.85) : DS.card))
            .foregroundColor(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Maintenance reminders (free)

struct MaintenanceView: View {
    let scooterID: UUID
    @ObservedObject var trips: TripManager
    @ObservedObject var store = MaintenanceStore.shared
    @EnvironmentObject var themes: ThemeStore
    @State private var adding = false
    @State private var newName = ""
    @State private var newMiles = 100
    @State private var newDays = 30

    private var mph: Bool { UnitPref.mph(themes) }
    private var totalKm: Double { MaintenanceStore.totalKm(for: scooterID, trips: trips.trips) }

    var body: some View {
        let _ = store.revision
        let km = totalKm
        let items = store.list(for: scooterID, totalKm: km)
        List {
            Section(footer: Text("Distance comes from this vehicle's trips (estimated from speed × time), so it only counts rides the app recorded. Whichever comes first, distance or days, makes it due.")) {
                HStack { Text("Ridden so far (estimated)"); Spacer(); Text(UnitPref.distance(km, mph: mph)).foregroundColor(.secondary) }
            }
            Section("Reminders") {
                ForEach(items) { i in
                    let st = MaintenanceMath.status(i, totalKm: km, now: Date())
                    HStack(spacing: 12) {
                        Image(systemName: i.icon).frame(width: 26).foregroundColor(color(st))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.name)
                            Text(interval(i) + " · " + MaintenanceMath.remaining(i, totalKm: km, now: Date(), mph: mph))
                                .font(.caption).foregroundColor(st == .ok ? .secondary : color(st))
                        }
                        Spacer()
                        Button("Done") { markDone(i, items: items, km: km) }.buttonStyle(.bordered)
                    }
                }
                .onDelete { idx in
                    var l = items
                    l.remove(atOffsets: idx)
                    store.set(l, for: scooterID)
                }
            }
            Section {
                if adding {
                    TextField("e.g. Lube the folding hinge", text: $newName)
                    Stepper("Every \(newMiles) \(mph ? "mi" : "km")", value: $newMiles, in: 10...2000, step: 10)
                    Stepper("or every \(newDays) days", value: $newDays, in: 1...365)
                    Button("Add reminder") {
                        let km = mph ? Units.milesToKm(Double(newMiles)) : Double(newMiles)
                        var l = items
                        let n = newName.trimmingCharacters(in: .whitespaces)
                        l.append(MaintenanceItem(name: n.isEmpty ? "Maintenance" : String(n.prefix(40)), everyKm: km, everyDays: newDays, lastDone: Date(), kmAtLastDone: totalKm))
                        store.set(l, for: scooterID)
                        adding = false
                        newName = ""
                    }
                } else {
                    Button { adding = true } label: { Label("Add a reminder", systemImage: "plus") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Maintenance")
    }

    private func markDone(_ i: MaintenanceItem, items: [MaintenanceItem], km: Double) {
        var l = items
        if let k = l.firstIndex(where: { $0.id == i.id }) { l[k] = MaintenanceMath.markDone(i, totalKm: km, now: Date()) }
        store.set(l, for: scooterID)
        if HapticsPref.on { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func interval(_ i: MaintenanceItem) -> String {
        var p: [String] = []
        if let k = i.everyKm { p.append(mph ? String(format: "every %.0f mi", Units.kmToMiles(k)) : String(format: "every %.0f km", k)) }
        if let d = i.everyDays { p.append("\(d) days") }
        return p.joined(separator: " / ")
    }

    private func color(_ s: MaintenanceDue) -> Color {
        switch s {
        case .ok: return .green
        case .soon: return .orange
        case .due: return .red
        }
    }
}

// MARK: - Help / FAQ (free)

struct HelpView: View {
    private struct QA: Identifiable { let id: Int; let q: String; let a: String }
    private let faq: [QA] = [
        QA(id: 0, q: "It says connected but nothing changes", a: "Wait for \"Ready\" on the Dashboard. On the J078 the app sends the same hello, password and keep-alive as v3. If it stays stuck, open More > Packet logger, record 20 seconds, and share the file."),
        QA(id: 1, q: "Why can't I control my e-bike or Ninebot?", a: "Fardriver and Ninebot support is new and read-only: live data only. Controls unlock only after a Bluetooth capture from that exact vehicle proves what each command does. Motor-controller settings can damage hardware, so the app never guesses."),
        QA(id: 2, q: "How do I send a capture?", a: "Controls (or More) > Packet logger > Start. Use the vehicle's official app at the same time if you can, press the buttons you want supported one at a time, then Stop and Share."),
        QA(id: 3, q: "Is the distance real?", a: "It's estimated from speed × time between samples. It isn't the scooter's odometer."),
        QA(id: 4, q: "How do I go past the stock speed?", a: "Controls > Set speed limits. Above-stock values sit behind a one-time warning, and the scooter can still clamp what it accepts: the app shows what you asked for and what it accepted."),
        QA(id: 5, q: "Speed alert", a: "More > Speed alert. Pick a speed; the phone buzzes and beeps once when you pass it. It never changes the scooter."),
        QA(id: 6, q: "mph or km/h", a: "More > App settings > Units changes every screen."),
        QA(id: 7, q: "Quick actions", a: "Long-press the speed on the Dashboard (or tap the bolt) for light, park and mode."),
        QA(id: 8, q: "Where is my data?", a: "Trips, logs, maintenance and your parked spot stay on this phone. Nothing is uploaded."),
        QA(id: 9, q: "Pro", a: "Pro is in test mode. Safety, fault warnings, controls and speed limits are free and stay free."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(faq) { item in
                    DisclosureGroup {
                        Text(item.a).font(.subheadline).foregroundColor(.secondary).padding(.vertical, 4)
                    } label: {
                        Text(item.q).font(.subheadline.weight(.semibold))
                    }
                }
            }
            Section(footer: Text("Ride safe: wear a helmet, and check the brakes before riding.")) {
                NavigationLink("What works (evidence)") { EvidenceView() }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Help")
    }
}

// MARK: - App settings: units, accent colour, haptics, app icon (free)

struct AppSettingsView: View {
    @EnvironmentObject var themes: ThemeStore
    @AppStorage(HapticsPref.key) private var haptics = true
    @State private var icon = AppIcons.supported ? AppIcons.current : ""
    @State private var iconError: String?

    static let accents = ["#0A84FF", "#00E5FF", "#30D158", "#9CFF2E", "#FFD60A", "#FF9F0A", "#FF3B30", "#FF2D55", "#BF5AF2", "#E5E5EA"]

    var body: some View {
        Form {
            Section(header: Text("Units"), footer: Text("Changes the dashboard, trips, stats, alerts and share cards.")) {
                Picker("Units", selection: Binding(get: { themes.theme.units }, set: { u in
                    themes.theme.units = u
                    UserDefaults.standard.set(u, forKey: Keys.displayUnit)
                })) {
                    Text("Scooter's own").tag("scooter")
                    Text("mph").tag("mph")
                    Text("km/h").tag("kmh")
                }
                .pickerStyle(.segmented)
            }
            Section("Accent color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                    ForEach(AppSettingsView.accents, id: \.self) { hex in
                        Button { themes.theme.accent = hex } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 38, height: 38)
                                .overlay(Circle().stroke(Color.white, lineWidth: themes.theme.accent.uppercased() == hex ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Accent \(hex)")
                    }
                }
                .padding(.vertical, 6)
                ColorPicker("Custom", selection: Binding(get: { Color(hex: themes.theme.accent) }, set: { themes.theme.accent = $0.hexString }), supportsOpacity: false)
            }
            Section(footer: Text("Turns off every vibration in the app (speed alert, mode changes, connects). Sounds have their own switches.")) {
                Toggle(isOn: $haptics) { Label("Haptics", systemImage: "iphone.radiowaves.left.and.right") }
                NavigationLink { FeedbackSettingsView() } label: { Label("Per-event haptics and sounds", systemImage: "waveform") }
            }
            Section(header: Text("App icon"), footer: Text(iconError ?? "Some sideloading tools keep only the main icon; if a choice doesn't stick, that's why.")) {
                ForEach(AppIcons.choices) { c in
                    Button {
                        AppIcons.set(c.id) { err in
                            iconError = err
                            if err == nil { icon = c.id }
                        }
                    } label: {
                        HStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: c.preview)).frame(width: 30, height: 30)
                            Text(c.name).foregroundColor(.primary)
                            Spacer()
                            if icon == c.id { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                        }
                    }
                    .disabled(!AppIcons.supported)
                }
            }
        }
        .navigationTitle("App settings")
    }
}

// MARK: - Packet logger (Developer, free)

struct PacketLoggerView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var rec = PacketRecorder.shared
    @State private var url: URL?

    var body: some View {
        List {
            Section(footer: Text("Records every Bluetooth frame in and out (passwords masked) until you stop, then share the file. Use it to send a capture from a new scooter or e-bike so its controls can be unlocked. Recording never sends anything to the vehicle.")) {
                if rec.isRecording {
                    Button(role: .destructive) { rec.stop(); url = rec.exportURL() } label: { Label("Stop recording", systemImage: "stop.circle.fill") }
                } else {
                    Button { url = nil; rec.start(ble: ble) } label: { Label(rec.frames.isEmpty ? "Start recording" : "Start a new recording", systemImage: "record.circle") }
                }
                HStack { Text("Frames"); Spacer(); Text("\(rec.frames.count) (in \(rec.rxCount), out \(rec.txCount))").foregroundColor(.secondary).monospacedDigit() }
                if let s = rec.startedAt { HStack { Text("Started"); Spacer(); Text(s.formatted(date: .omitted, time: .standard)).foregroundColor(.secondary) } }
                HStack { Text("Device"); Spacer(); Text(ble.isActive ? (ble.isSimulating ? "Simulator" : ble.connectedName) : "Not connected").foregroundColor(.secondary).lineLimit(1) }
            }
            if !rec.isRecording && !rec.frames.isEmpty {
                Section {
                    if let u = url {
                        ShareLink(item: u) { Label("Share capture (.txt)", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { url = rec.exportURL() } label: { Label("Prepare file", systemImage: "doc") }
                    }
                }
            }
            Section("Latest frames") {
                ForEach(Array(rec.frames.suffix(40).reversed())) { e in
                    Text(e.exportLine).font(.system(size: 11, design: .monospaced)).lineLimit(3)
                }
                if rec.frames.isEmpty { Text("Nothing recorded yet.").foregroundColor(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Packet logger")
    }
}

// MARK: - Experimental / unknown vehicles: live data only (free)

struct ReadOnlyLiveView: View {
    @ObservedObject var ble: BLEManager

    var body: some View {
        Group {
            Section(header: Text("\(ble.adapter.displayName) · \(ble.adapter.level.rawValue)"),
                    footer: Text("Live data only. Needs a capture to unlock controls: record one with the packet logger and send it in.")) {
                Label("Read-only: nothing is sent to this vehicle.", systemImage: "lock.shield")
                    .font(.subheadline)
                NavigationLink { PacketLoggerView(ble: ble) } label: {
                    Label(PacketRecorder.shared.isRecording ? "Packet logger (recording)" : "Start the packet logger", systemImage: "record.circle")
                }
                .simultaneousGesture(TapGesture().onEnded { if !PacketRecorder.shared.isRecording { PacketRecorder.shared.start(ble: ble) } })
            }
            if let f = ble.fardriver {
                FardriverLiveSection(t: f)
            }
            if let n = ble.ninebot {
                Section(header: Text("Ninebot live data (unverified)"),
                        footer: Text("Only plain (unencrypted) replies can be read. New Ninebot firmware is encrypted, and most Ninebots only answer when asked, which needs a write, so this may stay empty until a capture.")) {
                    row("Speed", n.speedKmh.map { String(format: "%.1f km/h", $0) } ?? "--")
                    row("Battery", n.batteryPercent.map { "\($0) %" } ?? "--")
                    row("Odometer", n.odometerKm.map { String(format: "%.1f km", $0) } ?? "--")
                    row("Range", n.rangeKm.map { String(format: "%.1f km", $0) } ?? "--")
                    row("Frames read / encrypted", "\(n.validFrames) / \(n.encryptedFrames)")
                }
            }
            Section("Bluetooth") {
                row("Packets / s", String(format: "%.1f", ble.rxPerSecond.isFinite ? ble.rxPerSecond : 0))
                row("Services", ble.serviceList.isEmpty ? "--" : ble.serviceList.map { ServiceID.short($0) }.joined(separator: ", "))
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary).monospacedDigit() }
    }
}

struct FardriverLiveSection: View {
    let t: FardriverTelemetry
    var body: some View {
        Section(header: Text("Fardriver live data (unverified)"),
                footer: Text("Decoded from the public, MIT-licensed Fardriver notes. Values are unverified until a capture is checked against the official app. Power is volts × amps, worked out here.")) {
            if let f = t.faults, !f.active.isEmpty {
                ForEach(f.active, id: \.self) { name in
                    Label(name, systemImage: "exclamationmark.triangle.fill").foregroundColor(.red)
                }
            }
            row("Battery", t.volts.map { String(format: "%.1f V", $0) } ?? "--")
            row("Current", t.amps.map { String(format: "%.1f A", $0) } ?? "--")
            row("Power", t.watts.map { String(format: "%.0f W", $0) } ?? "--")
            row("Charge", t.socPercent.map { "\($0) %" } ?? "--")
            row("Motor speed (raw, likely RPM)", t.motorSpeedRaw.map { "\($0)" } ?? "--")
            row("Gear (raw)", t.gear.map { "\($0)" } ?? "--")
            row("Motor temp", t.motorTempC.map { "\($0) °C" } ?? "--")
            row("Brake", t.faults.map { $0.brake ? "on" : "off" } ?? "--")
            row("Frames OK / rejected", "\(t.validFrames) / \(t.rejectedFrames)")
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary).monospacedDigit() }
    }
}
