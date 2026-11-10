# Contribute a capture

HackTheScoot only controls a vehicle after a real Bluetooth capture proves what each button sends. New brands start **read-only**: live data only. A capture from someone who owns one is how that changes.

## Where each brand stands (5.1)

| Brand | Now | What a capture would add |
|---|---|---|
| Joyhis J078 | Controls verified from captures | Battery / odometer meaning |
| VOLPAM (Zydtech) | Speed limit verified | Lights and the other feature bits |
| KuKirin G2 (2026) / G4 | **Experimental, untested on hardware:** live data only (G2 speed, volts, rpm, mode; G4 mode). Never written to | **Every control**: no KuKirin command is public. Capture the official **Kugoo** app |
| Xiaomi M365 (old Bluetooth firmware) | **Experimental, untested on hardware:** live data + KERS, cruise, tail light (read, confirm, read back) | Headlight; confirmation of the three settings on your firmware |
| Xiaomi M365 Pro / Pro 2 / 1S / Essential | **Experimental, untested on hardware:** our own Ninebot pairing, then live data only | Any setting (capture the Mi Home app) |
| Xiaomi M365 (newer Xiaomi login) | Not supported (only AGPL code exists) | - |
| Ninebot Max G30 | **Experimental, untested on hardware:** live data + cruise control; pairing for encrypted firmware | Lights, KERS, speed mode (the public sources disagree). Capture the Segway-Ninebot app |
| Fardriver | Live data only, never written to | - |
| Anything else | Read-only (packet logger) | Everything |

If you own a KuKirin, a G30 or a Xiaomi and try the 5.1 beta, a capture (and a note saying whether the live numbers match your dashboard) is the most useful thing you can send.

It takes about 5 minutes. In the app: **More > Help unlock your scooter or e-bike** (also linked from the read-only vehicle screen, Help and the packet logger).

## What each route can see (honest version)

