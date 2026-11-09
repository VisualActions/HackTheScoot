import Foundation
import CoreBluetooth

struct FoundDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var advertisedServices: [String]
    var kind: ScooterKind
    var lastSeen: Date
}

struct SavedScooter: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var kind: ScooterKind
    var lastConnected: Date
}

struct LogEntry: Identifiable {
    enum Kind: String {
        case rx = "RX"
        case tx = "TX"
        case info = "--"
    }

    let id = UUID()
    let time: Date
    let kind: Kind
    let channel: String
    /// Bytes exactly as they went over the air.
    let raw: [UInt8]
    /// Unscrambled bytes (nil when the frame is not scrambled).
    let decoded: [UInt8]?
    let note: String

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var exportLine: String {
        var s = "\(LogEntry.timeFormatter.string(from: time)) \(kind.rawValue) \(channel)"
        if !raw.isEmpty { s += " air: " + Proto.hex(raw) }
        if let d = decoded { s += " | dec: " + Proto.hex(d) }
        if !note.isEmpty { s += " | " + note.replacingOccurrences(of: "\n", with: " / ") }
        return s
    }
}

final class BLEManager: NSObject, ObservableObject {

    // MARK: Published state

    @Published var bluetoothState = "Bluetooth: starting..."
    @Published var isPoweredOn = false
    @Published var isScanning = false
    @Published var devices: [FoundDevice] = []
    @Published var connected: CBPeripheral?
    @Published var connectedName = ""
    @Published var connectionStatus = "Not connected"
    /// Detected (or chosen) protocol for the connected device.
    @Published var kind: ScooterKind = .unknown
    /// J078: write + notify characteristics found and notify turned on.
    @Published var j078Ready = false
    @Published var characteristicsInfo: [String] = []

    @Published var status: ScooterStatus?
    @Published var lastStatusTime: Date?
    /// Gear speed limits in km/h. Live values from DB EB BA replies overwrite the captured defaults.
    @Published var limitsKmh: [Gear: Int] = [:]
    @Published var limitsLive: Set<Gear> = []
    /// Speed-limit writes: what he asked for, and what the scooter's ack said it actually set.
    @Published var limitRequested: [Gear: Int] = [:]
    @Published var limitAccepted: [Gear: Int] = [:]
    @Published var limitSentAt: [Gear: Date] = [:]
    @Published var limitAckAt: [Gear: Date] = [:]
    /// Highest speed seen this session, per gear, in the scooter's unit at the time.
    @Published var topSeen: [Gear: Double] = [:]
    @Published var tripMax: Double = 0
    @Published var passwordState = "not sent yet"
    @Published var busy: String?

    @Published var log: [LogEntry] = []
    /// Characteristics that can be written to (for the dev terminal).
    @Published var writableNames: [String] = []
    @Published var savedScooters: [SavedScooter] = []

    // Volpam / F1F1 path (v1)
    @Published var hasF1F1 = false
    @Published var volpamHeartbeatOn = false
    @Published var volpamHeartbeatsSent = 0

