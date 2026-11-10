# Acknowledgements

HackTheScoot is built on public research by other people. This file says exactly what we used from each source, under which licence, and what we did **not** use.

**Everything added in 5.1 is experimental and untested on hardware.** It should work, but nobody has tried it on a real scooter yet. If you try it, please send a capture (see [CAPTURES.md](CAPTURES.md)).

## The rules we follow

- **No AGPL or GPL code**, and no code copied from projects without a licence. From those we use **facts only** (which byte means what), written up in our own words and our own code.
- **No firmware.** HackTheScoot never flashes firmware, never bundles or downloads firmware files, and never uses ScooterHacking's firmware generator or tools.
- **No secrets** in the code or docs. A Ninebot session password is made fresh on your phone during pairing and kept only in the iPhone Keychain.

## Sources used in 5.1

### Segway-Ninebot BLE protocol specification, by NootNooot (Apache-2.0)
- https://codeberg.org/nootnooot/segway-ninebot-ble and https://nootnooot.codeberg.page/segway-ninebot-ble/
- **Licence:** Apache License 2.0. Its NOTICE is reproduced in our [NOTICE](NOTICE) file.
- **What we used:** the Encryption2 algorithm (key derivation, nonce, CTR keystream, 4-byte CBC-MAC, non-SN mode, the fixed Gen2 protocol constant), the PRE_COMM / SET_PWD / AUTH pairing flow, frame formats, the BLE transport notes (UUIDs, fragmentation, the iOS echo quirk) and the KickScooter Max command table.
- **How:** HackTheScoot's own Swift implementation in `J078/ProtocolAdapters/NBEncryption2.swift` and `NBXSession.swift`, written from the spec. We changed nothing in the spec; the code is ours.
- **Not used:** scooterhacking/NinebotCrypto. It is AGPL-3.0, so nobody working on HackTheScoot read or copied it.

### Ninebot "ES Communication Protocol" V1.4 (no licence; Ninebot's own document, hosted by ScooterHacking)
- https://cloud.scooterhacking.org/release/nbdoc.pdf
- **What we used:** facts only: the Protocol 2 frame layout, command numbers, the checksum (checked against its worked example), units of a few registers, error-code meanings and which commands are dangerous (they are blocked).

### CamiAlfa / M365-BLE-PROTOCOL, by Camilo Ruiz (LGPL-2.1+ per its README)
- https://github.com/CamiAlfa/M365-BLE-PROTOCOL
- **What we used:** facts only: the M365 `55 AA` frame, addresses, and the register numbers and values for battery, speed, odometer, trip, temperature, range, error, firmware, KERS (0x7B), cruise (0x7C) and tail light (0x7D). Credit to Camilo Ruiz. **No code linked or copied.**

### jx-grxf / scooter-tuning-db (CC BY 4.0)
- https://github.com/jx-grxf/scooter-tuning-db
- **What we used:** facts only, as a second source to confirm the three M365 settings. Where it disagreed with the others (several Ninebot indexes), we left the feature off.

### ScooterHacking wiki (CC BY-SA 4.0)
- https://wiki.scooterhacking.org/ ("Ninebot ESx/Max Error Codes", "Xiaomi error codes", model pages)
- **What we used:** facts only: what each error number means and which models use which protocol. All the wording in the app's error explanations is our own (nothing quoted), and the advice never suggests firmware or serial-number changes.

### KuKirin G2 (2026): joaobenites / bancada-g2 (no licence)
- https://github.com/joaobenites/bancada-g2
- **What we used:** facts only, from the README's published observations: service `FFF0`, notify `FFF2`, the two frame types (`27 22`, `F2 B0`), battery voltage (bytes 4-5), motor rpm (bytes 10-11), speed (byte 12), motor active (byte 18 bit 1) and ride mode (byte 3 of `F2 B0`). The repo has no licence, so **no code was copied**; our parser is `J078/ProtocolAdapters/KukirinProtocol.swift`. Thanks for publishing the observations, and for the "never touch the OAD service" warning, which we follow.

### KuKirin G4: maksdoner / Kukirin-G4-Bluetooth-Control (MIT)
- https://github.com/maksdoner/Kukirin-G4-Bluetooth-Control
- **Licence:** MIT, Copyright (c) maksdoner.
- **What we used:** facts only: notify `FFF2`, byte 6 = `00` gate, byte 5 = ride mode (01 Eco, 02 Sport, 03 Race). Our own code.

## Sources used before 5.1
- **Fardriver:** jackhumbert/fardriver-controllers (MIT, Copyright (c) Jack Humbert): facts for the frame layout, address table, CRC parameters and field names. No code copied.
- **Joyhis J078 and VOLPAM:** decoded from Credence's own Bluetooth captures.

## Not affiliated
HackTheScoot is not affiliated with or endorsed by Segway-Ninebot, Xiaomi, KuKirin/Kugoo, Joyhis, Zydtech, VOLPAM, Fardriver, ScooterHacking or any author above. Names are used only to say which hardware the app talks to.
