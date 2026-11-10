import SwiftUI
import PhotosUI

/// Small round badge: the scooter's photo, or its color with a scooter icon.
struct ScooterAvatar: View {
    let scooter: GarageScooter
    var size: CGFloat = 48
    @ObservedObject var garage = GarageStore.shared

    var body: some View {
        ZStack {
            if let img = garage.photo(scooter) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color(hex: scooter.colorHex).opacity(0.85)
                Image(systemName: scooter.vehicleType.icon).font(.system(size: size * 0.45, weight: .semibold)).foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct CompatBadge: View {
    let level: CompatibilityLevel
    var color: Color {
        switch level {
        case .full: return .green
        case .partial: return .blue
        case .diagnosticsOnly: return .teal
        case .experimental: return .orange
        case .unsupported: return .gray
        }
    }
    var body: some View {
        Text(level.rawValue)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.22)))
            .foregroundColor(color)
            .accessibilityLabel("Compatibility: \(level.rawValue)")
    }
}

/// More > Garage.
struct GarageView: View {
    @ObservedObject var ble: BLEManager
    @ObservedObject var garage = GarageStore.shared
    @State private var adding = false

    var body: some View {
        List {
            if garage.connectedButUnlinked {
                Section(footer: Text("This scooter is connected but not in your garage yet.")) {
                    Button { garage.addCurrent() } label: { Label("Add \(ble.connectedName) to the garage", systemImage: "plus.circle.fill") }
                }
            }
            Section(header: Text("My scooters"), footer: Text("The active scooter is the one the app auto-connects to, and new trips and stats go to it.")) {
                ForEach(garage.scooters) { s in
                    NavigationLink { GarageDetailView(ble: ble, scooterID: s.id) } label: { GarageRow(scooter: s, active: s.id == garage.activeID, connected: garage.isConnected(s)) }
                        .swipeActions(edge: .leading) {
                            if s.id != garage.activeID { Button("Make active") { garage.setActive(s.id) }.tint(.blue) }
                        }
                }
            }
            Section { Button { adding = true } label: { Label("Add a scooter or e-bike", systemImage: "plus") } }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Garage")
        .sheet(isPresented: $adding) { AddScooterView { adding = false } }
    }
}

struct GarageRow: View {
    let scooter: GarageScooter
    let active: Bool
    let connected: Bool
    var body: some View {
        HStack(spacing: 12) {
            ScooterAvatar(scooter: scooter)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(scooter.name).font(.headline).lineLimit(1)
                    if active { Text("ACTIVE").font(.caption2.weight(.heavy)).foregroundColor(.accentColor) }
                }
                Text(scooter.compat.displayName).font(.caption).foregroundColor(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    CompatBadge(level: scooter.compat.level)
                    if connected { Text("Connected").font(.caption2.weight(.semibold)).foregroundColor(.green) }
                    else if let d = scooter.lastConnected { Text("Seen \(d.formatted(.relative(presentation: .named)))").font(.caption2).foregroundColor(.secondary) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// v4.2 controller-type picker shared by add + edit.
struct ControllerPicker: View {
    @Binding var controller: ControllerType
    var body: some View {
        Picker("Controller", selection: $controller) {
            ForEach(ControllerType.allCases) { c in Text(c.label).tag(c) }
        }
    }
}

/// Model picker shared by add + edit.
struct CompatPicker: View {
    @Binding var compatID: String
    var body: some View {
        Picker("Model", selection: $compatID) {
            ForEach(CompatSeed.all) { e in Text(e.displayName).tag(e.id) }
        }
    }
}

struct AddScooterView: View {
    var done: () -> Void
    @ObservedObject var garage = GarageStore.shared
    @State private var name = ""
    @State private var compatID = "joyhis-j078"
    @State private var color = Color(hex: "#30D158")
    @State private var vehicle: VehicleType = .escooter
    @State private var controller: ControllerType = .joyhis365

    var body: some View {
        NavigationView {
            Form {
                Section("Name") { TextField("e.g. My J078", text: $name) }
                Section("Type") {
                    Picker("Vehicle", selection: $vehicle) {
                        ForEach(VehicleType.allCases) { v in Label(v.label, systemImage: v.icon).tag(v) }
                    }
                    .pickerStyle(.segmented)
                }
                Section(footer: Text(CompatSeed.find(compatID).note)) {
                    CompatPicker(compatID: $compatID)
                    HStack { Text("Compatibility"); Spacer(); CompatBadge(level: CompatSeed.find(compatID).level) }
                }
                .onChange(of: compatID) { id in controller = ControllerType.from(compatAdapter: CompatSeed.find(id).adapter) }
                Section(footer: Text(controller.note)) {
                    ControllerPicker(controller: $controller)
                    if controller.readOnlyUntilCapture {
                        Label("Live data only: needs a capture to unlock controls", systemImage: "lock.shield").font(.footnote).foregroundColor(.orange)
                    }
                }
                Section("Look") { ColorPicker("Color", selection: $color, supportsOpacity: false) }
            }
            .navigationTitle("Add vehicle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        garage.add(name: name.isEmpty ? CompatSeed.find(compatID).model : name, compatID: compatID, colorHex: color.hexString,
                                   vehicleType: vehicle, controller: controller)
                        done()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct GarageDetailView: View {
    @ObservedObject var ble: BLEManager
    let scooterID: UUID
    @ObservedObject var garage = GarageStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var confirmDelete = false

    private var scooter: GarageScooter? { garage.scooters.first { $0.id == scooterID } }

    private func binding<T>(_ kp: WritableKeyPath<GarageScooter, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { scooter?[keyPath: kp] ?? fallback },
                set: { v in if var s = scooter { s[keyPath: kp] = v; garage.update(s) } })
    }

    var body: some View {
        if let s = scooter {
            content(s)
        } else {
            Text("This scooter was removed.").foregroundColor(.secondary).navigationTitle("Garage")
        }
    }

    @ViewBuilder
    private func content(_ s: GarageScooter) -> some View {
        List {
            Section {
                HStack(spacing: 16) {
                    ScooterAvatar(scooter: s, size: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.name).font(.title3.bold())
                        CompatBadge(level: s.compat.level)
                        if garage.isConnected(s) { Text("Connected now").font(.caption.weight(.semibold)).foregroundColor(.green) }
                    }
                }
                if s.id == garage.activeID {
                    Label("Active scooter", systemImage: "checkmark.circle.fill").foregroundColor(.accentColor)
                } else {
                    Button { garage.setActive(s.id) } label: { Label("Make this the active scooter", systemImage: "arrow.right.circle") }
                }
            }
            Section("Details") {
                TextField("Name", text: binding(\.name, ""))
                Picker("Vehicle", selection: binding(\.vehicleType, .escooter)) {
                    ForEach(VehicleType.allCases) { v in Text(v.label).tag(v) }
                }
                CompatPicker(compatID: binding(\.compatID, "other"))
                ControllerPicker(controller: Binding(get: { scooter?.controllerType ?? .unknown },
                                                     set: { c in if var x = scooter { x.controller = c; garage.update(x) } }))
                ColorPicker("Color", selection: Binding(get: { Color(hex: s.colorHex) }, set: { c in if var x = scooter { x.colorHex = c.hexString; garage.update(x) } }), supportsOpacity: false)
                PhotosPicker(selection: $photoItem, matching: .images) { Label(s.photoFile == nil ? "Add a photo" : "Change photo", systemImage: "photo") }
                if s.photoFile != nil { Button("Remove photo", role: .destructive) { garage.setPhoto(nil, for: s.id) } }
            }
            Section(header: Text("Compatibility"), footer: Text(s.compat.note)) {
                HStack { Text("Adapter"); Spacer(); Text(s.compat.adapter ?? "none").foregroundColor(.secondary) }
                HStack { Text("Level"); Spacer(); Text(s.compat.level.rawValue).foregroundColor(.secondary) }
            }
            if s.readOnlyUntilCapture {
                Section(header: Text("Read-only"), footer: Text(s.controllerType.note)) {
                    Label("Live data only. Needs a capture to unlock controls.", systemImage: "lock.shield").foregroundColor(.orange)
                    NavigationLink { PacketLoggerView(ble: ble) } label: { Label("Start the packet logger", systemImage: "record.circle") }
                        .simultaneousGesture(TapGesture().onEnded { if !PacketRecorder.shared.isRecording { PacketRecorder.shared.start(ble: ble) } })
                    NavigationLink { CaptureGuideView(ble: ble) } label: { Label("Help unlock it (capture tutorial)", systemImage: "lock.open") }
                }
            }
            Section("Care") {
                NavigationLink { MaintenanceView(scooterID: s.id, trips: TripManager.sharedForMore) } label: {
                    Label("Maintenance reminders", systemImage: "wrench.and.screwdriver")
                }
            }
            Section("Notes") {
                TextEditor(text: binding(\.notes, "")).frame(minHeight: 80)
            }
            Section(header: Text("Last known"), footer: Text("Saved from this scooter only. Another scooter's numbers never land here.")) {
                if let st = s.lastStats {
                    row("Updated", st.at.formatted(date: .abbreviated, time: .shortened))
                    row("Top speed seen", String(format: "%.1f mph", Units.kmhToMph(st.topKmh)))
                    if let m = st.mode { row("Mode", m) }
                    ForEach(st.limitsKmh.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in row("\(k) limit", "\(v) km/h") }
                } else {
                    Text("Nothing yet. Connect to this scooter and its numbers show up here.").foregroundColor(.secondary)
                }
                if let n = s.bleName { row("Bluetooth name", n) }
                if s.bleID != nil {
                    Button("Unlink from this phone's Bluetooth") { garage.unlink(s.id) }
                } else if ble.phase.isLinked, !ble.isSimulating, ble.connected != nil {
                    Button("Link to the connected scooter (\(ble.connectedName))") { garage.linkCurrent(to: s.id) }
                }
            }
            Section("Trips") {
                let mine = garage.state.trips(TripStore().load(), for: s.id)
                if mine.isEmpty {
                    Text("No trips with this scooter yet.").foregroundColor(.secondary)
                } else {
                    row("Rides", "\(mine.count)")
                    row("Distance (est.)", String(format: "%.1f mi", Units.kmToMiles(mine.reduce(0) { $0 + $1.stats.distanceKm })))
                    ForEach(mine.prefix(5)) { t in TripCard(trip: t, mph: true) }
                }
            }
            Section {
                Button("Remove from garage", role: .destructive) { confirmDelete = true }
                    .disabled(garage.scooters.count <= 1)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(s.name)
        .onChange(of: photoItem) { item in
            guard let item = item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run { garage.setPhoto(data, for: s.id); photoItem = nil }
            }
        }
        .confirmationDialog("Remove \(s.name)? Its trips stay in Trips.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { garage.remove(s.id); dismiss() }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary).monospacedDigit() }
    }
}
