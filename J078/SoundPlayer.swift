import Foundation
import AVFoundation

/// Plays the startup sound on the phone when a scooter connects.
/// The built-in sounds are generated in code (no audio files in the app);
/// "My own sound" plays an audio file picked from Files.
final class SoundPlayer: ObservableObject {
    static let shared = SoundPlayer()

    enum Preset: String, CaseIterable, Identifiable {
        case powerUp = "Power up"
        case chime = "Chime"
        case rev = "Rev"
        case scifi = "Sci-fi"
        case custom = "My own sound"

        var id: String { rawValue }
    }

    @Published var customName: String? = UserDefaults.standard.string(forKey: "customSoundName")

    private var player: AVAudioPlayer?
    private let customFileKey = "customSoundFile"

    var enabled: Bool {
        return UserDefaults.standard.object(forKey: Keys.soundOn) as? Bool ?? true
    }

    var preset: Preset {
        return Preset(rawValue: UserDefaults.standard.string(forKey: Keys.soundPreset) ?? "") ?? .powerUp
    }

    func playStartup() {
        guard enabled else { return }
        play(preset)
    }

    func play(_ p: Preset) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Still try to play.
        }
        if p == .custom, let url = customURL, FileManager.default.fileExists(atPath: url.path) {
            player = try? AVAudioPlayer(contentsOf: url)
        } else {
            player = try? AVAudioPlayer(data: Synth.wav(p == .custom ? .powerUp : p))
        }
        player?.prepareToPlay()
        player?.play()
    }

    private var documents: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var customURL: URL? {
        guard let name = UserDefaults.standard.string(forKey: customFileKey) else { return nil }
        return documents.appendingPathComponent(name)
    }

    /// Copies an audio file picked in Files into the app.
    func importCustom(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let fileName = "startup-sound." + ext
        let dest = documents.appendingPathComponent(fileName)
        if let old = customURL, FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.removeItem(at: old)
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        UserDefaults.standard.set(fileName, forKey: customFileKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: "customSoundName")
        customName = url.lastPathComponent
    }
}

/// Tiny synth that renders the built-in sounds to WAV data.
enum Synth {
    static let rate = 44100.0

    struct Tone {
        var start: Double
        var length: Double
        var f0: Double
        var f1: Double
        var amp: Double
        var saw: Bool = false
        var vibrato: Double = 0
    }

    static func tones(_ p: SoundPlayer.Preset) -> [Tone] {
        switch p {
        case .chime:
            return [Tone(start: 0, length: 0.35, f0: 880, f1: 880, amp: 0.5),
                    Tone(start: 0.18, length: 0.8, f0: 1318.5, f1: 1318.5, amp: 0.45)]
        case .rev:
            return [Tone(start: 0, length: 0.7, f0: 70, f1: 260, amp: 0.35, saw: true, vibrato: 18),
                    Tone(start: 0.6, length: 0.6, f0: 240, f1: 140, amp: 0.3, saw: true, vibrato: 12)]
        case .scifi:
            return [Tone(start: 0.00, length: 0.08, f0: 1200, f1: 1200, amp: 0.35),
                    Tone(start: 0.12, length: 0.08, f0: 1600, f1: 1600, amp: 0.35),
                    Tone(start: 0.24, length: 0.08, f0: 2000, f1: 2000, amp: 0.35),
                    Tone(start: 0.38, length: 0.45, f0: 2400, f1: 500, amp: 0.3)]
        case .powerUp, .custom:
            return [Tone(start: 0, length: 0.5, f0: 220, f1: 880, amp: 0.3, saw: true),
                    Tone(start: 0.45, length: 0.9, f0: 523.25, f1: 523.25, amp: 0.25),
                    Tone(start: 0.45, length: 0.9, f0: 659.25, f1: 659.25, amp: 0.22),
                    Tone(start: 0.45, length: 0.9, f0: 783.99, f1: 783.99, amp: 0.2)]
        }
    }

    static func wav(_ p: SoundPlayer.Preset) -> Data {
        let list = tones(p)
        let total = (list.map { $0.start + $0.length }.max() ?? 1) + 0.05
        let n = Int(total * rate)
        var samples = [Double](repeating: 0, count: n)
        for t in list {
            let s0 = Int(t.start * rate)
            let len = Int(t.length * rate)
            var phase = 0.0
            for i in 0..<len {
                let idx = s0 + i
                if idx >= n { break }
                let x = Double(i) / Double(max(len, 1))
                var f = t.f0 + (t.f1 - t.f0) * x
                if t.vibrato > 0 { f += t.vibrato * sin(2 * Double.pi * 9 * Double(i) / rate) }
                phase += f / rate
                phase -= floor(phase)
                let wave = t.saw ? (2 * phase - 1) * 0.6 + sin(2 * Double.pi * phase) * 0.4
                                 : sin(2 * Double.pi * phase)
                let attack = min(1, Double(i) / (0.01 * rate))
                let release = exp(-3.5 * x)
                samples[idx] += wave * t.amp * attack * release
            }
        }
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        let byteCount = UInt32(n * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(byteCount)
        for v in samples {
            let c = Int16(max(-1, min(1, v)) * 32000)
            u16(UInt16(bitPattern: c))
        }
        return data
    }
}
