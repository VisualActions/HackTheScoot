import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var ble: BLEManager
    var chooseScooter: () -> Void = {}
    @ObservedObject private var sound = SoundPlayer.shared
    @AppStorage("chosenModel") private var chosenModel = ""
    @AppStorage("devMode") private var devMode = false
    @State private var confirmDev = false

    @AppStorage(Keys.speedColor) private var speedColorHex = "#00E5FF"
    @AppStorage(Keys.colorMode) private var colorMode = "solid"
    @AppStorage(Keys.gaugeStyle) private var gaugeStyle = "arc"
    @AppStorage(Keys.bgStyle) private var bgStyle = "black"
    @AppStorage(Keys.bgColor) private var bgColorHex = "#101018"
    @AppStorage(Keys.fontDesign) private var fontName = "rounded"
    @AppStorage(Keys.displayUnit) private var displayUnit = "scooter"
    @AppStorage(Keys.gaugeMaxAuto) private var gaugeMaxAuto = true
    @AppStorage(Keys.gaugeMax) private var gaugeMaxManual = 25.0
    @AppStorage(Keys.showGear) private var showGear = true
    @AppStorage(Keys.showTops) private var showTops = true
    @AppStorage(Keys.showBattery) private var showBattery = true
    @AppStorage(Keys.showLightPark) private var showLightPark = true
    @AppStorage(Keys.showTrip) private var showTrip = true
    @AppStorage(Keys.showOdo) private var showOdo = false
    @AppStorage(Keys.showDashControls) private var showDashControls = true
    @AppStorage(Keys.keepAwake) private var keepAwake = true
    @AppStorage(Keys.unitsSwapped) private var unitsSwapped = false
    @AppStorage(Keys.startSwapped) private var startSwapped = false
    @AppStorage(Keys.password) private var password = "000000"
    @AppStorage(Keys.soundOn) private var soundOn = true
    @AppStorage(Keys.soundPreset) private var soundPreset = SoundPlayer.Preset.powerUp.rawValue

    @State private var pickingSound = false
    @State private var soundError: String?

    private let swatches = ["#00E5FF", "#39FF14", "#FF2D55", "#FF9500", "#BF5AF2", "#FFD60A", "#FFFFFF", "#0A84FF"]

    var body: some View {
        NavigationStack {
            Form {
                Section("My scooter") {
                    Button {
                        chooseScooter()
                    } label: {
                        HStack {
                            Text(ScooterModels.find(chosenModel)?.name ?? "Choose your scooter")
                            Spacer()
                            Text("Change").foregroundColor(.secondary)
                        }
                    }
                }

                Section("Speedometer color") {
                    ColorPicker("Pick any color", selection: Binding(
                        get: { Color(hex: speedColorHex) },
                        set: { speedColorHex = $0.hexString }
                    ), supportsOpacity: false)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(swatches, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Color.white, lineWidth: speedColorHex.uppercased() == hex ? 3 : 0))
                                    .onTapGesture { speedColorHex = hex }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Picker("Color mode", selection: $colorMode) {
                        Text("One color").tag("solid")
                        Text("Color per mode").tag("mode")
                        Text("Heat (red near top)").tag("heat")
                    }
                }

                Section("Dashboard") {
                    Picker("Speedometer style", selection: $gaugeStyle) {
                        Text("Arc gauge").tag("arc")
                        Text("Digital").tag("digital")
                        Text("Minimal (big number)").tag("minimal")
                    }
                    Picker("Font", selection: $fontName) {
                        Text("Rounded").tag("rounded")
                        Text("Mono").tag("mono")
                        Text("Normal").tag("normal")
                    }
                    Picker("Background", selection: $bgStyle) {
                        Text("Black").tag("black")
                        Text("Gradient").tag("gradient")
                        Text("Solid color").tag("color")
                    }
                    if bgStyle != "black" {
                        ColorPicker("Background color", selection: Binding(
                            get: { Color(hex: bgColorHex) },
                            set: { bgColorHex = $0.hexString }
                        ), supportsOpacity: false)
                    }
                    Picker("Speed unit", selection: $displayUnit) {
                        Text("Same as scooter").tag("scooter")
                        Text("Always mph").tag("mph")
                        Text("Always km/h").tag("kmh")
                    }
                    Toggle("Gauge max: auto (from sport top)", isOn: $gaugeMaxAuto)
                    if !gaugeMaxAuto {
                        Stepper("Gauge max: \(Int(gaugeMaxManual))", value: $gaugeMaxManual, in: 10...60, step: 5)
                    }
                    Toggle("Show mode name", isOn: $showGear)
                    Toggle("Show mode top speed", isOn: $showTops)
                    Toggle("Show max this ride", isOn: $showTrip)
                    Toggle("Show battery? (unverified)", isOn: $showBattery)
                    Toggle("Show light / park", isOn: $showLightPark)
                    Toggle("Show odometer? raw bytes", isOn: $showOdo)
                    Toggle("Buttons on dashboard", isOn: $showDashControls)
                    Toggle("Keep screen on while on Dash", isOn: $keepAwake)
                }

                Section("Startup sound (plays on the phone when it connects)") {
                    Toggle("Play on connect", isOn: $soundOn)
                    Picker("Sound", selection: $soundPreset) {
                        ForEach(SoundPlayer.Preset.allCases) { p in
                            Text(p.rawValue).tag(p.rawValue)
                        }
                    }
                    Button("Choose my own sound from Files...") {
                        pickingSound = true
                    }
                    if let name = sound.customName {
                        Text("My own sound: \(name)").font(.caption).foregroundColor(.secondary)
                    }
                    if let e = soundError {
                        Text(e).font(.caption).foregroundColor(.red)
                    }
                    Button("Test sound") {
                        sound.play(SoundPlayer.Preset(rawValue: soundPreset) ?? .powerUp)
                    }
                }
                .fileImporter(isPresented: $pickingSound, allowedContentTypes: [.audio]) { result in
                    switch result {
                    case .success(let url):
                        do {
                            try sound.importCustom(from: url)
                            soundPreset = SoundPlayer.Preset.custom.rawValue
                            soundError = nil
                        } catch {
                            soundError = "Couldn't use that file: \(error.localizedDescription)"
                        }
                    case .failure(let error):
                        soundError = error.localizedDescription
                    }
                }

                Section {
                    Toggle("Swap start mode (zero / glide)", isOn: $startSwapped)
                    Toggle("Swap units (mph / km/h)", isOn: $unitsSwapped)
                    HStack {
                        Text("Park password")
                        Spacer()
                        TextField("000000", text: $password)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    Toggle("Auto-connect to my last scooter", isOn: $ble.autoReconnect)
                } header: {
                    Text("Scooter")
                } footer: {
                    Text("Start mode and units are UNVERIFIED: if the scooter does the opposite of the button, flip the swap switch. Park uses the 365 app's password, 000000 unless you changed it there.")
                }

                Section {
                    Toggle("Developer mode", isOn: Binding(
                        get: { devMode },
                        set: { on in
                            if on { confirmDev = true } else { devMode = false }
                        }
                    ))
                    if devMode {
                        NavigationLink("Terminal (send codes, see every code live)") {
                            TerminalView(ble: ble)
                        }
                        NavigationLink("Experimental (command explorer)") {
                            ExperimentalView(ble: ble)
                        }
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("The terminal and the explorer only send when you tap Send. Unknown codes can change scooter settings, so try them parked or with the wheel off the ground.")
                }
                .alert("Turn on developer mode?", isPresented: $confirmDev) {
                    Button("Turn on") { devMode = true }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You can type and send any code to the scooter. Codes nobody has tested might change settings or do something unexpected.")
                }

                Section("Speed limits") {
                    NavigationLink("Speed limits (coming soon)") {
                        SpeedLimitsView(ble: ble)
                    }
                }

                Section("About") {
                    Text("J078 app v2. Talks to the J078 the same way the 365 app does (decoded from your own Bluetooth captures, Nov 9). Light, park, modes and speed are checked on your scooter. Start mode, units, battery and odometer are best guesses. Nothing in this app changes speed limits.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
