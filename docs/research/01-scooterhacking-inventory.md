# ScooterHacking repo inventory

Research only. Nothing was forked or copied. Every repo below was read through the GitHub API on 2026-11-09 (repo list, license endpoint, LICENSE file, file tree). Source for the list: https://api.github.com/orgs/scooterhacking/repos (accessed 2026-11-09).

**Short version**
- Safe to depend on directly: **NinebotTEA** (MIT) and **fw-zip-package-v3** (MIT). But neither does BLE comms. They deal with firmware packaging and encryption, which v4 won't ship.
- Learn from, then clean-room: **NinebotCrypto** (AGPL-3.0) and the **wiki** (CC BY-SA 4.0).
- Never redistribute: **firmware**, **niu_scooters** and the `.bin` files in **ninebot-esx-patcher**. These are manufacturer firmware with no license.
- No license, so not reusable (all rights reserved by default): Ninebot_IAP_V1, ninebot-esx-patcher, mijia_ble_libs, niu_scooters, firmware, scooterhacking-issues-public.

## Table

| Repo | License (exact) | Contents | Reuse risk for a closed-source App Store app | Recommendation |
|---|---|---|---|---|
| [NinebotCrypto](https://github.com/scooterhacking/NinebotCrypto) | **AGPL-3.0**. LICENSE is the full GNU AGPL v3 text, and GitHub detects AGPL-3.0 | Source: the same crypto in C, C++, C#, Kotlin, Rust and **Swift** (11 files). It does the 0x5B/0x5C/0x5D pairing for the legacy 5A A5 protocol | **High.** AGPL code inside a closed app forces the whole app's source out under the AGPL. Apple's App Store terms are widely seen as incompatible with GPL-family licenses (see note 1) | **Clean-room only.** Use the README's description of the handshake (BLE versions, steps) as facts. Don't copy or port the code |
| [wiki](https://github.com/scooterhacking/wiki) | **CC BY-SA 4.0** (LICENSE file) | Docs: 56 DokuWiki pages (`pages/*.txt`). Model tables, error codes, serial anatomy, update logs | **Medium.** Facts (UUIDs, speeds, model lists) aren't copyrightable. Copying text or tables means attributing it **and** releasing that derived text under CC BY-SA | Learn from it and cite it. Don't paste tables into the app. If we quote text, keep it in a separately licensed docs folder with attribution |
| [NinebotTEA](https://github.com/scooterhacking/NinebotTEA) | **MIT**, "Copyright (c) 2024 ScooterHacking" | Source: a Python library and CLI for Ninebot **firmware** encryption and decryption | Low license risk. Product risk: firmware tooling is out of scope (no flashing) | Allowed with attribution, but **not needed**. Don't integrate it, since firmware work is disabled |
| [fw-zip-package-v3](https://github.com/scooterhacking/fw-zip-package-v3) | **MIT**. Note: the copyright line still says "[year] [fullname]" (template not filled in) | Source: Java and Python examples for making and reading ScooterHacking firmware zip packages | Low license risk. Same scope issue | Not needed. If ever used, keep the MIT notice and note the unfilled copyright line |
| [Ninebot_IAP_V1](https://github.com/scooterhacking/Ninebot_IAP_V1) | **None** (no LICENSE file; GitHub license = null). Archived | Source **plus compiled binaries**: C# Windows flasher (24 `.cs`, 4 `IAP.exe`, `.pdb`) | **Not reusable.** No license = all rights reserved. Also a firmware flasher | Don't use. Firmware flashing is disabled in our plan |
| [firmware](https://github.com/scooterhacking/firmware) | **None** | **Firmware binaries:** 406 files (146 `.zip`, 145 `.bin`, 115 `.enc`) for m365, 1s, lite, mi3, max, g2, esx, e, f, f2, d18/d28, and more (BLE/BMS/DRV folders) | **Never redistribute.** Manufacturer firmware with no license | Never bundle, mirror or download it into the app. We didn't download any of it |
| [ninebot-esx-patcher](https://github.com/scooterhacking/ninebot-esx-patcher) | **None** | Python, PHP and HTML patcher plus **5 DRV firmware `.bin` files** | Not reusable. Contains firmware. Patching firmware is out of scope | Don't use |
| [mijia_ble_libs](https://github.com/scooterhacking/mijia_ble_libs) | **None** at the repo level. It's an "Archive of MiEcosystem/mijia_ble_libs"; a bundled `third_party/micro-ecc` has its own LICENSE.txt | Source (C) plus prebuilt `.lib`/`.a`: Xiaomi's device-side BLE SDK (standard_auth, gatt_dfu) | Not reusable. Third-party Xiaomi SDK mirror with unclear rights | Background reading at most |
| [niu_scooters](https://github.com/scooterhacking/niu_scooters) | **None** | **Firmware:** 12 `.bin` and 12 `update.json` for NIU KQi2 Pro and KQi3 Sport/Pro/Max (DE/EU/US) | **Never redistribute** | Reading the README alone tells us NIU KQi has region-specific firmware. That's a fact, not code |
| [scooterhacking-issues-public](https://github.com/scooterhacking/scooterhacking-issues-public) | **None** | Issue templates only | Nothing to reuse | Use it to report bugs to ScooterHacking tools, not as code |
| [giveaways](https://github.com/scooterhacking/giveaways) | n/a | Empty (the API's tree endpoint returns 404) | n/a | n/a |

Note 1 (not legal advice): the FSF's position is that App Store distribution terms conflict with GPL/AGPL. See https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement (accessed 2026-11-09; not fetched in this session, widely cited). Treat AGPL/GPL as **incompatible** unless a lawyer says otherwise.

## Related (non-ScooterHacking) sources checked

| Project | License | Why it matters |
|---|---|---|
| [NootNooot/segway-ninebot-ble](https://nootnooot.codeberg.page/segway-ninebot-ble/) (Codeberg) | **Apache-2.0** (stated on its About page, accessed 2026-11-09) | The best current Ninebot/Segway protocol doc: transport, frames, AES handshake, and command tables for 66 devices. Apache-2.0 **is** compatible with a closed app (keep the NOTICE and attribution). Our best legal source for a Ninebot adapter |
| [dnandha/miauth](https://github.com/dnandha/miauth) | **Conflicting:** the LICENSE file on `main` is AGPL-3.0, but the README says "The Apache2 license applies to the code in this branch" | Documents Xiaomi's newer ECDH + AES-CCM login. Until the author clears up the license, **treat it as AGPL**: docs only, clean-room |
| [CamiAlfa/M365-BLE-PROTOCOL](https://github.com/CamiAlfa/M365-BLE-PROTOCOL) | README says **LGPL 2.1+** (GitHub shows no license) | M365 55 AA register map (firmware 1.3.4) |
| [etransport/py9b](https://github.com/etransport/py9b) | **GPL-3.0** | Ninebot/Xiaomi library. Learn only |
| [salvamr/m365-ble-msg-builder](https://github.com/salvamr/m365-ble-msg-builder) | LGPL-3.0 | M365 message builder. Learn only |
| [macbury/m365](https://github.com/macbury/m365) | AGPL-3.0 | Rust M365 library. Learn only |
| [ownbee/ninebot-ble](https://github.com/ownbee/ninebot-ble) | **MIT** | Ninebot BLE client. Reusable with attribution (still check which crypto it uses) |
| [maksdoner/Kukirin-G4-Bluetooth-Control](https://github.com/maksdoner/Kukirin-G4-Bluetooth-Control) | MIT | Read-only KuKirin G4 mode monitor (FFF2 notify) |
| [AlexIII/faovo-app](https://github.com/AlexIII/faovo-app) | **None** | Web app for "fake AOVO Pro M1" clones. Learn only |

## Fork decision (later)
Forking a repo doesn't add any rights. Forking only makes sense for MIT/Apache repos we'd actually build on, and right now that's none: our app doesn't need firmware tooling. Recommendation: **don't fork anything for v4.** Write our own adapters from the documented facts, and credit the sources in `docs/legal/open-source-attribution.md`.
