import SwiftUI

/// Drives what the gauge SHOWS between real samples (SpeedInterpolator never
/// overshoots the real value and goes stale after 1.5 s with no sample).
final class GaugeDriver: ObservableObject {
    private var interp = SpeedInterpolator()
    private var lastStep = Date()
    private var lastSample: Date?

    func feed(_ value: Double, at t: Date?) {
        guard let t = t, t != lastSample else { return }
        lastSample = t
        interp.sample(value, at: t)
    }

    func value(at now: Date, intensity: Double) -> Double {
        let dt = min(0.2, max(0, now.timeIntervalSince(lastStep)))
        lastStep = now
        return interp.step(dt: dt, intensity: intensity)
    }

    func isStale(_ now: Date) -> Bool { interp.isStale(now: now) }
}

struct GaugeModel {
    var speed: Double
    var maxSpeed: Double
    var unit: String
    var color: Color
    var accent: Color
    var font: Font.Design
    var stale: Bool
    var simulated: Bool
    var intensity: Double
    var night: Bool
}

struct SpeedReadout: View {
    let m: GaugeModel
    var size: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            Text(m.stale ? "--" : String(format: "%.0f", m.speed))
                .font(.system(size: size, weight: .bold, design: m.font))
                .monospacedDigit()
                .foregroundColor(m.night ? m.color.opacity(0.85) : .primary)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Text(m.stale ? "no live data" : m.unit)
                .font(.system(size: size * 0.16, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            if m.simulated {
                Text("SIMULATED")
                    .font(.system(size: max(10, size * 0.1), weight: .heavy, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.purple.opacity(0.85)))
                    .foregroundColor(.white)
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.stale ? "Speed unavailable" : "\(Int(m.speed.rounded())) \(m.unit)\(m.simulated ? ", simulated" : "")")
    }
}

/// Classic: round dial, ticks, smooth needle.
struct ClassicGauge: View {
    let m: GaugeModel
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let frac = max(0, min(1, m.speed / max(1, m.maxSpeed)))
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.25), lineWidth: s * 0.015)
                ForEach(0...20, id: \.self) { i in
                    let major = i % 5 == 0
                    Capsule()
                        .fill(Double(i) / 20 <= frac && !m.stale ? m.color : Color.secondary.opacity(0.5))
                        .frame(width: major ? s * 0.012 : s * 0.006, height: major ? s * 0.07 : s * 0.035)
                        .offset(y: -s * 0.42)
                        .rotationEffect(.degrees(-135 + Double(i) * 13.5))
                }
                ForEach(0...4, id: \.self) { i in
                    Text("\(Int(m.maxSpeed * Double(i) / 4))")
                        .font(.system(size: s * 0.055, weight: .medium, design: m.font))
                        .foregroundColor(.secondary)
                        .offset(y: -s * 0.31)
                        .rotationEffect(.degrees(-135 + Double(i) * 67.5))
                        .rotationEffect(.degrees(135 - Double(i) * 67.5), anchor: .center)
                }
                Capsule()
                    .fill(m.stale ? Color.secondary : m.color)
                    .frame(width: s * 0.018, height: s * 0.4)
                    .offset(y: -s * 0.2)
                    .rotationEffect(.degrees(-135 + 270 * (m.stale ? 0 : frac)))
                    .shadow(color: m.night ? .clear : m.color.opacity(0.6), radius: 6)
                Circle().fill(Color.secondary.opacity(0.6)).frame(width: s * 0.06)
                SpeedReadout(m: m, size: s * 0.16).offset(y: s * 0.24)
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

/// Digital: giant digits, a thin progress line, nothing else moving.
struct DigitalGauge: View {
    let m: GaugeModel
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height * 1.4)
            let frac = max(0, min(1, m.speed / max(1, m.maxSpeed)))
            VStack(spacing: s * 0.03) {
                SpeedReadout(m: m, size: s * 0.42)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule().fill(m.color).frame(width: g.size.width * (m.stale ? 0 : frac))
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, s * 0.12)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Performance: thick arc with an animated gradient that brightens near the limit.
struct PerformanceGauge: View {
    let m: GaugeModel
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let frac = max(0, min(1, m.speed / max(1, m.maxSpeed)))
            let shown = m.stale ? 0 : frac
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * shown)
                    .stroke(AngularGradient(gradient: Gradient(colors: [m.color.opacity(0.35), m.color, m.night ? m.color : .white]),
                                            center: .center, startAngle: .degrees(0), endAngle: .degrees(270 * max(0.01, shown))),
                            style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .shadow(color: m.night ? .clear : m.color.opacity(0.25 + 0.5 * shown * m.intensity), radius: s * 0.04 * m.intensity)
                SpeedReadout(m: m, size: s * 0.3)
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

struct AnyGauge: View {
    let style: String
    let m: GaugeModel
    var body: some View {
        switch style {
        case "classic": ClassicGauge(m: m)
        case "digital": DigitalGauge(m: m)
        default: PerformanceGauge(m: m)
        }
    }
}

/// The short color sweep when the riding mode changes.
struct ModeSweep: View {
    let color: Color
    let trigger: Int
    @State private var x: CGFloat = -1.2
    var body: some View {
        GeometryReader { g in
            LinearGradient(colors: [.clear, color.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: g.size.width * 0.6)
                .offset(x: x * g.size.width)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _ in
            x = -0.8
            withAnimation(.easeOut(duration: 0.6)) { x = 1.4 }
        }
    }
}
