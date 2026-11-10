# HackTheScoot (v4 beta)

An iPhone companion for the **Joyhis J078** scooter (and, carefully, dad's **Volpam**). Everything it does on the J078 was decoded from real Bluetooth captures of the 365 app on Nov 9 2026. Nothing is guessed silently: every feature below says how sure we are.

> **Stable vs beta.** `main` is v3, the stable build (release **latest**). v4 lives on the `v4-dev` branch and is published as the separate prerelease **v4-beta** only after the unit tests pass. Merging the v4 PR is what makes v4 stable.

Downloads:
- Stable v3: https://github.com/VisualActions/HackTheScoot/releases/latest/download/J078-unsigned.ipa
- v4 beta: https://github.com/VisualActions/HackTheScoot/releases/download/v4-beta/HackTheScoot-v4-beta-unsigned.ipa

## What works on the J078 (evidence levels)

| Feature | Level | Evidence |
|---|---|---|
| Live speed | **Verified** | status bytes 7-8 (x10, scooter's unit); matched his 4 / 8 / 11 / 19 mph wheel-lift test (Nov 9 14:35) |
| Riding mode read + change (walk/eco/drive/sport) | **Verified** | cmd 05 values 04/01/02/03 matched his tap order; status byte 5 |
| Front light on/off | **Verified** | cmd 00, status flag 0x02 |
| Park on/off | **Verified** | cmd 02, flag 0x04. **v4 fix:** only sent after the scooter answers `DB EB CA CA FF` to the password |
| Speed-limit readout per mode | **Verified** | `DB EB BA` = 6 / 12 / 18 / 31 km/h, confirmed by Credence |
| Sport speed-limit write (6-31 km/h) | **Verified** | `BD BE AB A2 [kmh]` + ack; 32 km/h was clamped to 31 by the scooter |
| Walk / eco / drive limit write | Experimental | same pattern (A3/A0/A1), never captured; sent on Set like v3, labelled experimental |
| Units (mph/km/h), start mode (zero/kick) | Experimental | the flag bit follows the command, but which value is which is a guess; each send asks first; Swap switches in Settings |
| Battery % | **Unavailable (unverified)** | byte 10 read 100 in every capture and never moved |
| Odometer | **Unavailable (unverified)** | bytes 23-26 never changed |
| Firmware version, fault codes, temperatures, voltage | Unsupported | never seen in any capture; not shown, not invented |
| Above-stock speeds | **Back in v4.0.1** (v3 behaviour) | 6-45 km/h per mode after the one-time warning; the scooter clamps what it won't take and the app shows what it accepted (Nov 9: asked 32, kept 31) |
| Stock LCD startup / firmware | Research only | nothing is sent; see Lab > LCD research |

**Volpam (Zydtech family):** Partial. The CRC is CRC16-Modbus (low byte first) and it reproduces all 25 distinct frames the vendor app wrote, byte-for-byte (tests in `Tests/VolpamTests.swift`). Verified: sport speed-limit write (Modbus register 0x20, km/h x10), capped at the factory 35 km/h (37.3 was declined, 35.7 clamped to 35). Experimental (own page, confirm every send): lock, light, mode, units and start bits, which were lined up from button order only. The Bluetooth password is typed by you and kept in the iOS Keychain; it is never in the code, the log or this README. Hiboy S2 Pro and AovoPro/365GO reportedly use the same Zydtech protocol: **unverified**, they get read-only until someone captures one.

**Anything else:** Diagnostics only. Unknown devices are listened to and logged; nothing is written.

## What's new in v4

Reliability first:
- Connection states you can see (scanning, connecting, discovering services, subscribing, synchronizing, connected, reconnecting), RSSI signal bars, packets per second.
- Commands wait until the notify subscription is **confirmed** by iOS; nothing is sent before.
- All session timers live in one owner (`SessionTimers`): one timer per name (no duplicate heartbeats), all cancelled the moment the link drops, and a late tick from an old session is ignored.
- Auto-reconnect with back-off (0.5, 1, 2, 4, 5 s...), and the `bluetooth-central` background mode + state restoration so a pending reconnect survives the phone locking (iOS still decides how long the app may run in the background).
- One scooter at a time: connecting to a new one disconnects the old one, so two sessions can't send conflicting commands.
- **Every** byte leaves through one gate (`WriteGuard`). Blocked: firmware / bootloader / identity characteristics, speed limits outside 6-45 km/h, anything while simulating or replaying. Experimental frames (above-stock limits, eco/drive/walk limits, terminal frames) go out only after your confirmation or the developer-mode warning, never automatically.
- Incoming packets: length checked before any byte is read, malformed frames rejected and counted, the raw bytes are kept beside the decoded ones.
- A BLE "write OK" is never treated as the scooter accepting a setting: the readouts change only from the scooter's own replies.

Dashboard:
- Three gauges: **Classic** (dial + needle), **Digital** (giant digits), **Performance** (gradient arc). The needle eases between real samples but never past the real value, and shows `--` / "no live data" when samples stop for 1.5 s.
- Themes: accent, background, font, light/dark, per-mode colors (walk muted white, eco green, drive blue, sport red, all overridable), animation intensity, units, layout, tiles. Saved on the phone.
- Mode change plays a short color sweep and a haptic (both can be turned off).
- Landscape dashboard for a mounted phone; quick controls disappear while you're moving.
- Night theme: dim colors, no glow, no sweeps.
- Dashboard designer: reorder / add / remove tiles, save named layouts, presets (Default, Classic, Minimal, Performance, Night).
- Theme sharing: export / import JSON. Imports are validated and missing fields get defaults. Theme files contain no names, IDs, passwords or rides.

Features:
- **Trip computer + history**: max, average (moving), duration, ESTIMATED distance from speed samples (gaps > 2 s add nothing), time per mode, connection interruptions. Ride cards, delete one, clear all, export a text summary, speed chart.
- **Trip replay**: plays a saved ride through the gauge. It has no connection to the scooter.
- **Offline simulator**: idle, connecting, city ride, sport run, mode tour, disconnect + reconnect, malformed packets. It produces real-format scrambled frames that go through the real parser, is marked SIMULATED everywhere, and can never send Bluetooth (enforced in the write gate and tested).
- **Diagnostics**: link state, signal, model, protocol family, compatibility level, services, packets/s, last data, rejected packets, latest status packet, per-capability evidence, and a health light built only from things we can observe.
- **Developer Lab**: read-only by default. Packet monitor with search and RX/TX/blocked filter, status byte inspector, UUID viewer, export log, offline decoder, compare two captures, protocol self-tests. Manual sending (terminal, byte explorer) needs a separate advanced warning, and the gate still blocks unknown frames. No fuzzing, no scanning.
- **Startup Studio**: the phone's startup (logo animation, text, theme, duration, sound incl. imported audio, haptic sequence) with a full preview. Default: the HACKTHESCOOT logo. It does **not** change the scooter's LCD.
- **Feedback**: haptics / sounds for connect, disconnect, mode change, trip start, trip end, each switchable.
- **App icon**: drawn in code (`Support/make_icon.py`, a speedometer dial on a wheel hub); the same mark is `LogoView` in the app.
- **Keychain**: the J078 park PIN (moved out of v3's settings on first launch) and the Volpam password.

## Not done yet (honest list)

- **Live Activity / Lock Screen**: not in this beta. A Live Activity needs a widget-extension target, and an unsigned sideloaded build can't be checked in CI for whether iOS would actually refresh it; iOS also limits update frequency, so it could only ever show "last known speed" with an age. Fallback today: keep-awake dashboard + background reconnect.
- Walk / eco / drive speed-limit writes and the units / start-mode value meaning: need one capture each to become verified.
- Volpam lock / light / mode controls: need a capture where the app screen and the frames can be matched one by one (screen recording + sysdiagnose).
- Battery, odometer, firmware version, fault codes on the J078: no evidence yet.
- GPS route recording: the data model has room for it (`Trip.route`), but no location code ships in this beta (no location permission is asked).
- LCD segment simulator is a generic 7-segment model, not the J078's real segment shapes.
- Multi-brand: the adapter system is in (`ProtocolAdapters/`), but only the J078 and the Volpam have adapters. Other brands, the compatibility database, billing, onboarding and the Garage are separate work (see the research docs PR).

## Code layout

```
J078/
  Core/                 pure logic, unit-tested, no UI / no CoreBluetooth objects
    Protocol.swift        J078 scramble, frames, status parsing, gears, factory limits
    VolpamProtocol.swift  Volpam frames + CRC16-Modbus
    Safety.swift          command classification, CommandGate, incoming parser, limit outcome
    Gates.swift           ParkGate (password-before-park), WriteGuard (single write door)
    SessionTimers.swift   one owner for all session timers
    ConnectionState.swift phases, reconnect policy, RSSI words, rate meter
    Simulator.swift       offline J078 simulator (real-format frames)
    TripComputer.swift    trip math, detector, local store
    Theme.swift           DashTheme (JSON import/export), tiles, layouts
    Units.swift           unit conversion + SpeedInterpolator (never overshoots)
    CaptureTools.swift    offline decoder, capture compare, on-phone self-tests
  ProtocolAdapters/     capability model + adapters (Joyhis365, Zydtech/Volpam, GenericReadOnly)
  Transport/            BLEManager (CoreBluetooth), Keychain
  Features/             Dashboard, Controls, Connect, Trips, Diagnostics, Customization, Startup, Feedback
  Research/             Developer Lab, LCD research
Tests/                  XCTest (run on a simulator in CI before anything publishes)
Support/                Info.plist, make_icon.py
```

## Tests

`xcodebuild test -scheme J078Tests` on an iPhone simulator (CI does this on every push). Covered: scramble round trip for all 256 byte values + permutation, packet parsing and lengths (every length 0-80 never crashes), status values, gear codes, speed unit conversion, speed-limit writes and acks (incl. the 32→31 clamp), limit outcomes, password replies, the park gate (timeout never parks, late OK doesn't count, expiry, reset), the write gate (simulation / replay never send, experimental needs confirmation, blocked frames and identity characteristics never sent), session timers (no duplicates, cleanup on disconnect, stale ticks ignored), reconnect back-off, adapters (unknown = read-only, name alone isn't enough, Nordic UART isn't a J078, no above-factory writes), trip math (distance, gaps, invalid samples, mode time, detector), theme import validation, and the Volpam CRC against every captured frame.

## Credits and licenses

- Protocol work: decoded by us from Credence's own captures. No vendor code is included.
- Ideas (not code) from open-source scooter apps: speed / trip / mode-tile dashboards and log-export ideas common to projects like the ScooterHacking community tools (scooterhacking.org) and open M365 dashboard apps. No source from any of them is copied into this repo. If code is ever reused, its license and copyright notice will be added here first; AGPL/GPL code won't be reused in an App Store build.
- App icon and logo: drawn in code in this repo.

## 1. Put it on GitHub

Already have the v1 repo? Use it: delete the old `J078` folder (v1 had `ScooterView.swift` and `LogView.swift`, which are gone now), upload this whole folder over it, and commit. The Actions build starts by itself.

New repo:


1. On github.com make a new repository (private is fine), e.g. `j078-app`.
2. Unzip this folder and upload everything in it, including the hidden `.github` folder and `.gitignore`.
   - Easiest on a computer: in the new repo click "uploading an existing file" and drag the folder contents in (Chrome/Edge keep the folders).
   - Or with git:
     ```
     cd j078-app
     git init -b main
     git add .
     git commit -m "HackTheScoot v4"
     git remote add origin https://github.com/YOUR-NAME/j078-app.git
     git push -u origin main
     ```
   - Check that `.github/workflows/build.yml` is in the repo. Without it nothing builds.

## 2. Get the .ipa

1. Open the repo, tap the **Actions** tab. A build named "Build unsigned IPA" starts on every push to main or v4-dev (or press "Run workflow"). It runs the tests first; nothing publishes unless they pass.
2. Wait for the green check (about 5 to 10 minutes). If it is red, open it and read the failed step.
3. Open the finished run, scroll to **Artifacts**, download `J078-unsigned-ipa`. GitHub gives you a .zip; inside is `J078-unsigned.ipa`.

No Mac needed for this part: GitHub's Mac machines generate the Xcode project (XcodeGen) and build it.

## 3. Install it on your iPhone (the honest part)

The .ipa is **unsigned**. iPhones only run signed apps, so you must sign it yourself. Options:

- **Free Apple ID + a sideloading tool** (Sideloadly or AltStore). You need a Windows PC or Mac at least once to install it. Apps signed with a free Apple ID **stop opening after 7 days** and must be re-signed (AltStore can refresh over Wi-Fi if its helper is running on the computer). Free accounts are also limited to a few apps at once.
- **Paid Apple Developer account** ($99/year). A signed build lasts up to a year, and you could later set up TestFlight builds straight from GitHub Actions (needs certificates added as repo secrets; not set up here).

Either way, on iOS 16+ you also have to turn on **Settings > Privacy & Security > Developer Mode** the first time, and allow Bluetooth when the app asks.

## 4. Using it

1. Scooter on, **close the 365 app** (the scooter may only allow one connection).
2. **Connect** tab: Start scan, tap "365_scooter" (it has a green J078 tag). Next time it auto-connects.
3. You hear the startup sound, then the **Dash** shows live speed.
4. If start mode or units do the opposite, flip its Swap switch.
5. Something weird? **Debug** tab, share button, send the log.

