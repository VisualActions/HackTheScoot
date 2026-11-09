# HackTheScoot (v3)

iPhone app for your Joyhis J078 scooter (and other scooters in log mode). Formerly "J078 app".
It talks to the J078 the same way the 365 app does. The protocol was decoded on Nov 9 2026 from your own Bluetooth captures.

## What's in it

- **Dash**: big live speedometer (about 15 updates a second), current mode, that mode's top speed, max speed this ride, battery? and light/park. Quick buttons for the 4 modes, light and park.
- **Custom dashboard** (Settings): speedometer color picker plus swatches, color modes (one color / color per mode / heat that turns red near the top), arc, digital or minimal style, font, background (black, gradient, solid color), unit (same as scooter / always mph / always km/h), gauge max, which tiles show, keep the screen on.
- **Controls**: front light, park (sends the password first, like the 365 app), walk / eco / drive / sport, start mode, units, and the top speed for each mode.
- **Startup sound**: plays on the phone when the scooter connects. 4 built-in sounds or your own audio file from Files.
- **Connect**: finds "365_scooter" with no pairing and works out the protocol by name and Bluetooth service: J078, Volpam / F1F1 (the v1 heartbeat path, A5 02 FD 5A), or log-only for anything else. You can change the protocol by hand. Remembers your scooters and auto-connects to the last one (it reconnects when the scooter comes back on).
- **Debug**: packet log (bytes sent over the air plus unscrambled), status bytes table (all 29 bytes, odometer? raw), scramble self-test, export the log as .txt.
- **Choose your scooter** (DJI-style, on first launch and in Settings): Joyhis J078, Volpam, or Other. Your pick is listed first when scanning; auto-detect still decides the protocol.
- **Developer mode** (Settings > Developer, asks first): a **Terminal** where you type hex codes (or shortcuts like `light on`, `gear sport`, `pw`) and send them, scrambled like the 365 app or raw, to any writable characteristic, and see every code live. Plus **Experimental**: a command explorer for `BD BE AB [cmd] [value]` that shows which status bytes changed after you send. These only send when you tap Send.
- **Speed limits (new in v3)**: a slider per mode, 6–45 km/h, shown in mph and km/h. Tap **Set** to send one command (`BD BE AB [mode byte] [km/h]`, scrambled). Under it you see what you asked for and what the scooter actually accepted (from its reply `DB EB BA [mode byte] [km/h set]`). If they differ it says "scooter declined, kept X mph". Above each mode's stock limit (Sport 31 km/h) is locked until you accept a one-time warning. Sport (A2) is checked on your scooter; Eco (A0), Drive (A1) and Walk (A3) are experimental. Volpam: needs a capture from the Volpam first, nothing is sent.

## What's checked and what isn't

Checked on your scooter (Nov 9 captures): the scramble, light, park + password 000000, the 4 modes, the 500 ms keep-alive, live speed (bytes 7-8 / 10), and mode top speeds 4 / 8 / 11 / 19 mph (6 / 12 / 18 / 31 km/h), and the Sport speed-limit write + its reply.

UNVERIFIED (best guesses):
- **Start mode**: cmd 07, 01 = zero start, 00 = glide. If it's backwards, turn on "Swap" under Start mode (Controls or Settings).
- **Units**: cmd 01, 01 = mile, 00 = km. Same "Swap" switch.
- **Battery?**: status byte 10 (it read 100).
- **Odometer?**: status bytes 23-26, shown raw in Debug.
- **Speed limit for Eco / Drive / Walk**: mode bytes A0 / A1 / A3 follow the keep-alive pattern (experimental).
- The Volpam path is from reading the vendor app; not checked on a real Volpam.

**Speed limit evidence:** the Nov 9 5:11 PM capture has the 365 app setting Sport 19 → 18 → 19 mph (`A2 1F` → `A2 1D` → `A2 1F`). At 3:23 PM the 365 app asked for 32 km/h and the scooter answered 31, so above-stock values may be refused by the scooter's firmware. The app shows you its answer either way. Running above stock can overheat or damage the motor, controller or battery. Wear a helmet.

Nothing is installed on the scooter. On its own the app only sends the commands the 365 app sends (speed limits only when you tap Set); anything else only goes out when you type it in developer mode.

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
     git commit -m "HackTheScoot v3"
     git remote add origin https://github.com/YOUR-NAME/j078-app.git
     git push -u origin main
     ```
   - Check that `.github/workflows/build.yml` is in the repo. Without it nothing builds.

## 2. Get the .ipa

1. Open the repo, tap the **Actions** tab. A build named "Build unsigned IPA" starts on every push to main (or press "Run workflow").
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

## Files

- `project.yml`: XcodeGen project (the .xcodeproj is generated on CI).
- `Support/Info.plist`: app settings, including the Bluetooth permission text.
- `J078/Protocol.swift`: the decoded protocol (scramble, commands, status parsing, gears, scooter kinds).
- `J078/BLEManager.swift`: all Bluetooth code (scan, auto-detect, keep-alive, commands, saved scooters).
- `J078/Settings.swift`: settings keys, the two swap-able mappings, colors.
- `J078/SoundPlayer.swift`: startup sounds (generated in code) and your own sound.
- `J078/DevViews.swift`: terminal, experimental explorer, choose-your-scooter screen.
- `J078/DashboardView.swift`, `ControlsView.swift`, `ConnectView.swift`, `DebugView.swift`, `SettingsView.swift`, `J078App.swift`: the screens.
- `.github/workflows/build.yml`: the cloud build (unsigned .ipa).
