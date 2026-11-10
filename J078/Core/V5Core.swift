import Foundation

// HackTheScoot 5.0: pure logic for the 5.0 features (no UI, no CoreBluetooth objects),
// so every rule here is unit-tested in CI.

// MARK: - Capture tutorial

struct CaptureStep: Identifiable, Equatable {
    let id: Int
    let title: String
    let detail: String
    let icon: String
}

enum CaptureRoute: String, CaseIterable, Identifiable {
    case quick, sysdiagnose
    var id: String { rawValue }
    var title: String { return self == .quick ? "Quick: the in-app packet logger" : "Advanced: iPhone Bluetooth log (sysdiagnose)" }
}

enum CaptureGuide {
    static let repo = "VisualActions/HackTheScoot"
    static let issueTemplate = "new-vehicle-capture.yml"
    static let pauseSeconds = 5

    /// Apple's public pages for the advanced route (checked Nov 10 2026).
    static let appleBluetoothProfilePage = "https://developer.apple.com/bug-reporting/profiles-and-logs/?name=bluetooth"
    static let appleSysdiagnosePDF = "https://podcasters.apple.com/assets/iOS-sysdiagnose-logging-instructions.pdf"

    /// What to press in the official app, one at a time, in this order.
    static let functionsToPress: [String] = [
        "Lights on", "Lights off",
        "Mode / gear 1", "Mode / gear 2", "Mode / gear 3", "Mode / gear 4 (if it has one)",
        "Speed limit changed (say the number)",
        "Park / lock on", "Park / lock off",
        "Cruise control on / off (if it has it)",
        "Units mph / km/h (if it has it)",
        "Zero start / kick start (if it has it)",
    ]

    /// Short labels for the "I pressed..." buttons in the packet logger.
    static let quickMarks: [String] = ["Lights on", "Lights off", "Mode up", "Mode down", "Speed limit", "Park on", "Park off", "Other"]

    static let quickSteps: [CaptureStep] = [
        CaptureStep(id: 1, title: "Get ready",
                    detail: "Install the vehicle's OFFICIAL app and check it works. Turn the vehicle on and keep the phone next to it. Write down the brand, model and (if the official app shows it) the firmware version.",
                    icon: "checklist"),
        CaptureStep(id: 2, title: "Start the packet logger",
                    detail: "In HackTheScoot: More > Packet logger > Start recording. Leave it running the whole time.",
                    icon: "record.circle"),
        CaptureStep(id: 3, title: "Connect",
                    detail: "Open the official app and connect it to the vehicle. Then come back to HackTheScoot > Connect and tap the vehicle. If it isn't listed, tap \"Find vehicles already connected to this phone\". Unknown vehicles are read-only: HackTheScoot only listens.",
                    icon: "antenna.radiowaves.left.and.right"),
        CaptureStep(id: 4, title: "Press one thing at a time in the official app",
                    detail: "Lights on, lights off, each mode / gear, a speed-limit change, park on, park off. After each press, tap the matching \"I pressed...\" button in the logger, then wait 5 seconds before the next one. Don't ride while you do this.",
                    icon: "hand.tap"),
        CaptureStep(id: 5, title: "Stop and export",
                    detail: "Back in the packet logger: Stop recording, then Share capture. You get a .txt file.",
                    icon: "stop.circle"),
        CaptureStep(id: 6, title: "Send it",
                    detail: "Open a \"New vehicle capture\" issue on GitHub and drag the file in, or email it, or use the share sheet. Say what you pressed and in what order.",
                    icon: "paperplane"),
    ]

