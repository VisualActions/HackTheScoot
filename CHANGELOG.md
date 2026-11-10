# Changelog

## 5.1.0 beta (build 9): experimental KuKirin, Xiaomi and Ninebot

Built and tested in CI (simulator) only. **Experimental, untested on hardware**: it should work, but nobody has tried it on a real KuKirin, Xiaomi or Ninebot yet. Nothing from 5.0 was removed or capped; the J078 and Volpam flows and v3's above-stock warning are unchanged. Published as the `v5.1-beta` prerelease; `v5-beta` (5.0) and `latest` (v3) are untouched.

- **KuKirin G2 (2026) / G4** (`KukirinProtocol.swift`): read-only live data (G2: speed, battery volts, motor rpm, ride mode; G4: ride mode) from published observations (facts only). Nothing is ever written to a KuKirin.
- **Xiaomi M365 / Ninebot session** (`NBXSession.swift`): plain M365 (`55 AA`) and plain Ninebot (`5A A5`) reads; if neither answers, a Pair button.
- **Clean-room Ninebot Encryption2 + pairing** (`NBEncryption2.swift`) from the Apache-2.0 NootNooot spec (no AGPL code). PRE_COMM / SET_PWD (power button) / AUTH, tried over four documented variants. The session password is random per phone and kept in the Keychain.
- **Experimental settings** (read first, standing still, confirm, write once, read back): M365 (plain) KERS 0x7B, cruise 0x7C, tail light 0x7D; Max G30 cruise 0x7C. Encrypted Xiaomi models stay read-only. Everything else is blocked by `NBXSafety` (firmware/IAP, power off, reboot, engine, lock/unlock, PIN, serial, speed limit, max speed/power, BMS).
- **Ninebot and Xiaomi error codes** (`NBErrorCodes.swift`): own wording, facts from the ScooterHacking wiki (CC BY-SA) and Ninebot's document.
- Capture guide and compatibility checker show each brand's real status; compatibility DB adds KuKirin G2 and M365 Pro / Pro 2 / 1S / Essential; Garage controller type KuKirin.
- `ACKNOWLEDGEMENTS.md` + `NOTICE` (Apache-2.0 attribution), and the in-app credits list every source.
- CI: the release workflow now publishes `v5.1-beta` and leaves `v5-beta` alone.
- Tests: V51Tests (KuKirin parser, AES/FIPS-197 check, Encryption2 vectors from an independent implementation of the spec, pairing flow on a fake radio, read-back, the safety gate, error codes) and NewScreenTests51 (every new screen and section, portrait + landscape, dark + light).

## 5.0.0 beta (build 8): public release candidate

Built and tested in CI (simulator). Not yet tried on a real phone, scooter or e-bike. Nothing from 4.2 was removed or capped. Published as the `v5-beta` prerelease; `latest` is still v3.

