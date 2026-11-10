# Release checklist: from 5.0 beta to a public release

Nothing on this list is switched on yet. 5.0.0 is published as the **v5-beta prerelease**; `main` and the `latest` release are still v3. Billing is Stripe **TEST mode** only. Each step says who has to do it.

Not legal advice. Re-check every requirement on Apple's and Stripe's own pages when you do it.

## A. Make v5 the main download on GitHub (Credence can do this, when he says go)

Do this only after 5.0 has been tested on a real iPhone and the J078 (connect, speed, modes, light, park, speed limits) and, if possible, the Volpam.

1. Open PR #2 (`v4-dev` -> `main`): https://github.com/VisualActions/HackTheScoot/pull/2
2. Check the PR's checks are green (secret scan, license scan, unit tests, screen tests, IPA build).
3. Click **Merge pull request** (a normal merge commit is fine). Don't delete `v4-dev` yet.
4. The push to `main` runs the same workflow. When it's green, it **replaces the `latest` release** with the 5.0 IPA (`HackTheScoot-unsigned.ipa`), and v3 stops being the stable download.
   - Want to keep v3 downloadable? Before merging, open Releases > `latest` and download its `.ipa`, or re-tag it: Releases > Draft a new release > tag `v3.0.0` on commit `b9b954d`, attach the old IPA.
5. Update the download page (https://j078-app.sites.tab.bot/) so the big button points at `latest`, and move v3 to an "older versions" line.
6. After the merge, GitHub shows the **New vehicle capture** issue form (it reads issue templates from `main` only). Until then the app's and the page's issue links open a plain issue with the same questions filled in.
7. Optional: delete the old `v4-beta` prerelease (4.2) once nobody needs it.

Rolling back: revert the merge commit on `main` (GitHub: the merged PR > Revert). The workflow republishes `latest` from the reverted code.

## B. App Store (needs an adult)

Credence is under 18, so these need a parent or guardian (sources in `docs/legal/age-and-legal-checklist.md` on the research-docs branch).

- [ ] **Apple Developer Program**: the parent enrolls with their own Apple Account (99 USD per year per Apple's enroll page) and adds Credence to the team. The seller name on the App Store is the parent's (or an LLC's).
- [ ] **Paid Apps Agreement, tax forms and bank account** in App Store Connect: the parent (account holder).
- [ ] **Bundle id**: create the App ID in the developer account, e.g. `com.hackthescoot.app` (see "Bundle id" below).
- [ ] **In-App Purchase**: Pro sold inside the iPhone app must use Apple's In-App Purchase (App Store Review Guideline 3.1.1). Create the two auto-renewable subscriptions in one group, matching `Support/HackTheScoot.storekit`: `com.hackthescoot.pro.monthly` ($3.99) and `com.hackthescoot.pro.yearly` ($29.99), with the intro trial if wanted. The Stripe web checkout can't be linked from inside the app except where Apple allows it (check the current rules for your storefront before showing any web purchase link in the app).
- [ ] Remove the **test unlock** and the Stripe **test return link** from the App Store build (`Billing.testMode = false`, hide Developer settings' test unlock). Keep them only in sideloaded betas.
- [ ] **Paywall**: restore button, clear price / trial / renewal terms, and links to the privacy policy and terms (Guideline 3.1.2). The current paywall has restore and cancellation info already.
- [ ] **App Privacy "nutrition label"** in App Store Connect. Today's build collects nothing off the phone, so it should be "Data Not Collected". Re-check if accounts, sync or crash reporting are ever added. `J078/PrivacyInfo.xcprivacy` (the privacy manifest) is already in the app: no tracking, no collected data, UserDefaults (reason CA92.1) and file timestamps (C617.1).
- [ ] **Privacy policy URL** (required): publish the privacy policy (the in-app DRAFT, after an adult and a legal review) at a public URL, e.g. a page on the download site.
- [ ] **Support URL** (required): a page with a contact email and how to send a capture (CAPTURES.md works as a start).
- [ ] **Age rating** questionnaire in App Store Connect. **Age / parent steps**: the publisher is the adult; the terms say minors need a parent's consent. No accounts means no child-data collection today.
- [ ] **Signing**: archive with the team's certificate in Xcode, or add an App Store Connect API key + certificate as GitHub secrets for a CI TestFlight build (not set up).
- [ ] **TestFlight** with 5 to 10 riders first.
- [ ] **Review notes**: explain Bluetooth use, that the app never flashes firmware, and that above-stock speed settings sit behind a warning and are only sent to vehicles with verified commands. Apple may ask about the speed sliders; local laws differ, so decide with the adult whether the App Store build keeps them.
- [ ] **Widgets / Live Activity**: need an App Group, which needs the paid developer account. Possible after enrollment (see README "Not done yet").

## C. Stripe live mode (needs an adult)

- [ ] Add the parent as the Stripe account **Representative** before switching on live mode (Stripe Services Agreement: users under 18 need an adult Representative who is responsible for the account).
- [ ] Bank account for payouts in the parent's name, or one the parent controls.
- [ ] A small server (Supabase or similar) for real entitlements: Checkout session -> verified webhook (signature check, idempotent) -> entitlement the app can check. Until then a web payment can't securely unlock the app; the 5.0 return link is TEST only and unverified.
- [ ] Customer Portal for cancel / manage, and a refund policy in the terms.
- [ ] Decide whether to keep Stripe's "Managed Payments" (Stripe as seller of record); it was turned off for the test links only.
- [ ] Never put the live secret key in the app or the repo. CI's secret scan fails the build if a key-shaped string is committed.

## D. Legal (needs an adult + a review)

- [ ] Privacy policy and terms: the in-app texts are DRAFTS from the research outlines. The publisher's name, contact email, liability wording and governing law are still blank.
- [ ] Open-source credits are in the app (More > Open-source credits). Keep them up to date if code is ever reused; no GPL/AGPL code (CI's license scan checks).
- [ ] Taxes: income is reportable. Talk to whoever does the family's taxes.

## Bundle id

5.0 keeps `com.example.j078app` (and the product name `J078`) on purpose. iOS identifies an app by its bundle id: a new one would install as a **separate app** next to the old one, with none of its settings, Garage or trips, and sideloading tools would treat it as new too.

When the App Store build is made:

1. In 5.x, the rider makes a backup: More > Backup and restore > Make a backup file (settings, Garage, maintenance, themes, trips).
2. Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to the registered id (e.g. `com.hackthescoot.app`). Optionally `PRODUCT_NAME: HackTheScoot` too: then also change `@testable import J078` in the tests, `TEST_HOST` in `project.yml`, and the `.app` path in the workflow.
3. Install the new app, then More > Backup and restore > Restore. The Volpam password lives in the Keychain and isn't in backups: re-enter it once.

## E. Before every release

- [ ] CI green on the exact commit: secret scan, license scan, unit tests, screen tests, IPA build.
- [ ] Version bumped in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) and `WhatsNew.version`.
- [ ] CHANGELOG.md updated, including known limitations.
- [ ] Tested on a real iPhone and the J078 (and anything else claimed).
- [ ] Nothing removed or capped compared to the last release.