    static let sysdiagnoseSteps: [CaptureStep] = [
        CaptureStep(id: 1, title: "Install Apple's Bluetooth logging profile",
                    detail: "On the iPhone, open developer.apple.com/bug-reporting/profiles-and-logs/?name=bluetooth in Safari. Under \"Bluetooth for iOS/iPadOS\" tap Profile, sign in with an Apple Account (a free Apple Developer sign-in) and allow the download. Then Settings > Profile Downloaded > Install. Apple's \"Instructions\" PDF on the same page has the details.",
                    icon: "doc.badge.gearshape"),
        CaptureStep(id: 2, title: "Record what you press",
                    detail: "Start a screen recording with the microphone on (Control Center > long-press Screen Recording > Microphone on), so the video shows the time and what you tapped. Or write the time of every press down.",
                    icon: "record.circle"),
        CaptureStep(id: 3, title: "Use the official app",
                    detail: "Connect with the official app, then press one thing at a time: lights on, lights off, each mode, a speed-limit change, park on, park off. Pause 5 seconds between presses and say out loud what you pressed.",
                    icon: "hand.tap"),
        CaptureStep(id: 4, title: "Trigger a sysdiagnose",
                    detail: "Right after, press and release BOTH volume buttons and the side (or top) button at the same time, quickly: Apple says about 250 milliseconds. Holding longer than 1 second locks the phone (or opens the power-off screen) instead. A short vibration and a screenshot mean it started.",
                    icon: "iphone.radiowaves.left.and.right"),
        CaptureStep(id: 5, title: "Wait about 10 minutes, then find the file",
                    detail: "Settings > Privacy & Security > Analytics & Improvements > Analytics Data. Look for \"sysdiagnose_\" with today's date. If you only see new \"stacks-\" files and no sysdiagnose, it didn't start: do step 4 again.",
                    icon: "folder"),
        CaptureStep(id: 6, title: "Send it privately",
                    detail: "Tap the sysdiagnose file, then Share (AirDrop to a computer, or save to Files). It is big and holds a lot about your phone, so don't post it publicly. The Bluetooth part is logs/Bluetooth/bluetoothd-hci-latest.pklg inside it: send that, plus your screen recording.",
                    icon: "paperplane"),
        CaptureStep(id: 7, title: "Remove the profile",
                    detail: "When you're done: Settings > General > VPN & Device Management, tap the Bluetooth logging profile, Remove.",
                    icon: "trash"),
    ]

    static let privacyNote = "Captures can contain your vehicle's Bluetooth password or PIN. HackTheScoot masks the ones it knows (the J078 password, Volpam AT+PWD, and any PIN you type below), but it can't recognise every brand's. Never post a password publicly: check the file first, or send it privately."

    static let honestyNote = "What each route can see: iPhone apps can't read what ANOTHER app sends, so the quick route records what the vehicle sends back (its status changing as you press things). The advanced route records both directions, which is what's usually needed to unlock controls. Send both if you can."

    /// The GitHub "New vehicle capture" issue, with what we know filled in.
    static func issueURL(brand: String = "", model: String = "", controller: String = "", vehicleType: String = "") -> URL? {
        var c = URLComponents(string: "https://github.com/\(repo)/issues/new")
        var items = [URLQueryItem(name: "template", value: issueTemplate)]
        let title = ["Capture:", brand, model].filter { !$0.isEmpty }.joined(separator: " ")
        items.append(URLQueryItem(name: "title", value: title == "Capture:" ? "Capture: (brand model)" : title))
        if !brand.isEmpty { items.append(URLQueryItem(name: "brand", value: String(brand.prefix(60)))) }
        if !model.isEmpty { items.append(URLQueryItem(name: "model", value: String(model.prefix(80)))) }
        if !controller.isEmpty { items.append(URLQueryItem(name: "controller", value: String(controller.prefix(60)))) }
        if !vehicleType.isEmpty { items.append(URLQueryItem(name: "vehicle", value: vehicleType)) }
        // GitHub reads issue templates from the default branch (main = v3 until PR #2 is merged),
        // so until then the same questions ride in the body of a blank issue.
        items.append(URLQueryItem(name: "body", value: issueBody(brand: brand, model: model, controller: controller, vehicleType: vehicleType)))
        c?.queryItems = items
        return c?.url
    }

    static func issueBody(brand: String = "", model: String = "", controller: String = "", vehicleType: String = "") -> String {
        return """
        **Brand:** \(brand)
        **Model:** \(model)
        **Vehicle type:** \(vehicleType)
        **Controller (if known):** \(controller)
        **Firmware (if known):**
        **Official app + version:**
        **How it was captured:** HackTheScoot packet logger / iPhone sysdiagnose

        **What I pressed, in order (with times if you have them):**
        1.

        **Capture file:** (drag the .txt or .pklg here)

        - [ ] I checked the file has no password, PIN or personal info in it (issues are public).
        """
    }

