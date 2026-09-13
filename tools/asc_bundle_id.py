"""Register the Turnstile bundle id in the Developer Portal (idempotent)."""
import json, sys, urllib.request, urllib.error
sys.path.insert(0, r"C:\Users\M5\Downloads")
from asc_credentials import API, token
IDENT = "tech.advancedfield.Turnstile"
def call(method, path, body=None):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode() if body else None, method=method)
    req.add_header("Authorization", "Bearer " + token()); req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r: return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read().decode() or "{}")
st, res = call("GET", f"/v1/bundleIds?filter[identifier]={IDENT}&limit=5")
existing = [b for b in res.get("data", []) if b["attributes"]["identifier"] == IDENT]
if existing:
    print("exists:", existing[0]["id"], existing[0]["attributes"]["name"])
else:
    st, res = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": IDENT, "name": "Turnstile", "platform": "IOS"}}})
    print(st, res.get("data", {}).get("id") or res.get("errors"))
