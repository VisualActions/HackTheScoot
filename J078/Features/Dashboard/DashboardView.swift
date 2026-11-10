import SwiftUI

struct DashboardView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var trips: TripManager
    @EnvironmentObject var themes: ThemeStore
    var goToConnect: () -> Void
    @StateObject private var driver = GaugeDriver()
    @AppStorage(Keys.unitsSwapped) private var unitsSwapped = false
    @AppStorage(Keys.keepAwake) private var keepAwake = true
    @AppStorage("modeHaptics") private var modeHaptics = true
    @State private var sweep = 0
    @State private var lastGear: Gear?

    private var theme: DashTheme { themes.theme }
    private var scooterMile: Bool {
        guard let s = ble.status else { return true }
        return Mapping.unitsIsMile(flagBit: s.unitsBit, swapped: unitsSwapped)
    }
    private var gear: Gear? { ble.status?.gear }
    private var modeColor: Color { themes.modeColor(gear) }

    private func display(_ raw: Double) -> SpeedDisplay {
        SpeedDisplay.make(raw: raw, scooterIsMile: scooterMile, display: theme.units)
    }

    private var maxScale: Double {
        let kmh = Double(ble.adapter.factoryMaxKmh ?? 31)
        let unitIsMile = display(0).isMile
        let v = unitIsMile ? Units.kmhToMph(kmh) : kmh
        return (v / 5).rounded(.up) * 5 + 5
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                background.ignoresSafeArea()
                ModeSweep(color: modeColor, trigger: sweep).ignoresSafeArea()
                if landscape {
                    HStack(spacing: 16) {
                        gauge.frame(width: geo.size.width * 0.58)
                        VStack(spacing: 10) {
                            header
                            tileGrid(columns: 2, compact: true)
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(12)
                } else {
                    VStack(spacing: 12) {
                        header
                        gauge.frame(height: min(geo.size.width, geo.size.height * 0.5))
                        if theme.layout != "focus" { tileGrid(columns: 2, compact: false) }
                        if ble.isActive && theme.layout == "standard" { quickControls }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: ble.status?.gearCode) { _ in
            guard let g = gear, g != lastGear else { return }
            if lastGear != nil, theme.animationIntensity > 0, !theme.night { sweep += 1 }
            lastGear = g
        }
    }

    @ViewBuilder private var background: some View {
        switch theme.backgroundStyle {
        case "black": Color.black
        case "solid": themes.background
        default:
            LinearGradient(colors: [themes.background, modeColor.opacity(theme.night ? 0.05 : 0.18), themes.background],
                           startPoint: .top, endPoint: .bottom)
                .animation(.easeInOut(duration: 0.6), value: gear)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ConnectionPill(ble: ble)
            Spacer()
            if ble.isActive {
                Text(ble.adapter.level.rawValue)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().stroke(Color.secondary.opacity(0.5)))
                    .foregroundColor(.secondary)
            } else {
                Button("Connect", action: goToConnect).buttonStyle(.borderedProminent).tint(themes.accent)
            }
        }
    }

    private var gauge: some View {
        TimelineView(.animation(minimumInterval: theme.night ? 0.25 : 1.0 / 30.0)) { ctx in
            let raw = ble.status?.speed ?? 0
            let _ = driver.feed(raw, at: ble.lastStatusTime)
            let v = driver.value(at: ctx.date, intensity: theme.night ? 0 : theme.animationIntensity)
            let stale = ble.status == nil || driver.isStale(ctx.date)
            let d = display(v)
            AnyGauge(style: theme.gauge, m: GaugeModel(speed: d.value, maxSpeed: maxScale, unit: d.unit, color: modeColor,
                                                       accent: themes.accent, font: themes.font, stale: stale,
                                                       simulated: ble.isSimulating, intensity: theme.animationIntensity, night: theme.night))
        }
    }

    private func tileGrid(columns: Int, compact: Bool) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(theme.tiles.compactMap { DashTile(rawValue: $0) }) { t in
                InfoTile(title: t.title, value: tileValue(t), color: t == .mode ? modeColor : .primary, compact: compact)
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
            return display(0).isMile ? String(format: "%.2f mi est.", Units.kmToMiles(km)) : String(format: "%.2f km est.", km)
        case .avg:
            guard let c = trips.current else { return "--" }
            let a = c.stats.avgMovingKmh
            return display(0).isMile ? String(format: "%.1f mph", Units.kmhToMph(a)) : String(format: "%.1f km/h", a)
        case .lightPark:
            guard let s = ble.status else { return "--" }
            return "\(s.light ? "Light on" : "Light off") / \(s.parked ? "Parked" : "Ride")"
        case .signal:
            if ble.isSimulating { return "Simulated" }
            return SignalStrength.from(rssi: ble.rssi).rawValue + (ble.rssi.map { " (\($0) dBm)" } ?? "")
        case .battery: return "Unavailable (unverified)"
        case .odometer: return "Unavailable (unverified)"
        }
    }

    private var moving: Bool { (ble.status?.speed ?? 0) > 2 }

    @ViewBuilder private var quickControls: some View {
        if moving {
            Label("Controls hidden while moving", systemImage: "hand.raised.fill")
                .font(.footnote).foregroundColor(.secondary)
        } else if ble.canControl {
            HStack(spacing: 8) {
                ForEach(Gear.allCases) { g in
                    Button { ble.setGear(g) } label: {
                        Text(g.name).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(gear == g ? themes.modeColor(g).opacity(0.85) : Color.secondary.opacity(0.15)))
                            .foregroundColor(gear == g ? .black : .primary)
                    }
                    .accessibilityLabel("Switch to \(g.name)")
                }
                Button { ble.setLight(!(ble.status?.light ?? false)) } label: {
                    Image(systemName: (ble.status?.light ?? false) ? "lightbulb.fill" : "lightbulb")
                        .frame(width: 44, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15)))
                }
                .accessibilityLabel("Toggle light")
            }
        }
    }
}

struct InfoTile: View {
    let title: String
    let value: String
    var color: Color = .primary
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundColor(.secondary)
            Text(value).font(compact ? .headline : .title3.weight(.semibold)).foregroundColor(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

struct ConnectionPill: View {
    @ObservedObject var ble: BLEManager
    var color: Color {
        switch ble.phase {
        case .ready: return ble.isSimulating ? .purple : .green
        case .synchronizing, .subscribing, .discovering, .connecting, .authenticating: return .yellow
        case .reconnecting: return .orange
        default: return .gray
        }
    }
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(ble.isSimulating ? "Simulator · \(ble.phase.label)" : ble.phase.label).font(.caption.weight(.semibold)).lineLimit(1)
            if !ble.isSimulating, ble.phase.isLinked { SignalBars(bars: SignalStrength.from(rssi: ble.rssi).bars) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
        .accessibilityElement(children: .combine)
    }
}

struct SignalBars: View {
    let bars: Int
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= bars ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 3, height: CGFloat(3 + i * 3))
            }
        }
        .accessibilityLabel("Signal \(bars) of 4")
    }
}
