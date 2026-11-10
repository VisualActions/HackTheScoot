# HackTheScoot (v5.0 beta, public release candidate)

An iPhone companion for the **Joyhis J078** scooter (and, carefully, dad's **Volpam**), plus read-only support for new brands until someone sends a capture. Everything it does on the J078 was decoded from real Bluetooth captures of the 365 app on Nov 9 2026. Nothing is guessed silently: every feature below says how sure we are.

> **Stable vs beta.** `main` is v3, the stable build (release **latest**). v5 lives on the `v4-dev` branch (PR #2) and is published as the separate prerelease **v5-beta** only after the secret scan, license scan, unit tests and screen tests pass. Merging PR #2 is what makes v5 the main download: see [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md).

Downloads:
- Stable v3: https://github.com/VisualActions/HackTheScoot/releases/latest
- v5 beta: https://github.com/VisualActions/HackTheScoot/releases/download/v5-beta/HackTheScoot-5.0.0-beta-unsigned.ipa
- Older 4.2 beta: https://github.com/VisualActions/HackTheScoot/releases/tag/v4-beta

**Got a scooter or e-bike that isn't supported?** Send a capture: [CAPTURES.md](CAPTURES.md), or in the app More > Help unlock your scooter or e-bike.

## What's new in 5.0 (beta)

Built and tested in CI (simulator). Not tried on a real phone, scooter or e-bike yet, so everything that touches hardware *should* work but is unproven. Nothing from 4.2 was removed or capped (6-45 km/h sliders behind the warning, the 4.0.1 Bluetooth flow, the terminal, Garage, intro, Pro test mode and every 4.2 feature are all as before). Everything below is free.

- **Capture tutorial: "Help unlock your scooter or e-bike"** (More > Vehicle, Help, the packet logger and every read-only vehicle screen). Two routes, step by step:
  - **Quick:** start the packet logger, connect, press one thing at a time in the brand's official app with a 5-second pause, tap **I pressed...** after each (it writes a `MARK` line into the capture), stop, share.
  - **Advanced:** Apple's Bluetooth logging profile + a sysdiagnose (both directions of the Bluetooth traffic), checked against Apple's own instructions. Includes "only stacks files = it didn't start".
  - **Send a capture** screen: mask a PIN, share sheet, email, or a prefilled GitHub **New vehicle capture** issue (`.github/ISSUE_TEMPLATE/new-vehicle-capture.yml`).
  - **Find vehicles already connected to this phone** (Connect): lists a vehicle the official app is connected to, so HackTheScoot can listen at the same time. Listening only.
  - Honest limit: iPhone apps can't see what another app sends, so the quick route records the vehicle's replies; the advanced route has both directions.
- **GPS route maps** (opt-in, More > App settings > GPS routes): each real ride saves its route while the app is open (no background location) and shows it on a map in the ride. Stays on the phone; GPX export (Pro) now has data.
- **Ride history search and filters** (Trips): search by vehicle, date or mode; filter by vehicle, time, real or simulated, and rides with a route.
- **Battery and range estimates** (More > Ride): labelled **estimated** everywhere. From Fardriver charge or volts (pick the pack voltage), Ninebot battery, or a battery % you set (the J078 / Volpam readings are still unverified), times your own full-charge range and the riding mode.
- **Vehicle info and firmware** (More > Vehicle): adapter, support level, signal, services, and the standard Device Information values (firmware, hardware, model) when the vehicle shares them. Read only when you tap "Read device info"; serial numbers are hidden.
- **Fault explanations**: tap a Fardriver warning to see what it usually means and what to check (general guidance, marked unverified). J078 / Volpam faults: none decoded, none made up.
- **Compatibility checker** (free): search the compatibility database before you buy.
- **Backup and restore**: settings, Garage, maintenance, themes, layouts and (optionally) trips as one JSON file. Passwords, PINs, photos and the test unlock are never included. Restoring adds trips, never deletes them.
- **What's new** screen, shown once after updating.
- **Privacy policy and terms of use**: DRAFTS from the research outlines, clearly marked as needing an adult and a legal review. Plus **open-source credits**.
- **Crash-safe logging**: the packet logger writes to disk as it records (an unfinished capture is offered back after a crash), and a small app log (More > App log) notes connects and phases and flags when the last session ended unexpectedly. Local only, passwords masked.
- **Appearance**: dark / light / system in App settings (the tab bar now follows light mode too).
- **Accessibility**: VoiceOver reads the dashboard speed and mode, every new screen has labels, lists use Dynamic Type.
- **Localization scaffolding**: English + a first Spanish pass of the main screens (iOS Settings > HackTheScoot > Language).
- **Stripe TEST return link**: after the test checkout, the thank-you page has "Open HackTheScoot", which turns on Pro as a labelled **test** unlock. It isn't verified (that needs the server), so it's for testing the flow only.
- **Release readiness**: version 5.0.0 (build 8), the IPA is named `HackTheScoot-...ipa`, a privacy manifest (`PrivacyInfo.xcprivacy`), CI secret and license scans, and [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md).

### Deferred in 5.0 (and why)
- **Widgets and Live Activity**: still not shipped. Both need a widget extension, and sharing ride data with it needs an App Group, which needs a paid Apple Developer team; free-Apple-ID sideloading usually drops extensions too. Possible after the adult enrolls (RELEASE-CHECKLIST.md B).
- **A Stripe payment securely unlocking Pro**: needs a small server (webhook + entitlement) holding the secret key. The 5.0 return link is TEST and unverified.
- **Real App Store purchases**: need App Store Connect (adult account) and a signed build.
- **Writes to Fardriver, Ninebot or unknown vehicles**: need captures. Fardriver road speed needs wheel size from a capture.
- **Bundle id rename**: kept as `com.example.j078app` so existing installs update in place; how to change it at App Store time is in RELEASE-CHECKLIST.md.
- **Full translations**: only the main screens have Spanish so far.

## What was new in 4.2

Built and tested in CI (simulator). Not tried on a real phone, scooter or e-bike yet, so everything that touches hardware *should* work but is unproven. Nothing from 4.1 was removed or capped (6-45 km/h sliders, the 4.0.1 Bluetooth flow, the terminal, Garage, intro and Pro test mode are all as before). Everything below is free; safety, fault warnings and controls never go behind Pro, and there is no paid speed unlock.

- **Ride stats** (More > Ride, Trips): this ride and all rides: average and top speed, ride and moving time, distance. Distance is labelled **estimated**: it is speed × time between samples, not the odometer.
- **Speed alert**: you pick a speed; the phone buzzes and beeps once when you go over it and re-arms after you slow down. It never changes the scooter.
- **Ride timer with laps**: start / pause / lap / reset, best lap marked.
- **Units everywhere**: More > App settings > Units (scooter's own / mph / km/h) changes the dashboard, trips, stats, alerts and share cards.
- **Last parked here** (opt-in, location only while the app is in use): when the scooter parks or the link drops while the app is open, the phone saves where you are. Map + directions. Stays on the phone.
- **Share card**: a ride summary image (Trips > a ride > Share card image).
- **Maintenance reminders** (Garage > a vehicle > Maintenance): tire pressure, brakes, bolts, or your own, every N miles or N days, whichever comes first.
- **Quick actions**: long-press the speed on the Dashboard (or tap the bolt) for light, park and mode.
- **App settings**: accent colour, a master haptics switch, alternate app icons (Classic, Ember, Mono, Lime).
- **Packet logger** (More > Tools, Controls, Garage): records every Bluetooth frame in and out (passwords masked) and exports a .txt capture.
- **Help / FAQ** in More.
- **Garage: e-bikes and controller types**: "Add vehicle" picks e-scooter or e-bike and the controller (Joyhis/365, Zydtech, Ninebot, Fardriver, Unknown).

### New brands: read-only until a capture
- **Fardriver (ND-series e-bike / e-scooter controllers)**: `FardriverAdapter`, **Experimental, read-only, no writes at all** (motor-controller writes can damage hardware). Detected by name, by the Garage's controller type, or by its frame shape (AA + valid CRC, 3 frames). Shows battery volts, current, power (worked out as V × A), state of charge, raw motor speed (likely RPM; no road speed without wheel size), gear, motor temperature, brake and fault bits. All unverified until a capture. If the controller only streams after the official app wakes it, the screen stays empty: that also needs a capture.
- **Ninebot / Segway (Max G30 first)**: `NinebotAdapter`, **Experimental, read-only, writes off**. Decodes plain Protocol 2 read replies (speed, battery, odometer, range) if any arrive. Most Ninebots only answer when asked (a write) and current firmware is encrypted, so live data will usually stay empty until a real capture.
- Experimental and Unknown vehicles show live data only, with a "needs a capture to unlock controls" note and a button that starts the packet logger.
- The scooterhacking GitHub org has no Fardriver code (it covers Ninebot/Xiaomi), and its code isn't reused: NinebotCrypto is AGPL and most other repos there have no license. Both adapters are clean-room from the public docs credited below.

### Deferred (honest list)
- **Widgets**: not shipped. A widget needs an app extension plus an App Group to read ride data, and App Groups need a paid Apple signing team; sideloading tools on a free Apple ID usually drop extensions. Worth doing once there is a signed build.
- Fardriver road speed (needs wheel size + pole pairs from a capture), any Fardriver/Ninebot writes, Ninebot's encrypted login.

## What was new in 4.1

- **First-launch intro**: welcome, why Bluetooth, your scooter, find it, the four tabs. Skippable, shown once, More > Show the intro again.
- **Garage** (More > Garage): every scooter you own with its own name, model, compatibility level, photo or color, notes, last-known stats and trips. Switch the active scooter and the app auto-connects to it. Starts with "My J078" and "Dad's Volpam".
- **HackTheScoot Pro, TEST MODE**: FREE / PRO ($3.99/mo, $29.99/yr) / DEVELOPER (later). Details below.
- Nothing from 4.0.1 was removed or capped.

## HackTheScoot Pro (test mode)

| FREE (always) | PRO $3.99/mo or $29.99/yr | DEVELOPER (later, not for sale) |
|---|---|---|
| Connecting, every control, speed limits incl. the above-stock 6-45 km/h sliders, fault warnings, safety info, compatibility info, Garage, dashboard themes + designer + layouts, trips + replay + summary export, diagnostics, Developer Lab, packet log, terminal | Pro theme pack (6 looks), advanced trip analytics (per scooter), CSV + GPX export, extended packet-log analysis | Frame compare workspace, JSON log export for fixtures |

Rules (unit-tested): nothing that controls or protects the scooter is sold, nothing that was free before 4.1 moved behind the paywall, and there is **no paid speed unlock**.

**How to test it**
- **On the sideloaded beta (what you have):** More > Developer settings > **Test unlock** > Pro (test) or Developer (test). That turns the Pro screens on, on this phone, without paying. It's labelled TEST everywhere and never touches the scooter.
- **Web checkout (Stripe TEST mode):** the download page has a "Get Pro (test)" section. Pay with **4242 4242 4242 4242**, any future date, any CVC, any ZIP. No real money moves. The links are made by the `Stripe test setup` workflow (`.github/workflows/stripe-test-setup.yml`) from the `STRIPE_SECRET_KEY` repo secret, which is never printed, committed or put in the app. The script refuses anything that isn't a `sk_test_` key.
- **In Xcode:** the app scheme uses `Support/HackTheScoot.storekit`, a local StoreKit config with both subscriptions and a 1-week free trial, so purchase / restore / renew / expire can be tested on a simulator with no Apple account.

**What an unsigned sideloaded IPA can't do (honest part)**
- It can't buy anything from the App Store. Real StoreKit sandbox purchases need an Apple Developer account, the two products created in App Store Connect, and a signed build (TestFlight or Xcode with a team). Until then the paywall says "store unavailable" and Test unlock is the way to see Pro.
- A Stripe web purchase can't unlock the app yet. That needs the small server from the billing plan (`docs/business/billing-plan.md`, phase 2: Supabase + verified webhooks) to tell the app who paid.
- Apple's rules: in the app, subscriptions must be Apple in-app purchase. A Stripe link-out button is allowed only on the **US** storefront, next to IAP. The in-app "Get Pro on the web (test)" button only exists because this build is in test mode; before an App Store release it must be gated on `Storefront.current` = USA.

### Going live (checklist, an adult must do these)
Nothing is live today. Don't switch any of this on without a parent or guardian.
1. **Apple:** a parent/guardian enrolls in the Apple Developer Program (you have to be 18, or the legal age of majority) and adds Credence to the team. Sign the Paid Apps Agreement, add tax and bank info. Enroll in the Small Business Program (15%).
2. **App Store Connect:** create the subscription group "HackTheScoot Pro" with `com.hackthescoot.pro.monthly` ($3.99) and `com.hackthescoot.pro.yearly` ($29.99), the optional 1-week intro trial, screenshots and review notes. Set a real bundle id (not `com.example`).
3. **Signed build:** archive with the team, test in the sandbox with a Sandbox Apple ID (buy, restore, cancel, expire), then TestFlight.
4. **Hide Test unlock** in release builds (wrap `DeveloperSettingsView` in `#if DEBUG` or a TestFlight check) and set `Billing.testMode = false` only after review.
5. **Stripe:** Stripe needs an adult as the account representative for anyone under 18. Activate the account (business details, bank, tax), then create a **live** key yourself. Never paste a live key into GitHub Actions for this repo's test workflow (it refuses live keys on purpose).
6. **Server (if web purchases should unlock the app):** Supabase (or similar) with Sign in with Apple, Stripe webhooks verified with the `whsec_` signing secret, idempotent event handling, Customer Portal for cancel, refunds and failed payments revoke Pro, account deletion. App Store Server Notifications V2 for Apple.
7. **Legal:** Privacy Policy, Terms, the App Store privacy label, and a review of `docs/legal/` by an adult (ideally a lawyer).

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
- GPS route recording: shipped in 5.0 (opt-in, while the app is open).
- LCD segment simulator is a generic 7-segment model, not the J078's real segment shapes.
- Multi-brand: the adapter system is in (`ProtocolAdapters/`), but only the J078 and the Volpam have adapters. The compatibility database seed is built in (Garage), and 5.0 adds the searchable checker.
- Billing is TEST MODE only (see below). No real money can move from this build.

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
    Garage.swift          Garage rules (link / switch / per-scooter stats + trips)  (4.1)
    CompatSeed.swift      research compatibility database seed                       (4.1)
    Entitlements.swift    tiers, products, what Pro unlocks, never-paywalled rules   (4.1)
    ProTools.swift        CSV/GPX export, ride analytics, log analysis, frame diff   (4.1)
    RideFeatures.swift    speed alert, ride timer, maintenance, ride totals, vehicle/controller types (4.2)
    V5Core.swift          capture tutorial + PIN masking, ride filter, GPS route math, battery/range estimates,
                          fault explanations, what's new, Stripe test return link, backup/restore      (5.0)
    AppJournal.swift      crash-safe app log + capture file written as it records                   (5.0)
  ProtocolAdapters/     capability model + adapters (Joyhis365, Zydtech/Volpam, Fardriver + Ninebot read-only (4.2), GenericReadOnly)
  Transport/            BLEManager (CoreBluetooth), Keychain
  Features/             Dashboard, Controls, Connect, Trips, Diagnostics, Customization, Startup, Feedback,
                        Onboarding (4.1), Garage (4.1), Ride (4.2: alert, timer, stats, share card, parked spot,
                        maintenance, quick actions, app settings, packet logger, help, read-only live view)
  Premium/              StoreKit 2 StoreManager, paywall, ProGate, Pro tools, Developer settings (4.1)
  Features/Capture      capture tutorial, send-a-capture (5.0)
  Features/V5           compatibility checker, vehicle info, faults, battery/range, backup, what's new,
                        privacy / terms (DRAFT), credits, app log (5.0)
  Features/Trips/RouteRecorder.swift  opt-in GPS route + map (5.0)
  en.lproj, es.lproj    localization (5.0)
  PrivacyInfo.xcprivacy privacy manifest (5.0)
  Research/             Developer Lab, LCD research
Tests/                  XCTest (run on a simulator in CI before anything publishes)
Support/                Info.plist, make_icon.py
```

## Tests

`xcodebuild test -scheme J078Tests` on an iPhone simulator (CI does this on every push). Covered: scramble round trip for all 256 byte values + permutation, packet parsing and lengths (every length 0-80 never crashes), status values, gear codes, speed unit conversion, speed-limit writes and acks (incl. the 32→31 clamp), limit outcomes, password replies, the park gate (timeout never parks, late OK doesn't count, expiry, reset), the write gate (simulation / replay never send, experimental needs confirmation, blocked frames and identity characteristics never sent), session timers (no duplicates, cleanup on disconnect, stale ticks ignored), reconnect back-off, adapters (unknown = read-only, name alone isn't enough, Nordic UART isn't a J078, no above-factory writes), trip math (distance, gaps, invalid samples, mode time, detector), theme import validation, and the Volpam CRC against every captured frame. 5.0 adds: the capture tutorial's steps and links, password / PIN masking (text and hex), ride search and filters, GPS route math (distance, glitches, spacing), battery-from-voltage and range estimates, every Fardriver fault has an explanation and unknown ones are never invented, what's-new versioning, the Stripe test return link, backup (blocked keys can't get in or out, round trip, merge-not-replace) and the crash-safe journal (written as it records, survives a relaunch), plus screen tests for every new screen (portrait, landscape, dark and light).

## Credits and licenses

- Protocol work: decoded by us from Credence's own captures. No vendor code is included.
- Ideas (not code) from open-source scooter apps: speed / trip / mode-tile dashboards and log-export ideas common to projects like the ScooterHacking community tools (scooterhacking.org) and open M365 dashboard apps. No source from any of them is copied into this repo. If code is ever reused, its license and copyright notice will be added here first; AGPL/GPL code won't be reused in an App Store build.
- **Fardriver adapter (4.2)**: written clean-room from the public notes in [jackhumbert/fardriver-controllers](https://github.com/jackhumbert/fardriver-controllers) (MIT License, Copyright (c) Jack Humbert): the serial frame layout, the id-to-address table, the CRC parameters and the field names. No code is copied; the CRC is computed bitwise and checked in tests against frames built with that project's own tables. Facts only (no code) from public forum threads that the Bluetooth module notifies on FFE1.
- **Ninebot adapter (4.2)**: written clean-room from the [Segway-Ninebot BLE Protocol docs](https://nootnooot.codeberg.page/segway-ninebot-ble/) by NootNooot (Apache-2.0): frame format, checksum, register numbers. No code from scooterhacking's repos (NinebotCrypto is AGPL; most others have no license).
- App icon and logo: drawn in code in this repo (4.2's alternate icons are recolours of it).

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
3. Open the finished run, scroll to **Artifacts**, download `HackTheScoot-unsigned-ipa`. GitHub gives you a .zip; inside is `HackTheScoot-unsigned.ipa`. (Or just download it from the Releases page.)

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

