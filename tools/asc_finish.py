#!/usr/bin/env python3
"""Finish what the API can finish for Turnstile AI: set the price to Free,
report build processing, and attach the newest VALID build to version 1.0.

    python3 tools/asc_finish.py            # report only
    python3 tools/asc_finish.py --apply    # set Free price + attach the build

App Privacy and pressing Submit stay in the browser (no public API).
"""
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, r"C:\Users\M5\Downloads")
from asc_credentials import API, token  # noqa: E402

BUNDLE = "tech.advancedfield.Turnstile"
APPLY = "--apply" in sys.argv


def call(method, path, body=None, ok=(200, 201, 204)):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode() if body is not None else None, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        payload = e.read().decode()
        try:
            payload = json.loads(payload)
        except Exception:
            pass
        if e.code not in ok:
            return e.code, payload
        return e.code, payload


def need(status, res, label):
    if status >= 300:
        sys.exit(f"{label} failed ({status}): {json.dumps(res)[:500]}")
    return res


app = need(*call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}"), "find app")["data"]
if not app:
    sys.exit("no app record for " + BUNDLE)
APP = app[0]["id"]
print(f"app {APP} {app[0]['attributes']['name']}")

# ---- price ----
st, res = call("GET", f"/v1/appPriceSchedules/{APP}/manualPrices?limit=1&include=appPricePoint&fields[appPricePoints]=customerPrice")
if st == 200:
    print("price: already set ->", [i["attributes"]["customerPrice"] for i in res.get("included", [])])
elif st != 404:
    print("price: unexpected", st, str(res)[:200])
elif not APPLY:
    print("price: NOT set (re-run with --apply to make it Free)")
else:
    pts = need(*call("GET", f"/v1/apps/{APP}/appPricePoints?filter[territory]=USA&limit=200&fields[appPricePoints]=customerPrice"), "price points")["data"]
    free = next(p for p in pts if float(p["attributes"]["customerPrice"]) == 0.0)
    need(*call("POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules",
                 "relationships": {"app": {"data": {"type": "apps", "id": APP}},
                                   "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                                   "manualPrices": {"data": [{"type": "appPrices", "id": "${p}"}]}}},
        "included": [{"type": "appPrices", "id": "${p}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]}), "set price")
    chk = need(*call("GET", f"/v1/appPriceSchedules/{APP}/manualPrices?limit=1&include=appPricePoint&fields[appPricePoints]=customerPrice"), "read price")
    print("price: set to Free ->", [i["attributes"]["customerPrice"] for i in chk.get("included", [])])

# ---- builds ----
builds = need(*call("GET", f"/v1/builds?filter[app]={APP}&limit=10&sort=-uploadedDate&fields[builds]=version,processingState,uploadedDate,expired"), "builds")["data"]
if not builds:
    print("builds: none have arrived yet (App Store Connect processing can take 10-30 minutes)")
else:
    for b in builds:
        a = b["attributes"]
        print(f"  build {a['version']:>4}  {a['processingState']:<10} uploaded {a['uploadedDate']}")

# ---- version + attach ----
ver = need(*call("GET", f"/v1/apps/{APP}/appStoreVersions?limit=1&fields[appStoreVersions]=versionString,appStoreState"), "version")["data"]
if ver:
    v = ver[0]
    print(f"version {v['attributes']['versionString']} ({v['attributes']['appStoreState']})")
    st, cur = call("GET", f"/v1/appStoreVersions/{v['id']}/build?fields[builds]=version")
    attached = cur.get("data") if st == 200 else None
    valid = [b for b in builds if b["attributes"]["processingState"] == "VALID" and not b["attributes"].get("expired")]
    newest = valid[0] if valid else None   # builds are sorted newest first
    if not newest:
        print("  no VALID build to attach yet")
    elif attached and attached.get("id") == newest["id"]:
        print(f"  newest build {newest['attributes']['version']} is already attached")
    elif not APPLY:
        was = f" (replacing build {attached['attributes']['version']})" if attached else ""
        print(f"  build {newest['attributes']['version']} is ready to attach{was}; re-run with --apply")
    else:
        need(*call("PATCH", f"/v1/appStoreVersions/{v['id']}/relationships/build",
                   {"data": {"type": "builds", "id": newest["id"]}}), "attach build")
        was = f", replacing build {attached['attributes']['version']}" if attached else ""
        print(f"  attached build {newest['attributes']['version']}{was}")

# ---- what is left ----
st, usages = call("GET", f"/v1/apps/{APP}/appDataUsages?limit=1")
print("\nApp Privacy:", "answered" if st == 200 and usages.get("data") else "NOT answered (browser only)")
print("Remaining by hand: App Privacy questionnaire, then Add for Review and Submit.")
