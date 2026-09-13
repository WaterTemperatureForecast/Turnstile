#!/usr/bin/env python3
"""Export every canonical rule of every tier with its 729-bit truth table, so
worker/test/crosscheck.ts can prove the TypeScript interpreter agrees with the
Python engine on all inputs.  python engine/export_fixtures.py worker/fixtures/rules.json"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rules  # noqa: E402

out = {"inputs": len(rules.INPUTS), "tiers": {}}
for tier in rules.TIERS:
    rs = rules.enumerate_rules(tier)
    out["tiers"][str(tier)] = [{"id": r.id, "ast": r.ast, "mask": format(r.mask, "x")} for r in rs]
    print(f"tier {tier}: {len(rs)} rules")
path = sys.argv[1] if len(sys.argv) > 1 else "rules.json"
with open(path, "w", encoding="utf-8") as fh:
    json.dump(out, fh, separators=(",", ":"))
print("wrote", path, os.path.getsize(path), "bytes")
