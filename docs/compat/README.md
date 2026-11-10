# Compatibility database

The database is versioned JSON. It lives outside the app code, so it can be updated without an app release.

| File | What |
|---|---|
| `schema/compat-db.schema.json` | JSON Schema (draft 2020-12), `schema_version` 1.0.0. Covers every Phase 4 field |
| `seed/compat-db.seed.json` | Seed data, `db_version` 0.1.0: J078 (partial), Volpam (partial), Hiboy S2 Pro, Ninebot Max G30, Xiaomi M365, KuKirin G4 (experimental), Dualtron EY3/EY4/EYA (unsupported) |
| `validate.py` | Validator: the schema plus policy rules. `python3 docs/compat/validate.py` exits 0 if valid, 1 if not |

## Field map (Phase 4 → schema)
| Phase 4 field | Schema field |
|---|---|
| Manufacturer / Exact model / Year or revision | `manufacturer`, `model`, `revision`, `aliases` |
| Controller manufacturer / identifier | `controller_manufacturer`, `controller_id` |
| Display model | `display_model` |
| BLE services and characteristics | `ble.services[].characteristics[]`, `ble.auth`, `ble.encryption` (a scheme name, **never a password**) |
| Firmware versions tested | `firmware_tested[]` |
| Supported telemetry | `telemetry{name: {status, evidence[], note}}` |
| Supported commands | `commands[]` with `status`, `writes_state`, `frame_template`, `ack_template`, `verify_by` |
| Factory speed specifications | `factory_speed.factory_max_kmh`, `per_mode_kmh`, `observed_cap_kmh`, `observed_note` (kept apart on purpose) |
| Region-specific limitations | `region_limits[]` |
| Firmware update support | `firmware_update_support` (`none_in_hts` / `official_app_only` / `unknown`) |
| Recovery availability | `recovery.status`, `recovery.method` |
| Known issues | `known_issues[]` |
| Evidence sources | `evidence[]` (`kind`, `ref`, `date`, `license`); features point to them by index |
| Last verification date | `last_verified` |
| Checker card (Connection, Live Speed, Lights, Modes, …) | `checker{…}`, using exactly the words from the spec |

Statuses:
- `verified_hardware`: tested with HackTheScoot on the real scooter
- `verified_capture`: decoded from a capture of the official app on the real scooter
- `documented_public`
- `unverified`
- `unsupported`
- `unknown`

## Policy rules (enforced by validate.py)
1. `full` requires an `hts_hardware_test` evidence row, and every feature must be `verified_hardware` (or `unsupported`).
2. `partial` requires at least one verified feature, backed by `own_capture` or `hts_hardware_test`.
3. `experimental`, `diagnostics_only` and `unsupported` must have `write_policy: "none"`.
4. Every verified write needs `verify_by`. A BLE write ack is never proof.
5. The checker can't say "verified" for speed, lights or modes unless the telemetry says so.
6. `firmware_modification` can never be `verified`. Flashing is disabled.
7. No passwords, `AT+PWD[digits]` strings, or Stripe keys. No "speed unlock/bypass" wording.
8. Evidence indexes must exist, ids must be unique, and dates must be valid.

## Loader spec (for the app)
1. **Bundle** a copy of the DB in the app. The app works offline and never depends on the network to connect to a scooter.
2. **Optional update**: fetch `compat-db.json` and `compat-db.json.sig` over HTTPS from a fixed URL (for example GitHub Releases).
   - Verify an **Ed25519 signature** with a public key pinned in the app.
   - Accept the file only if `schema_version` major == 1 and `db_version` > the bundled version.
   - If either check fails, keep the bundled copy.
3. **Validate on load** (the same rules, in Swift). Drop any entry that fails and log it. Never crash.
4. **Matching** (Phase 3):
   - Score candidates from GATT service UUIDs and the frame shape of a **read-only** notify.
   - The advertised name is a weak hint only.
   - Never pick an adapter from the name alone.
   - A tie or no match falls back to `generic_readonly`.
5. **Enabling features**: the `CapabilityEngine` enables a control only if all four hold:
   - the entry's `write_policy` is `verified_only`;
   - that command's `status` is verified;
   - the adapter implements it;
   - the user isn't in simulator mode.

   Everything else is display-only.
6. **The DB can't add commands the adapter doesn't implement.** It only gates them. New byte sequences ship only in app code that has passed review and tests. That's Phase 8's "no automatic deployment of unverified community commands".
7. Updating the DB is a reviewed PR that bumps `db_version`, passes `validate.py` in CI, and is then signed.
