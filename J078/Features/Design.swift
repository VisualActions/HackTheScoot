import SwiftUI

// v4.0.1 design system: black background, one accent color, SF Pro, one spacing
// scale. Every screen uses these so the app looks like one product.

enum DS {
    static let pad: CGFloat = 16
    static let gap: CGFloat = 12
    static let radius: CGFloat = 20
    static let card = Color(white: 0.09)
    static let cardStroke = Color.white.opacity(0.06)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)
}

/// A rounded dark surface. Used sparingly: one or two per screen.
struct Card<Content: View>: View {
    var padding: CGFloat = DS.pad
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).fill(DS.card))
            .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).stroke(DS.cardStroke, lineWidth: 1))
    }
}

/// A Slider that can never be built with a zero-width or reversed range.
/// (v4.0.0 crashed opening Controls: the Walk speed-limit slider was 6...6 km/h.)
struct SafeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    static func safeRange(_ r: ClosedRange<Double>, step: Double) -> ClosedRange<Double> {
        let lo = r.lowerBound.isFinite ? r.lowerBound : 0
        var hi = r.upperBound.isFinite ? r.upperBound : lo + 1
        if hi <= lo { hi = lo + max(step, 1) }
        return lo...hi
    }

    var body: some View {
        let r = SafeSlider.safeRange(range, step: step)
        Slider(value: Binding(get: { min(max(value.isFinite ? value : r.lowerBound, r.lowerBound), r.upperBound) },
                              set: { value = $0 }),
               in: r, step: step)
    }
}

/// Status dot + words, used at the top of Dashboard and Controls.
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
            Text(ble.isSimulating ? "Simulator" : ble.phase.label)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            if !ble.isSimulating, ble.phase.isLinked { SignalBars(bars: SignalStrength.from(rssi: ble.rssi).bars) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.08)))
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

/// One label/value pair inside a stats card.
struct StatCell: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(DS.tertiaryText)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Kept for the designer preview and older screens.
struct InfoTile: View {
    let title: String
    let value: String
    var color: Color = .primary
    var compact = false
    var body: some View {
        StatCell(title: title, value: value)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.card))
    }
}

/// Safe Int for display: never traps on NaN / infinity / huge values.
func safeInt(_ v: Double) -> Int {
    guard v.isFinite else { return 0 }
    return Int(max(-1_000_000, min(1_000_000, v.rounded())))
}
