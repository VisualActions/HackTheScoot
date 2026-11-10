# Compliance checklist (before real payments or public launch)

**Apple**
- [ ] App Privacy "nutrition label" filled in App Store Connect ([Apple: App privacy details](https://developer.apple.com/app-store/app-privacy-details/)).
  - Local-only v1 likely declares "Data Not Collected". Re-check once accounts, sync or crash reporting exist.
  - Likely categories then: Contact Info (email), Identifiers (user ID), Purchases, Diagnostics (if crash reporting), Location (only if GPS routes sync, which isn't planned).
- [ ] Purpose strings: `NSBluetoothAlwaysUsageDescription`, location when-in-use (only if GPS trips), plus the privacy manifest `PrivacyInfo.xcprivacy` with required-reason APIs (e.g. UserDefaults).
- [ ] IAP rules (3.1.1/3.1.2): Restore button, clear trial and renewal terms, links to the EULA and privacy policy on the paywall.
- [ ] Account deletion in-app if accounts exist (5.1.1(v)).
- [ ] Storefront check before showing any Stripe link (US only).

**GDPR basics** (if EU users)
- [ ] Privacy policy (outline here), legal bases, Data Processing Agreements with processors (Stripe, Supabase), a records-of-processing note, a breach plan, and export and delete on request.
- [ ] Consent for optional data (sync, crash reports, submissions), off by default.

**CCPA/CPRA basics** (California)
- [ ] Notice at collection, "we do not sell or share", and a way to request delete, know or correct.
- [ ] (CCPA thresholds likely aren't met at launch, but following them is cheap.)

**Security**
- [ ] No secrets in the app or repo. CI runs secret scanning (e.g. gitleaks) and dependency scanning.
- [ ] Webhooks verify signatures, and an idempotency table is in place. Stripe stays in test mode until audited.
- [ ] Keychain for any user-entered scooter password. Never hardcode or log passwords.

**Licenses**
- [ ] License check in CI (no GPL/AGPL code in the app target).
- [ ] Attribution page shipped in-app (Settings › Acknowledgements).
