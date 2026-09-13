#!/usr/bin/env python3
"""Print non-secret validation stats for an author's machines (tier, live
candidates, worst-case queries, certificate). Never prints rules or examples."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "engine"))
import rules  # noqa: E402


def depth(node, d=0):
    if node is None or "query" not in node:
        return d
    return max(depth(node["reject"], d + 1), depth(node["accept"], d + 1))


author = sys.argv[1]
for n in (1, 2, 3):
    p = os.path.join(HERE, author, "secret", f"machine_{n}.json")
    if not os.path.exists(p):
        print(f"{author}/{n}: missing")
        continue
    with open(p, encoding="utf-8-sig") as fh:
        m = json.load(fh)
    try:
        v = rules.validate(m)
        status = "VALID"
        cand = v["validation"]["candidate_count"]
        worst = depth(v["validation"]["strategy"])
    except ValueError as e:
        status, cand, worst = f"INVALID ({e})", m.get("validation", {}).get("candidate_count"), depth(m.get("validation", {}).get("strategy"))
    print(f"{author}/{n}: tier {m.get('tier')} certificate={m.get('certificate', 'identify')} "
          f"candidates={cand} worst_case_queries={worst} {status}")
