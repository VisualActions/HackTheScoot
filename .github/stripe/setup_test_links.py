#!/usr/bin/env python3
"""HackTheScoot: create (or find) the Stripe TEST-mode Pro products, prices and
Payment Links, and print ONLY their public URLs.

Safety:
- Reads STRIPE_SECRET_KEY from the environment (a GitHub Actions secret). Never prints it.
- Refuses to run with anything but a TEST key (sk_test_ / rk_test_). Live mode is a
  separate, adult-approved step (README > Going live).
- Checks every object Stripe returns has livemode == false.
- Idempotent: prices are found by lookup_key and links by metadata, so re-running
  creates nothing new.
"""
import json, os, sys, urllib.parse, urllib.request, urllib.error, hashlib

API = "https://api.stripe.com/v1"
SITE = "https://j078-app.sites.tab.bot"
KEY = os.environ.get("STRIPE_SECRET_KEY", "").strip()

PLANS = [
    {"key": "pro_monthly", "lookup": "hts_pro_monthly_test", "amount": 399, "interval": "month", "label": "Pro monthly ($3.99/mo)"},
    {"key": "pro_yearly", "lookup": "hts_pro_yearly_test", "amount": 2999, "interval": "year", "label": "Pro yearly ($29.99/yr)"},
]


def fail(msg):
    print(f"::error title=Stripe test setup::{msg}")
    sys.exit(1)


def call(method, path, params=None, idem=None):
    data = None
    url = API + path
    if params:
        enc = urllib.parse.urlencode(params, doseq=True)
        if method == "GET":
            url += "?" + enc
        else:
            data = enc.encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + KEY)
    req.add_header("Stripe-Version", "2024-06-20")
    if idem:
        req.add_header("Idempotency-Key", idem)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            obj = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            err = json.loads(e.read().decode()).get("error", {})
            fail(f"Stripe said {e.code}: {err.get('type')} {err.get('code') or ''} {err.get('message', '')[:200]}")
        except Exception:
            fail(f"Stripe said HTTP {e.code}")
    check_test(obj)
    return obj


def check_test(obj):
    if isinstance(obj, dict):
        if obj.get("livemode") is True:
            fail("Stripe returned a LIVE-mode object. Stopping; nothing more is created.")
        for v in obj.values():
            check_test(v)
    elif isinstance(obj, list):
        for v in obj:
            check_test(v)


def idem(*parts):
    return "hts-test-" + hashlib.sha256("|".join(parts).encode()).hexdigest()[:32]


def main():
    if not KEY:
        fail("STRIPE_SECRET_KEY is not set for this workflow. Add it under Settings > Secrets and variables > Actions.")
    if not (KEY.startswith("sk_test_") or KEY.startswith("rk_test_")):
        fail("STRIPE_SECRET_KEY is not a TEST key (it must start with sk_test_). Refusing to touch live mode.")

    # 1. product
    found = call("GET", "/products/search", {"query": "metadata['hts_key']:'pro' AND active:'true'"})
    if found.get("data"):
        product = found["data"][0]
    else:
        product = call("POST", "/products", {
            "name": "HackTheScoot Pro (TEST)",
            "description": "Pro extras for HackTheScoot: Pro themes, trip analytics, CSV/GPX export, log analysis. Test mode.",
            "metadata[hts_key]": "pro",
        }, idem=idem("product", "pro"))
    print(f"product {product['id']} (test mode)")

    # 2. prices by lookup key
    lookups = [p["lookup"] for p in PLANS]
    have = call("GET", "/prices", {"lookup_keys[]": lookups, "active": "true", "limit": "10"})
    prices = {p["lookup_key"]: p for p in have.get("data", [])}
    for p in PLANS:
        if p["lookup"] not in prices:
            prices[p["lookup"]] = call("POST", "/prices", {
                "product": product["id"], "currency": "usd", "unit_amount": str(p["amount"]),
                "recurring[interval]": p["interval"], "lookup_key": p["lookup"],
                "nickname": p["label"], "metadata[hts_key]": p["key"],
            }, idem=idem("price", p["lookup"]))
        print(f"price {p['key']}: {prices[p['lookup']]['id']}")

    # 3. payment links (found by metadata)
    links = {}
    starting_after = None
    for _ in range(10):
        q = {"limit": "100", "active": "true"}
        if starting_after:
            q["starting_after"] = starting_after
        page = call("GET", "/payment_links", q)
        for l in page.get("data", []):
            k = (l.get("metadata") or {}).get("hts_key")
            if k and k not in links:
                links[k] = l
        if not page.get("has_more"):
            break
        starting_after = page["data"][-1]["id"]

    out = {"mode": "test", "test_card": "4242 4242 4242 4242", "links": {}}
    for p in PLANS:
        l = links.get(p["key"])
        if not l:
            l = call("POST", "/payment_links", {
                "line_items[0][price]": prices[p["lookup"]]["id"],
                "line_items[0][quantity]": "1",
                "after_completion[type]": "redirect",
                "after_completion[redirect][url]": f"{SITE}/pro-thanks.html?plan={p['key']}",
                "allow_promotion_codes": "false",
                "metadata[hts_key]": p["key"],
            }, idem=idem("link", p["key"], prices[p["lookup"]]["id"]))
        url = l["url"]
        out["links"][p["key"]] = url
        print(f"::notice title=Stripe test link {p['key']}::{url}")

    with open("stripe-test-links.json", "w") as f:
        json.dump(out, f, indent=2)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("## Stripe TEST links\n\nTest card 4242 4242 4242 4242, any future date, any CVC.\n\n")
            for k, u in out["links"].items():
                f.write(f"- {k}: {u}\n")
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
