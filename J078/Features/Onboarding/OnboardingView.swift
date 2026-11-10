import SwiftUI
import CoreBluetooth

enum Onboarding {
    static let doneKey = "onboarding.v41.done"
    static var done: Bool {
        get { UserDefaults.standard.bool(forKey: doneKey) }
        set { UserDefaults.standard.set(newValue, forKey: doneKey) }
    }
}

/// First launch: welcome, why Bluetooth, your scooter, find it, the four tabs.
/// Skippable from every page, shown once, re-openable from More.
struct OnboardingView: View {
    @ObservedObject var ble: BLEManager
    var onFinish: () -> Void
    var startPage: Int = 0
    @ObservedObject var garage = GarageStore.shared
    @AppStorage("chosenModel") private var chosenModel = ""
    @State private var page = 0
    @State private var started = false

    static let pageCount = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("\(page + 1) of \(OnboardingView.pageCount)").font(.footnote.monospacedDigit()).foregroundColor(DS.tertiaryText)
                    Spacer()
                    if page < OnboardingView.pageCount - 1 {
                        Button("Skip") { finish() }.font(.body.weight(.semibold)).accessibilityHint("Skips the intro. You can open it again from More.")
                    }
                }
                .padding(.horizontal, DS.pad).padding(.top, 12)

                TabView(selection: $page) {
                    welcome.tag(0)
                    bluetooth.tag(1)
                    scooter.tag(2)
                    find.tag(3)
                    tour.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(action: next) {
                    Text(primaryTitle).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor))
                        .foregroundColor(.white)
                }
                .padding(DS.pad)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { if !started { started = true; page = min(max(0, startPage), OnboardingView.pageCount - 1) } }
    }

    private var primaryTitle: String {
        switch page {
        case 1: return ble.bluetoothStarted ? "Continue" : "Allow Bluetooth"
        case OnboardingView.pageCount - 1: return "Start riding"
        default: return "Continue"
        }
    }

    private func next() {
        if page == 1 && !ble.bluetoothStarted {
            ble.startBluetooth()   // iOS shows its permission prompt now, right after the explanation
            return
        }
        if page < OnboardingView.pageCount - 1 { withAnimation { page += 1 } } else { finish() }
    }

    private func finish() {
        Onboarding.done = true
        ble.startBluetooth()
        if chosenModel.isEmpty {
            chosenModel = (garage.active?.kind == .volpam) ? "volpam" : "j078"
        }
        onFinish()
    }

    // MARK: Pages

    private func pageLayout<C: View>(icon: String, title: String, text: String, @ViewBuilder extra: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: icon).font(.system(size: 54, weight: .semibold)).foregroundColor(.accentColor).padding(.top, 30)
                Text(title).font(.system(size: 32, weight: .bold))
                Text(text).font(.body).foregroundColor(DS.secondaryText).fixedSize(horizontal: false, vertical: true)
                extra()
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var welcome: some View {
        pageLayout(icon: "scooter", title: "Welcome to HackTheScoot",
                   text: "Your scooter's dashboard, controls, trips and diagnostics in one app. It works with the Joyhis J078 and the Volpam today, and shows honestly what works on other scooters.") {
            HStack(spacing: 12) {
                LogoView().frame(width: 56, height: 56)
                Text("Everything stays on this phone. No account needed.").font(.footnote).foregroundColor(DS.secondaryText)
            }
        }
    }

    private var bluetooth: some View {
        pageLayout(icon: "antenna.radiowaves.left.and.right", title: "Bluetooth",
                   text: "The app talks to your scooter over Bluetooth, straight from your phone. iOS will ask once. Without it the app can still run the simulator, but it can't reach a scooter.") {
            VStack(alignment: .leading, spacing: 10) {
                bullet("checkmark.shield", "Only scooters you pick get connected")
                bullet("lock", "Nothing goes through the internet")
                bullet("gearshape", "Change it any time in Settings › HackTheScoot")
                if ble.bluetoothStarted {
                    Label(ble.bluetoothState, systemImage: ble.isPoweredOn ? "checkmark.circle.fill" : "info.circle")
                        .font(.footnote.weight(.semibold)).foregroundColor(ble.isPoweredOn ? .green : .orange)
                }
            }
        }
    }

    private var scooter: some View {
        pageLayout(icon: "car.2.fill", title: "Your garage",
                   text: "Pick the scooter you ride. Each one keeps its own name, look, stats and trips. Add more any time in More › Garage.") {
            VStack(spacing: 10) {
                ForEach(garage.scooters) { s in
                    Button {
                        garage.setActive(s.id)
                        chosenModel = s.kind == .volpam ? "volpam" : (s.kind == .j078 ? "j078" : "other")
                    } label: {
                        HStack(spacing: 12) {
                            ScooterAvatar(scooter: s, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.name).font(.headline)
                                CompatBadge(level: s.compat.level)
                            }
                            Spacer()
                            Image(systemName: s.id == garage.activeID ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(s.id == garage.activeID ? .accentColor : DS.tertiaryText)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.card))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var find: some View {
        pageLayout(icon: "dot.radiowaves.left.and.right", title: "Find your scooter",
                   text: "Turn the scooter on and keep it close. Tap it below to connect. After the first time, the app connects to your active scooter on its own.") {
            VStack(alignment: .leading, spacing: 10) {
                if !ble.bluetoothStarted {
                    Text("Bluetooth isn't on for the app yet (go back one page).").font(.footnote).foregroundColor(.orange)
                } else if ble.phase.isLinked && !ble.isSimulating {
                    Label("Connected to \(ble.connectedName)", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                } else {
                    Button { ble.isScanning ? ble.stopScan() : ble.startScan() } label: {
                        Label(ble.isScanning ? "Scanning... tap to stop" : "Scan for scooters", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    ForEach(ble.visibleDevices.filter { $0.kind != .unknown }.prefix(5)) { d in
                        Button { ble.connect(d) } label: {
                            HStack { Text(d.name.isEmpty ? "Unnamed" : d.name).font(.subheadline.weight(.semibold)); Spacer(); Text(d.kind.short).foregroundColor(.secondary) }
                                .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(DS.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("No scooter nearby? Skip this. Connect later from the Dashboard, or try the simulator in More › Developer Lab.")
                    .font(.footnote).foregroundColor(DS.tertiaryText)
            }
        }
    }

    private var tour: some View {
        pageLayout(icon: "square.grid.2x2", title: "Four tabs",
                   text: "That's the whole app.") {
            VStack(alignment: .leading, spacing: 14) {
                bullet("speedometer", "Dashboard: big speed, mode, limit and your trip")
                bullet("slider.horizontal.3", "Controls: modes, light, park, speed limits, units")
                bullet("road.lanes", "Trips: every ride, replay and export")
                bullet("ellipsis.circle", "More: Garage, themes, Pro, diagnostics and dev tools")
            }
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 26).foregroundColor(.accentColor)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}
