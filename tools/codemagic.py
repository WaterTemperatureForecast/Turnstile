#!/usr/bin/env python3
"""Codemagic API helper (token in ~/.config/codemagic.env, CODEMAGIC_API_TOKEN=...; never printed).

  python tools/codemagic.py apps                 # list apps (id, name, repo)
  python tools/codemagic.py add                  # add this repo as an app (idempotent)
  python tools/codemagic.py start                # start the ios-testflight workflow on main (billed)
  python tools/codemagic.py builds               # recent builds for this app
  python tools/codemagic.py log <build_id>       # step names/status + error lines
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

HOST = "https://api.codemagic.io"
REPO = "https://github.com/WaterTemperatureForecast/Turnstile"
WORKFLOW = "ios-testflight"


def token():
    p = os.path.join(os.path.expanduser("~"), ".config", "codemagic.env")
    for line in open(p, encoding="utf-8"):
        if line.startswith("CODEMAGIC_API_TOKEN="):
            return line.split("=", 1)[1].strip().strip('"')
    sys.exit("no CODEMAGIC_API_TOKEN in " + p)


def call(method, path, body=None):
    req = urllib.request.Request(HOST + path, data=json.dumps(body).encode() if body is not None else None, method=method)
    req.add_header("x-auth-token", token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "{}")
        except Exception:
            return e.code, {"error": str(e)}


def find_app():
    st, res = call("GET", "/apps")
    for a in res.get("applications", []):
        if "turnstile" in (a.get("repository", {}).get("htmlUrl") or a.get("appName") or "").lower():
            return a
    return None


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "apps"
    if cmd == "apps":
        st, res = call("GET", "/apps")
        for a in res.get("applications", []):
            print(a["_id"], a.get("appName"), a.get("repository", {}).get("htmlUrl"))
    elif cmd == "add":
        a = find_app()
        if a:
            print("exists:", a["_id"], a.get("appName"))
            return
        st, res = call("POST", "/apps", {"repositoryUrl": REPO})
        print(st, res.get("_id") or res)
    elif cmd == "start":
        a = find_app() or sys.exit("app not added yet")
        st, res = call("POST", "/builds", {"appId": a["_id"], "workflowId": WORKFLOW, "branch": "main"})
        print(st, res.get("buildId") or res)
    elif cmd == "builds":
        a = find_app() or sys.exit("app not added yet")
        st, res = call("GET", f"/builds?appId={a['_id']}&limit=10")
        for b in res.get("builds", []):
            print(b["_id"], b.get("status"), b.get("startedAt"), (b.get("commit") or {}).get("hash", "")[:8], b.get("buildNumber"))
    elif cmd == "log":
        st, res = call("GET", f"/builds/{sys.argv[2]}")
        b = res.get("build", res)
        print("status:", b.get("status"), "number:", b.get("buildNumber"))
        for s in b.get("buildActions", []):
            print(f"  [{s.get('status')}] {s.get('name')}")
            log = s.get("log") or ""
            if s.get("status") in ("failed", "error") and log:
                for line in log.splitlines():
                    if re.search(r"error:|fatal|FAILED|Error", line):
                        print("     ", line[:220])
        for art in b.get("artefacts", []):
            print("  artifact:", art.get("name"), art.get("url"))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