    // Debug options
    @Published var showOnlyScooters = false
    @Published var logKeepAlives = false
    @Published var logEveryStatus = false
    @Published var autoReconnect: Bool = UserDefaults.standard.object(forKey: "autoReconnect") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: "autoReconnect") }
    }

    let maxLogEntries = 3000

    // MARK: Private

    private var central: CBCentralManager!
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var f1f1Char: CBCharacteristic?
    private var keepAliveTimer: Timer?
    private var helloTimer: Timer?
    private var pingTimer: Timer?
    private var volpamTimer: Timer?
    private var readySince: Date?
    private var lastLoggedStatus: [UInt8] = []
    private var lastLoggedLimit: [UInt8] = []
    private var userWantsDisconnect = false
    private var forcedKind: ScooterKind?
    private var passwordWaiter: ((Bool?) -> Void)?
    private var passwordTimeout: DispatchWorkItem?
    private var playedSoundThisConnection = false
    private var pendingServices = 0

    private let savedKey = "savedScooters"
    private let lastGearKey = "lastGear"

    override init() {
        super.init()
        for g in Gear.allCases { limitsKmh[g] = g.capturedLimitKmh }
        loadSaved()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: Log

    func addLog(_ kind: LogEntry.Kind, _ channel: String, raw: [UInt8] = [], decoded: [UInt8]? = nil, note: String = "") {
        log.append(LogEntry(time: Date(), kind: kind, channel: channel, raw: raw, decoded: decoded, note: note))
        if log.count > maxLogEntries {
            log.removeFirst(log.count - maxLogEntries)
        }
    }

    func info(_ text: String) {
        addLog(.info, "--", note: text)
    }

    func clearLog() {
        log.removeAll()
    }

    func exportLogFile() -> URL? {
        var lines = ["HackTheScoot v3 log, exported \(Date())", "device: \(connectedName) kind: \(kind.short)"]
        if let s = status {
            lines.append("last status (decoded): " + Proto.hex(s.decoded))
        }
        lines.append("")
        lines.append(contentsOf: log.map { $0.exportLine })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("j078-log-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            info("Export failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Saved scooters

    private func loadSaved() {
        if let data = UserDefaults.standard.data(forKey: savedKey),
           let list = try? JSONDecoder().decode([SavedScooter].self, from: data) {
            savedScooters = list.sorted { $0.lastConnected > $1.lastConnected }
        }
    }

    private func persistSaved() {
        if let data = try? JSONEncoder().encode(savedScooters) {
            UserDefaults.standard.set(data, forKey: savedKey)
        }
    }

    private func rememberConnected() {
        guard let p = connected else { return }
        let entry = SavedScooter(id: p.identifier, name: connectedName, kind: kind, lastConnected: Date())
        savedScooters.removeAll { $0.id == p.identifier }
        savedScooters.insert(entry, at: 0)
        persistSaved()
    }

    func forget(_ s: SavedScooter) {
        savedScooters.removeAll { $0.id == s.id }
        persistSaved()
    }

    func connectSaved(_ s: SavedScooter) {
        guard isPoweredOn else { return }
        let found = central.retrievePeripherals(withIdentifiers: [s.id])
        guard let p = found.first else {
            info("\(s.name) is not known to this phone right now. Scan for it instead.")
            return
        }
        forcedKind = nil
        startConnecting(p, name: s.name)
        kind = s.kind
    }

    // MARK: Scan / connect

    func startScan() {
        guard isPoweredOn else {
            info("Can't scan: \(bluetoothState)")
            return
        }
        devices.removeAll()
        // Scan for everything: the J078 is matched by name and service, the
        // Volpam by its F1F0 / F2F0 services, and anything else is still listed.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        info("Scan started")
    }

    func stopScan() {
        if central.isScanning {
            central.stopScan()
        }
        if isScanning {
            info("Scan stopped")
        }
        isScanning = false
    }

    var visibleDevices: [FoundDevice] {
        let list = showOnlyScooters ? devices.filter { $0.kind != .unknown } : devices
        return list.sorted { a, b in
            let ra = a.kind == .unknown ? 1 : 0
            let rb = b.kind == .unknown ? 1 : 0
            if ra != rb { return ra < rb }
            return a.rssi > b.rssi
        }
    }

    func connect(_ device: FoundDevice) {
        forcedKind = nil
        startConnecting(device.peripheral, name: device.name)
        kind = device.kind
    }

    private func startConnecting(_ p: CBPeripheral, name: String) {
        stopScan()
        if let old = connected, old.identifier != p.identifier {
            central.cancelPeripheralConnection(old)
        }
        userWantsDisconnect = false
        resetSession()
        connected = p
        connectedName = name
        p.delegate = self
        connectionStatus = "Connecting to \(name)..."
        info("Connecting to \(name) (\(p.identifier.uuidString.prefix(8)))")
        central.connect(p, options: nil)
    }

    func disconnect() {
        userWantsDisconnect = true
        stopTimers()
        if let p = connected {
            central.cancelPeripheralConnection(p)
        }
        connected = nil
        connectionStatus = "Not connected"
        resetSession()
    }

    /// Let the user override auto-detect ("Treat as").
    func setKind(_ k: ScooterKind) {
        forcedKind = k
        kind = k
        info("Protocol set by hand: \(k.label)")
        stopTimers()
        j078Ready = false
        setupChannels()
    }

    private func resetSession() {
        stopTimers()
        writeChar = nil
        notifyChar = nil
        f1f1Char = nil
        hasF1F1 = false
        j078Ready = false
        readySince = nil
        characteristicsInfo = []
        writableNames = []
        status = nil
        lastStatusTime = nil
        tripMax = 0
        topSeen = [:]
        limitsLive = []
        limitRequested = [:]
        limitAccepted = [:]
        limitSentAt = [:]
        limitAckAt = [:]
        passwordState = "not sent yet"
        busy = nil
        lastLoggedStatus = []
        lastLoggedLimit = []
        playedSoundThisConnection = false
        volpamHeartbeatsSent = 0
        if let w = passwordWaiter {
            passwordWaiter = nil
            w(nil)
        }
    }

    private func stopTimers() {
        keepAliveTimer?.invalidate(); keepAliveTimer = nil
        helloTimer?.invalidate(); helloTimer = nil
        pingTimer?.invalidate(); pingTimer = nil
        volpamTimer?.invalidate(); volpamTimer = nil
        volpamHeartbeatOn = false
        passwordTimeout?.cancel(); passwordTimeout = nil
    }

    // MARK: Channel setup after discovery

    private func allCharacteristics() -> [CBCharacteristic] {
        guard let p = connected else { return [] }
        return (p.services ?? []).flatMap { $0.characteristics ?? [] }
    }

    private func setupChannels() {
        guard let p = connected else { return }
        let chars = allCharacteristics()
        writeChar = chars.first { Proto.name(for: $0.uuid) == Proto.writePrefix }
        notifyChar = chars.first { Proto.name(for: $0.uuid) == Proto.notifyPrefix }
        f1f1Char = chars.first { Proto.name(for: $0.uuid) == "F1F1" }
        hasF1F1 = f1f1Char != nil
        writableNames = chars
            .filter { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
            .map { Proto.name(for: $0.uuid) }

        if forcedKind == nil {
            var k = Proto.kind(fromServices: (p.services ?? []).map { $0.uuid })
            if connectedName.lowercased().hasPrefix(Proto.advertisedName) { k = .j078 }
            if k == .unknown && hasF1F1 { k = .volpam }
            kind = k
        }
        info("Detected: \(kind.label)")
        rememberConnected()

        switch kind {
        case .j078:
            guard writeChar != nil, let n = notifyChar else {
                info("J078 channels not found (need 6E400002 write + 6E400003 notify). Use Debug > Treat as, or check the service list.")
                return
            }
            if !n.isNotifying {
                p.setNotifyValue(true, for: n)
            }
            startJ078Session()
        case .volpam:
            info("Volpam path: notifications on, heartbeat off until you turn it on (Connect tab).")
            playStartupOnce()
        case .nusOther, .unknown:
            info("Log-only: every notification is shown in the Debug tab.")
            playStartupOnce()
        }
    }

    // MARK: J078 session

    private func startJ078Session() {
        j078Ready = true
        readySince = Date()
        connectionStatus = "Connected: \(connectedName)"
        sendRaw(Proto.helloRaw, note: "hello (raw)")
        sendRaw(Proto.pingRaw, note: "AC CC CC (raw, purpose unknown)")

        keepAliveTimer?.invalidate()
        helloTimer?.invalidate()
        pingTimer?.invalidate()
        keepAliveTimer = makeTimer(0.5) { [weak self] in
            self?.keepAliveTick()
        }
        helloTimer = makeTimer(3.0) { [weak self] in
            guard let self = self else { return }
            self.sendRaw(Proto.helloRaw, note: "hello (raw)", logIt: self.logKeepAlives)
        }
        pingTimer = makeTimer(20.0) { [weak self] in
            guard let self = self else { return }
            self.sendRaw(Proto.pingRaw, note: "AC CC CC (raw)", logIt: self.logKeepAlives)
        }
        playStartupOnce()
    }

    /// Timer that keeps firing while a list is being scrolled (.common mode).
    private func makeTimer(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: interval, repeats: true) { _ in block() }
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    private func keepAliveTick() {
        guard j078Ready else { return }
        var gear = status?.gear
        if gear == nil, let since = readySince, Date().timeIntervalSince(since) > 2 {
            // No status yet: echo the last gear we saw on an earlier ride.
            let saved = UserDefaults.standard.object(forKey: lastGearKey) as? Int
            gear = saved.flatMap { Gear(rawValue: $0) } ?? .eco
        }
        guard let g = gear else { return }
        writeJ078(Proto.keepAlive(g), note: "keep-alive (\(g.name))", logIt: logKeepAlives)
    }

    private func playStartupOnce() {
        guard !playedSoundThisConnection else { return }
        playedSoundThisConnection = true
        SoundPlayer.shared.playStartup()
    }

    // MARK: Writes

    private func writeType(for c: CBCharacteristic) -> CBCharacteristicWriteType {
        return c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
    }

    /// Scrambles a decoded frame and writes it to 6E400002.
    private func writeJ078(_ decoded: [UInt8], note: String, logIt: Bool = true) {
        guard let p = connected, let c = writeChar else {
            if logIt { info("Not sent (not connected): \(note)") }
            return
        }
        let air = Proto.encode(decoded)
        p.writeValue(Data(air), for: c, type: writeType(for: c))
        if logIt {
            addLog(.tx, "6E400002", raw: air, decoded: decoded, note: note)
        }
    }

    /// Writes bytes as-is (no scramble) to 6E400002.
    private func sendRaw(_ bytes: [UInt8], note: String, logIt: Bool = true) {
        guard let p = connected, let c = writeChar else { return }
        p.writeValue(Data(bytes), for: c, type: writeType(for: c))
        if logIt {
            addLog(.tx, "6E400002", raw: bytes, decoded: nil, note: note)
        }
    }

    var canControl: Bool { kind == .j078 && j078Ready }

    func sendCommand(_ cmd: UInt8, _ value: UInt8, note: String) {
        guard canControl else {
            info("Not sent, no J078 connected: \(note)")
            return
        }
        writeJ078(Proto.command(cmd, value), note: note)
    }

    /// One speed-limit write, only when he taps Set. No loops, no retries.
    func setSpeedLimit(_ g: Gear, kmh: Int) {
        guard canControl else {
            info("Not sent, no J078 connected: speed limit")
            return
        }
        limitRequested[g] = kmh
        limitAccepted[g] = nil
        limitAckAt[g] = nil
        limitSentAt[g] = Date()
        let tag = g.limitWriteVerified ? "" : " (experimental)"
        writeJ078(Proto.setLimit(g, kmh: kmh), note: "set speed limit \(g.name) = \(kmh) km/h\(tag)")
    }

    func setLight(_ on: Bool) {
        sendCommand(Proto.Cmd.light, on ? 0x01 : 0x00, note: on ? "light on" : "light off")
    }

    func setGear(_ g: Gear) {
        sendCommand(Proto.Cmd.gear, g.setValue, note: "gear \(g.name)")
    }

    func setStartMode(value: UInt8, label: String) {
        sendCommand(Proto.Cmd.startMode, value, note: "start mode \(String(format: "%02X", value)) (\(label))")
    }

    func setUnits(value: UInt8, label: String) {
        sendCommand(Proto.Cmd.units, value, note: "units \(String(format: "%02X", value)) (\(label))")
    }

    /// Password first (like the 365 app), then park on/off.
    func setPark(_ on: Bool, pin: String) {
        guard canControl else {
            info("Not sent, no J078 connected: park")
            return
        }
        busy = on ? "Parking..." : "Unparking..."
        sendPassword(pin) { [weak self] result in
            guard let self = self else { return }
            if result == false {
                self.info("Password WRONG, park not sent. Check the password in Settings.")
            } else {
                if result == nil {
                    // No reply in time. The 365 app's order is password then park, so send it.
                    self.info("No password reply within 2 s, sending park anyway.")
                }
                self.sendCommand(Proto.Cmd.park, on ? 0x01 : 0x00, note: on ? "park on" : "park off")
            }
            self.busy = nil
        }
    }

    func sendPassword(_ pin: String, done: @escaping (Bool?) -> Void) {
        if let w = passwordWaiter {
            passwordWaiter = nil
            w(nil)
        }
        passwordTimeout?.cancel()
        passwordWaiter = done
        passwordState = "sent, waiting..."
        writeJ078(Proto.password(pin), note: "password")
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, let w = self.passwordWaiter else { return }
            self.passwordWaiter = nil
            self.passwordState = "no reply"
            w(nil)
        }
        passwordTimeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    // MARK: Dev mode: manual sends (only when the user taps Send)

    /// Writes bytes the user typed. `scramble` runs them through the J078 encode first.
    @discardableResult
    func sendManual(_ bytes: [UInt8], scramble: Bool, to charName: String, source: String) -> Bool {
        guard !bytes.isEmpty else { return false }
        guard let p = connected,
              let c = allCharacteristics().first(where: { Proto.name(for: $0.uuid) == charName }) else {
            info("Not sent (\(source)): not connected or no characteristic \(charName)")
            return false
        }
        let air = scramble ? Proto.encode(bytes) : bytes
        p.writeValue(Data(air), for: c, type: writeType(for: c))
        let label = scramble ? Proto.txLabel(bytes) : ""
        addLog(.tx, charName, raw: air, decoded: scramble ? bytes : nil,
               note: "\(source)" + (label.isEmpty ? "" : ": " + label))
        return true
    }

    // MARK: Volpam heartbeat (v1 path)

    func setVolpamHeartbeat(_ on: Bool) {
        volpamTimer?.invalidate()
        volpamTimer = nil
        volpamHeartbeatOn = false
        guard on else {
            info("F1F1 heartbeat off")
            return
        }
        guard f1f1Char != nil, connected != nil else {
            info("No F1F1 characteristic, heartbeat unavailable")
            return
        }
        volpamHeartbeatOn = true
        info("F1F1 heartbeat on (A5 02 FD 5A every 500 ms)")
        sendVolpamHeartbeat()
        volpamTimer = makeTimer(Proto.volpamHeartbeatInterval) { [weak self] in
            self?.sendVolpamHeartbeat()
        }
    }

    private func sendVolpamHeartbeat() {
        guard let p = connected, let c = f1f1Char else { return }
        p.writeValue(Data(Proto.volpamHeartbeat), for: c, type: writeType(for: c))
        volpamHeartbeatsSent += 1
        if logKeepAlives || volpamHeartbeatsSent == 1 {
            addLog(.tx, "F1F1", raw: Proto.volpamHeartbeat, note: "heartbeat")
        }
    }

    // MARK: Incoming

    private func handleJ078(_ raw: [UInt8]) {
        let d = Proto.decode(raw)
        if let s = Proto.parseStatus(d) {
            handleStatus(s)
            // The status repeats ~15x a second; log it when something other than speed changes.
            var key = d
            if key.count > 9 { for i in 6...9 { key[i] = 0 } }
            if logEveryStatus || key != lastLoggedStatus {
                lastLoggedStatus = key
                addLog(.rx, "6E400003", raw: raw, decoded: d, note: Proto.label(d))
            }
            return
        }
        if let ack = Proto.parseLimitAck(d) {
            limitAccepted[ack.0] = ack.1
            limitAckAt[ack.0] = Date()
            limitsKmh[ack.0] = ack.1
            limitsLive.insert(ack.0)
            var note = Proto.label(d)
            if let want = limitRequested[ack.0], want != ack.1 {
                note += " (asked \(want), scooter declined)"
            }
            addLog(.rx, "6E400003", raw: raw, decoded: d, note: note)
            return
        }
        if let lim = Proto.parseLimit(d) {
            limitsKmh[lim.0] = lim.1
            limitsLive.insert(lim.0)
            if logKeepAlives || d != lastLoggedLimit {
                lastLoggedLimit = d
                addLog(.rx, "6E400003", raw: raw, decoded: d, note: Proto.label(d))
            }
            return
        }
        if Proto.isPasswordOK(d) || Proto.isPasswordWrong(d) {
            let ok = Proto.isPasswordOK(d)
            passwordState = ok ? "OK" : "WRONG"
            passwordTimeout?.cancel()
            if let w = passwordWaiter {
                passwordWaiter = nil
                w(ok)
            }
        }
        addLog(.rx, "6E400003", raw: raw, decoded: d, note: Proto.label(d))
    }

    private func handleStatus(_ s: ScooterStatus) {
        status = s
        lastStatusTime = Date()
        if s.speed > tripMax { tripMax = s.speed }
        if let g = s.gear {
            if s.speed > (topSeen[g] ?? 0) { topSeen[g] = s.speed }
            UserDefaults.standard.set(g.rawValue, forKey: lastGearKey)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isPoweredOn = central.state == .poweredOn
        switch central.state {
        case .poweredOn: bluetoothState = "Bluetooth: on"
        case .poweredOff: bluetoothState = "Bluetooth: off"
        case .unauthorized: bluetoothState = "Bluetooth: not allowed (Settings > HackTheScoot > Bluetooth)"
        case .unsupported: bluetoothState = "Bluetooth: not supported"
        case .resetting: bluetoothState = "Bluetooth: resetting"
        case .unknown: bluetoothState = "Bluetooth: unknown"
        @unknown default: bluetoothState = "Bluetooth: unknown state"
        }
        if !isPoweredOn {
            isScanning = false
            if connected != nil {
                stopTimers()
                j078Ready = false
                connectionStatus = "Bluetooth went off"
            }
            return
        }
        if autoReconnect, connected == nil, let last = savedScooters.first {
            info("Auto-connect: waiting for \(last.name)")
            connectSaved(last)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name ?? "(no name)"
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let rssi = RSSI.intValue
        if let i = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[i].rssi = rssi == 127 ? devices[i].rssi : rssi
            devices[i].lastSeen = Date()
            if devices[i].name == "(no name)" && name != "(no name)" {
                devices[i].name = name
                devices[i].kind = Proto.guessKind(name: name, services: uuids)
            }
            return
        }
        let d = FoundDevice(id: peripheral.identifier, peripheral: peripheral, name: name, rssi: rssi,
                            advertisedServices: uuids.map { Proto.name(for: $0) },
                            kind: Proto.guessKind(name: name, services: uuids), lastSeen: Date())
        devices.append(d)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = "Connected, discovering..."
        info("Connected. Discovering services")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = "Connect failed"
        info("Connect failed: \(error?.localizedDescription ?? "unknown error")")
        connected = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stopTimers()
        j078Ready = false
        info("Disconnected" + (error.map { ": \($0.localizedDescription)" } ?? ""))
        if !userWantsDisconnect && autoReconnect && connected?.identifier == peripheral.identifier {
            // Stays pending until the scooter is back in range / turned on.
            connectionStatus = "Lost connection, reconnecting..."
            resetSession()
            central.connect(peripheral, options: nil)
        } else {
            connected = nil
            connectionStatus = "Not connected"
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            info("Service discovery error: \(error.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        info("Services: " + services.map { Proto.name(for: $0.uuid) }.joined(separator: ", "))
        pendingServices = services.count
        if services.isEmpty {
            setupChannels()
        }
        for s in services {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            info("Characteristic error on \(Proto.name(for: service.uuid)): \(error.localizedDescription)")
        }
        for c in service.characteristics ?? [] {
            var props: [String] = []
            if c.properties.contains(.read) { props.append("read") }
            if c.properties.contains(.write) { props.append("write") }
            if c.properties.contains(.writeWithoutResponse) { props.append("writeNoResp") }
            if c.properties.contains(.notify) { props.append("notify") }
            if c.properties.contains(.indicate) { props.append("indicate") }
            characteristicsInfo.append("\(Proto.name(for: service.uuid)) / \(Proto.name(for: c.uuid)): \(props.joined(separator: ", "))")
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: c)
            }
        }
        // Set up once every service has answered (even with an error).
        pendingServices -= 1
        if pendingServices == 0 {
            setupChannels()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let n = Proto.name(for: characteristic.uuid)
        if let error = error {
            info("Notify on \(n) failed: \(error.localizedDescription)")
        } else {
            info("Notify on \(n): \(characteristic.isNotifying ? "on" : "off")")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        let n = Proto.name(for: characteristic.uuid)
        if n == Proto.notifyPrefix && kind == .j078 {
            handleJ078(bytes)
        } else if n == Proto.notifyPrefix {
            let d = Proto.decode(bytes)
            addLog(.rx, n, raw: bytes, decoded: d, note: Proto.label(d))
        } else {
            addLog(.rx, n, raw: bytes, note: Proto.rawHints(bytes))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            info("Write to \(Proto.name(for: characteristic.uuid)) failed: \(error.localizedDescription)")
        }
    }
}
