#!/usr/bin/env python3
"""Validate the HackTheScoot compatibility database.

Usage: python3 docs/compat/validate.py [db.json] [schema.json]
Exit 0 = valid, 1 = errors. Uses `jsonschema` if installed (pip install jsonschema),
and always runs the policy rules below (stdlib only).
"""
import json, re, sys, os, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
db_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "seed", "compat-db.seed.json")
schema_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "schema", "compat-db.schema.json")
db = json.load(open(db_path))
errors, warnings = [], []

try:
    import jsonschema
    v = jsonschema.Draft202012Validator(json.load(open(schema_path)), format_checker=jsonschema.FormatChecker())
    for e in sorted(v.iter_errors(db), key=lambda e: list(e.path)):
        errors.append("schema: /%s: %s" % ("/".join(map(str, e.path)), e.message))
except ImportError:
    warnings.append("jsonschema not installed; only policy rules were checked")

VERIFIED = {"verified_hardware", "verified_capture"}
STRONG_EVIDENCE = {"hts_hardware_test", "own_capture"}
SECRET_PATTERNS = [re.compile(r"AT\+PWD\[\d{4,}\]"), re.compile(r"\b(?:3\d ){5}3\d\b"),
                   re.compile(r"sk_(?:test|live)_"), re.compile(r"pk_(?:test|live)_")]
FORBIDDEN_WORDS = re.compile(r"speed[ _-]?(unlock|bypass|hack)|derestrict", re.I)

def date(s):
    return datetime.date.fromisoformat(s)

seen = set()
gen = date(db["generated"]) if "generated" in db else None
for i, e in enumerate(db.get("entries", [])):
    eid = e.get("id", "#%d" % i)
    where = "entry %s" % eid
    if eid in seen: errors.append(where + ": duplicate id")
    seen.add(eid)
    ev = e.get("evidence", [])
    n = len(ev)
    feats = dict(e.get("telemetry", {}))
    feats.update({"cmd:" + c.get("id", "?"): c for c in e.get("commands", [])})
    for k, f in feats.items():
        for idx in f.get("evidence", []):
            if idx >= n: errors.append("%s: %s points at evidence[%d], only %d exist" % (where, k, idx, n))
    for sec in ("factory_speed",):
        for idx in e.get(sec, {}).get("factory_source", []):
            if idx >= n: errors.append("%s: factory_source[%d] out of range" % (where, idx))
    level = e.get("compatibility_level")
    kinds = {x.get("kind") for x in ev}
    verified = [k for k, f in feats.items() if f.get("status") in VERIFIED]
    if level == "full":
        if "hts_hardware_test" not in kinds:
            errors.append(where + ": 'full' needs an hts_hardware_test evidence row")
        bad = [k for k, f in feats.items() if f.get("status") not in ("verified_hardware", "unsupported")]
        if bad: errors.append(where + ": 'full' but not hardware-verified: " + ", ".join(bad))
    if level == "partial":
        if not verified: errors.append(where + ": 'partial' needs at least one verified feature")
        if not (kinds & STRONG_EVIDENCE): errors.append(where + ": 'partial' needs own_capture or hts_hardware_test evidence")
    if level in ("experimental", "diagnostics_only", "unsupported") and e.get("write_policy", "none") != "none":
        errors.append(where + ": %s scooters must have write_policy 'none'" % level)
    for c in e.get("commands", []):
        if c.get("writes_state") and c.get("status") in VERIFIED and not c.get("verify_by"):
            errors.append("%s: verified write %s has no verify_by (a BLE ack is not proof)" % (where, c.get("id")))
    ck, tel = e.get("checker", {}), e.get("telemetry", {})
    for ckey, tkeys in (("live_speed", ["speed"]), ("lights", ["front_light", "light"]), ("modes", ["mode", "gear"])):
        if ck.get(ckey) == "verified" and not any(tel.get(t, {}).get("status") in VERIFIED for t in tkeys):
            errors.append("%s: checker.%s says verified but telemetry %s is not" % (where, ckey, "/".join(tkeys)))
    if ck.get("firmware_modification") == "verified":
        errors.append(where + ": firmware modification is disabled in HackTheScoot; cannot be 'verified'")
    blob = json.dumps(e)
    for pat in SECRET_PATTERNS:
        if pat.search(blob): errors.append(where + ": looks like a secret/password (%s)" % pat.pattern)
    if FORBIDDEN_WORDS.search(blob): errors.append(where + ": mentions a speed unlock/bypass")
    try:
        if gen and date(e["last_verified"]) > gen: errors.append(where + ": last_verified after db 'generated'")
    except Exception as ex:
        errors.append("%s: bad last_verified (%s)" % (where, ex))
    if e.get("ble", {}).get("advertised_names") and not e.get("ble", {}).get("services") and level in ("partial", "full"):
        warnings.append(where + ": identified by name only; names can be spoofed")

for w in warnings: print("WARN ", w)
for er in errors: print("ERROR", er)
print("%s: %d entries, %d errors, %d warnings" % (os.path.basename(db_path), len(db.get("entries", [])), len(errors), len(warnings)))
sys.exit(1 if errors else 0)
