import Foundation

// MARK: - v5.1: what's known per brand (capture guide + compatibility checker)

struct BrandStatus: Identifiable, Equatable {
    let id: String
    let brand: String
    let status: String
    let needsCapture: String
}

enum BrandStatusList {
    static let all: [BrandStatus] = [
        BrandStatus(id: "j078", brand: "Joyhis J078", status: "Controls verified from captures (lights, gears, park, speed limits).", needsCapture: "Battery and odometer meaning."),
        BrandStatus(id: "volpam", brand: "VOLPAM (Zydtech)", status: "Speed limit verified from captures.", needsCapture: "Lights and the other feature bits."),
        BrandStatus(id: "kukirin", brand: "KuKirin G2 (2026) / G4", status: "Experimental, untested on hardware: live data only. G2: speed, battery volts, motor rpm, mode. G4: mode.", needsCapture: "Every control. Capture the official Kugoo app while you press each button: no KuKirin command is public yet."),
        BrandStatus(id: "m365", brand: "Xiaomi M365 (old Bluetooth firmware)", status: "Experimental, untested on hardware: live data, plus KERS, cruise and tail light (read first, confirm, read back).", needsCapture: "Headlight, and a capture confirming the three settings on your firmware."),
        BrandStatus(id: "m365pro", brand: "Xiaomi M365 Pro / Pro 2 / 1S / Essential", status: "Experimental, untested on hardware: HackTheScoot's own Ninebot pairing (press the power button), then live data only.", needsCapture: "Any control. A capture from the Mi Home app shows them."),
        BrandStatus(id: "m365new", brand: "Xiaomi M365 (newer Xiaomi login)", status: "Not supported: the only public code for that login is AGPL.", needsCapture: "Nothing we can use yet."),
        BrandStatus(id: "g30", brand: "Ninebot Max G30", status: "Experimental, untested on hardware: live data and cruise control (read first, confirm, read back). Pairing for encrypted firmware.", needsCapture: "Lights, KERS and speed mode: the public sources disagree, so they stay off until a capture of the Segway-Ninebot app settles it."),
        BrandStatus(id: "fardriver", brand: "Fardriver (e-bikes)", status: "Experimental: live data only. Never written to.", needsCapture: "A capture is welcome, but writes to a motor controller stay off."),
        BrandStatus(id: "other", brand: "Everything else", status: "Read-only: the packet logger and raw data.", needsCapture: "A capture of the official app is how a new brand gets added."),
    ]
}
