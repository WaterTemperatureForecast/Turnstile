#!/usr/bin/env python3
"""Certificate strictness analysis (shared, no secrets).

  python playtest/analysis.py dist 2            # candidates left by 6 random examples
  python playtest/analysis.py greedy 2 '<rule>' '<herring>' [--restarts 40]
     greedy example choice that keeps the herring alive; reports best candidate
     count, whether the singleton certificate passes, and whether the weaker
     "tests decided" certificate passes.
"""
import argparse
import json
import os
import random
import sys
from functools import lru_cache

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "engine"))
sys.path.insert(0, HERE)
import rules  # noqa: E402
from oracle import describe, seq_str  # noqa: E402


def strategy_tests(tier, candidates, tests, forbidden=(), budget=4):
    """Weaker certificate: after <= budget queries (never on tests/examples),
    every surviving candidate agrees on every test item. Greedy split."""
    cols = rules.columns(tier)
    allowed = [i for i in range(729) if i not in set(forbidden)]
    tests = list(tests)

    def decided(state):
        return all((state & cols[i]) == 0 or (state & cols[i]) == state for i in tests)

    @lru_cache(maxsize=None)
    def visit(state, remaining):
        if decided(state):
            return {"decided": True}
        if remaining == 0:
            return None
        size = state.bit_count()
        best = None
        for i in allowed:
            yes = state & cols[i]
            n = yes.bit_count()
            if 0 < n < size:
                # prefer the split that leaves the fewest undecided tests on the worse side
                key = (max(n, size - n), i)
                if best is None or key < best[0]:
                    best = (key, i, yes)
        if best is None:
            return None
        _, i, yes = best
        no = state ^ yes
        left, right = visit(no, remaining - 1), visit(yes, remaining - 1)
        if left is None or right is None:
            return None
        return {"query": list(rules.INPUTS[i]), "reject": left, "accept": right}

    return visit(candidates, budget)


def depth(node, d=0):
    if node is None or "query" not in node:
        return d
    return max(depth(node["reject"], d + 1), depth(node["accept"], d + 1))


def state_after(tier, labels):
    cols = rules.columns(tier)
    state = (1 << len(rules.enumerate_rules(tier))) - 1
    for i, acc in labels:
        state &= cols[i] if acc else ~cols[i]
    return state


def cmd_dist(tier, samples=300, seed=0):
    rng = random.Random(seed)
    rs = rules.enumerate_rules(tier)
    counts = []
    for _ in range(samples):
        r = rng.choice(rs)
        yes = [i for i in range(729) if r.mask >> i & 1]
        no = [i for i in range(729) if not r.mask >> i & 1]
        labels = [(i, True) for i in rng.sample(yes, 3)] + [(i, False) for i in rng.sample(no, 3)]
        counts.append(state_after(tier, labels).bit_count())
    counts.sort()
    n = len(counts)
    print(f"tier {tier}: {len(rs)} rules; after 6 random examples candidates min={counts[0]} "
          f"p10={counts[n//10]} median={counts[n//2]} p90={counts[9*n//10]} max={counts[-1]}; "
          f"share <=16: {sum(c <= 16 for c in counts)/n:.1%}")


def cmd_greedy(tier, rule_ast, herring_ast, restarts=40, seed=0, budget=4):
    rmask, hmask = rules.extension(rule_ast), rules.extension(herring_ast)
    by_mask = {r.mask: r for r in rules.enumerate_rules(tier)}
    if rmask not in by_mask:
        sys.exit("rule not eligible in tier")
    rid = by_mask[rmask].id
    cols = rules.columns(tier)
    pool_yes = [i for i in range(729) if (rmask >> i & 1) and (hmask >> i & 1)]
    pool_no = [i for i in range(729) if not (rmask >> i & 1) and not (hmask >> i & 1)]
    rng = random.Random(seed)
    best = None
    for _ in range(restarts):
        labels, state = [], (1 << len(by_mask)) - 1
        quotas = {True: 3, False: 3}
        for _ in range(6):
            opts = []
            for acc, pool in ((True, pool_yes), (False, pool_no)):
                if not quotas[acc]:
                    continue
                for i in pool:
                    if any(i == j for j, _ in labels):
                        continue
                    ns = state & (cols[i] if acc else ~cols[i])
                    opts.append((ns.bit_count(), rng.random(), i, acc, ns))
            opts.sort()
            # random among the top few to diversify restarts
            c, _, i, acc, ns = rng.choice(opts[:6])
            labels.append((i, acc))
            quotas[acc] -= 1
            state = ns
        if best is None or state.bit_count() < best[0]:
            best = (state.bit_count(), labels, state)
    count, labels, state = best
    print(f"rule: {describe(rule_ast)}\nherring: {describe(herring_ast)}")
    print(f"greedy best (herring alive): {count} candidates after 6 examples")
    examples = [{"seq": list(rules.INPUTS[i]), "accepted": a} for i, a in labels]
    try:
        m = rules.construct(tier, rid, examples)
        print(f"singleton certificate: PASS, worst-case {depth(m['validation']['strategy'])} queries")
    except ValueError as e:
        print(f"singleton certificate: FAIL ({e})")
        m = None
    # weaker certificate: choose tests as construct would (first 2 ambiguous yes / no), then check
    used = {i for i, _ in labels}
    ambiguous = [i for i in range(729) if i not in used and 0 < (state & cols[i]).bit_count() < state.bit_count()]
    yes = [i for i in ambiguous if rmask >> i & 1][:2]
    no = [i for i in ambiguous if not rmask >> i & 1][:2]
    tests = yes + no
    tree = strategy_tests(tier, state, tests, used | set(tests), budget)
    print(f"tests-decided certificate: {'PASS, worst-case %d queries' % depth(tree) if tree else 'FAIL'}")
    for i, a in labels:
        print(f"  {seq_str(rules.INPUTS[i]):<12} {'ACCEPT' if a else 'REJECT'}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("dist"); d.add_argument("tier", type=int); d.add_argument("--samples", type=int, default=300)
    g = sub.add_parser("greedy"); g.add_argument("tier", type=int); g.add_argument("rule"); g.add_argument("herring")
    g.add_argument("--restarts", type=int, default=40); g.add_argument("--seed", type=int, default=0); g.add_argument("--budget", type=int, default=4)
    a = ap.parse_args()
    if a.cmd == "dist":
        cmd_dist(a.tier, a.samples)
    else:
        cmd_greedy(a.tier, json.loads(a.rule), json.loads(a.herring), a.restarts, a.seed, a.budget)


if __name__ == "__main__":
    main()
