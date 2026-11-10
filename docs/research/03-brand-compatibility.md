# Brand-by-brand compatibility

Levels: **Full**, **Partial**, **Diagnostics Only**, **Experimental**, **Unsupported**.
- Nothing is **Full** without hardware testing.
- Only the J078 has features verified from real captures of the official app. Those features: speed, mode, light, park, and the speed-limit readout.
- Evidence levels:
  - **A**: our own BLE captures
  - **B**: a public reverse-engineering writeup or open-source code for that model
  - **C**: an official app exists, but no public protocol
  - **D**: no evidence found

All sources are accessed 2026-11-09. "Snippet" = search-result text only, page not read.

## Summary table

| Brand | Public BLE protocol? | Open-source apps/tools | Evidence | Level now |
|---|---|---|---|---|
| **Joyhis** (J078) | Our own decode (j078-map.md): `365_scooter` name, service `6e400001-0000-1000-8000-00805f9b34fb`, write `…0002`, notify `…0003`, byte-scrambled `BD BE`/`DB EB` frames | HackTheScoot | **A** | **Partial** (speed, mode, light, park, speed-limit readout + sport limit write/ack verified from captures) |
| **VOLPAM** (dad's) | Our own decode: F1F1 write, ASCII `AT+PWD[…]` login, `AC 00 0A` feature frame + CRC16-Modbus (task 9ebab375 reproduced all 25 captured frames, 2026-11-09), Modbus `01 10 00 20` speed write | — | **A** | **Partial (capture-only).** Speed write clamped to 35 km/h in the capture. Flag bits are UNVERIFIED. Nothing sent from HackTheScoot yet |
| **AOVOPRO** | No official doc. The AOVO Pro uses the **365GO** app ([YouTube](https://www.youtube.com/watch?v=saTmSNsYoxg), snippet; the official AovoPro app is `com.zydtech.aovopro`). The [faovo-app](https://github.com/AlexIII/faovo-app) README (no license) decoded "fake AOVO Pro M1" clones from the LENZOD app | faovo-app (web, unlicensed) | **B** (clones only) | **Experimental** |
| ⭐ **Hiboy** (S2 Pro) | **Yes**, public writeup: [Lee Holmes, 2024-08-10](https://www.leeholmes.com/reverse-engineering-hiboy-btle-protocol/) (page read): service `0xF1F0`, char `0xF1F1`, `AT+PWD[…]` login, `AB 00 0A …` frame, **CRC16/MODBUS little-endian**; the firmware ignored speeds above ~30 km/h | none found | **B** | **Experimental** |
| **NAVIC** | None found. The maker's product page title says "…e-scooter for adults with app" ([navicscooter.com](https://www.navicscooter.com/product/navic-electric-scooter-350w-500w-motor-19-22-mph-max-22-27-49-miiles-range-foldable-e-scooter-for-adults-with-app/), URL/snippet). Which app is UNVERIFIED | none | **D** | **Unsupported** |
| **MAXSHOT** | None found. A third-party guide says the app name is in the manual ([page read](https://maxshotscooter.com/bluetooth-app-pairing)) | none | **D** | **Unsupported** |
| **KuKirin / Kugoo** | None official. The maker says "KuKirin currently has no official app. Please do not download or use unauthorized…" ([kugooescooters.com](https://www.kugooescooters.com/), snippet; the page returned 403 to us) and posted an official statement against "Manager for KuKirin" ([Facebook](https://www.facebook.com/61573046081409/posts/english-official-statement-thirdparty-app-manager-for-kukirinwe-have-noticed-som/122188155860768202/), snippet) | [maksdoner/Kukirin-G4-Bluetooth-Control](https://github.com/maksdoner/Kukirin-G4-Bluetooth-Control) (MIT, **read-only**, FFF2 notify, ECO/SPORT/RACE on one G4); closed "Scooter Manager for KuKirin" (BLDev, ads + IAP, [Play](https://play.google.com/store/apps/details?id=com.unofficial.kukirinmanager)) | **B** (G4 read-only, one unit) | **Experimental, read-only.** G2/G2 Master/G2 Pro/G2 Max/G3/G3 Pro: **no evidence found** |
| **Dualtron** (Minimotors) | **No public protocol found.** Official app "Minimotors Dualtron" ([App Store id1630063549](https://apps.apple.com/ru/app/minimotors-dualtron/id1630063549), [Play com.minimotors.escooter](https://play.google.com/store/apps/details?id=com.minimotors.escooter), snippets). [EyeX](https://eyex.app/en) (page read): free, closed source, "52 models… EY3 Connect, EY4, EYA and connected Minimotors displays", security "built in collaboration with Minimotors" | none found on GitHub | **C** | **Unsupported** |
| **Rovoron** | Same as Dualtron. EyeX lists Rovoron 9, S7, R7, R5, Kullter Luxury, Kullter Ten+, Ten, Leger, Cute | none | **C** | **Unsupported** |
| **Kaabo** | None found. Official "Kaabo" app ([App Store id6739793819](https://apps.apple.com/au/app/kaabo/id6739793819); [kaabousa.com](https://www.kaabousa.com/pages/app-download)) | none | **C** | **Unsupported** |
| **Apollo** | None found. Official "Apollo Scooters" app; its listing mentions "advanced controller settings" ([Play com.apolloscooters](https://play.google.com/store/apps/details?id=com.apolloscooters), snippet; [App Store id1572345798](https://apps.apple.com/us/app/apollo-scooters/id1572345798)) | none | **C** | **Unsupported** |
| **NIU** (KQi) | None found for BLE. Official NIU app, "only available for selected models" ([global.niu.com](https://global.niu.com/en-us/smartapp), snippet). ScooterHacking hosts KQi2/KQi3 firmware by region (unlicensed) | [belveder79/NIUScooterHacking](https://github.com/belveder79/NIUScooterHacking) (BSD-3, a **wired** ESP32 BMS emulator, not BLE) | **C** | **Unsupported** |
| **VSETT** | None found. Owners ask whether any app exists ([Reddit](https://www.reddit.com/r/ElectricScooters/comments/ygofjm/is_there_an_app_that_i_can_connect_my_vsett_9_to/), snippet) and use NFC cards to unlock ([Reddit](https://www.reddit.com/r/ElectricScooters/comments/11cha57/vsett_10_owners/), snippet). A dealer, Falcon PEV, sells an aftermarket "app-based VSETT immobilizer and speed limiter" ([Facebook video](https://www.facebook.com/FalconPEV/videos/throw-away-that-remote-now-with-our-app-based-vsett-immobilizer-and-speed-limite/246682207673679/), snippet) | none | **D** | **Unsupported** (no stock BLE app found) |
| **Inokim** | None. "The Inokim OXO does not have companion app" ([scooterrank](https://scooterrank.com/scooters/inokim-oxo/companion-app), snippet) | none | **D** | **Unsupported** |
| **ZERO** | No protocol. The ZERO 10X Limited uses a USB Bluetooth module on YYK/ZERO controllers plus the **MQCON** app ([zeroelectricscooter.com module](https://zeroelectricscooter.com/products/limited-bluetooth-module), page read; [YouTube](https://www.youtube.com/watch?v=VO026Mq_I64), snippet) | none | **C** | **Unsupported** |
| **Gotrax** | None found. Official "GOTRAX" app ([App Store id6451111378](https://apps.apple.com/us/app/gotrax/id6451111378)). A review says Bluetooth is "effectively non-functional for most" models ([levyelectric](https://www.levyelectric.com/resources/connecting-bluetooth-to-your-gotrax-electric-scooter-a-step-by-step-guide), snippet) | none | **C** | **Unsupported** |
| **TurboAnt** | None found. Owners report the X7 Pro pairing with the **"HX E-Scooter"** app ([Facebook](https://www.facebook.com/groups/237469038529740/posts/1104119631864672/), snippet), and other owners say TurboAnt has no app ([Reddit](https://www.reddit.com/r/ElectricScooters/comments/1c7m63e/first_scooter_ride_turboant_simply_awesome/), snippet) | none | **D** (conflicting) | **Unsupported** |
| **Razor** | None found. "Razor E Rides" app by Shenzhen inet Mobile Internet Technology, rated 2.2★ ([App Store id1626022708](https://apps.apple.com/us/app/razor-e-rides/id1626022708), page read) | none | **C** | **Unsupported** |
| Ninebot/Segway, Xiaomi | Yes, see [02-protocols](02-protocols-ninebot-xiaomi.md) | several (licenses in [01-inventory](01-scooterhacking-inventory.md)) | **B** | **Experimental** (no hardware yet) |

## ⭐ The "365 / F1F1" (zydtech) family: Joyhis, Volpam, Hiboy, AOVOPRO, 365GO
**Status: UNVERIFIED until we capture a real Hiboy (and an AOVO Pro).** Key source: [Lee Holmes, "Reverse Engineering the Hiboy Scooter BTLE Protocol", 2024-08-10](https://www.leeholmes.com/reverse-engineering-hiboy-btle-protocol/).

This is the most promising lead for multi-brand support. The pattern is strong, but each item below is still separate evidence:
- **Same app publisher.** The 365GO (`com.zydtech.pro365`) and AovoPro (`com.zydtech.aovopro`) apps are both published by "Shenzhen high-end manufacturing Co.,Ltd". The Hiboy S2 app's package is also `com.zydtech.hiboys2` (published by Freeman Intelligent Power INC) (Google Play, pages read). A shared package prefix suggests a shared codebase (UNVERIFIED).
- **Same protocol shape.** Hiboy (public writeup) and our Volpam capture both use the F1F1 write characteristic, an `AT+PWD[6 digits]` ASCII login, a 10-byte `A? 00 0A [flags] … [crc]` settings frame, and CRC16/MODBUS little-endian. The header byte differs: Hiboy uses `AB`, Volpam uses `AC`. Both firmwares **clamp speeds above stock**.
- **Partial overlap with the J078.** The "365" app that drives the J078 has two write paths in its code: F1F1 (the Volpam-style one) and 6E400002 (j078-map.md). The J078 capture showed **no** F1F1 traffic, only scrambled `BD BE` frames on the NUS-style service. So one app family speaks at least two protocols. An adapter has to pick a protocol from the GATT services it discovers, not from the app name.

Recommendation: build a `Zydtech365` adapter family with **per-model profiles**. Identify read-only first (service UUIDs + notify frame shape), then let each model unlock writes separately. A Hiboy profile can be added once someone captures a Hiboy.

## What "no evidence found" means
We searched the web and GitHub on 2026-11-09 and found nothing public. It doesn't mean impossible. For those brands, the path forward is the Compatibility Submission flow: the owner captures traffic from the official app, and we decode it the way we decoded the J078.

**Never** take commands from a closed app like EyeX or Manager for KuKirin by decompiling it. Our own captures of the **manufacturer's** app on hardware we own are the clean path.