    /// Service UUIDs used to find a vehicle that another app on this phone is already connected to.
    static let knownServiceUUIDs: [String] = [
        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E",   // Nordic UART (J078 / Ninebot family)
        "FFE0", "FFF0", "FFB0", "FEE7",           // common serial modules (Fardriver and others)
        "F1F0", "F2F0",                           // Zydtech / Volpam style
        "180A",                                   // Device Information
    ]
}

/// Masks passwords in an exported capture. Pure, so it is tested.
enum CaptureSanitizer {
    /// "AT+PWD" in hex as it appears in an export line.
    static let atPwdHex = "41 54 2B 50 57 44"

    /// Masks: Zydtech-style AT+PWD[...] payloads (in hex and as text) and every PIN in `pins`
    /// (as text, and as ASCII bytes in hex).
    static func mask(_ text: String, pins: [String] = []) -> String {
        var out = text
        // AT+PWD as text: AT+PWD[123456] -> AT+PWD[******]
        if let re = try? NSRegularExpression(pattern: "AT\\+PWD\\[?[^\\]\\s|]{1,16}\\]?", options: []) {
            let r = NSRange(out.startIndex..., in: out)
            out = re.stringByReplacingMatches(in: out, options: [], range: r, withTemplate: "AT+PWD[******]")
        }
        // AT+PWD in hex: mask up to 16 following bytes (stop at "]" = 5D)
        out = out.components(separatedBy: "\n").map(maskHexAtPwd).joined(separator: "\n")
        for raw in pins {
            let pin = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard pin.count >= 3 else { continue }
            out = out.replacingOccurrences(of: pin, with: String(repeating: "*", count: pin.count))
            let hex = pin.utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
            out = out.replacingOccurrences(of: hex, with: Array(repeating: "**", count: pin.utf8.count).joined(separator: " "))
        }
        return out
    }

    private static func maskHexAtPwd(_ line: String) -> String {
        guard let r = line.range(of: atPwdHex) else { return line }
        let head = String(line[..<r.upperBound])
        var rest = String(line[r.upperBound...])
        var tokens = rest.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        // tokens[0] is "" (the space after AT+PWD)
        var masked = 0
        var i = 0
        while i < tokens.count && masked < 17 {
            let t = tokens[i]
            if t.isEmpty { i += 1; continue }
            guard t.count == 2, UInt8(t, radix: 16) != nil else { break }
            if t == "5D" { break }
            if t != "5B" { tokens[i] = "**" }
            masked += 1
            i += 1
        }
        rest = tokens.joined(separator: " ")
        return head + rest
    }

    /// True if the text still looks like it carries a password.
    static func looksUnmasked(_ text: String) -> Bool {
        if let re = try? NSRegularExpression(pattern: "AT\\+PWD\\[?[0-9A-Za-z]{3,}", options: []) {
            if re.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil { return true }
        }
        return false
    }
}

// MARK: - Ride history search / filter

struct TripFilter: Equatable {
    enum Source: String, CaseIterable, Identifiable { case all, real, simulated; var id: String { rawValue } }
    enum Period: String, CaseIterable, Identifiable { case all, week, month, year; var id: String { rawValue }
        var label: String {
            switch self { case .all: return "Any time"; case .week: return "7 days"; case .month: return "30 days"; case .year: return "This year" }
        }
    }
    var query = ""
    var vehicleID: UUID? = nil
    var source: Source = .all
    var period: Period = .all
    var withRouteOnly = false

    var isActive: Bool { return !query.isEmpty || vehicleID != nil || source != .all || period != .all || withRouteOnly }

    func apply(_ trips: [Trip], now: Date = Date(), calendar: Calendar = .current) -> [Trip] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trips.filter { t in
            if let v = vehicleID, t.scooterID != v { return false }
            switch source {
            case .all: break
            case .real: if t.source == "simulation" { return false }
            case .simulated: if t.source != "simulation" { return false }
            }
            switch period {
            case .all: break
            case .week: if t.start < now.addingTimeInterval(-7 * 86400) { return false }
            case .month: if t.start < now.addingTimeInterval(-30 * 86400) { return false }
            case .year: if calendar.component(.year, from: t.start) != calendar.component(.year, from: now) { return false }
            }
            if withRouteOnly && (t.route?.count ?? 0) < 2 { return false }
            if !q.isEmpty {
                let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
                let hay = (t.scooterName + " " + f.string(from: t.start) + " " + t.source + " " + (t.samples.compactMap { $0.mode }.joined(separator: " "))).lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }.sorted { $0.start > $1.start }
    }
}

