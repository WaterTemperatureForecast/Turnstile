#!/usr/bin/env python3
"""Admin helper for the Turnstile worker (needs ADMIN_TOKEN in the environment
or ~/.turnstile/admin.token). Standard library only.

  python scripts/admin.py pool fixtures/pool.json          # upload fallback machines
  python scripts/admin.py pool-count
  python scripts/admin.py agents                           # list agents with ids
  python scripts/admin.py setter <agent_id> [--off]        # flag as house setter + featured
  python scripts/admin.py machines [YYYY-MM-DD]            # today's / pending machines WITH rules (secret!)
  python scripts/admin.py finalize YYYY-MM-DD
  python scripts/admin.py sponsor "Name" "tagline" https://url   |  sponsor --clear
  python scripts/admin.py promos promos.json               # [{title, subtitle, url}]
  python scripts/admin.py reports

Set TURNSTILE_URL to point at another server (e.g. http://localhost:8787).
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("TURNSTILE_URL", "https://turnstile.advancedfield.tech").rstrip("/")


def token():
    t = os.environ.get("ADMIN_TOKEN")
    if t:
        return t
    p = os.path.join(os.path.expanduser("~"), ".turnstile", "admin.token")
    if os.path.exists(p):
        return open(p, encoding="utf-8").read().strip()
    sys.exit("set ADMIN_TOKEN or create ~/.turnstile/admin.token")


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("X-Admin-Token", token())
    req.add_header("Accept", "application/json")
    req.add_header("User-Agent", "turnstile-admin/1.0")   # Cloudflare's browser check 403s the default urllib UA
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, {"error": str(e)}


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    cmd = args[0]
    if cmd == "pool":
        machines = json.load(open(args[1], encoding="utf-8"))
        st, res = call("POST", "/v1/admin/pool", {"machines": machines})
    elif cmd == "pool-count":
        st, res = call("GET", "/v1/admin/pool")
    elif cmd == "agents":
        st, res = call("GET", "/v1/admin/agents")
    elif cmd == "setter":
        on = "--off" not in args
        st, res = call("POST", f"/v1/admin/agents/{args[1]}/flags", {"setter": on, "featured": on})
    elif cmd == "machines":
        q = f"?date={args[1]}" if len(args) > 1 else ""
        st, res = call("GET", "/v1/admin/machines" + q)
    elif cmd == "finalize":
        st, res = call("POST", f"/v1/admin/finalize/{args[1]}")
    elif cmd == "sponsor":
        body = {"clear": True} if "--clear" in args else {"name": args[1], "tagline": args[2] if len(args) > 3 else "", "url": args[-1]}
        st, res = call("POST", "/v1/admin/sponsor", body)
    elif cmd == "promos":
        st, res = call("POST", "/v1/admin/promos", {"promos": json.load(open(args[1], encoding="utf-8"))})
    elif cmd == "reports":
        st, res = call("GET", "/v1/admin/reports")
    else:
        sys.exit(__doc__)
    print(st, json.dumps(res, indent=2)[:4000])
    sys.exit(0 if st < 300 else 1)


if __name__ == "__main__":
    main()
