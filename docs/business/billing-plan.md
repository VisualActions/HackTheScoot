# Billing plan (plan only, not implemented)

**Status:** research doc, accessed 2026-11-09. **Test mode only** until audited. Not legal advice. Have an adult and, ideally, a lawyer review it.

## 1. The rules that decide the design
| Rule | What it says | Source |
|---|---|---|
| App Store Guideline **3.1.1** | Unlocking features or functionality, including **subscriptions**, "you must use in-app purchase" | [https://developer.apple.com/app-store/review/guidelines/](https://developer.apple.com/app-store/review/guidelines/), last updated **Oct 16, 2026** (page read) |
| Guideline **3.1.1(a)** | Apple's link-out entitlements "are not required for developers to include buttons, external links, or other calls to action in their **United States storefront** apps". In other storefronts, apps may not include them, except under region-specific StoreKit External Purchase entitlements | same page |
| Guideline **3.1.2** | Subscriptions must give ongoing value, last at least 7 days, and work on all of the user's devices | same page |
| Guideline **3.1.4** | Hardware-specific features may unlock without IAP "in limited circumstances". Don't rely on this: our Pro features (themes, analytics) are not hardware-dependent | same page |
| Guideline **5.1.1(v)** | Apps with account creation must let users start account deletion **inside the app**, and explain how billing and cancellation work | [Apple: account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/) (page read) |
| Court background | Epic v. Apple: on 2025-04-30 the district court barred Apple from blocking US link-outs. The 9th Circuit (filed **2025-12-11**) affirmed the contempt finding, but held that the commission ban "did not qualify as a civil contempt sanction in its present form" and **remanded**. So whether Apple may charge a commission on US linked-out purchases is still being decided (current status UNVERIFIED; re-check before launch) | [9th Cir. opinion No. 25-2935](https://cdn.ca9.uscourts.gov/datastore/opinions/2025/12/11/25-2935.pdf) (PDF read) |
| Stripe on iOS | "For iOS apps selling digital products… in the **US**, you can redirect customers to an external payment page… using Stripe Checkout. Use StoreKit's Storefront property to detect which storefront your app was downloaded from" | [Stripe docs](https://docs.stripe.com/mobile/digital-goods/checkout) (page read) |

**Conclusion:**
- **StoreKit 2 IAP is required everywhere.** It's the baseline.
- A Stripe Checkout link-out is allowed **only on the US storefront**, alongside IAP, and only if we check `Storefront.current` at runtime.
- Outside the US, no Stripe link, button or call to action in the app.
- Stripe on our own website (outside the app) is fine anywhere. Per 3.1.3(b), features bought there can be honored in the app **if they're also offered as IAP in the app**.

## 2. Phased approach (recommended)
1. **v1 billing: Apple only, no backend.** StoreKit 2:
   - `Product.products(for:)`, `purchase()`, `Transaction.updates`, `Transaction.currentEntitlements`, `AppStore.sync()` (for Restore);
   - the system manage-subscriptions sheet;
   - free-trial **introductory offer**, with eligibility from `isEligibleForIntroOffer`.

   Entitlements are checked on-device from signed transactions. No account needed. This is the safest first launch.
2. **v2: backend + web billing (US).** Add only when cloud sync or web purchase is actually wanted. Stripe Checkout (hosted) + Billing + Customer Portal + webhooks. A server merges Apple and Stripe into one entitlement.
3. **Developer tier:** later. Same machinery, a separate product.

## 3. Tiers (exactly as Credence drafted)
| FREE | PRO ($3.99/mo or $29.99/yr suggested; optional eligible free trial) | DEVELOPER (later) |
|---|---|---|
| Scooter discovery, compatibility database, verified basic controls, basic speedometer, factory-supported riding modes, battery status when available, essential diagnostics, safety information, basic trip history | Advanced dashboards, premium themes, custom startup audio, advanced trip analytics, trip replay, unlimited saved dashboard layouts, extended log analysis, data export, theme sharing, enhanced simulator, detailed performance reports, optional cloud sync | Advanced offline protocol analysis, multi-capture comparison, protocol documentation workspace, device profile development, test fixtures, developer export formats |

Never paywalled: safety-critical functions, fault warnings, basic factory controls, accurate compatibility info, connecting to a scooter. **No speed-unlock entitlement, ever.**

Pricing notes:
- $29.99/yr is about 37% off 12 × $3.99 ($47.88).
- Apple's net is 70% in year one and 85% after a subscriber's first paid year ([Apple subscriptions page](https://developer.apple.com/app-store/subscriptions/), page read).
- The **Small Business Program** lowers the rate to 15% ([Apple](https://developer.apple.com/app-store/small-business-program/), snippet). Enroll at launch.

## 4. Trial and paywall UX checklist
- Show trial length and renewal price, both in the store's localized price string.
- List what Pro adds. Free features are never shown behind the paywall.
- Eligibility comes from StoreKit (Apple). On Stripe, one trial per customer (enforced server-side).
- "Restore Purchases" button. "Manage subscription" (Apple sheet / Stripe Customer Portal). Plain cancellation steps.
- Entitlements expire automatically (Apple: expiration plus billing grace period if enabled; Stripe: subscription status).
- No dark patterns, no pre-checked upsells, no countdown timers.

## 5. Stripe pieces (phase 2, US/web)
| Piece | Use | Doc |
|---|---|---|
| Checkout (hosted, `mode=subscription`) | The web or US link-out purchase page. Card data never touches us | [docs.stripe.com/mobile/digital-goods/checkout](https://docs.stripe.com/mobile/digital-goods/checkout) |
| Billing + trials | `trial_period_days`, trial-end behavior | [docs.stripe.com/billing/subscriptions/trials](https://docs.stripe.com/billing/subscriptions/trials) |
| Customer Portal | Cancel, update card, invoices | [docs.stripe.com/customer-management](https://docs.stripe.com/customer-management) |
| Webhooks | Verify the `Stripe-Signature` header with the `whsec_` signing secret on the **raw body**; return 2xx fast; "track event IDs to identify duplicate deliveries" | [docs.stripe.com/webhooks](https://docs.stripe.com/webhooks) (page read) |
| Idempotency keys | On every server-side POST to Stripe | [docs.stripe.com/api/idempotent_requests](https://docs.stripe.com/api/idempotent_requests) |

Events to handle:
- `checkout.session.completed`
- `customer.subscription.created/updated/deleted`
- `invoice.paid`
- `invoice.payment_failed` (grace, then revoke)
- `charge.refunded` (revoke if it's a full refund)
- `customer.subscription.trial_will_end` (send a notice)

**Keys (current setup):**
- The Stripe **TEST secret key** is a GitHub Actions repo secret named `STRIPE_SECRET_KEY`. It's server-side only, and it must **never** go in the iOS app, the repo files or logs.
  - GitHub Actions secrets reach CI jobs only. A deployed backend needs the key copied into the backend's own secret store (e.g. `supabase secrets set STRIPE_SECRET_KEY=…`) by the account owner.
- The **test publishable key** is kept outside the repo, in Tab's working note `work/hts-v4/stripe-test-config.md`. It isn't secret, but it isn't needed in the app either, because hosted Checkout runs on the server.
- The webhook signing secret (`whsec_…`) will be another server secret, created when the endpoint is registered.

## 6. Backend options
| | Supabase (Auth + Postgres + Edge Functions) | Small API (e.g. Cloudflare Workers + D1/KV, or Fly + Postgres) |
|---|---|---|
| Auth | Built in (Sign in with Apple, email) | Bring your own |
| Stripe webhooks | Official example: [Supabase docs](https://supabase.com/docs/guides/functions/examples/stripe-webhooks) (page updated Sep 11 2026) | Easy, but hand-rolled |
| Row-level security for per-user data | Yes | DIY |
| Cost at start | Free tier | Free tier |
| **Pick** | **Supabase**: least code, and auth plus deletion are built in | |

Data model (minimum):
- `users(id)`
- `entitlements(user_id, source[apple|stripe], product, status, expires_at, original_transaction_id | stripe_subscription_id)`
- `processed_events(id PRIMARY KEY, source, received_at)`. Insert-or-skip is what makes webhooks idempotent.

Apple on the server (phase 2):
- **App Store Server Notifications V2** ([docs](https://developer.apple.com/documentation/appstoreservernotifications)) to a function that verifies the JWS signature chain (Apple's App Store Server Library).
- Link purchases to users with `appAccountToken` ([docs](https://developer.apple.com/documentation/storekit/transaction/appaccounttoken)).
- Handle `REFUND` → revoke, and `DID_FAIL_TO_RENEW` / grace period.

Account deletion (5.1.1(v)):
- An in-app "Delete account" button removes the user row, entitlements and synced data, and cancels any **Stripe** subscription through the API.
- For **Apple** subscriptions, we can't cancel. Tell the user to cancel in Settings › Apple ID › Subscriptions, and link it.

Scooter BLE never goes through the backend.

## 7. Who must be an adult. See [age-and-legal-checklist.md](../legal/age-and-legal-checklist.md)
