import Foundation
import CoreBluetooth

struct FoundDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var advertisedServices: [String]
    var kind: ScooterKind
    var adapterName: String
    var confidence: MatchConfidence
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
        case blocked = "XX"
    }

    let id = UUID()
    let time: Date
    let kind: Kind
    let channel: String
    /// Exactly the bytes that went over the air (or would have, for blocked / simulated).
    let raw: [UInt8]
    /// Unscrambled form, when the channel is scrambled.
    let decoded: [UInt8]?
    let note: String
    var simulated: Bool = false

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var exportLine: String {
        var s = "\(LogEntry.timeFormatter.string(from: time)) \(kind.rawValue) \(channel)"
        if !raw.isEmpty { s += " air: " + Proto.hex(raw) }
        if let d = decoded { s += " | dec: " + Proto.hex(d) }
        if !note.isEmpty || simulated { s += " | " + (simulated ? "[SIM] " : "") + note }
        return s
    }

    func matches(_ q: String) -> Bool {
        if q.isEmpty { return true }
        let u = q.uppercased()
        return exportLine.uppercased().contains(u)
    }
}

/// Bluetooth transport + live scooter state. Protocol bytes come from Proto /
/// VolpamProto, safety decisions from WriteGuard, timers from SessionTimers.
final class BLEManager: NSObject, ObservableObject {

    // MARK: Published state

    @Published var bluetoothState = "Bluetooth: starting..."
    @Published var isPoweredOn = false
    @Published var isScanning = false
    @Published var devices: [FoundDevice] = []
    @Published var connected: CBPeripheral?
    @Published var connectedName = ""
    @Published var phase: ConnectionPhase = .idle
    @Published var connectionStatus = "Not connected"
    @Published var kind: ScooterKind = .unknown
    @Published var adapterID: String = GenericReadOnlyAdapter.adapterID
    @Published var matchConfidence: MatchConfidence = .none
    @Published var source: DataSource = .none
    @Published var simulationScenario: ScooterSimulator.Scenario?

    @Published var j078Ready = false
    @Published var characteristicsInfo: [String] = []
    @Published var serviceList: [String] = []
    @Published var rssi: Int?
    @Published var rxPerSecond: Double = 0
    @Published var lastRxTime: Date?
    @Published var rejectedFrames = 0
    @Published var interruptions = 0

    @Published var status: ScooterStatus?
    @Published var lastStatusTime: Date?
    @Published var volpamStatus: VolpamProto.Status?
    @Published var volpamLimits: [UInt8]?
    @Published var volpamAuthOK = false

    @Published var limitsKmh: [Gear: Int] = [:]
    @Published var limitsLive: Set<Gear> = []
    @Published var limitRequested: [Gear: Int] = [:]
    @Published var limitAccepted: [Gear: Int] = [:]
    @Published var limitSentAt: [Gear: Date] = [:]
    @Published var limitAckAt: [Gear: Date] = [:]

    @Published var topSeen: [Gear: Double] = [:]
    @Published var tripMax: Double = 0
    @Published var parkGate = ParkGate()
    @Published var passwordState = "not sent yet"
    @Published var busy: String?

    @Published var log: [LogEntry] = []
    @Published var writableNames: [String] = []
    @Published var savedScooters: [SavedScooter] = []

    @Published var hasF1F1 = false
    @Published var volpamHeartbeatOn = false
    @Published var volpamHeartbeatsSent = 0

