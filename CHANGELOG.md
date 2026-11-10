# Changelog

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
