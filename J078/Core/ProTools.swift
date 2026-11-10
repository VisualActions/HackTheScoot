import Foundation

// Pure helpers behind the Pro / Developer extras (unit-tested).

enum TripExport {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// One row per sample: time, seconds, speed, mode.
    static func csv(_ t: Trip, mph: Bool) -> String {
        var lines = ["time,seconds,speed_\(mph ? "mph" : "kmh"),mode,scooter,source"]
        let name = t.scooterName.replacingOccurrences(of: ",", with: " ")
        for s in t.samples {
            let v = mph ? Units.kmhToMph(s.kmh) : s.kmh
            let speed = v.isFinite ? String(format: "%.2f", v) : ""
            let ts = iso.string(from: t.start.addingTimeInterval(s.t.isFinite ? s.t : 0))
            lines.append("\(ts),\(String(format: "%.2f", s.t.isFinite ? s.t : 0)),\(speed),\(s.mode ?? ""),\(name),\(t.source)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// GPX track from the optional GPS route. nil when the ride has no route.
    static func gpx(_ t: Trip) -> String? {
        guard let route = t.route, !route.isEmpty else { return nil }
        var out = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                   "<gpx version=\"1.1\" creator=\"HackTheScoot\" xmlns=\"http://www.topografix.com/GPX/1/1\">",
                   "<trk><name>\(xml(t.scooterName)) \(iso.string(from: t.start))</name><trkseg>"]
        for p in route where p.lat.isFinite && p.lon.isFinite && abs(p.lat) <= 90 && abs(p.lon) <= 180 {
            out.append("<trkpt lat=\"\(String(format: "%.6f", p.lat))\" lon=\"\(String(format: "%.6f", p.lon))\"><time>\(iso.string(from: t.start.addingTimeInterval(p.t)))</time></trkpt>")
        }
        out.append("</trkseg></trk></gpx>")
        return out.joined(separator: "\n") + "\n"
    }

    static func xml(_ s: String) -> String {
        return s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Analytics across many rides.
struct RideAnalytics: Equatable {
    var rides = 0
    var distanceKm: Double = 0
    var movingTime: TimeInterval = 0
    var topKmh: Double = 0
    var longestKm: Double = 0
    var avgMovingKmh: Double = 0
    var timeInMode: [String: TimeInterval] = [:]
    /// Moving time per 5 km/h speed band: index 0 = 0-5, 1 = 5-10, ...
    var histogram: [TimeInterval] = []

    static let bandKmh: Double = 5

    static func compute(_ trips: [Trip]) -> RideAnalytics {
        var a = RideAnalytics()
        a.rides = trips.count
        var hist = [TimeInterval](repeating: 0, count: 10)
        for t in trips {
            let s = t.stats
            a.distanceKm += s.distanceKm
            a.movingTime += s.movingTime
            a.topKmh = max(a.topKmh, s.maxKmh)
            a.longestKm = max(a.longestKm, s.distanceKm)
            for (m, v) in s.timeInMode { a.timeInMode[m, default: 0] += v }
            let valid = t.samples.filter(TripMath.isValid)
            if valid.count > 1 {
                for i in 1..<valid.count {
                    let dt = valid[i].t - valid[i - 1].t
                    guard dt > 0, dt <= 2, valid[i].kmh > 0.5 else { continue }
                    let band = min(hist.count - 1, max(0, Int(valid[i].kmh / bandKmh)))
                    hist[band] += dt
                }
            }
        }
        while hist.count > 1, hist.last == 0 { hist.removeLast() }
        a.histogram = hist
        a.avgMovingKmh = a.movingTime > 0 ? a.distanceKm / (a.movingTime / 3600) : 0
        if !a.avgMovingKmh.isFinite { a.avgMovingKmh = 0 }
        return a
    }
}

/// One packet-log line reduced to what the analysis needs.
struct FrameRecord: Equatable {
    var time: Date
    var direction: String   // "RX" / "TX" / "XX"
    var channel: String
    var bytes: [UInt8]
}

struct LogAnalysis: Equatable {
    struct ChannelStat: Equatable, Identifiable {
        var id: String { channel + direction }
        var channel: String
        var direction: String
        var frames: Int
        var perSecond: Double
        var longestGap: TimeInterval
    }
    struct CommandStat: Equatable, Identifiable {
        var id: String { key }
        var key: String       // first bytes of the frame, hex
        var count: Int
    }

    var total = 0
    var span: TimeInterval = 0
    var channels: [ChannelStat] = []
    var commands: [CommandStat] = []
    var blocked = 0

    /// prefix = how many leading bytes identify a "command" (3 = BD BE AB / DB EB BA style).
    static func analyze(_ frames: [FrameRecord], prefix: Int = 4) -> LogAnalysis {
        var a = LogAnalysis()
        let f = frames.sorted { $0.time < $1.time }
        a.total = f.count
        guard let first = f.first?.time, let last = f.last?.time else { return a }
        a.span = last.timeIntervalSince(first)
        a.blocked = f.filter { $0.direction == "XX" }.count
        var groups: [String: [FrameRecord]] = [:]
        for r in f { groups[r.direction + "|" + r.channel, default: []].append(r) }
        for (k, list) in groups {
            let parts = k.split(separator: "|", maxSplits: 1).map(String.init)
            var gap: TimeInterval = 0
            if list.count > 1 { for i in 1..<list.count { gap = max(gap, list[i].time.timeIntervalSince(list[i - 1].time)) } }
            let dur = (list.last?.time ?? first).timeIntervalSince(list.first?.time ?? first)
            let rate = dur > 0 ? Double(list.count - 1) / dur : 0
            a.channels.append(ChannelStat(channel: parts.count > 1 ? parts[1] : "", direction: parts.first ?? "",
                                          frames: list.count, perSecond: rate.isFinite ? rate : 0, longestGap: gap))
        }
        a.channels.sort { $0.frames > $1.frames }
        var cmd: [String: Int] = [:]
        for r in f where !r.bytes.isEmpty {
            let key = r.direction + " " + r.bytes.prefix(max(1, prefix)).map { String(format: "%02X", $0) }.joined(separator: " ")
            cmd[key, default: 0] += 1
        }
        a.commands = cmd.map { CommandStat(key: $0.key, count: $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.key < $1.key }
        return a
    }
}

enum FrameDiff {
    /// Parses "BD BE AB 00 01", "bdbeab0001" or "0xBD,0xBE". nil on a bad character.
    static func parseHex(_ s: String) -> [UInt8]? {
        var t = s.uppercased().replacingOccurrences(of: "0X", with: "")
        for sep in [" ", ",", ":", "-", "\n", "\t"] { t = t.replacingOccurrences(of: sep, with: "") }
        guard t.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var i = t.startIndex
        while i < t.endIndex {
            let j = t.index(i, offsetBy: 2)
            guard let b = UInt8(t[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }

    struct Cell: Equatable {
        var index: Int
        var a: UInt8?
        var b: UInt8?
        var changed: Bool { return a != b }
    }

    static func compare(_ a: [UInt8], _ b: [UInt8]) -> [Cell] {
        let n = max(a.count, b.count)
        return (0..<n).map { i in Cell(index: i, a: i < a.count ? a[i] : nil, b: i < b.count ? b[i] : nil) }
    }
}

/// Developer JSON export of the packet log (fixtures). Never includes passwords:
/// the BLE layer already masks the password frame before it reaches the log.
enum DevExport {
    static func json(_ frames: [FrameRecord], device: String) -> Data? {
        let iso = TripExport.iso
        let rows: [[String: String]] = frames.map {
            ["t": iso.string(from: $0.time), "dir": $0.direction, "ch": $0.channel,
             "hex": $0.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")]
        }
        let obj: [String: Any] = ["app": "HackTheScoot", "kind": "packet-log", "version": 1, "device": device, "frames": rows]
        return try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }
}
