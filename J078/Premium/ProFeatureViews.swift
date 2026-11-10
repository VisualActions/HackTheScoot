import SwiftUI

/// Pro: analytics across all rides (or one Garage scooter).
struct TripAnalyticsView: View {
    @ObservedObject var trips: TripManager
    @ObservedObject var garage = GarageStore.shared
    @EnvironmentObject var themes: ThemeStore
    @State private var scope: String = "all"

    private var mph: Bool { themes.theme.units != "kmh" }

    private var selected: [Trip] {
        if scope == "all" { return trips.trips }
        guard let id = UUID(uuidString: scope) else { return trips.trips }
        return garage.state.trips(trips.trips, for: id)
    }

    var body: some View {
        ProGate(feature: .tripAnalytics) {
            let a = RideAnalytics.compute(selected)
            List {
                Section {
                    Picker("Scooter", selection: $scope) {
                        Text("All scooters").tag("all")
                        ForEach(garage.scooters) { s in Text(s.name).tag(s.id.uuidString) }
                    }
                }
                Section(header: Text("Totals"), footer: Text("Distance is estimated from speed samples, like on each ride.")) {
                    row("Rides", "\(a.rides)")
                    row("Distance (est.)", dist(a.distanceKm))
                    row("Riding time", TripMath.format(a.movingTime))
                    row("Average moving speed", speed(a.avgMovingKmh))
                }
                Section("Records") {
                    row("Top speed", speed(a.topKmh))
                    row("Longest ride", dist(a.longestKm))
                }
                Section("Time at each speed") {
                    if a.histogram.allSatisfy({ $0 == 0 }) {
                        Text("Ride a bit and this fills in.").foregroundColor(.secondary)
                    } else {
                        SpeedHistogram(bands: a.histogram, mph: mph).frame(height: 150)
                    }
                }
                Section("Time in each mode") {
                    if a.timeInMode.isEmpty { Text("No mode data yet.").foregroundColor(.secondary) }
                    ForEach(a.timeInMode.sorted(by: { $0.value > $1.value }), id: \.key) { k, v in row(k, TripMath.format(v)) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Trip analytics")
        }
    }

    private func speed(_ kmh: Double) -> String { mph ? String(format: "%.1f mph", Units.kmhToMph(kmh)) : String(format: "%.1f km/h", kmh) }
    private func dist(_ km: Double) -> String { mph ? String(format: "%.2f mi", Units.kmToMiles(km)) : String(format: "%.2f km", km) }
    private func row(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary).monospacedDigit() } }
}

struct SpeedHistogram: View {
    let bands: [TimeInterval]
    let mph: Bool
    var body: some View {
        let top = max(1, bands.max() ?? 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(bands.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(height: max(2, CGFloat(v / top) * 110))
                    Text(label(i)).font(.system(size: 9).monospacedDigit()).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityLabel("Time spent in each speed band")
    }
    private func label(_ i: Int) -> String {
        let lo = Double(i) * RideAnalytics.bandKmh
        return mph ? "\(safeInt(Units.kmhToMph(lo)))" : "\(safeInt(lo))"
    }
}

/// Pro: CSV + GPX for one ride. (The text summary export stays free on the ride page.)
struct TripProExportSection: View {
    let trip: Trip
    let mph: Bool
    @ObservedObject var store = StoreManager.shared
    @State private var share: ShareItem?

    var body: some View {
        Section(header: Text("Pro export"), footer: Text(store.allows(.dataExport) ? (trip.route == nil ? "GPX needs GPS to have been on during the ride." : "") : "CSV and GPX export are part of Pro.")) {
            if store.allows(.dataExport) {
                Button("Export CSV") { share = write(TripExport.csv(trip, mph: mph), ext: "csv") }
                Button("Export GPX") { if let g = TripExport.gpx(trip) { share = write(g, ext: "gpx") } }
                    .disabled(trip.route == nil)
            } else {
                NavigationLink { PaywallView(highlight: .dataExport) } label: { Label("CSV + GPX export (Pro)", systemImage: "lock.fill") }
            }
        }
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
    }

    private func write(_ text: String, ext: String) -> ShareItem? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hackthescoot-ride-\(Int(trip.start.timeIntervalSince1970)).\(ext)")
        do { try text.write(to: url, atomically: true, encoding: .utf8); return ShareItem(url: url) } catch { return nil }
    }
}

/// Pro: statistics over the packet log.
struct LogAnalysisView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var store = StoreManager.shared
    @State private var prefix = 4
    @State private var share: ShareItem?

