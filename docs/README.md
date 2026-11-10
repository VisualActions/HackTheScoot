# HackTheScoot research docs (Universal Edition)

Research and planning only; no app code here. Written 2026-11-09. Every claim carries a source URL and date. **UNVERIFIED** means no hardware evidence yet.

| Doc | What's in it |
|---|---|
| [research/01-scooterhacking-inventory.md](research/01-scooterhacking-inventory.md) | All 11 ScooterHacking repos: exact license, contents, App Store reuse risk, recommendation |
| [research/02-protocols-ninebot-xiaomi.md](research/02-protocols-ninebot-xiaomi.md) | BLE services, frames, auth and model generations for Ninebot (ES, Max G30, G2, F, D, P) and Xiaomi (M365 → Mi 4). Pick: **Ninebot Max G30** first |
| [research/03-brand-compatibility.md](research/03-brand-compatibility.md) | 18 brands, with evidence level and compatibility level. ⭐ The Hiboy/zydtech "365" family find |
| [compat/](compat/README.md) | Versioned JSON schema, seed DB (7 models), validator (`python3 docs/compat/validate.py`), loader spec |
| [performance-compatibility.md](performance-compatibility.md) | Factory max vs regional limit vs observed. Never an unlock |
| [business/billing-plan.md](business/billing-plan.md) | StoreKit 2 vs Stripe (Guideline 3.1.1(a) US rules), tiers, trials, backend, webhooks, deletion |
| [legal/age-and-legal-checklist.md](legal/age-and-legal-checklist.md) | What needs a parent: Apple and Stripe terms quoted |
| [legal/privacy-policy-outline.md](legal/privacy-policy-outline.md) · [legal/terms-of-service-outline.md](legal/terms-of-service-outline.md) | Drafts **for legal review** |
| [legal/compliance-checklist.md](legal/compliance-checklist.md) · [legal/open-source-attribution.md](legal/open-source-attribution.md) | GDPR/CCPA basics, privacy label, license policy |
| [roadmap.md](roadmap.md) | Priorities 1–8 with milestones |

## Top findings
1. **ScooterHacking:** only NinebotTEA and fw-zip-package-v3 are MIT, and both are firmware tools we don't need. NinebotCrypto is **AGPL** (clean-room only). The wiki is CC BY-SA. Six repos have **no license**, and the firmware repos must never be redistributed. **Fork nothing for now.**
2. **Best legal Ninebot source** is an **Apache-2.0** protocol doc (NootNooot, Codeberg) covering 66 Segway-Ninebot devices. First model to adapt: **Ninebot Max G30**.
3. ⭐ **Hiboy S2 Pro uses the same protocol shape as the Volpam**: F1F1, `AT+PWD`, a 10-byte settings frame, CRC16-Modbus. Hiboy, AovoPro and 365GO apps all ship under `com.zydtech.*`. A "zydtech 365" adapter could cover several brands. UNVERIFIED until we capture a Hiboy.
4. **Billing:** StoreKit 2 IAP is required; a Stripe link-out is allowed **only on the US storefront** (Guideline 3.1.1(a), Oct 16 2026). **Apple and Stripe both require an adult** (parent) for a minor.