// MARK: - GPS route math

enum RouteMath {
    /// Great-circle distance in km (haversine).
    static func km(_ a: Trip.RoutePoint, _ b: Trip.RoutePoint) -> Double {
        let r = 6371.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let la1 = a.lat * .pi / 180, la2 = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(max(0, h))))
    }

    static func isValid(_ p: Trip.RoutePoint) -> Bool {
        return p.lat.isFinite && p.lon.isFinite && abs(p.lat) <= 90 && abs(p.lon) <= 180 && !(p.lat == 0 && p.lon == 0)
    }

    /// Route length in km; jumps over 1 km between two points (GPS glitches) are skipped.
    static func lengthKm(_ route: [Trip.RoutePoint]) -> Double {
        let pts = route.filter(isValid)
        guard pts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            let d = km(pts[i - 1], pts[i])
            if d < 1.0 { total += d }
        }
        return total
    }

    /// Should a new GPS point be kept? (at least `minMeters` from the last kept one)
    static func shouldKeep(_ p: Trip.RoutePoint, after last: Trip.RoutePoint?, minMeters: Double = 8) -> Bool {
        guard isValid(p) else { return false }
        guard let l = last else { return true }
        return km(l, p) * 1000 >= minMeters
    }

    struct Box: Equatable { var minLat, maxLat, minLon, maxLon: Double }
    static func bounds(_ route: [Trip.RoutePoint]) -> Box? {
        let pts = route.filter(isValid)
        guard let f = pts.first else { return nil }
        var b = Box(minLat: f.lat, maxLat: f.lat, minLon: f.lon, maxLon: f.lon)
        for p in pts { b.minLat = min(b.minLat, p.lat); b.maxLat = max(b.maxLat, p.lat); b.minLon = min(b.minLon, p.lon); b.maxLon = max(b.maxLon, p.lon) }
        return b
    }
}

// MARK: - Battery and range ESTIMATES

enum BatteryEstimate {
    /// Common pack voltages and their Li-ion cell counts.
    static let packs: [(nominal: Int, cells: Int)] = [(24, 7), (36, 10), (48, 13), (52, 14), (60, 16), (72, 20)]

    static func cells(forNominal v: Int) -> Int? { return packs.first { $0.nominal == v }?.cells }

    /// A typical Li-ion resting curve (volts per cell -> %). Rough: real packs differ,
    /// and voltage sags under load, so this is labelled "estimated" everywhere.
    static let curve: [(v: Double, pct: Double)] = [
        (3.00, 0), (3.30, 3), (3.40, 7), (3.50, 14), (3.60, 25), (3.70, 40), (3.80, 57), (3.90, 70), (4.00, 81), (4.10, 91), (4.20, 100),
    ]

    static func percent(packVolts: Double, nominal: Int) -> Int? {
        guard packVolts.isFinite, packVolts > 0, let n = cells(forNominal: nominal) else { return nil }
        let v = packVolts / Double(n)
        if v <= curve.first!.v { return 0 }
        if v >= curve.last!.v { return 100 }
        for i in 1..<curve.count where v <= curve[i].v {
            let a = curve[i - 1], b = curve[i]
            let t = (v - a.v) / (b.v - a.v)
            return Int((a.pct + t * (b.pct - a.pct)).rounded())
        }
        return nil
    }
}

enum RangeEstimate {
    /// Riding-mode factor: slower modes go further.
    static func modeFactor(_ mode: String?) -> Double {
        switch mode?.lowercased() {
        case "walk", "eco": return 1.15
        case "sport": return 0.8
        default: return 1.0
        }
    }

    /// km left = full-charge range x battery % x mode factor. A rough ESTIMATE.
    static func kmLeft(fullRangeKm: Double, batteryPercent: Double, mode: String? = nil) -> Double {
        guard fullRangeKm.isFinite, batteryPercent.isFinite, fullRangeKm > 0 else { return 0 }
        let p = max(0, min(100, batteryPercent)) / 100
        return max(0, fullRangeKm * p * modeFactor(mode))
    }

