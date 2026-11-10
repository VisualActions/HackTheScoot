import SwiftUI
import UniformTypeIdentifiers

/// The HackTheScoot mark, drawn in code: a speedometer dial whose needle is a
/// scooter-wheel spoke. Same geometry as the app icon (Support/make_icon.py).
struct LogoView: View {
    var progress: Double = 1      // 0...1, animates the arc + needle
    var accent: Color = Color(hex: "#00E5FF")
    var hot: Color = Color(hex: "#FF3B3B")
    var showBackground = true

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                if showBackground {
                    RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                        .fill(RadialGradient(colors: [Color(hex: "#1A2230"), Color(hex: "#05070B")], center: .center, startRadius: 0, endRadius: s * 0.7))
                }
                // outer wheel ring
                Circle().stroke(Color.white.opacity(0.10), lineWidth: s * 0.035).frame(width: s * 0.74)
                // speed arc
                Circle()
                    .trim(from: 0, to: 0.75 * max(0, min(1, progress)))
                    .stroke(AngularGradient(gradient: Gradient(colors: [accent, accent, hot]), center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(270)),
                            style: StrokeStyle(lineWidth: s * 0.075, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: s * 0.62)
                    .shadow(color: accent.opacity(0.6), radius: s * 0.03)
                // ticks
                ForEach(0..<10, id: \.self) { i in
                    Capsule().fill(Color.white.opacity(0.55))
                        .frame(width: s * 0.012, height: s * 0.045)
                        .offset(y: -s * 0.23)
                        .rotationEffect(.degrees(-135 + Double(i) * 30))
                }
                // needle
                Capsule()
                    .fill(LinearGradient(colors: [.white, hot], startPoint: .bottom, endPoint: .top))
                    .frame(width: s * 0.03, height: s * 0.24)
                    .offset(y: -s * 0.12)
                    .rotationEffect(.degrees(-135 + 230 * max(0, min(1, progress))))
                    .shadow(color: hot.opacity(0.6), radius: s * 0.02)
                // hub (the wheel axle)
                Circle().fill(Color.white).frame(width: s * 0.09)
                Circle().fill(Color(hex: "#05070B")).frame(width: s * 0.04)
            }
            .frame(width: s, height: s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("HackTheScoot logo")
    }
}

struct StartupSettings {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "startup.enabled") as? Bool ?? true }
    static var text: String { UserDefaults.standard.string(forKey: "startup.text") ?? "HACKTHESCOOT" }
    static var theme: String { UserDefaults.standard.string(forKey: "startup.theme") ?? "neon" }
    static var duration: Double { UserDefaults.standard.object(forKey: "startup.duration") as? Double ?? 2.2 }
    static var haptics: Bool { UserDefaults.standard.object(forKey: "startup.haptics") as? Bool ?? true }
    static var sound: Bool { UserDefaults.standard.object(forKey: "startup.sound") as? Bool ?? false }
}

/// The phone's startup experience. It runs on the PHONE only; it does not change
/// the scooter's own LCD.
struct StartupOverlay: View {
    var text: String
    var theme: String
    var duration: Double
    var onDone: () -> Void
    @State private var progress: Double = 0
    @State private var letters = 0
    @State private var fade = 1.0

    private var accent: Color {
        switch theme {
        case "racing": return Color(hex: "#FF3B3B")
        case "minimal": return .white
        default: return Color(hex: "#00E5FF")
        }
    }

    var body: some View {
        ZStack {
            (theme == "minimal" ? Color.black : Color(hex: "#05070B")).ignoresSafeArea()
            VStack(spacing: 28) {
                LogoView(progress: progress, accent: accent, showBackground: false)
                    .frame(width: 180, height: 180)
                Text(String(text.prefix(letters)))
                    .font(.system(size: 30, weight: .heavy, design: theme == "minimal" ? .default : .rounded))
                    .tracking(theme == "minimal" ? 2 : 6)
                    .foregroundColor(.white)
                    .shadow(color: accent.opacity(theme == "minimal" ? 0 : 0.8), radius: 10)
                    .frame(height: 40)
                Text("phone startup · does not change the scooter's display")
                    .font(.caption2).foregroundColor(.white.opacity(0.35))
            }
        }
        .opacity(fade)
        .onAppear(perform: run)
        .accessibilityLabel("Startup animation: \(text)")
    }

    private func run() {
        let d = max(0.6, min(6, duration))
        withAnimation(.easeOut(duration: d * 0.6)) { progress = 1 }
        let n = text.count
        for i in 0...n {
            DispatchQueue.main.asyncAfter(deadline: .now() + d * 0.15 + d * 0.45 * Double(i) / Double(max(1, n))) { letters = i }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d * 0.85) { withAnimation(.easeIn(duration: d * 0.15)) { fade = 0 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + d) { onDone() }
    }
}

struct StartupStudioView: View {
    @AppStorage("startup.enabled") private var enabled = true
    @AppStorage("startup.text") private var text = "HACKTHESCOOT"
    @AppStorage("startup.theme") private var theme = "neon"
    @AppStorage("startup.duration") private var duration = 2.2
    @AppStorage("startup.haptics") private var haptics = true
    @AppStorage("startup.sound") private var sound = false
    @AppStorage(Keys.soundPreset) private var preset = SoundPlayer.Preset.powerUp.rawValue
    @ObservedObject private var player = SoundPlayer.shared
    @State private var previewing = false
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        Form {
            Section(footer: Text("This is the iPhone app's startup. It does not modify the scooter's own LCD (see LCD research).")) {
                Toggle("Play on app launch", isOn: $enabled)
                Button { previewing = true } label: { Label("Preview full startup", systemImage: "play.fill") }
            }
            Section("Animation") {
                TextField("Startup text", text: $text)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: text) { v in if v.count > 20 { text = String(v.prefix(20)) } }
                Picker("Theme", selection: $theme) {
                    Text("Neon").tag("neon"); Text("Racing").tag("racing"); Text("Minimal").tag("minimal")
                }
                VStack(alignment: .leading) {
                    Text(String(format: "Duration: %.1f s", duration))
                    Slider(value: $duration, in: 0.8...5, step: 0.1)
                }
                LogoView(progress: 0.8).frame(height: 120)
            }
            Section("Sound and haptics") {
                Toggle("Startup sound", isOn: $sound)
                Picker("Sound", selection: $preset) {
                    ForEach(SoundPlayer.Preset.allCases) { p in Text(p.rawValue).tag(p.rawValue) }
                }
                Button("Import audio file...") { importing = true }
                if let n = player.customName { Text("My own sound: \(n)").font(.footnote).foregroundColor(.secondary) }
                if let e = importError { Text(e).font(.footnote).foregroundColor(.red) }
                Toggle("Haptic sequence", isOn: $haptics)
            }
        }
        .navigationTitle("Startup Studio")
        .fullScreenCover(isPresented: $previewing) {
            StartupOverlay(text: text, theme: theme, duration: duration) { previewing = false }
                .onAppear {
                    if sound, let p = SoundPlayer.Preset(rawValue: preset) { SoundPlayer.shared.play(p) }
                    if haptics { Feedback.shared.sequence([0, duration * 0.2, duration * 0.4, duration * 0.6]) }
                }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do { try SoundPlayer.shared.importCustom(from: url); preset = SoundPlayer.Preset.custom.rawValue; importError = nil }
                catch { importError = "Couldn't import: \(error.localizedDescription)" }
            case .failure(let e): importError = e.localizedDescription
            }
        }
    }
}
