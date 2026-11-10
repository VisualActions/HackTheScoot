import SwiftUI

struct TripsView: View {
    @ObservedObject var trips: TripManager
    @ObservedObject var ble: BLEManager
    @EnvironmentObject var themes: ThemeStore
    @State private var confirmClear = false
    @State private var share: ShareItem?

    private var mph: Bool { themes.theme.units != "kmh" }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Trip computer"), footer: Text("Distance is ESTIMATED from speed samples (gaps over 2 s are skipped). It is not the scooter's odometer, which is unverified.")) {
                    if let c = trips.current {
                        let st = c.stats
                        statRow("Status", c.source == "simulation" ? "Recording (SIMULATED)" : "Recording")
                        statRow("Current speed", ble.status.map { speed(SpeedDisplay.toKmh($0.speed, scooterIsMile: true)) } ?? "--")
                        statRow("Max", speed(st.maxKmh))
                        statRow("Average (moving)", speed(st.avgMovingKmh))
                        statRow("Duration", TripMath.format(Date().timeIntervalSince(c.start)))
                        statRow("Distance (est.)", dist(st.distanceKm))
                        statRow("Interruptions", "\(c.interruptions)")
                        ForEach(st.timeInMode.sorted(by: { $0.key < $1.key }), id: \.key) { m, t in statRow("Time in \(m)", TripMath.format(t)) }
                        Button("End trip") { trips.finish() }
                    } else {
                        Text(trips.autoRecord ? "A trip starts on its own when you ride above 2 km/h." : "Auto-record is off.")
                            .foregroundColor(.secondary)
                    }
                    Toggle("Auto-record trips", isOn: $trips.autoRecord)
                }
                Section("History") {
                    if trips.trips.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "road.lanes").font(.largeTitle).foregroundColor(.secondary)
                            Text("No rides yet").font(.headline)
                            Text("Ride, or run the simulator, and your trips land here. They stay on this phone.").font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    ForEach(trips.trips) { t in
                        NavigationLink { TripDetailView(trip: t, mph: mph, trips: trips) } label: { TripCard(trip: t, mph: mph) }
                            .swipeActions { Button("Delete", role: .destructive) { trips.delete(t) } }
                    }
                }
                if !trips.trips.isEmpty {
                    Section { Button("Clear all history", role: .destructive) { confirmClear = true } }
                }
            }
            .navigationTitle("Trips")
            .confirmationDialog("Delete every saved trip?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { trips.clear() }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func speed(_ kmh: Double) -> String { mph ? String(format: "%.1f mph", Units.kmhToMph(kmh)) : String(format: "%.1f km/h", kmh) }
    private func dist(_ km: Double) -> String { mph ? String(format: "%.2f mi", Units.kmToMiles(km)) : String(format: "%.2f km", km) }
    private func statRow(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary).monospacedDigit() } }
}

struct TripCard: View {
    let trip: Trip
    let mph: Bool
    var body: some View {
        let s = trip.stats
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(trip.start.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                if trip.source == "simulation" { Text("SIM").font(.caption2.weight(.heavy)).foregroundColor(.purple) }
                Spacer()
                Text(TripMath.format(trip.duration)).font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
            }
            HStack(spacing: 14) {
                metric("Distance est.", mph ? String(format: "%.2f mi", Units.kmToMiles(s.distanceKm)) : String(format: "%.2f km", s.distanceKm))
                metric("Avg", mph ? String(format: "%.1f", Units.kmhToMph(s.avgMovingKmh)) : String(format: "%.1f", s.avgMovingKmh))
                metric("Max", mph ? String(format: "%.1f", Units.kmhToMph(s.maxKmh)) : String(format: "%.1f", s.maxKmh))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
    private func metric(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading) { Text(k).font(.caption2).foregroundColor(.secondary); Text(v).font(.subheadline.weight(.semibold)) }
    }
}

struct TripDetailView: View {
    let trip: Trip
    let mph: Bool
    @ObservedObject var trips: TripManager
    @State private var share: ShareItem?

    var body: some View {
        List {
            Section { TripCard(trip: trip, mph: mph) }
            Section("Speed over time") { SpeedChart(samples: trip.samples, mph: mph).frame(height: 160) }
            Section("Summary") { Text(TripMath.summary(trip, mph: mph)).font(.footnote.monospaced()).textSelection(.enabled) }
            Section {
                NavigationLink("Replay this trip") { TripReplayView(trip: trip, mph: mph) }
                Button("Export summary") { if let u = trips.exportURL(trip, mph: mph) { share = ShareItem(url: u) } }
            }
        }
        .navigationTitle("Ride")
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
    }
}

struct SpeedChart: View {
    let samples: [TripSample]
    let mph: Bool
    var body: some View {
        GeometryReader { g in
            let valid = samples.filter(TripMath.isValid)
            let maxT = max(1, valid.last?.t ?? 1)
            let maxV = max(1, valid.map { $0.kmh }.max() ?? 1)
            Path { p in
                for (i, s) in valid.enumerated() {
                    let pt = CGPoint(x: g.size.width * CGFloat(s.t / maxT), y: g.size.height * (1 - CGFloat(s.kmh / maxV)))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(Color.accentColor, lineWidth: 2)
        }
        .accessibilityLabel("Speed chart")
    }
}

/// Replays saved samples through the gauge. Completely disconnected from controls.
struct TripReplayView: View {
    let trip: Trip
    let mph: Bool
    @EnvironmentObject var themes: ThemeStore
    @State private var start = Date()
    @State private var speedUp: Double = 4
    @State private var playing = true

    var body: some View {
        VStack(spacing: 16) {
            Text("REPLAY · no scooter connection").font(.caption.weight(.heavy)).foregroundColor(.purple)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { ctx in
                let t = ctx.date.timeIntervalSince(start) * speedUp
                let s = sample(at: t)
                let v = mph ? Units.kmhToMph(s?.kmh ?? 0) : (s?.kmh ?? 0)
                let gear = Gear.allCases.first { $0.name == s?.mode }
                VStack {
                    AnyGauge(style: themes.theme.gauge, m: GaugeModel(speed: v, maxSpeed: mph ? 25 : 40, unit: mph ? "mph" : "km/h",
                                                                     color: themes.modeColor(gear), accent: themes.accent, font: themes.font,
                                                                     stale: s == nil, simulated: false, intensity: themes.theme.animationIntensity, night: themes.theme.night))
                        .frame(height: 300)
                    Text("\(TripMath.format(min(t, trip.duration))) / \(TripMath.format(trip.duration))  ·  \(s?.mode ?? "--")")
                        .font(.footnote.monospacedDigit()).foregroundColor(.secondary)
                }
            }
            Picker("Speed", selection: $speedUp) {
                Text("1x").tag(1.0); Text("4x").tag(4.0); Text("16x").tag(16.0)
            }
            .pickerStyle(.segmented)
            HStack {
                Button(playing ? "Pause" : "Play") { playing.toggle() }.buttonStyle(.bordered)
                Button("Restart") { start = Date(); playing = true }.buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Trip replay")
    }

    private func sample(at t: TimeInterval) -> TripSample? {
        guard t <= trip.duration + 1 else { return nil }
        return trip.samples.last { $0.t <= t } ?? trip.samples.first
    }
}
