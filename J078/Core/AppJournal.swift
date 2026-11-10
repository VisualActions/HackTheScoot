import Foundation

/// v5.0 crash-safe logging. Everything is a small local file in Application Support,
/// written as it happens (append + flush), so a crash or a force-quit loses nothing that
/// was already recorded. Nothing is uploaded; the rider shares a file only by choice.
final class AppJournal {
    static let shared = AppJournal()

    let directory: URL
    var journalURL: URL { return directory.appendingPathComponent("journal.txt") }
    /// The packet logger's live file, finished into capture-<time>.txt on Stop.
    var liveCaptureURL: URL { return directory.appendingPathComponent("capture-in-progress.txt") }

    static let maxJournalBytes = 256 * 1024
    private let cleanKey = "journal.cleanExit"
    private let queue = DispatchQueue(label: "hackthescoot.journal")
    private var captureHandle: FileHandle?
    /// True when the last session didn't reach the background cleanly (a crash, most likely).
    private(set) var lastSessionEndedUnexpectedly = false

    init(directory: URL? = nil) {
        let base = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("logs", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    // MARK: Session markers

    /// Call once at launch.
    func launched(version: String) {
        let d = UserDefaults.standard
        lastSessionEndedUnexpectedly = d.object(forKey: cleanKey) != nil && d.bool(forKey: cleanKey) == false
        d.set(false, forKey: cleanKey)
        note("launch v\(version)" + (lastSessionEndedUnexpectedly ? " (last session ended unexpectedly)" : ""))
        NSSetUncaughtExceptionHandler { e in
            AppJournal.shared.noteSync("CRASH (exception): \(e.name.rawValue) \(e.reason ?? "")")
        }
    }

    func becameActive() { UserDefaults.standard.set(false, forKey: cleanKey) }
    /// Background = a clean stop (iOS may end the app later without telling us).
    func wentToBackground() {
        UserDefaults.standard.set(true, forKey: cleanKey)
        note("background")
    }
    func dismissCrashNotice() { lastSessionEndedUnexpectedly = false }

    // MARK: Journal

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    func note(_ text: String) {
        let line = AppJournal.stamp.string(from: Date()) + " " + CaptureSanitizer.mask(text) + "\n"
        queue.async { [weak self] in self?.append(line) }
    }

    func noteSync(_ text: String) {
        let line = AppJournal.stamp.string(from: Date()) + " " + text + "\n"
        queue.sync { append(line) }
    }

    private func append(_ line: String) {
        let url = journalURL
        if let a = try? FileManager.default.attributesOfItem(atPath: url.path), let size = a[.size] as? Int, size > AppJournal.maxJournalBytes {
            // keep the newest half
            if let d = try? Data(contentsOf: url) { try? d.suffix(AppJournal.maxJournalBytes / 2).write(to: url) }
        }
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.synchronize(); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    func journalText() -> String {
        queue.sync {}
        return (try? String(contentsOf: journalURL, encoding: .utf8)) ?? ""
    }

    func clearJournal() { queue.sync { try? FileManager.default.removeItem(at: journalURL) } }

    // MARK: Live capture file (the packet logger)

    func beginCapture(header: String) {
        queue.sync {
            try? FileManager.default.removeItem(at: liveCaptureURL)
            try? (header + "\n").data(using: .utf8)?.write(to: liveCaptureURL)
            captureHandle = try? FileHandle(forWritingTo: liveCaptureURL)
            captureHandle?.seekToEndOfFile()
        }
    }

    private var pending = 0
    func appendCapture(_ line: String) {
        let masked = CaptureSanitizer.mask(line)
        queue.async { [weak self] in
            guard let self = self, let h = self.captureHandle, let d = (masked + "\n").data(using: .utf8) else { return }
            h.write(d)
            self.pending += 1
            if self.pending >= 20 { try? h.synchronize(); self.pending = 0 }
        }
    }

    /// Stop: flush and move the live file to capture-<time>.txt. Returns the finished file.
    @discardableResult
    func finishCapture(footer: String, stamp: Int) -> URL? {
        var out: URL?
        queue.sync {
            if let h = captureHandle {
                if let d = (footer + "\n").data(using: .utf8) { h.write(d) }
                try? h.synchronize(); try? h.close()
            }
            captureHandle = nil
            pending = 0
            let dest = directory.appendingPathComponent("capture-\(stamp).txt")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.moveItem(at: liveCaptureURL, to: dest)) != nil { out = dest }
        }
        pruneCaptures(keep: 10)
        return out
    }

    var isCaptureOpen: Bool { return queue.sync { captureHandle != nil } }

    /// A capture that was still recording when the app died.
    var unfinishedCapture: URL? {
        guard !isCaptureOpen, FileManager.default.fileExists(atPath: liveCaptureURL.path) else { return nil }
        return liveCaptureURL
    }

    func recoverUnfinished() -> URL? {
        guard let u = unfinishedCapture else { return nil }
        let dest = directory.appendingPathComponent("capture-recovered-\(Int(Date().timeIntervalSince1970)).txt")
        if (try? FileManager.default.moveItem(at: u, to: dest)) != nil { return dest }
        return nil
    }

    func discardUnfinished() { if let u = unfinishedCapture { try? FileManager.default.removeItem(at: u) } }

    var savedCaptures: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("capture-") && $0.lastPathComponent != liveCaptureURL.lastPathComponent }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func pruneCaptures(keep: Int) {
        for u in savedCaptures.dropFirst(keep) { try? FileManager.default.removeItem(at: u) }
    }
}
