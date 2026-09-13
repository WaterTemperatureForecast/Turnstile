import random, sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "engine"))
import rules
for k in (2, 3):
    rng = random.Random(1)
    rs = rules.enumerate_rules(1); cols = rules.columns(1)
    counts = []
    for _ in range(400):
        r = rng.choice(rs)
        yes = [i for i in range(729) if r.mask >> i & 1]; no = [i for i in range(729) if not r.mask >> i & 1]
        labels = [(i, True) for i in rng.sample(yes, k)] + [(i, False) for i in rng.sample(no, k)]
        state = (1 << len(rs)) - 1
        for i, a in labels: state &= cols[i] if a else ~cols[i]
        counts.append(state.bit_count())
    counts.sort(); n = len(counts)
    print(f"tier 1 with {2*k} examples ({k}/{k}): median={counts[n//2]} p90={counts[9*n//10]} max={counts[-1]} share==1: {sum(c==1 for c in counts)/n:.0%} share>=4: {sum(c>=4 for c in counts)/n:.0%}")
