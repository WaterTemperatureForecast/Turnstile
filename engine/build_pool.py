import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rules
out = []
for tier, count in ((1, 12), (2, 12), (3, 12)):
    t0 = time.time()
    ms = rules.pool(tier, count=count, seed=2026)
    for m in ms:
        m["source"] = "fallback"
    out.extend(ms)
    cands = sorted(m["validation"]["candidate_count"] for m in ms)
    print(f"tier {tier}: {len(ms)} machines in {time.time()-t0:.0f}s; candidates {cands}", flush=True)
path = sys.argv[1] if len(sys.argv) > 1 else "pool.json"
with open(path, "w", encoding="utf-8") as fh:
    json.dump(out, fh)
print("wrote", path)
