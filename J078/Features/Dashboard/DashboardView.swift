import SwiftUI

/// v4.0.1 dashboard: black, one huge readable speed, the mode, three numbers, and the
/// two buttons you actually use (mode + light). Everything else lives in Controls / More.
struct DashboardView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var trips: TripManager
    @EnvironmentObject var themes: ThemeStore
    var openConnect: () -> Void
    @StateObject private var driver = GaugeDriver()
    @AppStorage(Keys.unitsSwapped) private var unitsSwapped = false
    @AppStorage(Keys.keepAwake) private var keepAwake = true
    @AppStorage(Keys.showDashControls) private var showDashControls = true
    @AppStorage(Keys.gaugeMaxAuto) private var gaugeMaxAuto = true
    @AppStorage(Keys.gaugeMax) private var gaugeMax = 30.0

    private var theme: DashTheme { themes.theme }
    private var gear: Gear? { ble.status?.gear }
    private var modeColor: Color { themes.modeColor(gear) }
    private var scooterMile: Bool {
        guard let s = ble.status else { return true }
        return Mapping.unitsIsMile(flagBit: s.unitsBit, swapped: unitsSwapped)
    }
    private func display(_ raw: Double) -> SpeedDisplay {
        SpeedDisplay.make(raw: raw.isFinite ? raw : 0, scooterIsMile: scooterMile, display: theme.units)
    }
    private var maxScale: Double {
        if !gaugeMaxAuto, gaugeMax.isFinite, gaugeMax >= 5 { return gaugeMax }
        let kmh = Double(ble.adapter.factoryMaxKmh ?? 31)
        let v = display(0).isMile ? Units.kmhToMph(kmh) : kmh
        return max(10, (v / 5).rounded(.up) * 5 + 5)
    }
    private var moving: Bool { (ble.status?.speed ?? 0) > 2 }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                background.ignoresSafeArea()
                if landscape {
                    HStack(spacing: DS.pad) {
                        gauge.frame(width: geo.size.width * 0.55)
                        VStack(spacing: DS.gap) {
                            topBar
                            modeLine
                            stats
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(DS.pad)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: DS.pad) {
                            topBar
                            gauge.frame(height: min(geo.size.width * 0.95, 380))
                            modeLine
                            if ble.isActive {
                                if theme.layout != "focus" { stats }
                                if showDashControls && theme.layout == "standard" { quickControls }
                            } else {
                                connectCard
                            }
                        }
                        .padding(.horizontal, DS.pad)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder private var background: some View {
        switch theme.backgroundStyle {
        case "solid": themes.background
        case "gradient":
            LinearGradient(colors: [themes.background, modeColor.opacity(theme.night ? 0.04 : 0.10), Color.black],
                           startPoint: .top, endPoint: .bottom)
        default: Color.black
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: openConnect) {
                HStack(spacing: 8) {
                    ConnectionPill(ble: ble)
                    if ble.isActive {
                        Text(ble.isSimulating ? "SIMULATED" : (ble.connectedName.isEmpty ? ble.adapter.displayName : ble.connectedName))
                            .font(.footnote.weight(.medium))
                            .foregroundColor(ble.isSimulating ? .purple : DS.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if let s = ble.status {
                Image(systemName: s.light ? "lightbulb.fill" : "lightbulb")
                    .foregroundColor(s.light ? themes.accent : DS.tertiaryText)
                if s.parked {
                    Image(systemName: "parkingsign.circle.fill").foregroundColor(.orange)
                }
            }
        }
    }

    private var gauge: some View {
        TimelineView(.animation(minimumInterval: theme.night ? 0.25 : 1.0 / 30.0)) { ctx in
            let raw = ble.status?.speed ?? 0
            let _ = driver.feed(raw.isFinite ? raw : 0, at: ble.lastStatusTime)
            let v = driver.value(at: ctx.date, intensity: theme.night ? 0 : theme.animationIntensity)
            let stale = ble.status == nil || driver.isStale(ctx.date)
            let d = display(v)
            AnyGauge(style: theme.gauge,
                     m: GaugeModel(speed: d.value.isFinite ? d.value : 0, maxSpeed: maxScale, unit: d.unit,
                                   color: themes.modeColor(gear), accent: themes.accent, font: themes.font,
                                   stale: stale, simulated: ble.isSimulating,
                                   intensity: theme.animationIntensity, night: theme.night))
        }
        .accessibilityLabel("Speedometer")
    }

    private var modeLine: some View {
        HStack(spacing: 8) {
            Circle().fill(gear.map { Color(hex: theme.modeColor($0)) } ?? DS.tertiaryText).frame(width: 8, height: 8)
            Text(modeText).font(.title3.weight(.semibold))
            if let g = gear, let k = ble.limitsKmh[g] {
                Text("· max " + (display(0).isMile ? "\(Gear.mph(for: g, kmh: k)) mph" : "\(k) km/h"))
                    .font(.subheadline).foregroundColor(DS.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var modeText: String {
        if let g = gear { return g.name.uppercased() }
        if let m = ble.volpamStatus?.mode { return m.name.uppercased() }
        return ble.isActive ? "WAITING FOR DATA" : "NOT CONNECTED"
    }

    /// Three numbers in one card (the first three tiles of the chosen layout).
    private var stats: some View {
        let tiles = Array(theme.tiles.compactMap { DashTile(rawValue: $0) }.filter { $0 != .mode }.prefix(3))
        return Card {
            HStack(spacing: DS.gap) {
                ForEach(tiles) { t in StatCell(title: t.title, value: tileValue(t)) }
            }
        }
    }

    private var quickControls: some View {
        VStack(spacing: DS.gap) {
            if moving {
                Label("Moving: keep your eyes on the road", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundColor(.orange)
            }
            HStack(spacing: 8) {
                ForEach(Gear.allCases) { g in
                    Button { ble.setGear(g) } label: {
                        Text(g.name)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(gear == g ? themes.accent : DS.card))
                            .foregroundColor(gear == g ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Switch to \(g.name)")
                }
                Button { ble.setLight(!(ble.status?.light ?? false)) } label: {
                    Image(systemName: (ble.status?.light ?? false) ? "lightbulb.fill" : "lightbulb")
                        .font(.headline)
                        .frame(width: 52, height: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.card))
                        .foregroundColor((ble.status?.light ?? false) ? themes.accent : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle light")
            }
            .disabled(!ble.canControl)
            .opacity(ble.canControl ? 1 : 0.4)
            if ble.isActive && !ble.canControl && !ble.isSimulating {
                Text(ble.kind == .j078 ? "Getting ready..." : "This scooter is read-only here. See Controls.")
                    .font(.footnote).foregroundColor(DS.secondaryText)
            }
        }
    }

    private var connectCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.gap) {
                Text("Connect your scooter").font(.headline)
                Text("Turn the scooter on, keep the phone close, and tap Connect.")
                    .font(.subheadline).foregroundColor(DS.secondaryText)
                Button(action: openConnect) {
                    Text("Connect").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(themes.accent)
                Button { ble.startSimulation(.cityRide) } label: {
                    Text("Try the simulator").frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func tileValue(_ t: DashTile) -> String {
        let unit = display(0).unit
        switch t {
        case .mode: return gear?.name ?? (ble.volpamStatus?.mode?.name.appending(" (exp.)") ?? "--")
        case .limit:
            guard let g = gear, let k = ble.limitsKmh[g], ble.limitsLive.contains(g) else { return "--" }
            return display(0).isMile ? "\(Gear.mph(for: g, kmh: k)) mph" : "\(k) km/h"
        case .trip: return ble.isActive ? String(format: "%.1f %@", display(ble.tripMax).value, unit) : "--"
        case .tripTime:
            guard let c = trips.current else { return "--" }
            return TripMath.format(Date().timeIntervalSince(c.start))
        case .distance:
            guard let c = trips.current else { return "--" }
            let km = c.stats.distanceKm
            return display(0).isMile ? String(format: "%.2f mi", Units.kmToMiles(km)) : String(format: "%.2f km", km)
        case .avg:
            guard let c = trips.current else { return "--" }
            let a = c.stats.avgMovingKmh
            return display(0).isMile ? String(format: "%.1f mph", Units.kmhToMph(a)) : String(format: "%.1f km/h", a)
        case .lightPark:
            guard let s = ble.status else { return "--" }
            return "\(s.light ? "On" : "Off") / \(s.parked ? "P" : "Ride")"
        case .signal:
            if ble.isSimulating { return "Simulated" }
            return SignalStrength.from(rssi: ble.rssi).rawValue
        case .battery: return "N/A"
        case .odometer: return "N/A"
        }
    }
}