    @Published var showOnlyScooters = false
    @Published var logKeepAlives = false
    @Published var logEveryStatus = false
    @Published var autoReconnect: Bool = UserDefaults.standard.object(forKey: "autoReconnect") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoReconnect, forKey: "autoReconnect")
            reconnect.enabled = autoReconnect
        }
    }
    /// Developer Lab: manual writes stay locked until the advanced warning is accepted.
    @Published var advancedWritesUnlocked = false {
        didSet { writeGuard.advancedUnlocked = advancedWritesUnlocked }
    }

    let maxLogEntries = 5000
    let writeGuard = WriteGuard()
    var adapter: ProtocolAdapter {
        switch adapterID {
        case Joyhis365Adapter.adapterID: return Joyhis365Adapter()
        case VolpamAdapter.adapterID: return VolpamAdapter()
        default: return GenericReadOnlyAdapter()
        }
    }

    /// Called on every valid live sample (km/h, mode, simulated?). TripManager listens.
    var onSpeedSample: ((Double, String?, Bool) -> Void)?
    var onLinkLost: (() -> Void)?

    // MARK: Private

    private var central: CBCentralManager!
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var f1f1Char: CBCharacteristic?
    private var f2f1Char: CBCharacteristic?
    private var f1f2Char: CBCharacteristic?
    private var f2f2Char: CBCharacteristic?
    private let timers = SessionTimers()
    private var reconnect = ReconnectPolicy()
    private var rxMeter = RateMeter()
    private var readySince: Date?
    private var lastLoggedStatus: [UInt8] = []
    private var lastLoggedLimit: [UInt8] = []
    private var userWantsDisconnect = false
    private var forcedKind: ScooterKind?
    private var pendingPark: Bool?
    private var playedSoundThisConnection = false
    private var pendingNotify: Set<String> = []
    private var simulator: ScooterSimulator?
    private var reconnectWork: DispatchWorkItem?

    private let savedKey = "savedScooters"
    private let lastGearKey = "lastGear"
    static let restoreID = "com.hackthescoot.central"

    override init() {
        super.init()
        for g in Gear.allCases { limitsKmh[g] = g.capturedLimitKmh }
        reconnect.enabled = autoReconnect
        loadSaved()
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: BLEManager.restoreID])
    }

    // MARK: Log

    func addLog(_ kind: LogEntry.Kind, _ channel: String, raw: [UInt8] = [], decoded: [UInt8]? = nil, note: String = "") {
        log.append(LogEntry(time: Date(), kind: kind, channel: channel, raw: raw, decoded: decoded, note: note,
                            simulated: source.isSimulated))
        if log.count > maxLogEntries { log.removeFirst(log.count - maxLogEntries) }
    }

    func info(_ text: String) { addLog(.info, "--", note: text) }
    func clearLog() { log.removeAll() }

    func exportLogFile() -> URL? {
        var lines = ["HackTheScoot v4 log, exported \(Date())",
                     "device: \(connectedName) adapter: \(adapter.displayName) source: \(source.rawValue)"]
        if let s = status { lines.append("last status (decoded): " + Proto.hex(s.decoded)) }
        lines.append("")
        lines.append(contentsOf: log.map { $0.exportLine })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hackthescoot-log-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            info("Export failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Phase

    private func setPhase(_ p: ConnectionPhase) {
        phase = p
        switch p {
        case .ready, .synchronizing:
            connectionStatus = (source == .simulation ? "SIMULATED: " : "\(p.label): ") + connectedName
        default:
            connectionStatus = p.label
        }
        writeGuard.channelReady = p.canSendCommands
    }

    var isActive: Bool { return source == .simulation || phase.isLinked }
    var isSimulating: Bool { return source == .simulation }

    // MARK: Saved scooters

    private func loadSaved() {
        if let data = UserDefaults.standard.data(forKey: savedKey),
           let list = try? JSONDecoder().decode([SavedScooter].self, from: data) {
            savedScooters = list.sorted { $0.lastConnected > $1.lastConnected }
        }
    }

    private func persistSaved() {
        if let data = try? JSONEncoder().encode(savedScooters) { UserDefaults.standard.set(data, forKey: savedKey) }
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
        guard let p = central.retrievePeripherals(withIdentifiers: [s.id]).first else {
            info("\(s.name) is not known to this phone right now. Scan for it instead.")
            return
        }
        forcedKind = nil
        startConnecting(p, name: s.name)
        kind = s.kind
    }

    // MARK: Scan

    func startScan() {
        guard isPoweredOn else { info("Can't scan: \(bluetoothState)"); return }
        if isSimulating { stopSimulation() }
        devices.removeAll()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        if !phase.isLinked { setPhase(.scanning) }
        info("Scan started")
    }

    func stopScan() {
        if central.isScanning { central.stopScan() }
        if isScanning { info("Scan stopped") }
        isScanning = false
        if phase == .scanning { setPhase(.idle) }
    }

    var visibleDevices: [FoundDevice] {
        let list = showOnlyScooters ? devices.filter { $0.kind != .unknown } : devices
        return list.sorted { a, b in
            if a.confidence != b.confidence { return a.confidence > b.confidence }
            return a.rssi > b.rssi
        }
    }

    // MARK: Connect / disconnect

    func connect(_ device: FoundDevice) {
        forcedKind = nil
        startConnecting(device.peripheral, name: device.name)
        kind = device.kind
    }

    private func startConnecting(_ p: CBPeripheral, name: String) {
        stopScan()
        if isSimulating { stopSimulation() }
        if let old = connected, old.identifier != p.identifier {
            // One scooter at a time: no two sessions can send conflicting commands.
            central.cancelPeripheralConnection(old)
        }
        userWantsDisconnect = false
        reconnectWork?.cancel()
        resetSession()
        connected = p
        connectedName = name
        source = .bluetooth
        writeGuard.source = .bluetooth
        p.delegate = self
        setPhase(.connecting)
        info("Connecting to \(name) (\(p.identifier.uuidString.prefix(8)))")
        central.connect(p, options: nil)
    }

    func disconnect() {
        userWantsDisconnect = true
        reconnectWork?.cancel()
        if isSimulating { stopSimulation(); return }
        timers.cancelAll()
        if let p = connected { central.cancelPeripheralConnection(p) }
        connected = nil
        resetSession()
        source = .none
        writeGuard.source = .none
        setPhase(.idle)
    }

    func setKind(_ k: ScooterKind) {
        forcedKind = k
        kind = k
        info("Protocol set by hand: \(k.label). Writes still need that protocol's channels.")
        timers.newSession()
        j078Ready = false
        setupChannels()
    }

    private func resetSession() {
        timers.newSession()
        writeChar = nil; notifyChar = nil
        f1f1Char = nil; f2f1Char = nil; f1f2Char = nil; f2f2Char = nil
        hasF1F1 = false
        j078Ready = false
        readySince = nil
        characteristicsInfo = []
        serviceList = []
        writableNames = []
        status = nil
        volpamStatus = nil
        volpamLimits = nil
        volpamAuthOK = false
        lastStatusTime = nil
        tripMax = 0
        topSeen = [:]
        limitsLive = []
        limitRequested = [:]
        limitAccepted = [:]
        limitSentAt = [:]
        limitAckAt = [:]
        parkGate.reset()
        pendingPark = nil
        passwordState = "not sent yet"
        busy = nil
        lastLoggedStatus = []
        lastLoggedLimit = []
        playedSoundThisConnection = false
        volpamHeartbeatOn = false
        volpamHeartbeatsSent = 0
        pendingNotify = []
        rssi = nil
        rxMeter = RateMeter()
        rxPerSecond = 0
        adapterID = GenericReadOnlyAdapter.adapterID
        matchConfidence = .none
        writeGuard.channelReady = false
    }

    // MARK: Channels

    private func allCharacteristics() -> [CBCharacteristic] {
        guard let p = connected else { return [] }
        return (p.services ?? []).flatMap { $0.characteristics ?? [] }
    }

    private func char(_ name: String) -> CBCharacteristic? {
        return allCharacteristics().first { Proto.name(for: $0.uuid) == name }
    }

    private func setupChannels() {
        guard let p = connected else { return }
        let services = (p.services ?? []).map { $0.uuid.uuidString }
        serviceList = services
        writeChar = char(Proto.writePrefix)
        notifyChar = char(Proto.notifyPrefix)
        f1f1Char = char(VolpamProto.writeChar)
        f2f1Char = char(VolpamProto.dataNotifyChar)
        f1f2Char = char(VolpamProto.passwordChar)
        f2f2Char = char(VolpamProto.authNotifyChar)
        hasF1F1 = f1f1Char != nil
        writableNames = allCharacteristics()
            .filter { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
            .map { Proto.name(for: $0.uuid) }

        let (a, conf) = AdapterRegistry.best(name: connectedName, serviceIDs: services)
        if let f = forcedKind {
            kind = f
            adapterID = AdapterRegistry.adapter(for: f).id
            matchConfidence = .nameOnly
        } else {
            kind = AdapterRegistry.kind(for: a)
            adapterID = a.id
            matchConfidence = conf
        }
        info("Identified: \(adapter.displayName) (\(adapter.level.rawValue)), match: \(matchConfidence)")
        rememberConnected()

        switch kind {
        case .j078:
            guard writeChar != nil, let n = notifyChar else {
                info("J078 channels not found (need 6E400002 write + 6E400003 notify). Read-only.")
                adapterID = GenericReadOnlyAdapter.adapterID
                setPhase(.ready)
                return
            }
            subscribe([n])
        case .volpam:
            guard f1f1Char != nil, let d = f2f1Char else {
                info("Volpam channels not found (need F1F1 write + F2F1 notify). Read-only.")
                adapterID = GenericReadOnlyAdapter.adapterID
                setPhase(.ready)
                return
            }
            subscribe([d] + (f2f2Char.map { [$0] } ?? []))
        case .nusOther, .unknown:
            // Read-only: listen to everything that can notify, write nothing.
            let notif = allCharacteristics().filter { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
            for c in notif where !c.isNotifying { p.setNotifyValue(true, for: c) }
            info("Unknown device: listening only. Every notification is shown in the Developer Lab.")
            setPhase(.ready)
            playStartupOnce()
        }
    }

    /// Commands that need a reply wait for the subscription to be CONFIRMED.
    private func subscribe(_ chars: [CBCharacteristic]) {
        guard let p = connected else { return }
        setPhase(.subscribing)
        pendingNotify = Set(chars.filter { !$0.isNotifying }.map { Proto.name(for: $0.uuid) })
        for c in chars where !c.isNotifying { p.setNotifyValue(true, for: c) }
        if pendingNotify.isEmpty { subscriptionsConfirmed() }
        // If iOS never confirms, say so instead of sending blind.
        let sid = timers.sessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, self.timers.sessionID == sid, self.phase == .subscribing else { return }
            self.info("Notifications were not confirmed in 5 s. Nothing will be sent. Try reconnecting.")
            self.setPhase(.disconnected(reason: "notifications not confirmed"))
        }
    }

    private func subscriptionsConfirmed() {
        switch kind {
        case .j078: startJ078Session()
        case .volpam: startVolpamSession()
        default: break
        }
    }

    // MARK: J078 session

    private func startJ078Session() {
        j078Ready = true
        readySince = Date()
        setPhase(.synchronizing)
        sendRaw(Proto.helloRaw, note: "hello (raw)")
        sendRaw(Proto.pingRaw, note: "AC CC CC (raw, purpose unknown)")
        timers.start("keepalive", every: 0.5) { [weak self] in self?.keepAliveTick() }
        timers.start("hello", every: 3.0) { [weak self] in
            guard let self = self else { return }
            self.sendRaw(Proto.helloRaw, note: "hello (raw)", logIt: self.logKeepAlives)
        }
        timers.start("ping", every: 20.0) { [weak self] in
            guard let self = self else { return }
            self.sendRaw(Proto.pingRaw, note: "AC CC CC (raw)", logIt: self.logKeepAlives)
        }
        startHousekeeping()
    }

    private func startHousekeeping() {
        timers.start("rssi", every: 2.0) { [weak self] in self?.connected?.readRSSI() }
        timers.start("meter", every: 0.5) { [weak self] in
            guard let self = self else { return }
            let now = Date()
            self.rxPerSecond = self.rxMeter.rate(now: now)
            var g = self.parkGate
            g.tick(now: now)
            if g != self.parkGate { self.parkGate = g; self.passwordState = g.text }
        }
    }

    private func keepAliveTick() {
        guard j078Ready, phase.canSendCommands else { return }
        var gear = status?.gear
        if gear == nil, let since = readySince, Date().timeIntervalSince(since) > 2 {
            let saved = UserDefaults.standard.object(forKey: lastGearKey) as? Int
            gear = saved.flatMap { Gear(rawValue: $0) } ?? .eco
        }
        guard let g = gear else { return }
        writeJ078(Proto.keepAlive(g), note: "keep-alive (\(g.name))", origin: .session, logIt: logKeepAlives)
    }

    private func playStartupOnce() {
        guard !playedSoundThisConnection else { return }
        playedSoundThisConnection = true
        SoundPlayer.shared.playStartup()
        Feedback.shared.fire(.connected)
    }

    // MARK: Writes (all go through writeGuard)

    private func writeType(for c: CBCharacteristic) -> CBCharacteristicWriteType {
        return c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
    }

    @discardableResult
    private func guarded(_ air: [UInt8], decoded: [UInt8]?, to c: CBCharacteristic?, channel: String,
                         safety: CommandSafety, origin: WriteOrigin, confirmed: Bool = false,
                         note: String, logIt: Bool = true, logBytes: [UInt8]? = nil) -> Bool {
        let decision = writeGuard.decide(air, channel: channel, safety: safety, origin: origin, userConfirmed: confirmed)
        guard decision == .allow, let p = connected, let ch = c else {
            if case .deny(let why) = decision {
                if logIt || origin != .session { addLog(.blocked, channel, raw: logBytes ?? air, decoded: decoded, note: "NOT sent (\(why)): \(note)") }
            } else if logIt {
                addLog(.blocked, channel, raw: logBytes ?? air, decoded: decoded, note: "NOT sent (no channel): \(note)")
            }
            return false
        }
        p.writeValue(Data(air), for: ch, type: writeType(for: ch))
        if logIt { addLog(.tx, channel, raw: logBytes ?? air, decoded: decoded, note: note) }
        return true
    }

    @discardableResult
    private func writeJ078(_ decoded: [UInt8], note: String, origin: WriteOrigin, confirmed: Bool = false, logIt: Bool = true) -> Bool {
        let safety = J078Safety.classify(decoded: decoded, scrambled: true)
        return guarded(Proto.encode(decoded), decoded: decoded, to: writeChar, channel: Proto.writePrefix,
                       safety: safety, origin: origin, confirmed: confirmed, note: note, logIt: logIt)
    }

    private func sendRaw(_ bytes: [UInt8], note: String, logIt: Bool = true) {
        let safety = J078Safety.classify(decoded: bytes, scrambled: false)
        guarded(bytes, decoded: nil, to: writeChar, channel: Proto.writePrefix, safety: safety,
                origin: .session, note: note, logIt: logIt)
    }

    var canControl: Bool {
        if isSimulating { return kind == .j078 }
        return kind == .j078 && j078Ready && phase.canSendCommands
    }

    var canControlVolpam: Bool { return !isSimulating && kind == .volpam && volpamAuthOK && phase.canSendCommands }

    func sendCommand(_ cmd: UInt8, _ value: UInt8, note: String, experimentalConfirmed: Bool = false) {
        let frame = Proto.command(cmd, value)
        if isSimulating {
            simulator?.applyCommand(frame)
            addLog(.blocked, "SIM", raw: Proto.encode(frame), decoded: frame, note: "simulated, nothing sent: \(note)")
            return
        }
        guard canControl else { info("Not sent, no J078 ready: \(note)"); return }
        let safety = J078Safety.classify(decoded: frame, scrambled: true)
        let origin: WriteOrigin = safety == .experimental ? .experimental : .control
        writeJ078(frame, note: note, origin: origin, confirmed: experimentalConfirmed)
    }

    /// Speed limit, factory range only. Sport is verified; other gears need the
    /// experimental confirmation. The readout shows what the SCOOTER acked.
    func setSpeedLimit(_ g: Gear, kmh: Int, experimentalConfirmed: Bool = false) {
        guard let frame = Proto.setLimit(g, kmh: kmh) else {
            info("Not sent: \(kmh) km/h is outside the factory range for \(g.name) (\(g.limitRange.lowerBound)-\(g.limitRange.upperBound)).")
            return
        }
        if isSimulating {
            simulator?.applyCommand(frame)
            limitRequested[g] = kmh; limitSentAt[g] = Date(); limitAccepted[g] = nil
            addLog(.blocked, "SIM", decoded: frame, note: "simulated, nothing sent: speed limit \(g.name) \(kmh)")
            return
        }
        guard canControl else { info("Not sent, no J078 ready: speed limit"); return }
        if !g.limitWriteVerified && !experimentalConfirmed { info("Not sent: \(g.name) limit is experimental and needs confirmation."); return }
        limitRequested[g] = kmh
        limitAccepted[g] = nil
        limitAckAt[g] = nil
        limitSentAt[g] = Date()
        let tag = g.limitWriteVerified ? "" : " (experimental)"
        writeJ078(frame, note: "set speed limit \(g.name) = \(kmh) km/h\(tag)",
                  origin: g.limitWriteVerified ? .control : .experimental, confirmed: experimentalConfirmed)
    }

    func setLight(_ on: Bool) { sendCommand(Proto.Cmd.light, on ? 0x01 : 0x00, note: on ? "light on" : "light off") }
    func setGear(_ g: Gear) { sendCommand(Proto.Cmd.gear, g.setValue, note: "gear \(g.name)") }
    func setStartMode(value: UInt8, label: String) {
        sendCommand(Proto.Cmd.startMode, value, note: "start mode: \(label) (experimental)", experimentalConfirmed: true)
    }
    func setUnits(value: UInt8, label: String) {
        sendCommand(Proto.Cmd.units, value, note: "units: \(label) (experimental)", experimentalConfirmed: true)
    }

    /// v4 FIX: park is sent ONLY after the scooter answers DB EB CA CA FF to the
    /// password sent in this session. A timeout or a wrong-password reply sends nothing.
    func setPark(_ on: Bool, pin: String) {
        if isSimulating {
            simulator?.applyCommand(Proto.command(Proto.Cmd.park, on ? 1 : 0))
            passwordState = "simulated (nothing sent)"
            return
        }
        guard canControl else { info("Not sent, no J078 ready: park"); return }
        if parkGate.mayPark(now: Date()) {
            sendCommand(Proto.Cmd.park, on ? 0x01 : 0x00, note: on ? "park on" : "park off")
            return
        }
        pendingPark = on
        busy = "Checking password..."
        let pw = Proto.password(pin)
        let masked: [UInt8] = Array(pw.prefix(4)) + [UInt8](repeating: 0x2A, count: 6)
        if writeJ078Password(pw, masked: masked) {
            parkGate.passwordSent(at: Date())
            passwordState = parkGate.text
        } else {
            busy = nil
            pendingPark = nil
        }
    }

    private func writeJ078Password(_ pw: [UInt8], masked: [UInt8]) -> Bool {
        let air = Proto.encode(pw)
        return guarded(air, decoded: masked, to: writeChar, channel: Proto.writePrefix, safety: .verified,
                       origin: .control, note: "password (digits hidden)", logBytes: Proto.encode(masked))
    }

    private func passwordResolved() {
        busy = nil
        passwordState = parkGate.text
        guard let on = pendingPark else { return }
        pendingPark = nil
        if parkGate.mayPark(now: Date()) {
            sendCommand(Proto.Cmd.park, on ? 0x01 : 0x00, note: on ? "park on" : "park off")
        } else {
            info("Park NOT sent: \(parkGate.text)")
        }
    }

    /// Developer Lab manual send. Locked until the advanced warning is accepted, and
    /// each send needs its own confirmation. Unknown frames are blocked by the classifier.
    func sendManual(_ bytes: [UInt8], scramble: Bool, to charName: String, source label: String) -> Bool {
        guard !isSimulating else { info("Simulation: manual frames are never sent."); return false }
        guard let c = allCharacteristics().first(where: { Proto.name(for: $0.uuid) == charName }) else {
            info("Not sent: no characteristic \(charName)")
            return false
        }
        let air = scramble ? Proto.encode(bytes) : bytes
        let safety: CommandSafety
        if charName == VolpamProto.writeChar || charName == VolpamProto.passwordChar {
            safety = VolpamProto.safety(of: bytes, to: charName)
        } else if charName == Proto.writePrefix {
            safety = J078Safety.classify(decoded: bytes, scrambled: scramble)
        } else {
            safety = .blocked
        }
        return guarded(air, decoded: scramble ? bytes : nil, to: c, channel: charName, safety: safety,
                       origin: .manual, confirmed: true, note: "manual (\(label))")
    }

    // MARK: Volpam session

    private func startVolpamSession() {
        setPhase(.authenticating)
        startHousekeeping()
        guard let pin = Keychain.get("volpamPassword"), let frame = VolpamProto.passwordFrame(pin) else {
            passwordState = "enter the Volpam's Bluetooth password in Controls"
            info("Volpam: no Bluetooth password saved. Enter it in Controls; nothing is sent until then.")
            return
        }
        sendVolpamPassword(frame)
    }

    func saveVolpamPassword(_ pin: String) -> Bool {
        guard VolpamProto.passwordFrame(pin) != nil else { return false }
        Keychain.set(pin, for: "volpamPassword")
        if kind == .volpam && phase == .authenticating, let f = VolpamProto.passwordFrame(pin) { sendVolpamPassword(f) }
        return true
    }

    private func sendVolpamPassword(_ frame: [UInt8]) {
        let target = f1f2Char ?? f1f1Char
        let ch = f1f2Char != nil ? VolpamProto.passwordChar : VolpamProto.writeChar
        let safety: CommandSafety = frame.count == 14 ? .verified : .blocked
        // The guard needs a ready channel; the password is the step that makes it ready.
        writeGuard.channelReady = true
        let ok = guarded(frame, decoded: nil, to: target, channel: ch, safety: safety, origin: .control,
                         note: VolpamProto.passwordMask, logBytes: Array(VolpamProto.passwordMask.utf8))
        writeGuard.channelReady = false
        if ok {
            passwordState = "password sent, waiting for OK..."
            let sid = timers.sessionID
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self, self.timers.sessionID == sid, !self.volpamAuthOK else { return }
                self.passwordState = "no OK from the Volpam. Nothing else will be sent."
            }
        }
    }

    private func volpamAuthenticated() {
        volpamAuthOK = true
        passwordState = "password OK"
        setPhase(.synchronizing)
        writeVolpam(VolpamProto.sessionStart, note: "session start", origin: .session)
        setVolpamHeartbeat(true)
        playStartupOnce()
    }

    @discardableResult
    private func writeVolpam(_ frame: [UInt8], note: String, origin: WriteOrigin, confirmed: Bool = false, logIt: Bool = true) -> Bool {
        return guarded(frame, decoded: nil, to: f1f1Char, channel: VolpamProto.writeChar,
                       safety: VolpamProto.safety(of: frame, to: VolpamProto.writeChar),
                       origin: origin, confirmed: confirmed, note: note, logIt: logIt)
    }

    func setVolpamHeartbeat(_ on: Bool) {
        guard kind == .volpam, f1f1Char != nil else { volpamHeartbeatOn = false; return }
        if on {
            guard volpamAuthOK else { info("Volpam heartbeat needs the password OK first."); return }
            volpamHeartbeatOn = true
            timers.start("volpamHeartbeat", every: VolpamProto.heartbeatInterval) { [weak self] in
                guard let self = self else { return }
                if self.writeVolpam(VolpamProto.heartbeat, note: "heartbeat", origin: .session, logIt: self.logKeepAlives) {
                    self.volpamHeartbeatsSent += 1
                }
            }
        } else {
            timers.stop("volpamHeartbeat")
            volpamHeartbeatOn = false
        }
    }

    /// Volpam sport limit, VERIFIED write (Modbus register 0x20, km/h x10), 6.0-35.0 only.
    func setVolpamSpeedLimit(tenthsKmh: Int) {
        guard canControlVolpam else { info("Not sent: Volpam not signed in."); return }
        guard let f = VolpamProto.speedLimitWrite(tenthsKmh: tenthsKmh) else {
            info("Not sent: outside the Volpam's factory range (6.0-35.0 km/h)."); return
        }
        let kmh = Int((Double(tenthsKmh) / 10).rounded())
        limitRequested[.sport] = kmh
        limitAccepted[.sport] = nil
        limitSentAt[.sport] = Date()
        writeVolpam(f, note: String(format: "set sport limit %.1f km/h", Double(tenthsKmh) / 10), origin: .control)
    }

    /// EXPERIMENTAL Volpam feature frame (lock / light / mode / units / start). Only from
    /// the Experimental page, after a confirmation, and only once the scooter has
    /// reported its limits so the frame repeats them unchanged.
    func sendVolpamFeatures(_ f: VolpamProto.Features, confirmed: Bool) -> String {
        guard canControlVolpam else { return "Not sent: Volpam not signed in." }
        guard let lim = volpamLimits else { return "Not sent: waiting for the Volpam to report its limits." }
        guard let frame = VolpamProto.featureFrame(f, limits: lim) else { return "Not sent: limits outside factory values." }
        let ok = writeVolpam(frame, note: "feature frame (experimental)", origin: .experimental, confirmed: confirmed)
        return ok ? "Sent once. Watch the scooter; the status echo below shows what it reports." : "Not sent (see log)."
    }

    // MARK: Simulation (never touches Bluetooth)

    func startSimulation(_ scenario: ScooterSimulator.Scenario) {
        if phase.isLinked || connected != nil { disconnect() }
        stopScan()
        resetSession()
        userWantsDisconnect = false
        source = .simulation
        writeGuard.source = .simulation
        simulationScenario = scenario
        simulator = ScooterSimulator(scenario: scenario, seed: UInt64(Date().timeIntervalSince1970))
        kind = .j078
        adapterID = Joyhis365Adapter.adapterID
        matchConfidence = .servicesAndName
        connectedName = "Simulated J078"
        j078Ready = true
        setPhase(.connecting)
        info("SIMULATION started: \(scenario.rawValue). No Bluetooth commands are ever sent in this mode.")
        let sid = timers.newSession()
        timers.start("sim", every: 0.1) { [weak self] in
            guard let self = self, self.timers.sessionID == sid, let sim = self.simulator else { return }
            let wasUp = sim.linkUp
            let frames = sim.step(dt: 0.1)
            if wasUp && !sim.linkUp { self.simLinkDown() }
            if !wasUp && sim.linkUp { self.setPhase(.synchronizing); self.info("SIM: link back") }
            for f in frames { self.handleJ078(f) }
        }
        timers.start("meter", every: 0.5) { [weak self] in
            guard let self = self else { return }
            self.rxPerSecond = self.rxMeter.rate(now: Date())
        }
        setPhase(.synchronizing)
    }

    private func simLinkDown() {
        interruptions += 1
        setPhase(.reconnecting(attempt: 1))
        info("SIM: link dropped")
        Feedback.shared.fire(.disconnected)
        onLinkLost?()
    }

    func stopSimulation() {
        guard isSimulating else { return }
        timers.newSession()
        simulator = nil
        simulationScenario = nil
        resetSession()
        source = .none
        writeGuard.source = .none
        connectedName = ""
        kind = .unknown
        setPhase(.idle)
        info("SIMULATION stopped")
    }

    /// Replay / offline decoder entry: parse frames without any session.
    func feedOffline(_ raw: [UInt8]) -> J078Incoming { return J078Incoming.parse(raw: raw) }

    // MARK: Incoming

    private func noteRx() {
        let now = Date()
        rxMeter.tick(now)
        lastRxTime = now
    }

    func handleJ078(_ raw: [UInt8]) {
        noteRx()
        let parsed = J078Incoming.parse(raw: raw)
        let d = Proto.decode(raw)
        switch parsed {
        case .status(let s):
            if phase == .synchronizing { setPhase(.ready); playStartupOnce() }
            if logEveryStatus || s.decoded != lastLoggedStatus {
                addLog(.rx, Proto.notifyPrefix, raw: raw, decoded: d, note: Proto.label(d))
                lastLoggedStatus = s.decoded
            }
            handleStatus(s)
        case .limitAck(let g, let k):
            limitAccepted[g] = k
            limitAckAt[g] = Date()
            limitsKmh[g] = k
            limitsLive.insert(g)
            addLog(.rx, Proto.notifyPrefix, raw: raw, decoded: d, note: Proto.label(d))
        case .limitReport(let g, let k):
            limitsKmh[g] = k
            limitsLive.insert(g)
            if d != lastLoggedLimit || logEveryStatus {
                addLog(.rx, Proto.notifyPrefix, raw: raw, decoded: d, note: Proto.label(d))
                lastLoggedLimit = d
            }
        case .passwordOK, .passwordWrong:
            addLog(.rx, Proto.notifyPrefix, raw: raw, decoded: d, note: Proto.label(d))
            if parkGate.reply(parsed, at: Date()) { passwordResolved() }
        case .otherReply:
            addLog(.rx, Proto.notifyPrefix, raw: raw, decoded: d, note: Proto.label(d))
        case .rejected(let why):
            rejectedFrames += 1
            addLog(.rx, Proto.notifyPrefix, raw: raw, decoded: raw.count <= 64 ? d : nil, note: "rejected: \(why)")
        }
    }

    private func handleStatus(_ s: ScooterStatus) {
        let previousGear = status?.gear
        status = s
        lastStatusTime = Date()
        if let g = s.gear {
            UserDefaults.standard.set(g.rawValue, forKey: lastGearKey)
            topSeen[g] = max(topSeen[g] ?? 0, s.speed)
            if let p = previousGear, p != g { Feedback.shared.fire(.modeChange) }
        }
        tripMax = max(tripMax, s.speed)
        let mile = Mapping.unitsIsMile(flagBit: s.unitsBit, swapped: UserDefaults.standard.bool(forKey: Keys.unitsSwapped))
        onSpeedSample?(SpeedDisplay.toKmh(s.speed, scooterIsMile: mile), s.gear?.name, isSimulating)
    }

    private func handleVolpam(_ b: [UInt8], from channel: String) {
        noteRx()
        if channel == VolpamProto.authNotifyChar || VolpamProto.isPasswordOK(b) || VolpamProto.isPasswordRejected(b) {
            addLog(.rx, channel, raw: b, note: String(decoding: b, as: UTF8.self))
            if VolpamProto.isPasswordOK(b) && !volpamAuthOK { volpamAuthenticated() }
            if VolpamProto.isPasswordRejected(b) { passwordState = "the Volpam rejected the password" }
            return
        }
        switch VolpamProto.parse(b) {
        case .status(let st):
            volpamStatus = st
            lastStatusTime = Date()
            if phase == .synchronizing { setPhase(.ready) }
            if logEveryStatus { addLog(.rx, channel, raw: b, note: "status") }
        case .limits(let l):
            volpamLimits = l
            if l.count == 4 {
                let gears: [Gear] = [.walk, .eco, .drive, .sport]
                for (i, g) in gears.enumerated() { limitsKmh[g] = Int(l[i]); limitsLive.insert(g) }
            }
            addLog(.rx, channel, raw: b, note: "limits " + l.map { String($0) }.joined(separator: "/") + " km/h")
        case .sportLimit(let k):
            limitsKmh[.sport] = k
            limitsLive.insert(.sport)
            if limitRequested[.sport] != nil, limitAccepted[.sport] == nil {
                limitAccepted[.sport] = k
                limitAckAt[.sport] = Date()
            }
            addLog(.rx, channel, raw: b, note: "sport limit now \(k) km/h")
        case .register(let reg, let v):
            addLog(.rx, channel, raw: b, note: String(format: "register %02X = ", reg) + Proto.hex(v))
        case .passwordOK, .passwordRejected:
            break
        case .rejected(let why):
            rejectedFrames += 1
            addLog(.rx, channel, raw: b, note: "rejected: \(why)")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            isPoweredOn = true
            bluetoothState = "Bluetooth: on"
            if phase == .bluetoothOff { setPhase(.idle) }
            if let p = connected, !userWantsDisconnect, p.state != .connected {
                info("Bluetooth back on: reconnecting to \(connectedName)")
                central.connect(p, options: nil)
            }
        case .poweredOff:
            isPoweredOn = false
            bluetoothState = "Bluetooth: off"
            timers.cancelAll()
            if !isSimulating { setPhase(.bluetoothOff) }
        case .unauthorized:
            isPoweredOn = false
            bluetoothState = "Bluetooth: not allowed (Settings > HackTheScoot)"
        case .unsupported:
            isPoweredOn = false
            bluetoothState = "Bluetooth: not supported on this device"
        default:
            isPoweredOn = false
            bluetoothState = "Bluetooth: \(central.state.rawValue)"
        }
    }

    /// iOS relaunched us in the background with a scooter we were connected to.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
            connected = p
            connectedName = p.name ?? "scooter"
            source = .bluetooth
            writeGuard.source = .bluetooth
            p.delegate = self
            info("Restored by iOS in the background: \(connectedName)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name ?? "(no name)"
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let ids = uuids.map { $0.uuidString }
        let (a, conf) = AdapterRegistry.best(name: name, serviceIDs: ids)
        let k = conf == .none ? Proto.guessKind(name: name, services: uuids) : AdapterRegistry.kind(for: a)
        let entry = FoundDevice(id: peripheral.identifier, peripheral: peripheral, name: name, rssi: RSSI.intValue,
                                advertisedServices: uuids.map { Proto.name(for: $0) }, kind: k,
                                adapterName: conf == .none ? "Unknown" : a.displayName, confidence: conf, lastSeen: Date())
        if let i = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[i] = entry
        } else {
            devices.append(entry)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        reconnect.onConnected()
        setPhase(.discovering)
        info("Connected, discovering services...")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        info("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        linkLost(peripheral, reason: error?.localizedDescription ?? "failed to connect")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        info("Disconnected" + (error.map { ": \($0.localizedDescription)" } ?? ""))
        linkLost(peripheral, reason: error?.localizedDescription ?? "")
    }

    private func linkLost(_ peripheral: CBPeripheral, reason: String) {
        // Timers stop the moment the link goes: no writes into a dead connection.
        let wasLive = phase == .ready || phase == .synchronizing
        timers.newSession()
        j078Ready = false
        volpamAuthOK = false
        volpamHeartbeatOn = false
        parkGate.reset()
        pendingPark = nil
        busy = nil
        writeGuard.channelReady = false
        if wasLive {
            interruptions += 1
            Feedback.shared.fire(.disconnected)
            onLinkLost?()
        }
        guard connected?.identifier == peripheral.identifier else { return }
        let action = reconnect.onDisconnect(userRequested: userWantsDisconnect, bluetoothOn: isPoweredOn)
        switch action {
        case .giveUp(let why):
            setPhase(userWantsDisconnect ? .idle : .disconnected(reason: why))
        case .reconnect(let n, let delay):
            setPhase(.reconnecting(attempt: n))
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, !self.userWantsDisconnect, let p = self.connected, p.identifier == peripheral.identifier else { return }
                // A pending connect() has no timeout: it also completes after the phone is locked,
                // as long as iOS keeps the app (bluetooth-central background mode).
                self.central.connect(p, options: nil)
            }
            reconnectWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        info("Services: " + services.map { Proto.name(for: $0.uuid) }.joined(separator: ", "))
        if services.isEmpty { setupChannels(); return }
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            var props: [String] = []
            if c.properties.contains(.read) { props.append("read") }
            if c.properties.contains(.write) { props.append("write") }
            if c.properties.contains(.writeWithoutResponse) { props.append("writeNoResp") }
            if c.properties.contains(.notify) { props.append("notify") }
            if c.properties.contains(.indicate) { props.append("indicate") }
            let line = "\(Proto.name(for: service.uuid)) / \(Proto.name(for: c.uuid)) [\(props.joined(separator: ","))]  \(c.uuid.uuidString)"
            if !characteristicsInfo.contains(line) { characteristicsInfo.append(line) }
        }
        let all = peripheral.services ?? []
        if all.allSatisfy({ $0.characteristics != nil }) { setupChannels() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let n = Proto.name(for: characteristic.uuid)
        if let e = error {
            info("Notify on \(n) failed: \(e.localizedDescription)")
            return
        }
        guard characteristic.isNotifying else { return }
        info("Notifications confirmed on \(n)")
        if pendingNotify.remove(n) != nil, pendingNotify.isEmpty, phase == .subscribing { subscriptionsConfirmed() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        let n = Proto.name(for: characteristic.uuid)
        if n == Proto.notifyPrefix && kind == .j078 {
            handleJ078(bytes)
        } else if kind == .volpam && (n == VolpamProto.dataNotifyChar || n == VolpamProto.authNotifyChar) {
            handleVolpam(bytes, from: n)
        } else {
            noteRx()
            let hints = Proto.rawHints(bytes)
            addLog(.rx, n, raw: bytes, note: hints)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if error == nil { rssi = RSSI.intValue }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // A write that iOS confirms is NOT the scooter accepting a setting: the
        // readouts only change from the scooter's own replies.
        if let e = error { info("Write to \(Proto.name(for: characteristic.uuid)) failed: \(e.localizedDescription)") }
    }
}