    /// The rider's own average from recorded trips: km per 1% of battery, when they logged
    /// battery before and after. nil until there is data.
    static func kmPerPercent(distanceKm: Double, percentUsed: Double) -> Double? {
        guard distanceKm.isFinite, percentUsed.isFinite, distanceKm > 0.2, percentUsed >= 3 else { return nil }
        return distanceKm / percentUsed
    }
}

// MARK: - Fault explanations

struct FaultInfo: Equatable, Identifiable {
    enum Severity: String { case stop = "Stop riding", check = "Check soon", info = "Info" }
    let id: String
    let title: String
    let meaning: String
    let whatToDo: String
    let severity: Severity
}

enum FaultCatalog {
    static let source = "Fault names come from the public MIT-licensed Fardriver notes. The explanations are general guidance written for HackTheScoot, not from Fardriver, and are unverified on your controller."

    static let fardriver: [FaultInfo] = [
        FaultInfo(id: "Motor hall error", title: "Motor hall error", meaning: "The controller can't read the motor's position sensors (hall sensors).", whatToDo: "Turn it off. Check the thin motor cable plug for loose, bent or wet pins. If it stays, the motor sensors or cable need checking.", severity: .stop),
        FaultInfo(id: "Throttle error", title: "Throttle error", meaning: "The throttle signal is out of range, often because the throttle was pressed at power-on or its wire is damaged.", whatToDo: "Let go of the throttle and power cycle. Check the throttle cable and plug.", severity: .check),
        FaultInfo(id: "Current protection restart", title: "Current protection restart", meaning: "The controller cut power because the current got too high, then restarted.", whatToDo: "Ease off hard launches and hills. If it repeats on flat ground, check the motor wires.", severity: .check),
        FaultInfo(id: "Phase current surge", title: "Phase current surge", meaning: "A sudden spike in motor current.", whatToDo: "Stop and check the thick motor phase wires and plugs for damage or a short.", severity: .stop),
        FaultInfo(id: "Voltage protection", title: "Voltage protection", meaning: "Battery voltage is outside what the controller accepts (too low or too high).", whatToDo: "Charge the battery. If it's full, check the pack voltage matches the controller.", severity: .check),
        FaultInfo(id: "Alarm", title: "Alarm", meaning: "The controller's general alarm flag.", whatToDo: "Look at the other warnings shown with it.", severity: .info),
        FaultInfo(id: "Motor over-temperature", title: "Motor over-temperature", meaning: "The motor is too hot.", whatToDo: "Stop and let it cool. Avoid long full-power climbs.", severity: .stop),
        FaultInfo(id: "Controller over-temperature", title: "Controller over-temperature", meaning: "The controller is too hot.", whatToDo: "Stop and let it cool. Make sure air can reach the controller.", severity: .stop),
        FaultInfo(id: "Phase current overflow", title: "Phase current overflow", meaning: "Motor current went over the controller's limit.", whatToDo: "Ease off. If it repeats, check the motor and its wires.", severity: .check),
        FaultInfo(id: "Phase zero error", title: "Phase zero error", meaning: "The current sensor's zero reading at start-up was wrong.", whatToDo: "Power cycle with the throttle released. If it stays, the controller may need service.", severity: .check),
        FaultInfo(id: "Phase protection", title: "Phase protection", meaning: "A problem on the motor phase wires (loose or shorted).", whatToDo: "Stop. Check the thick motor wires and plugs.", severity: .stop),
        FaultInfo(id: "Line current zero error", title: "Line current zero error", meaning: "The battery current sensor's zero reading was wrong.", whatToDo: "Power cycle. If it stays, the controller may need service.", severity: .check),
        FaultInfo(id: "MOSFET high-side error", title: "MOSFET high-side error", meaning: "A power transistor inside the controller reported a fault.", whatToDo: "Stop riding. This usually needs the controller repaired or replaced.", severity: .stop),
        FaultInfo(id: "MOSFET low-side error", title: "MOSFET low-side error", meaning: "A power transistor inside the controller reported a fault.", whatToDo: "Stop riding. This usually needs the controller repaired or replaced.", severity: .stop),
        FaultInfo(id: "Current protection", title: "Current protection", meaning: "The controller limited power because the current was too high.", whatToDo: "Ease off. If it happens often, check the motor and wiring.", severity: .check),
    ]