    var body: some View {
        ProGate(feature: .extendedLogAnalysis) {
            let a = LogAnalysis.analyze(ble.frameRecords, prefix: prefix)
            List {
                Section(footer: Text("Read from the packet log on this phone. Nothing is sent to the scooter.")) {
                    row("Frames", "\(a.total)")
                    row("Time covered", TripMath.format(a.span))
                    row("Blocked by the write guard", "\(a.blocked)")
                    Stepper("Command = first \(prefix) bytes", value: $prefix, in: 1...8)
                }
                Section("Channels") {
                    if a.channels.isEmpty { Text("The log is empty. Connect or run the simulator.").foregroundColor(.secondary) }
                    ForEach(a.channels) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(c.direction) \(c.channel)").font(.subheadline.monospaced())
                            Text("\(c.frames) frames · \(String(format: "%.1f", c.perSecond))/s · longest gap \(String(format: "%.1f", c.longestGap)) s")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Section("Most common frames") {
                    ForEach(a.commands.prefix(25)) { c in
                        HStack { Text(c.key).font(.caption.monospaced()); Spacer(); Text("\(c.count)").foregroundColor(.secondary).monospacedDigit() }
                    }
                }
                if store.allows(.developerExport) {
                    Section(footer: Text("Developer: the log as JSON for test fixtures. Passwords are already masked in the log.")) {
                        Button("Export log as JSON") {
                            if let d = DevExport.json(ble.frameRecords, device: ble.connectedName) {
                                let url = FileManager.default.temporaryDirectory.appendingPathComponent("hackthescoot-log-\(Int(Date().timeIntervalSince1970)).json")
                                if (try? d.write(to: url)) != nil { share = ShareItem(url: url) }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Log analysis")
            .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        }
    }

    private func row(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary).monospacedDigit() } }
}

/// Developer: compare two frames byte by byte.
struct FrameDiffView: View {
    @State private var a = "DB EB BA 2A 1F"
    @State private var b = "DB EB BA 2A 23"

    var body: some View {
        ProGate(feature: .protocolWorkspace) {
            let pa = FrameDiff.parseHex(a)
            let pb = FrameDiff.parseHex(b)
            Form {
                Section(header: Text("Frame A"), footer: Text(pa == nil ? "Not valid hex." : "\(pa?.count ?? 0) bytes")) {
                    TextField("hex", text: $a).font(.body.monospaced()).textInputAutocapitalization(.characters).autocorrectionDisabled()
                }
                Section(header: Text("Frame B"), footer: Text(pb == nil ? "Not valid hex." : "\(pb?.count ?? 0) bytes")) {
                    TextField("hex", text: $b).font(.body.monospaced()).textInputAutocapitalization(.characters).autocorrectionDisabled()
                }
                if let x = pa, let y = pb {
                    let cells = FrameDiff.compare(x, y)
                    Section(header: Text("\(cells.filter { $0.changed }.count) of \(cells.count) bytes differ")) {
                        ForEach(cells, id: \.index) { c in
                            HStack {
                                Text("[\(c.index)]").frame(width: 44, alignment: .leading).foregroundColor(.secondary)
                                Text(c.a.map { String(format: "%02X", $0) } ?? "--")
                                Image(systemName: "arrow.right").font(.caption).foregroundColor(.secondary)
                                Text(c.b.map { String(format: "%02X", $0) } ?? "--")
                                Spacer()
                                if c.changed { Text("changed").font(.caption.weight(.bold)).foregroundColor(.orange) }
                            }
                            .font(.callout.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("Frame compare")
        }
    }
}
