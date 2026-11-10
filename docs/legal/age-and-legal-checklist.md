# Age and legal requirements (Credence is under 18)

Sources were read accessed 2026-11-09. Not legal advice.

## What the terms actually say
| Account | Requirement | Source |
|---|---|---|
| **Apple Developer Program** | "To enroll, you'll need an Apple Account with two-factor authentication turned on and be the **legal age of majority** in your region." | [developer.apple.com/support/enrollment](https://developer.apple.com/support/enrollment/) (page read) |
| | "If you're under the age of majority in your region, your **parent/guardian can enroll with their Apple Account and share their account with you**." | [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/) (page read) |
| **Stripe** | "Only people 13 years of age or older may open a Stripe Account… If User or User's Representative is not 18 years of age or older (or the age of majority where User resides): (i) User must add a Representative who is an adult (which may be a parent or legal guardian)…; (ii) both User and Representative agree to be bound…; and (iii) Representative agrees to be **responsible and liable** for User's actions" | [Stripe Services Agreement](https://stripe.com/legal/ssa), last modified Sep 28, 2026 (page read) |
| **App Store paid apps / IAP** | Selling requires the **Paid Apps Agreement**, tax forms and bank info in App Store Connect, all under the enrolled (adult) account holder | App Store Connect agreements (UNVERIFIED wording; check at setup) |

## What needs an adult (parent/guardian) checklist
- [ ] **Apple Developer Program**: the parent enrolls (99 USD per membership year, per Apple's enroll page) and adds Credence to the team. The "seller" name on the App Store will be the parent's (or an LLC's).
- [ ] **Paid Apps Agreement, tax (W-9) and bank account** in App Store Connect: parent.
- [ ] **Small Business Program** enrollment: parent (account holder).
- [ ] **Stripe**: add the parent as the account Representative before switching on **live** mode. Credence's existing account works for **test mode** only until then.
- [ ] **Bank account for payouts**: in the parent's name, or a custodial/joint account the parent controls.
- [ ] **Signing the Terms of Service and Privacy Policy** as the business: parent (or an LLC with an adult member). Optional later: form an LLC so that liability isn't personal.
- [ ] **Taxes**: income is reportable. Talk to whoever does the family's taxes.
- [ ] **Supabase or hosting accounts holding user data**: an adult owner is safer, because they're the data controller under GDPR/CCPA.

What Credence can do himself: write the code, run test mode, use Apple's free account for on-device builds, run TestFlight once the team exists, write the docs, and run GitHub.
