import SwiftUI

@main
struct J078App: App {
    @StateObject private var ble = BLEManager()
    @StateObject private var trips = TripManager()
    @StateObject private var themes = ThemeStore()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        Keychain.migrateParkPIN()
        AppAppearance.apply()
        AppJournal.shared.launched(version: AppInfo.version)   // v5.0 crash-safe log
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
                .onChange(of: scenePhase) { p in
                    switch p {
                    case .active: AppJournal.shared.becameActive()
                    case .background: AppJournal.shared.wentToBackground()
                    default: break
                    }
                }
        }
    }
}

/// Dark tab bar / navigation bar to match the black screens.
enum AppAppearance {
    static func apply() {
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        // v5.0: follows light / dark (it used to be black in light mode too)
        tab.backgroundColor = UIColor { t in
            t.userInterfaceStyle == .light ? UIColor(white: 0.97, alpha: 0.94) : UIColor(white: 0.04, alpha: 0.94)
        }
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
    @State private var wasLinked = false
    @State private var lastName = ""
    @State private var showWhatsNew = Onboarding.done && WhatsNew.shouldShow(seen: UserDefaults.standard.string(forKey: WhatsNew.seenKey), current: WhatsNew.version)
    @State private var proReturnMessage: String?

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
        .onAppear {
            if Onboarding.done { ble.startBluetooth() } else { UserDefaults.standard.set(WhatsNew.version, forKey: WhatsNew.seenKey) }
        }
        .sheet(isPresented: Binding(get: { showWhatsNew && !showStartup && !showOnboarding && !choosing }, set: { showWhatsNew = $0 })) {
            NavigationView { WhatsNewView(onDone: { showWhatsNew = false }) }
                .environmentObject(themes)
                .preferredColorScheme(themes.colorScheme)
        }
        // v5.0: the Stripe TEST checkout's thank-you page opens hackthescoot://pro-test
        .onOpenURL { url in
            guard let plan = ProReturnLink.plan(from: url), Billing.testMode else { return }
            StoreManager.shared.testUnlock = max(StoreManager.shared.testUnlock, .pro)
            UserDefaults.standard.set("stripe-test-\(plan)", forKey: "premium.unlockedBy")
            AppJournal.shared.note("pro test unlock from the Stripe test return link (\(plan))")
            proReturnMessage = ProReturnLink.note
        }
        .alert("Pro (test) is on", isPresented: Binding(get: { proReturnMessage != nil }, set: { if !$0 { proReturnMessage = nil } })) {
            Button("OK", role: .cancel) { proReturnMessage = nil }
        } message: {
            Text(proReturnMessage ?? "")
        }
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
            // v4.2 "last parked here": the link dropped (scooter turned off / walked away)
            if !p.isLinked, wasLinked, !ble.isSimulating { ParkedSpotStore.shared.noteParked(scooterName: lastName) }
            if p.isLinked { wasLinked = true; lastName = ble.connectedName } else { wasLinked = false }
        }
        .onChange(of: ble.status?.parked) { parked in
            if parked == true, !ble.isSimulating { ParkedSpotStore.shared.noteParked(scooterName: ble.connectedName) }
        }
    }
}


extension Notification.Name {
    /// More › "Show the intro again".
    static let hackTheScootShowOnboarding = Notification.Name("hackTheScootShowOnboarding")
}
