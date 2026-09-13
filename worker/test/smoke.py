#!/usr/bin/env python3
"""End-to-end smoke test against a running worker (local `wrangler dev` by default).

  python test/smoke.py [http://localhost:8787] [admin-token]

Uploads the fallback pool, registers two house setters, assembles today's round,
plays both machines as a human (with notes, tests, answers, star), checks the
reveal/results/leaderboard/me, uploads a setter machine for a future date, has
the rival investigate it, and finally deletes the human's data.
"""
import json
import os
import sys
import urllib.error
import urllib.request
import uuid

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8787").rstrip("/")
ADMIN = sys.argv[2] if len(sys.argv) > 2 else "devtoken"
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), "engine"))
import rules  # noqa: E402


def call(method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, {"error": str(e)}


def expect(status, res, want=200, label=""):
    if status != want:
        raise SystemExit(f"FAIL {label}: {status} {res}")
    return res


A = {"X-Admin-Token": ADMIN}
human = {"X-Player-Id": str(uuid.uuid4())}

# 0. health
print("health", expect(*call("GET", "/health"), label="health"))

# 1. pool
pool = json.load(open(os.path.join(os.path.dirname(HERE), "fixtures", "pool.json"), encoding="utf-8"))
res = expect(*call("POST", "/v1/admin/pool", {"machines": pool}, A), 201, "pool")
print("pool added", res["added"], expect(*call("GET", "/v1/admin/pool", None, A), label="pool count")["pool"])

# 2. house setters
setters = {}
for name, model in (("Claude Fable 5.1", "claude-fable-5-1"), ("GPT-6", "gpt-6-astra")):
    st, res = call("POST", "/v1/agents", {"name": name + " smoke", "model": model, "operator": "smoke"})
    expect(st, res, 201, "register")
    setters[name] = {"Authorization": "Bearer " + res["token"], "id": res["agent_id"]}
    expect(*call("POST", f"/v1/admin/agents/{res['agent_id']}/flags", {"setter": True, "featured": True}, A), label="flags")
claude, gpt = setters["Claude Fable 5.1"], setters["GPT-6"]
print("agents", expect(*call("GET", "/v1/agents"), label="agents")["agents"][:2])

# 3. today (assembles from pool)
today = expect(*call("GET", "/v1/round/today", None, human), label="today")
print("today", today["date"], "tier", today["tier"], "machines", [(m["slot"], m["setter"], len(m["examples"])) for m in today["machines"]])
assert len(today["machines"]) == 2 and not today["finished"]

# 4. play both machines as the human
for m in today["machines"]:
    mid = m["id"]
    expect(*call("POST", f"/v1/machine/{mid}/note", {"text": "I think it is about colour"}, human), label="note")
    r1 = expect(*call("POST", f"/v1/machine/{mid}/experiment", {"seq": [0, 3, 6]}, human), label="exp1")
    assert r1["queries"][0].get("note") == "I think it is about colour", r1
    r2 = expect(*call("POST", f"/v1/machine/{mid}/experiment", {"seq": [1, 4, 7], "note": "second try"}, human), label="exp2")
    assert r2["remaining"] == 2
    st, res = call("POST", f"/v1/machine/{mid}/answer", {"answers": [True, False, True, False]}, human)
    assert st == 409, (st, res)
    tests = expect(*call("POST", f"/v1/machine/{mid}/tests", None, human), label="tests")["tests"]
    assert len(tests) == 4
    st, res = call("POST", f"/v1/machine/{mid}/experiment", {"seq": [2, 2, 2]}, human)
    assert st == 409, (st, res)
    ans = expect(*call("POST", f"/v1/machine/{mid}/answer", {"answers": [True, True, False, False]}, human), 201, "answer")
    print(" machine", m["slot"], "score", ans["score"], "rule:", ans["reveal"]["rule_text"], "| stats", ans["reveal"]["stats"])
    assert ans["reveal"]["stats"]["finished"] == 1
    # star with the true rule -> hit; wrong rule -> counterexample
    star = expect(*call("POST", f"/v1/machine/{mid}/star", {"rule": ans["reveal"]["rule"]}, human), 201, "star")
    assert star["hit"], star
    st, res = call("POST", f"/v1/machine/{mid}/star", {"rule": ans["reveal"]["rule"]}, human)
    assert st == 409
    rev = expect(*call("GET", f"/v1/machine/{mid}/reveal", None, human), label="reveal")
    assert rev["you"]["star"]["hit"] is True and rev["you"]["score"] == ans["score"]

today2 = expect(*call("GET", "/v1/round/today", None, human), label="today2")
assert today2["finished"] and today2["player_count"] == 1, today2["player_count"]

# 5. results / leaderboard / me
results = expect(*call("GET", f"/v1/round/{today['date']}/results", None, human), label="results")
print("results you", results["you"], "board", results["leaderboard"])
assert results["you"]["stars"] == 2
board = expect(*call("GET", "/v1/leaderboard?period=today"), label="board")
assert board["players"][0]["stars"] == 2
me = expect(*call("GET", "/v1/me", None, human), label="me")
print("me", {k: me[k] for k in ("rounds_played", "streak", "stars")}, me["rounds"][:1])
assert me["streak"] == 1
expect(*call("PUT", "/v1/me", {"nickname": "Smoke Tester"}, human), label="nickname")
st, res = call("PUT", "/v1/me", {"nickname": "House"}, human)
assert st == 400, (st, res)

# 6. setter upload for the next round date, rival investigates it
h = expect(*call("GET", "/health"), label="health")
nxt = rules.__dict__  # noqa
import datetime as dt
next_date = (dt.date.fromisoformat(h["date"]) + dt.timedelta(days=1)).isoformat()
tier = 3 if dt.date.fromisoformat(next_date).weekday() == 6 else (1 if dt.date.fromisoformat(next_date).weekday() <= 2 else 2)
machine = rules.pool(tier, count=1, seed=99)[0]
machine["note"] = "smoke intent"
up = expect(*call("POST", "/v1/setter/machines", {"for_date": next_date, "machine": machine}, claude), 201, "setter upload")
print("setter upload", up)
st, res = call("POST", "/v1/setter/machines", {"for_date": next_date, "machine": dict(machine, tier=(tier % 3) + 1)}, claude)
assert st == 400, (st, res)
pend = expect(*call("GET", f"/v1/setter/pending?date={next_date}", None, gpt), label="pending")
assert [p["id"] for p in pend["machines"]] == [up["machine_id"]], pend
own = expect(*call("GET", f"/v1/setter/pending?date={next_date}", None, claude), label="pending own")
assert own["machines"] == []
mid = up["machine_id"]
st, res = call("POST", f"/v1/machine/{mid}/experiment", {"seq": [0, 0, 0]}, human)
assert st == 403, (st, res)
expect(*call("POST", f"/v1/machine/{mid}/experiment", {"seq": [0, 0, 0], "note": "rival probe"}, gpt), label="rival exp")
expect(*call("POST", f"/v1/machine/{mid}/tests", None, gpt), label="rival tests")
ra = expect(*call("POST", f"/v1/machine/{mid}/answer", {"answers": [True, False, True, False]}, gpt), 201, "rival answer")
print("rival scored", ra["score"], "on pending machine; agents in reveal:", [a["name"] for a in ra["reveal"]["agents"]])
assert ra["reveal"]["stats"]["finished"] == 0  # agents do not count as humans

# 7. privacy deletion
d = expect(*call("DELETE", "/v1/me", None, human), label="delete")
print("delete", d["ok"])
st, res = call("GET", "/v1/me", None, human)
assert st == 200 and res["rounds_played"] == 0, (st, res)
print("SMOKE PASS")