- iPhone apps can't read what **another** app sends. So the **quick route** (HackTheScoot's packet logger) records what the vehicle sends **back**: its status changing as you press things in the official app.
- The **advanced route** (Apple's Bluetooth logging profile + a sysdiagnose) records **both directions**, including the official app's commands. That's usually what's needed to unlock controls.
- Send both if you can.

Don't ride while capturing. Do it with the vehicle on a stand or the wheels off the ground.

## Quick route: the in-app packet logger

1. **Get ready.** Install the vehicle's official app and check it works. Turn the vehicle on, keep the phone next to it. Note the brand, model and (if the official app shows it) firmware version.
2. **Start the packet logger.** HackTheScoot: More > Packet logger > Start recording. Leave it running the whole time.
3. **Connect.** Open the official app and connect. Then HackTheScoot > Connect and tap the vehicle. If it isn't listed, tap **Find vehicles already connected to this phone** (vehicles don't advertise while another app is connected). Unknown vehicles are read-only: HackTheScoot only listens.
4. **Press one thing at a time in the official app**, in this order (skip what your vehicle doesn't have):
   - lights on, lights off
   - each mode / gear (1, 2, 3, 4)
   - a speed-limit change (say the number)
   - park / lock on, park / lock off
   - cruise control, units, zero start / kick start (if it has them)

   After each press, tap the matching **I pressed...** button in the logger (it writes a `MARK` line into the file), then **wait 5 seconds** before the next one.
5. **Stop and export.** Packet logger > Stop recording > Share capture. You get a `.txt` file. (It is also saved on the phone as it records, so a crash doesn't lose it.)
6. **Send it.** Open a [New vehicle capture issue](https://github.com/VisualActions/HackTheScoot/issues/new?template=new-vehicle-capture.yml&title=Capture%3A%20%28brand%20model%29&body=%2A%2ABrand%3A%2A%2A%0A%2A%2AModel%3A%2A%2A%0A%2A%2AVehicle%20type%3A%2A%2A%20e-scooter%20%2F%20e-bike%0A%2A%2AController%20%28if%20known%29%3A%2A%2A%0A%2A%2AFirmware%20%28if%20known%29%3A%2A%2A%0A%2A%2AOfficial%20app%20%2B%20version%3A%2A%2A%0A%2A%2AHow%20it%20was%20captured%3A%2A%2A%20HackTheScoot%20packet%20logger%20%2F%20iPhone%20sysdiagnose%0A%0A%2A%2AWhat%20I%20pressed%2C%20in%20order%20%28with%20times%20if%20you%20have%20them%29%3A%2A%2A%0A1.%0A%0A%2A%2ACapture%20file%3A%2A%2A%20%28drag%20the%20.txt%20or%20.pklg%20here%29%0A%0A-%20%5B%20%5D%20I%20checked%20the%20file%20has%20no%20password%2C%20PIN%20or%20personal%20info%20in%20it%20%28issues%20are%20public%29.) and drag the file in (until v5 is merged into `main`, GitHub shows a plain issue with the same questions filled in), or use the app's **Send a capture** screen (GitHub, email or the share sheet). List what you pressed, in order.

Some vehicles only allow one Bluetooth connection at a time. If HackTheScoot can't connect while the official app is connected, use the advanced route.

## Advanced route: iPhone Bluetooth log (sysdiagnose)

Checked against Apple's public pages on Nov 10 2026: the [Profiles and Logs page](https://developer.apple.com/bug-reporting/profiles-and-logs/?name=bluetooth) (Bluetooth for iOS/iPadOS: Profile + Instructions) and Apple's [sysdiagnose instructions PDF](https://podcasters.apple.com/assets/iOS-sysdiagnose-logging-instructions.pdf).

1. **Install Apple's Bluetooth logging profile.** On the iPhone, open the Profiles and Logs page above in Safari. Under "Bluetooth for iOS/iPadOS" tap **Profile**, sign in with an Apple Account (a free Apple Developer sign-in; if yours can't, a parent's works), allow the download, then **Settings > Profile Downloaded > Install**. Follow Apple's "Instructions" PDF on the same page if it asks for anything else.
2. **Record what you press.** Start a screen recording with the microphone on (Control Center > long-press Screen Recording > Microphone on), or write down the time of every press.
3. **Use the official app.** Connect, then press one thing at a time (same list as above), pausing 5 seconds and saying out loud what you pressed.
4. **Trigger a sysdiagnose right after.** Press and release **both volume buttons and the side (or top) button at the same time, quickly**. Apple says about **250 milliseconds**; holding longer than 1 second locks the phone (or opens the power-off screen) instead. You feel a short vibration and a screenshot is taken when it starts.
5. **Wait about 10 minutes**, then go to **Settings > Privacy & Security > Analytics & Improvements > Analytics Data** and find `sysdiagnose_YYYY.MM.DD_...` with today's date.
   - If you only see new `stacks-...` files and no `sysdiagnose_` file, the sysdiagnose didn't start. Do step 4 again.
6. **Send it privately.** Tap the file > Share (AirDrop to a computer, or save to Files). It's large and holds a lot about your phone, so **don't post the whole thing publicly**. The Bluetooth capture inside it is `logs/Bluetooth/bluetoothd-hci-latest.pklg` (opens in Wireshark, or Apple's PacketLogger on a Mac): attach that plus your screen recording.
7. **Remove the profile** when you're done: Settings > General > VPN & Device Management > the Bluetooth logging profile > Remove.

## Privacy

- **Captures can contain your vehicle's Bluetooth password or PIN.** HackTheScoot masks the ones it knows (the J078 password, the Zydtech/Volpam `AT+PWD[...]` password, and any PIN you type into "Mask a PIN" on the Send screen), but it can't recognise every brand's.
- **Never post a password publicly.** GitHub issues are public. Check the file first, or send it privately.
- The packet logger only records Bluetooth frames between HackTheScoot and the vehicle, plus your `MARK` lines. No location, no contacts, nothing else.
- A sysdiagnose is a whole-phone diagnostic (device name, networks, app list and more). Share only the `.pklg` publicly, if at all.

## What happens next

A capture is decoded by hand and checked against what you pressed. Commands are only turned on when the capture proves them, one at a time, and the vehicle's compatibility entry is updated with the evidence. Nothing from a capture is ever sent to a vehicle automatically, and motor-controller settings (Fardriver) stay off-limits because a wrong write can damage hardware.