- **Capture tutorial** "Help unlock your scooter or e-bike": quick route (packet logger + official app, one press at a time, 5 s pauses, "I pressed..." MARK buttons) and advanced route (Apple's Bluetooth logging profile + sysdiagnose, steps checked against Apple's docs, "stacks only = didn't start"). Reachable from the read-only vehicle screen, Help, the packet logger and More. Send screen: mask a PIN, share sheet, email, prefilled GitHub issue. "Find vehicles already connected to this phone" (listen-only).
- Repo: `CAPTURES.md`, `.github/ISSUE_TEMPLATE/new-vehicle-capture.yml`, `RELEASE-CHECKLIST.md`; download page "Contribute a capture" section.
- New (all free): opt-in GPS route maps, ride search + filters, battery and range estimates (labelled estimated), vehicle info / firmware (read-only Device Information), fault explanations, compatibility checker, backup / restore (JSON), what's new, DRAFT privacy policy and terms + open-source credits, crash-safe capture file + app log, light/system appearance for the tab bar, VoiceOver labels, English + first Spanish strings.
- Stripe TEST return link: the test checkout's thank-you page opens `hackthescoot://pro-test`, which turns on a labelled, unverified test unlock.
- Release readiness: 5.0.0 build 8, IPA named `HackTheScoot-unsigned.ipa` / `HackTheScoot-5.0.0-beta-unsigned.ipa`, `PrivacyInfo.xcprivacy`, CI secret scan and license scan. Bundle id unchanged on purpose (see RELEASE-CHECKLIST.md).
- Deferred: widgets / Live Activity (App Group = paid team), a verified Stripe unlock (needs a server), real App Store purchases (adult account + signed build), writes to Fardriver / Ninebot / unknown vehicles (need captures), full translations.
- Tests: V50Tests (capture steps, masking, ride filter, route math, estimates, faults, what's new, return link, backup, journal) and NewScreenTests50 (every new screen, portrait + landscape, dark + light).

## 4.2.0 beta (build 7): feature pack, e-bikes, Fardriver + Ninebot (read-only)

Built and tested in CI (simulator). Not yet tried on a real phone, scooter or e-bike. Nothing from 4.1 was removed or capped.

- New (all free): ride stats (distance labelled estimated), speed alert (haptic + sound), ride timer with laps, units everywhere, opt-in "last parked here" (when-in-use location), share card image, Garage maintenance reminders, long-press quick actions (light, park, mode), accent colour picker, master haptics switch, alternate app icons, packet logger with export, help/FAQ.
- Garage "Add vehicle": e-scooter or e-bike, and the controller type (Joyhis/365, Zydtech, Ninebot, Fardriver, Unknown). New Fardriver ND entry in the compatibility seed (8 entries now).
- `FardriverAdapter` (Experimental, read-only, never writes) and `NinebotAdapter` (Experimental, read-only, writes off) in the ProtocolAdapter layer. Experimental / Unknown vehicles show live data only, a "needs a capture to unlock controls" note and a packet-logger button. The terminal refuses to send to them.
- Deferred: widgets (need an App Group = paid signing), Fardriver road speed, any writes to the new brands.
- Tests: Fardriver CRC/parser/stream, Ninebot frames, speed alert, ride timer, maintenance, ride totals, Garage vehicle fields (incl. loading a 4.1 garage), and screen tests for every new screen (NewScreenTests42).

## 4.1.0 beta (build 6): onboarding, Garage, HackTheScoot Pro (test mode)

Built and tested in CI (simulator). Not yet tried on a real phone or scooter. Nothing from 4.0.1 was removed or capped: the 6-45 km/h sliders, v3's Bluetooth flow, the terminal, themes, designer, layouts, replay and export all work as before and stay free.

### First-launch intro
Five short pages: welcome, why the app needs Bluetooth (iOS's permission prompt now comes right after this page on a new install), pick your scooter from the Garage, find it (scan + connect), and the four tabs. Skippable on every page, shown once, re-openable from More > Show the intro again. Phones that already answered the Bluetooth prompt start Bluetooth exactly like 4.0.1.

### Garage
More > Garage. Save as many scooters as you like; the J078 ("My J078") and Dad's Volpam are there from the start. Each one has a name, model (from the research compatibility database), compatibility level, a photo or color, notes, its own last-known stats (top speed seen, mode, limits) and its own trips. Switch the active scooter and the app auto-connects to it (once it has connected on this phone). A scooter that connects is linked to its own entry by its Bluetooth id; an unknown device is never guessed onto one of yours. New trips are stamped with the active scooter. Old trips still show in Trips.

### HackTheScoot Pro (TEST MODE)
- Tiers from the spec: FREE / PRO ($3.99/mo, $29.99/yr) / DEVELOPER (later, not for sale).
- Pro adds NEW extras only: a Pro theme pack (6 looks), advanced trip analytics (totals, records, speed histogram, time in mode, per scooter), CSV + GPX export, extended packet-log analysis. Developer previews: frame compare and JSON log export.
- Never paywalled: connecting, controls, speed limits (incl. above-stock), fault warnings, safety info, compatibility info, Garage, and everything 4.0.1 had. There is no speed-unlock purchase. Unit tests enforce this.
- StoreKit 2 paywall: prices, intro trial, restore, manage subscription, cancel steps. `Support/HackTheScoot.storekit` for local testing in Xcode.
- More > Developer settings > Test unlock: a clearly labelled switch to see Pro/Developer without paying.
- Web: "Get Pro (test)" on the download page uses Stripe TEST Payment Links (card 4242 4242 4242 4242). The `Stripe test setup` workflow creates them from the `STRIPE_SECRET_KEY` secret and prints only the public links.

### Tests
New logic tests (Garage rules, compatibility seed, tiers, "nothing safety-related is sold", CSV/GPX, analytics, log analysis, frame compare) and new screen tests that open the intro (every page), Garage (list, every scooter, add), paywall, every Pro screen free and unlocked, developer settings and every Pro theme on the dashboard.

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
