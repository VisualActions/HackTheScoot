import UIKit
import AudioToolbox

/// Subtle haptics + optional sounds. Every event can be turned off on its own
/// (Settings > Feedback). Nothing here touches Bluetooth.
final class Feedback {
    static let shared = Feedback()

    enum Event: String, CaseIterable, Identifiable {
        case connected = "Connected"
        case disconnected = "Disconnected"
        case modeChange = "Mode change"
        case tripStart = "Trip started"
        case tripEnd = "Trip ended"
        var id: String { rawValue }
        var hapticKey: String { "fb.haptic." + rawValue }
        var soundKey: String { "fb.sound." + rawValue }
    }

    /// v4.2: More > App settings > Haptics turns every vibration off at once.
    func hapticOn(_ e: Event) -> Bool { HapticsPref.on && (UserDefaults.standard.object(forKey: e.hapticKey) as? Bool ?? true) }
    func soundOn(_ e: Event) -> Bool { UserDefaults.standard.object(forKey: e.soundKey) as? Bool ?? false }

    func fire(_ e: Event) {
        DispatchQueue.main.async {
            if self.hapticOn(e) {
                switch e {
                case .connected, .tripStart:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                case .disconnected:
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                case .modeChange:
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                case .tripEnd:
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
            if self.soundOn(e) {
                let ids: [Event: SystemSoundID] = [.connected: 1057, .disconnected: 1053, .modeChange: 1104, .tripStart: 1113, .tripEnd: 1114]
                if let id = ids[e] { AudioServicesPlaySystemSound(id) }
            }
        }
    }

    /// A short haptic sequence for the startup preview.
    func sequence(_ pattern: [Double]) {
        for (i, delay) in pattern.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard HapticsPref.on else { return }
                UIImpactFeedbackGenerator(style: i == pattern.count - 1 ? .heavy : .light).impactOccurred()
            }
        }
    }
}