    static func explain(_ name: String) -> FaultInfo {
        if let f = fardriver.first(where: { $0.id == name }) { return f }
        return FaultInfo(id: name, title: name, meaning: "No explanation is known for this one yet.", whatToDo: "If it stays on, stop and get the vehicle checked. A capture with the official app's own message helps us add it.", severity: .check)
    }
}

// MARK: - What's new

enum WhatsNew {
    static let version = "5.1.0"
    static let seenKey = "whatsNew.seenVersion"
    static let items: [(icon: String, title: String, detail: String)] = [
        // 5.1 (experimental, untested on hardware)
        ("scooter", "KuKirin G2 (2026) and G4", "Experimental, untested on hardware: live data only (G2: speed, battery volts, motor rpm, mode; G4: mode). Nothing is ever written to a KuKirin."),
        ("bolt.horizontal.circle", "Xiaomi M365 and Ninebot Max G30", "Experimental, untested on hardware: live data, plus a few settings that read first, ask you, and read back (M365: KERS, cruise, tail light; G30: cruise)."),
        ("key.horizontal", "Ninebot pairing", "Experimental: HackTheScoot's own pairing for encrypted Ninebots and the M365 Pro, Pro 2, 1S and Essential (press the power button). Read-only on those Xiaomis."),
        ("exclamationmark.octagon", "Ninebot and Xiaomi error codes", "Tap an error number to see what it usually means and what to check."),
        // 5.0
        ("questionmark.circle", "Help unlock your vehicle", "A step-by-step capture tutorial, two ways, and a GitHub template to send it in."),
        ("map", "GPS route maps", "Opt-in: draws each ride on a map. Stays on your phone."),
        ("magnifyingglass", "Ride history search", "Search and filter by vehicle, date and real or simulated."),
        ("battery.75", "Battery and range estimates", "Clearly labelled estimates from voltage or your own numbers."),
        ("info.circle", "Vehicle info", "Model, adapter, services and firmware (when the vehicle shares it). Read-only."),
        ("exclamationmark.triangle", "Fault explanations", "What each warning usually means and what to check."),
        ("checkmark.seal", "Compatibility checker", "Search the compatibility database before you buy."),
        ("externaldrive", "Backup and restore", "Settings, Garage, themes and (optionally) trips as one JSON file."),
        ("accessibility", "Accessibility", "VoiceOver labels on the dashboard and controls, and Dynamic Type in every list."),
        ("doc.text", "Privacy, terms and licenses", "DRAFT privacy policy and terms (they need an adult and a legal review), plus open-source credits."),
        ("lifepreserver", "Crash-safe logs", "Captures are saved as they record, so a crash doesn't lose them."),
    ]

    static func shouldShow(seen: String?, current: String) -> Bool {
        guard let s = seen, !s.isEmpty else { return true }
        return s.compare(current, options: .numeric) == .orderedAscending
    }
}

// MARK: - Stripe TEST return link

enum ProReturnLink {
    static let scheme = "hackthescoot"
    /// hackthescoot://pro-test?plan=monthly (the download page's thank-you page opens this).
    static func plan(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "pro-test" else { return nil }
        let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "plan" }?.value ?? "test"
        let plan = raw.hasPrefix("pro_") ? String(raw.dropFirst(4)) : raw
        let ok = ["monthly", "yearly", "test"]
        return ok.contains(plan) ? plan : "test"
    }
    static let note = "TEST MODE: the Stripe test checkout sends you back here and Pro turns on as a labelled test unlock. It isn't verified (that needs a small server holding the Stripe secret key), so anyone with the link could do the same. No real money moves."
}

// MARK: - Backup / restore

