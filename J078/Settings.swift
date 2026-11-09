import SwiftUI
import UIKit

/// UserDefaults keys used with @AppStorage across the app.
enum Keys {
    static let speedColor = "speedColor"
    static let colorMode = "colorMode"        // solid / mode / heat
    static let gaugeStyle = "gaugeStyle"      // arc / digital / minimal
    static let bgStyle = "bgStyle"            // black / gradient / color
    static let bgColor = "bgColor"
    static let fontDesign = "fontDesign"      // rounded / mono / normal
    static let displayUnit = "displayUnit"    // scooter / mph / kmh
    static let gaugeMaxAuto = "gaugeMaxAuto"
    static let gaugeMax = "gaugeMax"
    static let showGear = "showGear"
    static let showTops = "showTops"
    static let showBattery = "showBattery"
    static let showLightPark = "showLightPark"
    static let showTrip = "showTrip"
    static let showOdo = "showOdo"
    static let showDashControls = "showDashControls"
    static let keepAwake = "keepAwake"
    static let unitsSwapped = "unitsSwapped"
    static let startSwapped = "startSwapped"
    static let password = "password"
    static let soundOn = "soundOn"
    static let soundPreset = "soundPreset"
    static let aboveStockAccepted = "aboveStockAccepted"
}

/// The two UNVERIFIED mappings, in one place so a swap is one switch.
/// Defaults come from the Nov 9 capture: his scooter sat in mile + zero start
/// with flags bits 0x01 and 0x10 set, so "bit set" = mile / zero start.
enum Mapping {
    // Units: cmd 01. Default: 01 = mile, 00 = km/h.
    static func unitsValue(mile: Bool, swapped: Bool) -> UInt8 {
        return (mile != swapped) ? 0x01 : 0x00
    }

    static func unitsIsMile(flagBit: Bool, swapped: Bool) -> Bool {
        return flagBit != swapped
    }

    // Start mode: cmd 07. Default: 01 = zero start, 00 = glide (kick) start.
    static func startValue(zero: Bool, swapped: Bool) -> UInt8 {
        return (zero != swapped) ? 0x01 : 0x00
    }

    static func startIsZero(flagBit: Bool, swapped: Bool) -> Bool {
        return flagBit != swapped
    }
}

extension Gear {
    var color: Color {
        switch self {
        case .walk: return Color(red: 0.30, green: 0.85, blue: 0.40)
        case .eco: return Color(red: 0.10, green: 0.80, blue: 0.85)
        case .drive: return Color(red: 1.00, green: 0.62, blue: 0.10)
        case .sport: return Color(red: 1.00, green: 0.20, blue: 0.25)
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .eco: return "leaf.fill"
        case .drive: return "car.fill"
        case .sport: return "flame.fill"
        }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        let v = (s.count == 6 ? UInt32(s, radix: 16) : nil) ?? 0x00E5FF
        self.init(red: Double((v >> 16) & 0xFF) / 255.0,
                  green: Double((v >> 8) & 0xFF) / 255.0,
                  blue: Double(v & 0xFF) / 255.0)
    }

    private var rgb: (CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (max(0, min(1, r)), max(0, min(1, g)), max(0, min(1, b)))
    }

    var hexString: String {
        let c = rgb
        return String(format: "#%02X%02X%02X", Int(c.0 * 255), Int(c.1 * 255), Int(c.2 * 255))
    }

    /// Mix toward another color, t = 0...1.
    func mixed(with other: Color, _ t: Double) -> Color {
        let a = rgb
        let b = other.rgb
        let k = CGFloat(max(0, min(1, t)))
        return Color(red: Double(a.0 + (b.0 - a.0) * k),
                     green: Double(a.1 + (b.1 - a.1) * k),
                     blue: Double(a.2 + (b.2 - a.2) * k))
    }
}

/// Named so it doesn't clash with SwiftUI's View.fontDesign(_:) modifier.
func speedFontDesign(_ s: String) -> Font.Design {
    switch s {
    case "mono": return .monospaced
    case "normal": return .default
    default: return .rounded
    }
}

/// Speed in the unit the user wants to see. The scooter reports speed x10 in its
/// own current unit (mph while it is set to mile).
struct SpeedDisplay {
    let value: Double
    let unit: String
    let isMile: Bool

    static func make(raw: Double, scooterIsMile: Bool, display: String) -> SpeedDisplay {
        switch display {
        case "mph":
            return SpeedDisplay(value: scooterIsMile ? raw : raw * 0.621371, unit: "mph", isMile: true)
        case "kmh":
            return SpeedDisplay(value: scooterIsMile ? raw / 0.621371 : raw, unit: "km/h", isMile: false)
        default:
            return SpeedDisplay(value: raw, unit: scooterIsMile ? "mph" : "km/h", isMile: scooterIsMile)
        }
    }
}
