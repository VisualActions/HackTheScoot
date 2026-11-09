import SwiftUI

@main
struct J078App: App {
    @StateObject private var ble = BLEManager()

    var body: some Scene {
        WindowGroup {
            RootView(ble: ble)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @ObservedObject var ble: BLEManager
    @State private var tab = 0
    @State private var choosing = (UserDefaults.standard.string(forKey: "chosenModel") ?? "").isEmpty

    var body: some View {
        TabView(selection: $tab) {
            DashboardView(ble: ble, goToConnect: { tab = 2 })
                .tabItem { Label("Dash", systemImage: "speedometer") }
                .tag(0)
            ControlsView(ble: ble)
                .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }
                .tag(1)
            ConnectView(ble: ble)
                .tabItem { Label("Connect", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(2)
            DebugView(ble: ble)
                .tabItem { Label("Debug", systemImage: "ladybug") }
                .tag(3)
            SettingsView(ble: ble, chooseScooter: { choosing = true })
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .fullScreenCover(isPresented: $choosing) {
            ChooseScooterView(onDone: {
                choosing = false
                tab = 2
            })
        }
    }
}
