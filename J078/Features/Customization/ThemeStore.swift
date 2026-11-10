import SwiftUI

/// The active dashboard theme + saved layouts, persisted in UserDefaults as JSON.
final class ThemeStore: ObservableObject {
    @Published var theme: DashTheme { didSet { save() } }
    @Published var layouts: SavedLayouts { didSet { saveLayouts() } }

    private let key = "dashTheme.v1"
    private let layoutsKey = "dashLayouts.v1"

    init() {
        let ud = UserDefaults.standard
        if let d = ud.data(forKey: key), case .success(let t) = DashTheme.importJSON(d) {
            theme = t
        } else {
            var t = DashTheme()
            // carry the v3 settings over once
            if let a = ud.string(forKey: Keys.speedColor), let h = DashTheme.validHex(a) { t.accent = h }
            if let u = ud.string(forKey: Keys.displayUnit), ["scooter", "mph", "kmh"].contains(u) { t.units = u }
            if let f = ud.string(forKey: Keys.fontDesign), ["rounded", "mono", "normal"].contains(f) { t.font = f }
            theme = t
        }
        if let d = ud.data(forKey: layoutsKey), let l = try? JSONDecoder().decode(SavedLayouts.self, from: d) {
            layouts = l
        } else {
            layouts = SavedLayouts()
        }
    }

    private func save() {
        if let d = theme.exportJSON() { UserDefaults.standard.set(d, forKey: key) }
    }

    private func saveLayouts() {
        if let d = try? JSONEncoder().encode(layouts) { UserDefaults.standard.set(d, forKey: layoutsKey) }
    }

    var accent: Color { Color(hex: theme.accent) }
    func modeColor(_ g: Gear?) -> Color {
        guard let g = g else { return accent }
        return theme.useModeColor ? Color(hex: theme.modeColor(g)) : accent
    }
    var background: Color { Color(hex: theme.background) }
    var font: Font.Design { speedFontDesign(theme.font) }
    var colorScheme: ColorScheme? {
        switch theme.appearance {
        case "light": return .light
        case "system": return nil
        default: return .dark
        }
    }
}