enum BackupValue: Codable, Equatable {
    case bool(Bool), int(Int), double(Double), string(String), data(Data)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode([String: Bool].self), let v = b["b"] { self = .bool(v); return }
        if let i = try? c.decode([String: Int].self), let v = i["i"] { self = .int(v); return }
        if let d = try? c.decode([String: Double].self), let v = d["d"] { self = .double(v); return }
        if let s = try? c.decode([String: String].self) {
            if let v = s["s"] { self = .string(v); return }
            if let v = s["data"], let d = Data(base64Encoded: v) { self = .data(d); return }
        }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a backup value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let v): try c.encode(["b": v])
        case .int(let v): try c.encode(["i": v])
        case .double(let v): try c.encode(["d": v])
        case .string(let v): try c.encode(["s": v])
        case .data(let v): try c.encode(["data": v.base64EncodedString()])
        }
    }

    var plist: Any {
        switch self {
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .data(let v): return v
        }
    }

    static func from(_ any: Any) -> BackupValue? {
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n as CFNumber) { return .double(n.doubleValue) }
            return .int(n.intValue)
        }
        if let s = any as? String { return .string(s) }
        if let d = any as? Data { return .data(d) }
        return nil
    }
}

struct BackupBundle: Codable, Equatable {
    static let format = "hackthescoot-backup"
    static let currentVersion = 1

    var format: String = BackupBundle.format
    var version: Int = BackupBundle.currentVersion
    var appVersion: String = ""
    var created: Date = Date()
    var settings: [String: BackupValue] = [:]
    var trips: [Trip]? = nil

    /// Settings that are copied: the app's own keys only.
    static let allowedPrefixes = ["dashTheme", "dashLayouts", "garage.", "maint.", "speedAlert", "rideHub", "haptics", "feedback.",
                                  "startup.", "tripAutoRecord", "autoReconnect", "chosenModel", "parked.", "route.", "range.",
                                  "appSettings.", "units", "accent", "whatsNew.", "onboarding."]
    static let allowedKeys: Set<String> = ["keepAwake", "soundOn", "soundPreset", "unitsSwapped", "startSwapped", "showDashControls",
                                           "gaugeMaxAuto", "gaugeMax", "displayUnit", "fontDesign", "aboveStockAccepted", "speedColor",
                                           "colorMode", "gaugeStyle", "bgStyle", "bgColor", "showGear", "showTops", "showBattery",
                                           "showLightPark", "showTrip", "showOdo", "savedScooters", "lastGear"]
    /// Never copied, whatever the key: passwords, PINs, secrets, the test unlock.
    static let blockedWords = ["password", "pass", "pwd", "pin", "secret", "token", "key.", "premium", "keychain", "stripe"]

    static func isAllowed(_ key: String) -> Bool {
        let k = key.lowercased()
        if blockedWords.contains(where: { k.contains($0) }) { return false }
        if allowedKeys.contains(key) { return true }
        return allowedPrefixes.contains { key.hasPrefix($0) }
    }

    static func make(from defaults: [String: Any], trips: [Trip]?, appVersion: String, now: Date = Date()) -> BackupBundle {
        var b = BackupBundle()
        b.appVersion = appVersion
        b.created = now
        for (k, v) in defaults where isAllowed(k) {
            if let bv = BackupValue.from(v) { b.settings[k] = bv }
        }
        b.trips = trips
        return b
    }

    func encoded() -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? e.encode(self)
    }

    enum ImportError: Error, Equatable, CustomStringConvertible {
        case notJSON, wrongFormat, newerVersion(Int)
        var description: String {
            switch self {
            case .notJSON: return "not a JSON file"
            case .wrongFormat: return "not a HackTheScoot backup"
            case .newerVersion(let v): return "made by a newer HackTheScoot (backup v\(v))"
            }
        }
    }

    static func decode(_ data: Data) -> Result<BackupBundle, ImportError> {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.notJSON) }
        guard obj["format"] as? String == format else { return .failure(.wrongFormat) }
        if let v = obj["version"] as? Int, v > currentVersion { return .failure(.newerVersion(v)) }
        guard var b = try? d.decode(BackupBundle.self, from: data) else { return .failure(.wrongFormat) }
        // a hand-edited file can't smuggle in a blocked key
        b.settings = b.settings.filter { isAllowed($0.key) }
        return .success(b)
    }

    /// Trips merged by id: existing trips are kept, new ones added, newest first.
    static func merge(existing: [Trip], incoming: [Trip]) -> [Trip] {
        var seen = Set(existing.map { $0.id })
        var out = existing
        for t in incoming where !seen.contains(t.id) { out.append(t); seen.insert(t.id) }
        return out.sorted { $0.start > $1.start }
    }
}
