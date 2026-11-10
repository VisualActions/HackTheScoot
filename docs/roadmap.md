# Roadmap (Priorities 1–8)

Each milestone is "done" only when its proof exists: tests green in CI, a capture, or a doc merged.

| # | Priority | Milestones | Proof of done |
|---|---|---|---|
| 1 | Preserve and stabilize v4 + J078 | M1.1 v4-dev green with XCTest (scramble round-trip for all 256 bytes, status parsing, speed-limit ack). M1.2 Park only after `DB EB CA CA FF`. M1.3 Battery % and odometer shown as "unverified". M1.4 Credence rides with v4 beta on the J078 and confirms speed, mode, light, park and limit | CI test report; a ride note from Credence |
| 2 | Protocol adapter architecture | M2.1 A `ProtocolAdapter` protocol with declared capabilities. `Joyhis365` adapter = existing code, unchanged behavior. M2.2 A `GenericReadOnly` adapter for unknown devices. M2.3 `CapabilityEngine` gates writes from the compat DB (`write_policy`) **and** adapter support. M2.4 A simulator adapter per family that never touches CoreBluetooth | Adapter conformance test suite passes |
| 3 | Import verified info from legally reusable sources | M3.1 Clean-room Ninebot transport and frame codec from the **Apache-2.0** NootNooot doc. Unit tests from the doc's example frames. No AGPL code. M3.2 Attribution page | `docs/legal/open-source-attribution.md` + a license scan in CI |
| 4 | Public compatibility database | M4.1 Ship `compat-db.schema.json` and the seed. `validate.py` runs in CI. M4.2 In-app searchable checker (free). M4.3 Signed DB updates via GitHub Releases | The checker shows J078 = Partial, Volpam = Partial, Hiboy = Experimental |
| 5 | Add brands one verified model at a time | **M5.1 ⭐ Zydtech/365 family:** a `Zydtech365` adapter from the Volpam decode (CRC16-Modbus verified on 25 frames). Writes ship only for commands verified in Volpam captures. **M5.2 Hiboy S2 Pro:** UNVERIFIED until we capture one. Public writeup ([Lee Holmes, 2024](https://www.leeholmes.com/reverse-engineering-hiboy-btle-protocol/)) shows the same F1F1 / `AT+PWD` / CRC16-Modbus shape, so one capture could take it to Partial. M5.3 Ninebot Max G30, read-only telemetry after the handshake, on a borrowed unit. M5.4 Dualtron and KuKirin: research and submission flow only. No writes (KuKirin's maker warns against third-party apps; Dualtron has no public protocol) | A capture or test log per model, and an updated DB entry |
| 6 | Premium features + billing (test mode) | M6.1 StoreKit 2 Pro monthly/yearly with an intro trial, in the sandbox. M6.2 Paywall that never hides free or safety features. M6.3 (Optional) Supabase + Stripe test webhooks with idempotency | Sandbox purchase, restore and expire tests pass |
| 7 | Testing, privacy, security, release prep | M7.1 Secret scan, dependency scan, license scan in CI. M7.2 Privacy manifest + nutrition label. M7.3 Accessibility pass (Dynamic Type, VoiceOver). M7.4 Lawyer review of the Privacy Policy and Terms of Service | A checklist in `docs/legal/compliance-checklist.md`, all ticked |
| 8 | Public launch plan | M8.1 **A parent enrolls** in the Apple Developer Program and adds Credence. Paid Apps Agreement, tax, bank. M8.2 Stripe adult Representative added before live mode. M8.3 TestFlight beta with 5–10 riders. M8.4 Support page and safety disclaimer | App Store submission |

**Order and dependencies**
- Order: 1 → 2 → 4 → 5.1 (Volpam/zydtech) → 3 + 5.3 (Ninebot) → 6 → 7 → 8.
- Billing work (6) can run in parallel in test mode at any time. Real payments are blocked on the adult steps in 8.

**What only Credence or his dad can supply**
- Ride captures (J078 moving; Volpam via the official app).
- A Hiboy, AOVO or Ninebot unit to borrow and capture.
- A parent for Apple and Stripe.
