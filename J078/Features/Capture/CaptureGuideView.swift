import SwiftUI

/// v5.0 "Help unlock your scooter / e-bike": the capture tutorial. Reachable from the
/// read-only (experimental / unknown) vehicle screen, Help, the packet logger and More.
/// Nothing here ever sends anything to a vehicle.
struct CaptureGuideView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var rec = PacketRecorder.shared
    @State private var route: CaptureRoute = .quick
    @State private var found: Int?
    @State private var done: Set<String> = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Help unlock your scooter or e-bike", systemImage: "lock.open")
                        .font(.headline)
                    Text("New brands start read-only. A capture (a recording of the Bluetooth messages while you use the brand's OFFICIAL app) shows what each button really sends, so controls can be added safely. It takes about 5 minutes.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                Picker("Route", selection: $route) {
                    Text("Quick (in the app)").tag(CaptureRoute.quick)
                    Text("Advanced (iPhone log)").tag(CaptureRoute.sysdiagnose)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(CaptureGuide.honestyNote)
            }

            Section(route.title) {
                ForEach(route == .quick ? CaptureGuide.quickSteps : CaptureGuide.sysdiagnoseSteps) { step in
                    CaptureStepRow(step: step)
                }
            }

            if route == .quick {
                Section(footer: Text("HackTheScoot only listens to unknown vehicles: it never sends them anything.")) {
                    NavigationLink { PacketLoggerView(ble: ble) } label: {
                        Label(rec.isRecording ? "Packet logger (recording, \(rec.frames.count) frames)" : "Open the packet logger", systemImage: "record.circle")
                    }
                    NavigationLink { ConnectView(ble: ble) } label: { Label("Connect", systemImage: "antenna.radiowaves.left.and.right") }
                    Button {
                        found = ble.findConnectedToThisPhone()
                    } label: { Label("Find vehicles already connected to this phone", systemImage: "link") }
                    if let f = found {
                        Text(f == 0 ? "None found. Connect the official app first, or this vehicle uses a Bluetooth service we don't look for yet: use the advanced route." : "Found \(f). Open Connect and tap it.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
            } else {
                Section(footer: Text("Apple's pages, checked Nov 10 2026. Signing in to download the profile needs an Apple Account; if yours can't, a parent's works.")) {
                    if let u = URL(string: CaptureGuide.appleBluetoothProfilePage) {
                        Link(destination: u) { Label("Apple: Bluetooth logging profile", systemImage: "safari") }
                    }
                    if let u = URL(string: CaptureGuide.appleSysdiagnosePDF) {
                        Link(destination: u) { Label("Apple: how to take a sysdiagnose (PDF)", systemImage: "doc.richtext") }
                    }
                }
            }

            Section(header: Text("Press these, one at a time"), footer: Text("Wait \(CaptureGuide.pauseSeconds) seconds between presses, and say (or tap) what you pressed. Skip anything your vehicle doesn't have. Don't ride while capturing.")) {
                ForEach(CaptureGuide.functionsToPress, id: \.self) { f in
                    Button {
                        if done.contains(f) { done.remove(f) } else { done.insert(f) }
                    } label: {
                        HStack {
                            Image(systemName: done.contains(f) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(done.contains(f) ? .green : .secondary)
                            Text(f).foregroundColor(.primary)
                        }
                    }
                    .accessibilityValue(done.contains(f) ? "done" : "not done")
                }
            }

            Section(header: Text("Privacy"), footer: Text(CaptureGuide.privacyNote)) {
                NavigationLink { CaptureSendView(ble: ble) } label: { Label("Send a capture", systemImage: "paperplane") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Capture tutorial")
    }
}

struct CaptureStepRow: View {
    let step: CaptureStep
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.18)).frame(width: 34, height: 34)
                Text("\(step.id)").font(.headline).foregroundColor(.accentColor)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Label(step.title, systemImage: step.icon).font(.subheadline.weight(.semibold))
                Text(step.detail).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(step.id): \(step.title). \(step.detail)")
    }
}

/// Share the capture: share sheet, email, or a prefilled GitHub issue. Masks PINs first.
struct CaptureSendView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var rec = PacketRecorder.shared
    @ObservedObject var garage = GarageStore.shared
    @State private var brand = ""
    @State private var model = ""
    @State private var pin = ""
    @State private var file: URL?
    @State private var warning: String?

    private var controllerLabel: String { garage.active?.controllerType.label ?? "" }
    private var vehicleLabel: String { garage.active?.vehicleType.label ?? "" }

    var body: some View {
        Form {
            Section(header: Text("About the vehicle"), footer: Text("These go in the GitHub issue title and form. Don't put a password here.")) {
                TextField("Brand (e.g. Hiboy, Fardriver)", text: $brand)
                TextField("Model (e.g. S2 Pro, ND72530)", text: $model)
                if !controllerLabel.isEmpty { HStack { Text("Controller"); Spacer(); Text(controllerLabel).foregroundColor(.secondary) } }
            }
            Section(header: Text("Mask a PIN"), footer: Text("If your vehicle has a Bluetooth PIN or password, type it here and it's replaced with ***** in the file. It isn't saved anywhere.")) {
                SecureField("Vehicle PIN or password (optional)", text: $pin)
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
            }
            Section(header: Text("The file")) {
                if rec.frames.isEmpty {
                    Text("No capture yet. Record one with the packet logger first.").foregroundColor(.secondary)
                    NavigationLink { PacketLoggerView(ble: ble) } label: { Label("Open the packet logger", systemImage: "record.circle") }
                } else if rec.isRecording {
                    Text("Still recording (\(rec.frames.count) frames). Stop it in the packet logger first.").foregroundColor(.orange)
                } else {
                    Button { prepare() } label: { Label(file == nil ? "Prepare the masked file" : "Prepare again", systemImage: "doc.badge.gearshape") }
                    if let w = warning { Label(w, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.footnote) }
                    if let u = file {
                        ShareLink(item: u) { Label("Share (AirDrop, Files, Messages...)", systemImage: "square.and.arrow.up") }
                        ShareLink(item: u, subject: Text("HackTheScoot capture: \(brand) \(model)"),
                                  message: Text("Capture for \(brand) \(model). Pressed, in order: (see the MARK lines)")) {
                            Label("Email it", systemImage: "envelope")
                        }
                    }
                }
            }
            Section(header: Text("Post it on GitHub"), footer: Text("Opens the \"New vehicle capture\" form. Drag the file into it, and list what you pressed in order. GitHub issues are public: check the file has no password first.")) {
                if let u = CaptureGuide.issueURL(brand: brand, model: model, controller: controllerLabel, vehicleType: vehicleLabel) {
                    Link(destination: u) { Label("Open a New vehicle capture issue", systemImage: "chevron.left.forwardslash.chevron.right") }
                }
            }
            if !AppJournal.shared.savedCaptures.isEmpty {
                Section(header: Text("Saved on this phone"), footer: Text("The last 10 captures are kept so a crash can't lose one.")) {
                    ForEach(AppJournal.shared.savedCaptures, id: \.self) { u in
                        ShareLink(item: u) { Label(u.lastPathComponent, systemImage: "doc.text") }
                    }
                }
            }
        }
        .navigationTitle("Send a capture")
        .onAppear {
            if brand.isEmpty, let a = garage.active, a.readOnlyUntilCapture { brand = a.compat.manufacturer == "Other" ? "" : a.compat.manufacturer }
        }
    }

    private func prepare() {
        if !pin.isEmpty { rec.extraPins.append(pin) }
        file = rec.exportURL()
        let text = rec.exportText()
        warning = CaptureSanitizer.looksUnmasked(text) ? "Something that looks like a password is still in the file. Check it before posting publicly." : nil
        pin = ""
    }
}
