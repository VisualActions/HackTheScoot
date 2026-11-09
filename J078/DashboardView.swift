import SwiftUI
import UIKit

struct DashboardView: View {
    @ObservedObject var ble: BLEManager
    var goToConnect: () -> Void

    @AppStorage(Keys.speedColor) private var speedColorHex = "#00E5FF"
    @AppStorage(Keys.colorMode) private var colorMode = "solid"
    @AppStorage(Keys.gaugeStyle) private var gaugeStyle = "arc"
    @AppStorage(Keys.bgStyle) private var bgStyle = "black"
    @AppStorage(Keys.bgColor) private var bgColorHex = "#101018"
    @AppStorage(Keys.fontDesign) private var fontName = "rounded"
    @AppStorage(Keys.displayUnit) private var displayUnit = "scooter"
    @AppStorage(Keys.gaugeMaxAuto) private var gaugeMaxAuto = true
    @AppStorage(Keys.gaugeMax) private var gaugeMaxManual = 25.0
    @AppStorage(Keys.showGear) private var showGear = true
    @AppStorage(Keys.showTops) private var showTops = true
    @AppStorage(Keys.showBattery) private var showBattery = true
    @AppStorage(Keys.showLightPark) private var showLightPark = true
    @AppStorage(Keys.showTrip) private var showTrip = true
    @AppStorage(Keys.showOdo) private var showOdo = false
    @AppStorage(Keys.showDashControls) private var showDashControls = true
    @AppStorage(Keys.keepAwake) private var keepAwake = true
    @AppStorage(Keys.unitsSwapped) private var unitsSwapped = false
    @AppStorage(Keys.password) private var password = "000000"

    private var scooterIsMile: Bool {
        guard let s = ble.status else { return true }
        return Mapping.unitsIsMile(flagBit: s.unitsBit, swapped: unitsSwapped)
    }

    private var speed: SpeedDisplay {
        return SpeedDisplay.make(raw: ble.status?.speed ?? 0, scooterIsMile: scooterIsMile, display: displayUnit)
    }

    private var gaugeMax: Double {
        if !gaugeMaxAuto { return max(5, gaugeMaxManual) }
        let kmh = ble.limitsKmh[.sport] ?? Gear.sport.capturedLimitKmh
        let top = speed.isMile ? Double(Gear.mph(for: .sport, kmh: kmh)) : Double(kmh)
        return max(10, (top * 1.25 / 5).rounded(.up) * 5)
    }

    private var speedColor: Color {
        let base = Color(hex: speedColorHex)
        switch colorMode {
        case "mode":
            return ble.status?.gear?.color ?? base
        case "heat":
            let frac = speed.value / gaugeMax
            return base.mixed(with: .red, (frac - 0.4) / 0.6)
        default:
            return base
        }
    }

