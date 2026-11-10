# Open-source attribution plan

**Policy**
- No GPL, AGPL or LGPL code goes in the iOS app target. Those licenses conflict with closed App Store distribution: [FSF, 2010](https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement). LGPL static linking on iOS is impractical.
- Unlicensed repos are all-rights-reserved, so we don't use them.
- **Facts** like UUIDs, frame layouts and model specs aren't copyrightable. We reimplement from them and **credit** the source anyway.

**In-app "Acknowledgements" page + `docs/legal/NOTICE.md`.** Credit these as sources of protocol knowledge (no code copied):
- ScooterHacking community: wiki (CC BY-SA 4.0), NinebotCrypto README (AGPL-3.0, spec facts only). https://github.com/scooterhacking
- NootNooot, "Segway-Ninebot BLE Protocol" (Apache-2.0). https://nootnooot.codeberg.page/segway-ninebot-ble/. If we ever copy text or code, include its LICENSE and NOTICE.
- dnandha/miauth (Xiaomi auth docs). https://github.com/dnandha/miauth
- CamiAlfa, M365-BLE-PROTOCOL (LGPL per README; facts only). https://github.com/CamiAlfa/M365-BLE-PROTOCOL
- Lee Holmes, Hiboy BTLE writeup (2024-08-10). https://www.leeholmes.com/reverse-engineering-hiboy-btle-protocol/
- maksdoner/Kukirin-G4-Bluetooth-Control (MIT). https://github.com/maksdoner/Kukirin-G4-Bluetooth-Control

**If code is ever copied** (MIT/Apache/BSD only):
- Keep the file headers.
- Add the license text to `ThirdParty/LICENSES/`.
- List it in the in-app page.
- Record it in `docs/legal/third-party.json` (name, version, license, URL, files).

**CI:** a license-scan step fails the build on GPL/AGPL/LGPL/unknown licenses in Swift packages.

**Our own license** (Credence's call): the spec says "open-source", which conflicts with closed App Store sales only if we pick the GPL. Options:
- **MIT/Apache-2.0** app code + a **paid** App Store build (allowed, like many OSS apps);
- or keep it source-available but proprietary.

Decide before accepting outside PRs, and add a CLA or DCO.
