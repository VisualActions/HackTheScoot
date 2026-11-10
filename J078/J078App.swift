import SwiftUI

@main
struct J078App: App {
    @StateObject private var ble = BLEManager()
    @StateObject private var trips = TripManager()
    @StateObject private var themes = ThemeStore()

    init() { Keychain.migrateParkPIN() }

    var body: some Scene {
        WindowGroup {
            RootView(ble: ble, trips: trips)
                .environmentObject(themes)
                .preferredColorScheme(themes.colorScheme)
                .tint(themes.accent)
                .onAppear { trips.attach(ble) }
        }
    }
}

struct RootView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var trips: TripManager
    @State private var tab = 0
    @State private var choosing = (UserDefaults.standard.string(forKey: "chosenModel") ?? "").isEmpty
    @State private var showStartup = StartupSettings.enabled

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                DashboardView(ble: ble, trips: trips, goToConnect: { tab = 2 })
                    .tabItem { Label("Dash", systemImage: "speedometer") }.tag(0)
                ControlsView(ble: ble)
                    .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }.tag(1)
                ConnectView(ble: ble)
                    .tabItem { Label("Connect", systemImage: "antenna.radiowaves.left.and.right") }.tag(2)
                TripsView(trips: trips, ble: ble)
                    .tabItem { Label("Trips", systemImage: "road.lanes") }.tag(3)
                SettingsView(ble: ble, chooseScooter: { choosing = true })
                    .tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
            }
            if showStartup {
                StartupOverlay(text: StartupSettings.text, theme: StartupSettings.theme, duration: StartupSettings.duration) {
                    showStartup = false
                }
                .transition(.opacity)
                .zIndex(1)
                .onAppear { if StartupSettings.haptics { Feedback.shared.sequence([0, 0.4, 0.8]) } }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { choosing && !showStartup }, set: { choosing = $0 })) {
            ChooseScooterView(onDone: {
                choosing = false
                tab = 2
            })
        }
    }
}
