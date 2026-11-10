# Changelog

## 4.0.1 beta (build 5): crash fixes, v3 Bluetooth timing, features back, new UI

Untested on hardware yet: built and tested in CI (simulator), not on a real J078.

### What crashed in 4.0.0, and the fixes
- **Opening Controls crashed.** The Walk speed-limit slider was built with a 6...6 km/h range (stock min = stock max). A SwiftUI `Slider` with equal bounds crashes. v3 had guarded this (`max(top, min + 1)`); v4.0.0 dropped the guard. Every slider now goes through `SafeSlider`, and `Gear.sliderRange` is never zero-width (unit test).
- **Number conversions** that could trap on NaN/infinity (`Int(Double)` in the gauges) now use `safeInt`.
- **New CI screen tests** (`ViewTests/ScreenSmokeTests.swift`, hosted in the app): every tab (Dashboard, Controls, Trips, More), every speed-limit row (stock + above-stock), every gauge and preset, the Volpam/unknown Controls, and every More screen are built and laid out with a simulated scooter. A crash on open now fails CI before anything publishes.

### "Bluetooth connected but not working"
4.0.0 put new gates in front of every write that v3 never had:
- it waited for iOS to confirm the notification subscription, and after 5 s showed "disconnected" (while still connected) and sent nothing;
- it only set up the channels once every service had characteristics, so one service that failed discovery left it stuck;
- it turned on CoreBluetooth state restoration, which can hand back a "connected" scooter with no session started;
- auto-connect to the last scooter on launch was gone.

4.0.1 sends exactly what v3 sent, in the same order and timing: notifications on as each characteristic is found, then hello (`BD BE AF FF FF`) + `AC CC CC` right away, keep-alive every 500 ms (echoing the current gear), hello every 3 s, `AC CC CC` every 20 s, commands on tap. Detection falls back to v3's (16-bit-base `6E400001` service or the `365_scooter` name), and a device with `6E400002/6E400003` that isn't identified switches to the J078 path when a real J078 status frame arrives. The park fix stays: park only after the scooter answers `DB EB CA CA FF`.

### Features back from v3
- **Above-stock speed limits**: 6-45 km/h per mode, behind the same one-time warning v3 used. The scooter's own clamp and the requested-vs-accepted readout stay (Nov 9: asked 32, scooter kept 31).
- Walk/eco/drive limits, start mode and units are direct buttons again (labelled experimental/unverified), with the swap switches.
- Top speed per mode with "fastest seen now", park toggle with the password reply, auto-connect to the last scooter, cancel connecting, the Volpam F1F1 heartbeat toggle, mode buttons on the dashboard, gauge max (auto or fixed).
- Developer terminal can send any frame again (after the developer-mode warning + per-send confirmation). Firmware/DFU/identity characteristics stay blocked.

### New UI
Black background, one accent color, SF Pro, a huge readable speed, fewer cards. Tabs: Dashboard, Controls, Trips, More. Connect is a sheet from the dashboard (and in More). Mode colors are off by default (Theme can turn them back on) and the full-screen mode color sweep is gone. Every v4 feature is still there: themes, 3 gauges, designer, trips + replay, simulator, diagnostics, Developer Lab, Startup Studio, Volpam.


## v4.0.0-beta (v4-dev, Nov 9 2026)

### Fixed
- **Park could be sent after a password timeout.** Park now goes out only after the scooter replies `DB EB CA CA FF` to the password sent in the same session. Timeout, wrong password, disconnect or a late OK all send nothing (ParkGate + tests).
- Commands could be written before the notify subscription was confirmed. Now the session starts only after iOS confirms notifications; a 5 s no-confirm stops and says so.
- Duplicate / leftover timers. All session timers are owned by `SessionTimers`; disconnect cancels them all instantly and late ticks from an old session are ignored.
- Incoming packets are length-checked before reading; malformed ones are rejected and counted.
- Battery % and odometer were shown as values; they're now "unavailable (unverified)".

### Changed
- **Speed limits stay within factory values.** The v3 above-stock unlock is removed. J078 sport stops at 31 km/h; Volpam at 35 km/h.
- All writes go through one gate (`WriteGuard`); experimental frames never go out automatically; unknown, firmware and bootloader frames are blocked.
- Code reorganised into Core / ProtocolAdapters / Transport / Features / Research. Protocol adapters declare their capabilities and a compatibility level; unknown devices are read-only.
- The J078 park PIN moved from settings to the Keychain.
- Version 4.0.0 (build 4). Landscape enabled. `bluetooth-central` background mode for reconnects while locked.
- CI: unit tests on a simulator run on every push; the IPA builds in parallel; publishing needs both. `main` → release `latest` (stable), `v4-dev` → prerelease `v4-beta`.

### Added
- Three gauges (Classic, Digital, Performance), smooth but never-overshooting needle, stale indicator.
- Full theme editor, per-mode colors, mode-change sweep + haptic, night theme, dashboard designer with saved layouts and presets, theme JSON export/import.
- Landscape dashboard; controls hide while moving.
- Trip computer, ride history, trip replay, summary export.
- Offline simulator with 7 scenarios (never sends Bluetooth).
- Diagnostics page and evidence-based health light.
- Developer Lab: packet monitor with search, UUID viewer, offline decoder, capture compare, self-tests, read-only by default, manual writes behind an advanced warning.
- Startup Studio (phone only) with the HACKTHESCOOT logo animation, sounds, imported audio, haptics, preview.
- Connection / mode / trip feedback (haptics + optional sounds), each switchable.
- App icon and logo drawn in code.
- Volpam (Zydtech family) adapter: verified sport speed limit (CRC16-Modbus confirmed on all 25 captured frames), experimental feature frame on its own page, password in the Keychain.
- XCTest target (`J078Tests`).

### Known limitations
- No Live Activity yet (see README).
- Walk/eco/drive limits, units and start-mode values are experimental.
- Volpam lock/light/mode bits are experimental; Volpam live speed and battery are unverified and not shown as values.
- No GPS routes yet. LCD segment simulator is generic.
- Only two scooter adapters (J078, Volpam).

## v3.0.0 (main)
- Renamed to HackTheScoot; speed-limit slider (sport verified) with an above-stock unlock behind a warning.
