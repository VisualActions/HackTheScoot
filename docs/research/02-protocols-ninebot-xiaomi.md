# Protocol notes: Ninebot/Segway and Xiaomi

Facts only, each with a source (all accessed 2026-11-09). "UNVERIFIED" = nobody has tested it on real hardware with HackTheScoot. **Nothing here is tested on hardware by us.** Xiaomi M365-era scooters through the Mi 3 were made by Ninebot ([wiki mi365](https://github.com/scooterhacking/wiki/blob/main/pages/mi365.txt), "Manufacturer" row), so the two families share one protocol lineage.

## Transport (BLE GATT)
| Profile | Service | Write (app→scooter) | Notify (scooter→app) | Source |
|---|---|---|---|---|
| Ninebot custom (modern) | `6e400001-0000-0000-006e-696e65626f74` | `…0002` (also `…0003` = secondary write) | **`…0004`** (not 0003) | [https://nootnooot.codeberg.page/segway-ninebot-ble/transport/](https://nootnooot.codeberg.page/segway-ninebot-ble/transport/) |
| Nordic UART (older devices) | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | `6e400002-…` | `6e400003-…` | same page |
| HMSoft (very old) | `0000ffe0-…` | — | `0000ffe1-…` | same page |

Other transport facts from the same page:
- Default MTU payload is 20 bytes. The app must split frames longer than MTU−3 into chunks, about 10 ms apart.
- Frames are reassembled by scanning for `5A A5` plus the length byte.
- iOS caches the CCCD for bonded devices. Workaround: toggle notifications off, wait 300 ms, then turn them back on before the handshake.

## Frame generations (Ninebot lineage)
Source: [https://nootnooot.codeberg.page/segway-ninebot-ble/protocol/](https://nootnooot.codeberg.page/segway-ninebot-ble/protocol/)
| Gen | Header | Crypto | Notes |
|---|---|---|---|
| Protocol 1 | `55 AA` | optional XOR | `55 AA len target cmd index payload crcLo crcHi`. This is the original M365 frame. CamiAlfa documented it for M365 firmware 1.3.4 ([repo](https://github.com/CamiAlfa/M365-BLE-PROTOCOL), LGPL) |
| Protocol 2 | `5A A5` | optional XOR | Adds a BT_ID byte, always `0x3E` |
| Encryption2 | `5A A5` | AES-128, CTR-like mode, plus a CBC-MAC | Current production. Uses a 3-phase handshake: PRE_COMM `0x5B` → SET_PWD `0x5C` (the user presses the power button) → AUTH `0x5D`. Key = SHA-1(key1‖key2)[0:16] ([auth page](https://nootnooot.codeberg.page/segway-ninebot-ble/authentication/)) |
| Encryption3 | `5A A5` | AES-128 (V3Auth) | Newest. Details are thinner in the doc |

The "first crypto" pairing (5B/5C/5D) is also described in [NinebotCrypto's README](https://github.com/scooterhacking/NinebotCrypto) (AGPL; we use it as **facts only**). The serial number sits at offset 16, 14 bytes long, in the 0x5B reply. Wait for `21 3E 5C 01` (button pressed) before sending 0x5D.

## Ninebot / Segway models
HW ID and protocol come from the device table at [https://nootnooot.codeberg.page/segway-ninebot-ble/devices/](https://nootnooot.codeberg.page/segway-ninebot-ble/devices/) (taken from the official app's config files). "Crypto BLE versions" come from the NinebotCrypto README.

| Model | HW ID | Protocol (config) | Crypto BLE versions | Other evidence |
|---|---|---|---|---|
| KickScooter **ES** series (ES1–ES4) | 33 | Proto2 | ESx: BLE109, BLE110 | The wiki marks ESx/SNSC1.x as well documented ([nbesx](https://github.com/scooterhacking/wiki/blob/main/pages/nbesx.txt)) |
| KickScooter **Max (G30 family)** | 36 | Proto2 | Max: BLE110, BLE113, BLE114 | "Supported by many apps and developers" ([nbmax](https://github.com/scooterhacking/wiki/blob/main/pages/nbmax.txt)). Speed 20/25/30 km/h by region (same page) |
| **Max G2** | 131 | **Enc2** | — | "Not fully supported by any hacking tool as of 28/06/2023" ([nbmax](https://github.com/scooterhacking/wiki/blob/main/pages/nbmax.txt)) |
| E-series (E22/E25/E45) | 39 | Proto2 | E: BLE209, BLE213 | [nbeseries](https://github.com/scooterhacking/wiki/blob/main/pages/nbeseries.txt) |
| **F-series** (F, F2/F2 Plus/Pro) | 44 / 123; F2 127–129 | Proto2 | F: BLE307 | [nbfseries](https://github.com/scooterhacking/wiki/blob/main/pages/nbfseries.txt) |
| **D-series** (D18/D28/D38) | 116/114/115 | **Enc2** | — | [nbdseries](https://github.com/scooterhacking/wiki/blob/main/pages/nbdseries.txt) |
| **P-series** (P65, P100S) | 118, 119 | **Enc2** | — | — |
| GT1/GT2, G65, F65, MAX G3, F3, GT3, ZT3 Pro | various | **Enc2** | — | Newer generation |

Caveats:
- **Two sources disagree.** The devices page says *every* command needs the 3-phase auth. NinebotCrypto says some BLE versions still answer legacy unencrypted frames. Our reading (UNVERIFIED): this depends on the BLE firmware version, so the adapter must probe read-only and fall back.
- ScooterHacking says it "DOES NOT publicly support the SNSC2.2–2.4, C1 and S90L scooters to decrease theft rate" ([nbmax](https://github.com/scooterhacking/wiki/blob/main/pages/nbmax.txt)). Those are rental units, so don't add them.
- Speed: on the documented E125S (a moped), effective top speed = min(read-only rated cap, user speed lock) ([speed page](https://nootnooot.codeberg.page/segway-ninebot-ble/speed-configuration/)). Raising the lock doesn't beat the rated cap. Whether kick scooters behave the same way is UNVERIFIED.

## Xiaomi models
Specs come from the [wiki mi365 table](https://github.com/scooterhacking/wiki/blob/main/pages/mi365.txt).

| Model | Made by | Max speed | Protocol / auth (evidence) |
|---|---|---|---|
| M365 (and M187) | Ninebot | 25 km/h | Legacy `55 AA` (CamiAlfa, firmware 1.3.4). Newer BLE firmware moved to Xiaomi's encrypted login (`55 AB`). The miauth acknowledgments list "M365 – 55ab" ([miauth](https://github.com/dnandha/miauth)) |
| M365 Pro | Ninebot | 25 km/h | Ninebot crypto on BLE110, BLE122 (NinebotCrypto) |
| Pro 2 / 1S / Lite (Essential) | Ninebot | 25 (Essential 20) | BLE129, BLE132 with Ninebot crypto. "On some devices only 5AAB is enabled" on BLE132, so stay on 129 (NinebotCrypto) |
| Mi 3 | Ninebot | 25 km/h (Mi 3 Lite 20/25 by region) | UNVERIFIED which auth. The wiki lists stock Mi 3 firmware, so tools handled it at some point |
| Mi 4 / 4 Pro / 4 Ultra / 4 Lite / 4 Go | Ninebot or Brightway (Navee) | 20–25 | "Some newer models from the Mi 4 series, as well as all of the models manufactured by Navee/Brightway are not supported by any flashing app" ([mi365](https://github.com/scooterhacking/wiki/blob/main/pages/mi365.txt)) |

Xiaomi's encrypted login (from [miauth doc](https://github.com/dnandha/miauth/tree/main/doc)): an ECDH SECP256R1 key exchange → HKDF → a saved token. Each login then derives keys and IVs with HKDF. UART messages are AES-CCM with a counter nonce. The license is AGPL/Apache and conflicting (see the inventory), so this is a **clean-room implementation from the spec only**.

Region: Xiaomi and Ninebot ship regional speed caps (for example "20/25 km/h (region)" in the wiki table). NIU firmware is published separately for DE, EU and US ([niu_scooters README](https://github.com/scooterhacking/niu_scooters)). The adapter must read the region, never assume it.

## Pick: adapt the Ninebot KickScooter Max G30 first
Why:
1. It has the best **legally reusable** documentation: an Apache-2.0 doc with transport, frames, handshake and a 68-command table for "Ninebot KickScooter Max" ([devices](https://nootnooot.codeberg.page/segway-ninebot-ble/devices/)).
2. NinebotCrypto independently lists the BLE versions it was tested on (110/113/114).
3. The wiki calls the Max widely supported. It's common and cheap used, so borrowing one is realistic.
4. Unlike the G2, D or P series, its config protocol is Proto2. That means read-only telemetry (speed, battery, odometer, firmware version) is likely reachable after the handshake. Telemetry fields are UNVERIFIED until tested.

Runner-up: an original **M365 on old BLE firmware**. Its `55 AA` protocol is the simplest, but the auth on any given unit depends on its BLE firmware, and we can't control that.

**Blocker:** we have no G30. It stays **Experimental (read-only)** until Credence or a friend can test on one. Writes stay off until the response to each command has been checked on that exact BLE/DRV firmware.