    private var background: some View {
        Group {
            switch bgStyle {
            case "gradient":
                LinearGradient(colors: [Color(hex: bgColorHex), speedColor.opacity(0.35), .black],
                               startPoint: .top, endPoint: .bottom)
            case "color":
                Color(hex: bgColorHex)
            default:
                Color.black
            }
        }
        .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 14) {
                header
                SpeedGauge(speed: speed.value, maxSpeed: gaugeMax, color: speedColor,
                           style: gaugeStyle, unit: speed.unit, design: fontDesign(fontName),
                           subtitle: showGear ? (ble.status?.gear?.name.uppercased() ?? "--") : "")
                    .frame(maxHeight: 380)
                tiles
                if showDashControls {
                    quickControls
                }
                Spacer(minLength: 0)
            }
            .padding()
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepAwake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: keepAwake) { v in UIApplication.shared.isIdleTimerDisabled = v }
    }

    private var header: some View {
        HStack {
            Circle()
                .fill(ble.canControl ? Color.green : (ble.connected != nil ? Color.orange : Color.red))
                .frame(width: 10, height: 10)
            Text(ble.connected != nil ? ble.connectedName : "Not connected")
                .font(.subheadline.bold())
            Spacer()
            if ble.connected == nil {
                Button("Connect", action: goToConnect)
                    .buttonStyle(.borderedProminent)
                    .tint(speedColor)
            } else if ble.kind != .j078 {
                Text(ble.kind.short).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if showTops, let g = ble.status?.gear {
                let kmh = ble.limitsKmh[g] ?? g.capturedLimitKmh
                Tile(title: "\(g.name) top", value: speed.isMile ? "\(Gear.mph(for: g, kmh: kmh)) mph" : "\(kmh) km/h", color: g.color)
            }
            if showTrip {
                let trip = SpeedDisplay.make(raw: ble.tripMax, scooterIsMile: scooterIsMile, display: displayUnit)
                Tile(title: "Max this ride", value: String(format: "%.1f", trip.value) + " " + trip.unit, color: speedColor)
            }
            if showBattery {
                Tile(title: "Battery?", value: ble.status?.batteryGuess.map { "\($0)%" } ?? "--", color: .yellow)
            }
            if showLightPark {
                Tile(title: "Light / Park",
                     value: "\(ble.status?.light == true ? "ON" : "off") / \(ble.status?.parked == true ? "PARKED" : "off")",
                     color: .white)
            }
            if showOdo {
                Tile(title: "Odo? (raw)", value: ble.status.map { Proto.hex($0.odometerBytes) } ?? "--", color: .gray)
            }
        }
    }

    private var quickControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Gear.allCases) { g in
                    let on = ble.status?.gear == g
                    Button {
                        ble.setGear(g)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: g.icon)
                            Text(g.name).font(.caption2.bold())
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(on ? g.color.opacity(0.85) : Color.white.opacity(0.08))
                        .foregroundColor(on ? .black : .white)
                        .cornerRadius(12)
                    }
                }
            }
            HStack(spacing: 8) {
                let lightOn = ble.status?.light == true
                Button {
                    ble.setLight(!lightOn)
                } label: {
                    Label(lightOn ? "Light on" : "Light off", systemImage: lightOn ? "lightbulb.fill" : "lightbulb")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(lightOn ? Color.yellow.opacity(0.85) : Color.white.opacity(0.08))
                        .foregroundColor(lightOn ? .black : .white)
                        .cornerRadius(12)
                }
                let parked = ble.status?.parked == true
                Button {
                    ble.setPark(!parked, pin: password)
                } label: {
                    Label(ble.busy ?? (parked ? "Parked" : "Park"), systemImage: parked ? "parkingsign.circle.fill" : "parkingsign.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(parked ? Color.blue.opacity(0.85) : Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(ble.busy != nil)
            }
        }
        .disabled(!ble.canControl)
        .opacity(ble.canControl ? 1 : 0.4)
    }
}

struct Tile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.headline.monospacedDigit()).foregroundColor(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.07))
        .cornerRadius(12)
    }
}

struct SpeedGauge: View {
    let speed: Double
    let maxSpeed: Double
    let color: Color
    let style: String
    let unit: String
    let design: Font.Design
    let subtitle: String

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let frac = min(max(speed / max(maxSpeed, 1), 0), 1)
            ZStack {
                if style == "arc" {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    Circle()
                        .trim(from: 0, to: 0.75 * frac)
                        .stroke(color, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .shadow(color: color.opacity(0.8), radius: 14)
                        .animation(.easeOut(duration: 0.15), value: frac)
                    ForEach(0..<11) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i % 5 == 0 ? 0.8 : 0.35))
                            .frame(width: 2, height: size * (i % 5 == 0 ? 0.06 : 0.035))
                            .offset(y: -size * 0.36)
                            .rotationEffect(.degrees(-135 + Double(i) * 27))
                    }
                    Text(String(format: "%.0f", maxSpeed))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .offset(x: size * 0.28, y: size * 0.36)
                    Text("0")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .offset(x: -size * 0.28, y: size * 0.36)
                } else if style == "digital" {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(color.opacity(0.6), lineWidth: 3)
                        .frame(width: size * 0.95, height: size * 0.6)
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: size * 0.8, height: 10)
                        .offset(y: size * 0.22)
                    Capsule()
                        .fill(color)
                        .frame(width: max(10, size * 0.8 * frac), height: 10)
                        .offset(x: -size * 0.4 + max(10, size * 0.8 * frac) / 2, y: size * 0.22)
                        .animation(.easeOut(duration: 0.15), value: frac)
                }
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", speed))
                        .font(.system(size: size * (style == "minimal" ? 0.34 : 0.26), weight: .heavy, design: design))
                        .monospacedDigit()
                        .foregroundColor(style == "arc" ? .white : color)
                        .shadow(color: color.opacity(style == "arc" ? 0 : 0.6), radius: 10)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(unit)
                        .font(.system(size: size * 0.07, weight: .semibold, design: design))
                        .foregroundColor(.secondary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: size * 0.06, weight: .bold, design: design))
                            .foregroundColor(color)
                            .padding(.top, 4)
                    }
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
