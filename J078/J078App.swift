import SwiftUI

@main
struct J078App: App {
    @StateObject private var ble = BLEManager()
    @StateObject private var trips = TripManager()
    @StateObject private var themes = ThemeStore()

    init() {
        Keychain.migrateParkPIN()
        AppAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView(ble: ble, trips: trips)
                .environmentObject(themes)
                .preferredColorScheme(themes.colorScheme)
                .tint(themes.accent)
                .onAppear {
                    trips.attach(ble)
                    GarageStore.shared.attach(ble)
                    trips.scooterID = { GarageStore.shared.activeID }
                }
        }
    }
}

/// Dark tab bar / navigation bar to match the black screens.
enum AppAppearance {
    static func apply() {
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = UIColor(white: 0.04, alpha: 0.94)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

/// Four tabs: Dashboard, Controls, Trips, More. Every environment object is injected
/// once here, above the TabView, so every screen (and every sheet) gets it.
struct RootView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var trips: TripManager
    @EnvironmentObject var themes: ThemeStore
    @State private var tab = 0
    @State private var showConnect = false
    @State private var choosing = (UserDefaults.standard.string(forKey: "chosenModel") ?? "").isEmpty
    @State private var showStartup = StartupSettings.enabled
    @State private var showOnboarding = !Onboarding.done

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                DashboardView(ble: ble, trips: trips, openConnect: { showConnect = true })
                    .tabItem { Label("Dashboard", systemImage: "speedometer") }.tag(0)
                ControlsView(ble: ble)
                    .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }.tag(1)
                TripsView(trips: trips, ble: ble)
                    .tabItem { Label("Trips", systemImage: "road.lanes") }.tag(2)
                MoreView(ble: ble, chooseScooter: { choosing = true })
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }.tag(3)
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
        .sheet(isPresented: $showConnect) {
            NavigationView {
                ConnectView(ble: ble)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showConnect = false } } }
            }
            .environmentObject(themes)
            .preferredColorScheme(themes.colorScheme)
        }
        .fullScreenCover(isPresented: Binding(get: { showOnboarding && !showStartup }, set: { showOnboarding = $0 })) {
            OnboardingView(ble: ble, onFinish: {
                showOnboarding = false
                choosing = false
            })
            .environmentObject(themes)
        }
        .onAppear { if Onboarding.done { ble.startBluetooth() } }
        .onReceive(NotificationCenter.default.publisher(for: .hackTheScootShowOnboarding)) { _ in showOnboarding = true }
        .fullScreenCover(isPresented: Binding(get: { choosing && !showStartup && !showOnboarding }, set: { choosing = $0 })) {
            ChooseScooterView(onDone: {
                choosing = false
                showConnect = true
            })
            .environmentObject(themes)
        }
        .onChange(of: ble.phase) { p in
            // close the connect sheet once the scooter is up
            if p == .ready, showConnect, !ble.isSimulating { showConnect = false }
        }
    }
}


extension Notification.Name {
    /// More › "Show the intro again".
    static let hackTheScootShowOnboarding = Notification.Name("hackTheScootShowOnboarding")
}
