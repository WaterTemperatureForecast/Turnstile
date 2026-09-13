"""Turnstile reference engine (stdlib only). See CODEX_ROUND2.md for the spec.

CLI: python engine/rules.py selftest
     python engine/rules.py list 1
     python engine/rules.py generate 2 --seed 7
     python engine/rules.py validate machine.json
Import construct(tier, rule_id, examples, tests=None, certificate="identify")
for authored examples. Certificates are "identify" or "decide_tests".
Sequence JSON: three tile integers, shape-major: circle red=0, circle blue=1,
circle yellow=2, square red=3, ..., triangle yellow=8. Positions are 1-based.
Machine JSON contains secrets; never give the whole document to investigators.
"""

import argparse
from dataclasses import dataclass
from functools import lru_cache
import hashlib
import itertools
import json
import random

SHAPES = ("circle", "square", "triangle")
COLOURS = ("red", "blue", "yellow")
VALUES = {"shape": SHAPES, "colour": COLOURS}
INPUTS = tuple(itertools.product(range(9), repeat=3))
FULL = (1 << len(INPUTS)) - 1
TIERS = (1, 2, 3)
EXAMPLES_PER_TIER = {1: 4, 2: 6, 3: 6}
MIN_ACCEPT = 60
MAX_ACCEPT = 669
CERTIFICATES = ("identify", "decide_tests")


def sequence(value):
    if not isinstance(value, (list, tuple)) or len(value) != 3:
        raise ValueError("sequence must contain exactly three tile integers")
    if any(type(x) is not int or not 0 <= x < 9 for x in value):
        raise ValueError("tiles must be integers in 0..8")
    return tuple(value)


def input_id(seq):
    a, b, c = sequence(seq)
    return 81 * a + 9 * b + c


def check_ast(ast):
    """Validate interpreter syntax. Tier membership is checked by construct."""
    if type(ast) is not dict or type(ast.get("op")) is not str:
        raise ValueError("AST must be an object with a string op")
    op = ast["op"]
    fields = {
        "pos": {"op", "i", "attr", "value"},
        "count": {"op", "attr", "value", "n"},
        "same": {"op", "attr", "i", "j"},
        "allsame": {"op", "attr"}, "alldiff": {"op", "attr"},
        "not": {"op", "a"},
        "and": {"op", "a", "b"}, "or": {"op", "a", "b"},
        "xor": {"op", "a", "b"},
    }
    if op not in fields or set(ast) != fields[op]:
        raise ValueError("unknown op or incorrect AST fields")
    if op in ("not", "and", "or", "xor"):
        check_ast(ast["a"])
        if op != "not":
            check_ast(ast["b"])
        return
    attr = ast["attr"]
    if type(attr) is not str or attr not in VALUES:
        raise ValueError("attr must be shape or colour")
    if "value" in ast and ast["value"] not in VALUES[attr]:
        raise ValueError("unknown attribute value")
    for key in ("i", "j", "n"):
        if key in ast:
            lo, hi = (0, 3) if key == "n" else (1, 3)
            if type(ast[key]) is not int or not lo <= ast[key] <= hi:
                raise ValueError("invalid " + key)
    if op == "same" and ast["i"] >= ast["j"]:
        raise ValueError("same requires i < j")


def _eval(ast, seq):
    op = ast["op"]
    if op == "not":
        return not _eval(ast["a"], seq)
    if op in ("and", "or", "xor"):
        a, b = _eval(ast["a"], seq), _eval(ast["b"], seq)
        return (a and b) if op == "and" else ((a or b) if op == "or" else a != b)
    attr = ast["attr"]
    vals = [SHAPES[t // 3] if attr == "shape" else COLOURS[t % 3] for t in seq]
    if op == "pos":
        return vals[ast["i"] - 1] == ast["value"]
    if op == "count":
        return vals.count(ast["value"]) == ast["n"]
    if op == "same":
        return vals[ast["i"] - 1] == vals[ast["j"] - 1]
    return len(set(vals)) == (1 if op == "allsame" else 3)


def evaluate(ast, seq):
    check_ast(ast)
    return _eval(ast, sequence(seq))


def extension(ast):
    check_ast(ast)
    return sum(1 << i for i, seq in enumerate(INPUTS) if _eval(ast, seq))


def equivalent(a, b):
    """Optional rule star: compare all 729 answers, not AST spelling."""
    return extension(a) == extension(b)


def atoms():
    out = []
    for attr, values in VALUES.items():
        for value in values:
            out.extend({"op": "pos", "i": i, "attr": attr, "value": value}
                       for i in range(1, 4))
            out.extend({"op": "count", "attr": attr, "value": value, "n": n}
                       for n in range(4))
        out.extend({"op": "same", "attr": attr, "i": i, "j": j}
                   for i, j in itertools.combinations(range(1, 4), 2))
        out.extend({"op": op, "attr": attr} for op in ("allsame", "alldiff"))
    return out


@dataclass(frozen=True)
class Rule:
    id: str
    ast: dict
    mask: int


def rule_id(mask):
    return "r_" + hashlib.sha256(mask.to_bytes(92, "little")).hexdigest()


@lru_cache(maxsize=3)
def enumerate_rules(tier):
    """Cumulative tiers, simplest-first canonical ASTs; IDs depend on extension."""
    if type(tier) is not int or tier not in TIERS:
        raise ValueError("tier must be 1, 2, or 3")
    aa = [(a, extension(a)) for a in atoms()]
    unique = {}

    def add(ast, mask):
        if MIN_ACCEPT <= mask.bit_count() <= MAX_ACCEPT and mask not in unique:
            unique[mask] = Rule(rule_id(mask), ast, mask)

    for a, mask in aa:
        add(a, mask)
    for a, mask in aa:
        add({"op": "not", "a": a}, FULL ^ mask)
    if tier >= 2:
        for (a, am), (b, bm) in itertools.combinations(aa, 2):
            add({"op": "and", "a": a, "b": b}, am & bm)
            add({"op": "or", "a": a, "b": b}, am | bm)
    if tier >= 3:
        for (a, am), (b, bm) in itertools.combinations(aa, 2):
            add({"op": "xor", "a": a, "b": b}, am ^ bm)
    return tuple(unique.values())


@lru_cache(maxsize=3)
def columns(tier):
    """For each input, a bitset of the rules that accept it."""
    rules = enumerate_rules(tier)
    return tuple(sum(1 << j for j, rule in enumerate(rules) if rule.mask >> i & 1)
                 for i in range(729))


def labelled_examples(examples, tier=2):
    """Tier 1 shows four examples (2/2), tiers 2-3 show six (3/3). Measured
    reason (playtest 2026-09-13): six examples leave a single tier-1 candidate
    30% of the time, which makes the experiments pointless."""
    n = EXAMPLES_PER_TIER[tier]
    if not isinstance(examples, (list, tuple)) or len(examples) != n:
        raise ValueError(f"tier {tier} needs {n} examples")
    result = []
    for item in examples:
        if type(item) is not dict or set(item) != {"seq", "accepted"}:
            raise ValueError("example needs seq and accepted")
        if type(item["accepted"]) is not bool:
            raise ValueError("accepted must be a JSON boolean")
        result.append((input_id(item["seq"]), item["accepted"]))
    if len({i for i, _ in result}) != n or sum(v for _, v in result) != n // 2:
        raise ValueError(f"examples must be distinct, {n // 2} accepted and {n // 2} rejected")
    return result


def strategy(tier, candidates, forbidden=(), budget=4,
             certificate="identify", tests=()):
    """Greedy certificate: every branch identifies a rule or decides all tests.

    None is conservative rejection, not a proof that no strategy exists.
    This search never uses the secret rule or its test labels to choose a split.
    """
    if certificate not in CERTIFICATES:
        raise ValueError("certificate must be identify or decide_tests")
    cols, rules = columns(tier), enumerate_rules(tier)
    test_ids = tuple(input_id(s) for s in tests)
    excluded = set(forbidden) | set(test_ids)
    allowed = [i for i in range(729) if i not in excluded]

    @lru_cache(maxsize=None)
    def visit(state, remaining):
        size = state.bit_count()
        if not size:
            return None
        if certificate == "decide_tests":
            if all((state & cols[i]) in (0, state) for i in test_ids):
                return {"decided": True}
        elif size == 1:
            return {"rule_id": rules[state.bit_length() - 1].id}
        if remaining == 0 or (certificate == "identify" and size > 2 ** remaining):
            return None
        best = None
        for i in allowed:
            yes = state & cols[i]
            n = yes.bit_count()
            if 0 < n < size:
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
        return {"query": list(INPUTS[i]), "reject": left, "accept": right}

    return visit(candidates, budget)


def _context(tier, rid, examples):
    rules = enumerate_rules(tier)
    rule = next((r for r in rules if r.id == rid), None)
    if rule is None:
        raise ValueError("unknown rule id for tier")
    labels = labelled_examples(examples, tier)
    state = (1 << len(rules)) - 1
    for i, accepted in labels:
        if bool(rule.mask >> i & 1) != accepted:
            raise ValueError("example label contradicts secret rule")
        state &= columns(tier)[i] if accepted else ~columns(tier)[i]
    return rule, labels, state


def construct(tier, rule_id, examples, tests=None, certificate="identify"):
    """Validate chosen examples and explicit tests, or choose balanced tests.

    Returns private machine JSON plus a separately reproducible certificate.
    Raises ValueError on invalid or conservatively rejected constructions.
    """
    if certificate not in CERTIFICATES:
        raise ValueError("certificate must be identify or decide_tests")
    rule, labels, state = _context(tier, rule_id, examples)
    used = {i for i, _ in labels}
    ambiguous = [i for i, col in enumerate(columns(tier))
                 if i not in used and 0 < (state & col).bit_count() < state.bit_count()]
    if tests is None:
        yes = [i for i in ambiguous if rule.mask >> i & 1]
        no = [i for i in ambiguous if not rule.mask >> i & 1]
        if min(len(yes), len(no)) < 2:
            raise ValueError("not enough undecided balanced test items")
        # Sample the tests (the first undecided inputs all start "Cr Cr ...")
        # and shuffle so the order does not leak the answers; seeded by
        # private construction data so the choice is reproducible.
        rng = random.Random(rule.id + json.dumps(examples, sort_keys=True))
        tests = [list(INPUTS[i]) for i in rng.sample(yes, 2) + rng.sample(no, 2)]
        rng.shuffle(tests)
    if not isinstance(tests, (list, tuple)) or len(tests) != 4:
        raise ValueError("need four tests")
    ids = [input_id(s) for s in tests]
    if len(set(ids)) != 4 or used.intersection(ids):
        raise ValueError("tests must be distinct and disjoint from examples")
    if sum(bool(rule.mask >> i & 1) for i in ids) != 2:
        raise ValueError("tests must have two accepted and two rejected")
    if any(i not in ambiguous for i in ids):
        raise ValueError("every test must be undecided from examples alone")
    tree = strategy(tier, state, used | set(ids),
                    certificate=certificate, tests=tests)
    if tree is None:
        raise ValueError(f"no greedy four-query {certificate} certificate")
    # Round-trip copies prevent callers from modifying cached canonical ASTs.
    return json.loads(json.dumps({
        "version": 1, "tier": tier, "rule_id": rule.id, "rule": rule.ast,
        "examples": examples, "tests": tests, "certificate": certificate,
        "validation": {"candidate_count": state.bit_count(), "strategy": tree},
    }))


def validate(machine):
    """Recompute validation; never trust supplied validation metadata."""
    if type(machine) is not dict or type(machine.get("version")) is not int:
        raise ValueError("machine needs integer version")
    if machine["version"] != 1:
        raise ValueError("unsupported machine version")
    required = {"tier", "rule_id", "rule", "examples", "tests"}
    if not required <= machine.keys():
        raise ValueError("missing machine fields")
    canonical = construct(machine["tier"], machine["rule_id"],
                          machine["examples"], machine["tests"],
                          certificate=machine.get("certificate", "identify"))
    if machine["rule"] != canonical["rule"]:
        raise ValueError("machine must store the canonical AST for its rule id")
    return canonical


def generate(tier, seed=0, attempts=200, certificate="identify"):
    """Deterministic smoke-test generator; chooses informative balanced examples.

    Higher tiers use a rule newly introduced by that tier. Human constructors
    should use construct to supply examples designed around a wrong hypothesis.
    """
    if certificate not in CERTIFICATES:
        raise ValueError("certificate must be identify or decide_tests")
    rng = random.Random(seed)
    rules, cols = enumerate_rules(tier), columns(tier)
    earlier = {r.id for r in enumerate_rules(tier - 1)} if tier > 1 else set()
    choices = [r for r in rules if r.id not in earlier]
    rng.shuffle(choices)
    for rule in choices[:attempts]:
        state, examples, used = (1 << len(rules)) - 1, [], set()
        half = EXAMPLES_PER_TIER[tier] // 2
        quotas = {False: half, True: half}
        for _ in range(2 * half):
            options = []
            for i, col in enumerate(cols):
                accepted = bool(rule.mask >> i & 1)
                if i in used or not quotas[accepted]:
                    continue
                next_state = state & (col if accepted else ~col)
                # Preserve at least two hypotheses so the final test is live.
                if next_state.bit_count() >= 2:
                    options.append((next_state.bit_count(), i, next_state, accepted))
            if not options:
                break
            best = min(x[0] for x in options)
            _, i, state, accepted = rng.choice([x for x in options if x[0] == best])
            used.add(i)
            quotas[accepted] -= 1
            examples.append({"seq": list(INPUTS[i]), "accepted": accepted})
        try:
            return construct(tier, rule.id, examples, certificate=certificate)
        except ValueError:
            continue
    raise ValueError("generation exhausted; try another seed or more attempts")


def pool(tier, count=10, seed=0, certificate="decide_tests", lo=None, hi=None,
         attempts=20000):
    """Fallback machines for days a house constructor fails: random rules with
    random balanced examples, kept only when the surviving candidate count is in
    [lo, hi] and the certificate passes. Unlike generate(), examples are not
    chosen to be maximally informative, so the experiments matter."""
    if certificate not in CERTIFICATES:
        raise ValueError("certificate must be identify or decide_tests")
    lo = lo if lo is not None else (4 if tier == 1 else 8)
    hi = hi if hi is not None else (16 if tier == 1 else 40)
    rng = random.Random(seed)
    rules, cols = enumerate_rules(tier), columns(tier)
    earlier = {r.id for r in enumerate_rules(tier - 1)} if tier > 1 else set()
    choices = [r for r in rules if r.id not in earlier]
    half = EXAMPLES_PER_TIER[tier] // 2
    out, seen = [], set()
    for _ in range(attempts):
        if len(out) >= count:
            break
        rule = rng.choice(choices)
        if rule.id in seen:
            continue
        yes = [i for i in range(729) if rule.mask >> i & 1]
        no = [i for i in range(729) if not rule.mask >> i & 1]
        picks = [(i, True) for i in rng.sample(yes, half)] + [(i, False) for i in rng.sample(no, half)]
        rng.shuffle(picks)
        state = (1 << len(rules)) - 1
        for i, accepted in picks:
            state &= cols[i] if accepted else ~cols[i]
        if not lo <= state.bit_count() <= hi:
            continue
        examples = [{"seq": list(INPUTS[i]), "accepted": a} for i, a in picks]
        try:
            m = construct(tier, rule.id, examples, certificate=certificate)
        except ValueError:
            continue
        seen.add(rule.id)
        out.append(m)
    if len(out) < count:
        raise ValueError(f"only {len(out)} pool machines found; widen the band or raise attempts")
    return out


def selftest():
    """Exhaustive interpreter cross-check and independent certificate replay."""
    def require(condition, message):
        if not condition:
            raise AssertionError(message)

    def rejects(fn):
        try:
            fn()
        except ValueError:
            return
        raise AssertionError("invalid input was accepted")

    require(len(INPUTS) == len(set(INPUTS)) == 729, "input universe")
    require(len(atoms()) == 52, "atom count")
    require(evaluate({"op": "pos", "attr": "shape", "value": "square", "i": 2},
                     [0, 3, 8]), "shape encoding")
    require(evaluate({"op": "same", "attr": "colour", "i": 1, "j": 2},
                     [0, 3, 8]), "colour encoding")
    rejects(lambda: sequence([True, 0, 1]))
    rejects(lambda: evaluate({"op": "mystery"}, [0, 1, 2]))
    rejects(lambda: enumerate_rules(True))
    checked, previous = set(), set()
    for tier in TIERS:
        rules = enumerate_rules(tier)
        ids = {r.id for r in rules}
        require(previous <= ids, "tiers must be cumulative")
        require(len(ids) == len({r.mask for r in rules}) == len(rules), "dedup")
        for rule in rules:
            require(60 <= rule.mask.bit_count() <= 669, "balance filter")
            if rule.id not in checked:
                require(extension(rule.ast) == rule.mask, "interpreter/bitset mismatch")
                checked.add(rule.id)
        machine = generate(tier, seed=17)
        require(validate(json.loads(json.dumps(machine))) == machine, "JSON round trip")
        legacy = dict(machine)
        del legacy["certificate"]
        require(validate(legacy) == machine, "legacy certificate must identify")
        require(tier == 1 or machine["rule_id"] not in previous, "new tier form")
        _, labels, state = _context(tier, machine["rule_id"], machine["examples"])
        forbidden = {i for i, _ in labels} | {input_id(s) for s in machine["tests"]}
        worst = 0
        for j, candidate in enumerate(rules):
            if not state >> j & 1:
                continue
            node, seen = machine["validation"]["strategy"], set()
            while "query" in node:
                i = input_id(node["query"])
                require(i not in forbidden and i not in seen, "illegal query")
                seen.add(i)
                require(len(seen) <= 4, "query budget exceeded")
                node = node["accept" if evaluate(candidate.ast, INPUTS[i]) else "reject"]
            require(node["rule_id"] == candidate.id, "certificate fails a branch")
            worst = max(worst, len(seen))
        broken = json.loads(json.dumps(machine))
        broken["examples"][0]["accepted"] = not broken["examples"][0]["accepted"]
        rejects(lambda: validate(broken))
        rejects(lambda: construct(tier, machine["rule_id"], machine["examples"],
                                  [machine["tests"][0]] * 4))
        altered = json.loads(json.dumps(machine))
        altered["rule"] = {"op": "not", "a": altered["rule"]}
        rejects(lambda: validate(altered))
        require(strategy(tier, state, budget=0) is None, "unresolved zero budget")
        a = atoms()[0]
        require(equivalent(a, {"op": "not", "a": {"op": "not", "a": a}}),
                "extension star")
        print(f"tier {tier}: {len(rules)} distinct rules; generated machine VALID; "
              f"{state.bit_count()} candidates; worst-case {worst}/4 queries", flush=True)
        previous = ids
    # Exercise a larger tree separately from the easy generated smoke tests.
    rules = enumerate_rules(2)
    probe = sum(1 << j for j in range(8))
    tree = strategy(2, probe)
    require(tree is not None, "multi-branch certificate missing")
    for candidate in rules[:8]:
        node, depth = tree, 0
        while "query" in node:
            node = node["accept" if evaluate(candidate.ast, node["query"]) else "reject"]
            depth += 1
        require(depth <= 4 and node["rule_id"] == candidate.id,
                "multi-branch certificate failed")
    require(strategy(2, (1 << 17) - 1) is None, "information bound ignored")

    # A fixed authored fixture exceeds the singleton information bound, but
    # several rules can share a leaf when they agree on the four test answers.
    ast = {"op": "or", "a": {"op": "allsame", "attr": "shape"},
           "b": {"op": "same", "attr": "colour", "i": 2, "j": 3}}
    examples = [{"seq": seq, "accepted": accepted}
                for accepted, seqs in (
                    (True, [[3, 6, 0], [0, 8, 8], [3, 5, 5]]),
                    (False, [[5, 7, 6], [6, 0, 4], [6, 5, 0]]))
                for seq in seqs]
    tests = [[0, 0, 2], [0, 0, 4], [0, 0, 5], [0, 0, 1]]
    machine = construct(2, rule_id(extension(ast)), examples, tests,
                        certificate="decide_tests")
    require(validate(json.loads(json.dumps(machine))) == machine,
            "decide_tests JSON round trip")
    _, labels, state = _context(2, machine["rule_id"], examples)
    require(state.bit_count() >= 12, "decide_tests fixture too small")
    forbidden = {i for i, _ in labels} | {input_id(s) for s in tests}
    leaves, worst = {}, 0
    for j, candidate in enumerate(rules):
        if not state >> j & 1:
            continue
        node, seen, path = machine["validation"]["strategy"], set(), ()
        while "query" in node:
            i = input_id(node["query"])
            require(i not in forbidden and i not in seen, "illegal decide_tests query")
            seen.add(i)
            require(len(seen) <= 4, "decide_tests query budget exceeded")
            answer = evaluate(candidate.ast, INPUTS[i])
            path += (answer,)
            node = node["accept" if answer else "reject"]
        require(node == {"decided": True}, "incorrect decide_tests leaf")
        answers = tuple(evaluate(candidate.ast, test) for test in tests)
        if path in leaves:
            require(leaves[path] == answers, "leaf candidates disagree on tests")
        leaves[path] = answers
        worst = max(worst, len(seen))
    require(len(leaves) < state.bit_count(), "fixture must exercise shared leaves")
    require(strategy(2, state, forbidden, budget=0,
                     certificate="decide_tests", tests=tests) is None,
            "undecided tests accepted with zero budget")
    require(strategy(2, 0, certificate="decide_tests", tests=tests) is None,
            "empty candidate state accepted")
    rejects(lambda: construct(2, machine["rule_id"], examples, tests))
    legacy = dict(machine)
    del legacy["certificate"]
    rejects(lambda: validate(legacy))
    tampered = dict(machine, validation={"strategy": {"decided": True}})
    require(validate(tampered) == machine, "supplied metadata was trusted")
    for invalid in ("unknown", None, True, []):
        rejects(lambda: construct(2, machine["rule_id"], examples, tests,
                                  certificate=invalid))
        rejects(lambda: validate(dict(machine, certificate=invalid)))
        rejects(lambda: generate(2, certificate=invalid))
    print(f"tier 2 decide_tests: {state.bit_count()} candidates; "
          f"{len(leaves)} agreeing leaves; worst-case {worst}/4 queries", flush=True)
    print(f"PASS: {len(checked)} unique ASTs checked on all 729 inputs; "
          "four machine certificates replayed for every candidate.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("selftest")
    for name in ("list", "generate"):
        p = sub.add_parser(name)
        p.add_argument("tier", type=int, choices=TIERS)
        if name == "generate":
            p.add_argument("--seed", type=int, default=0)
            p.add_argument("--certificate", choices=CERTIFICATES, default="identify")
    p = sub.add_parser("validate")
    p.add_argument("file")
    p = sub.add_parser("pool")
    p.add_argument("tier", type=int, choices=TIERS)
    p.add_argument("--count", type=int, default=10)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--certificate", choices=CERTIFICATES, default="decide_tests")
    args = parser.parse_args()
    try:
        if args.command == "selftest":
            selftest()
            return
        if args.command == "list":
            result = [{"id": r.id, "rule": r.ast, "accepts": r.mask.bit_count()}
                      for r in enumerate_rules(args.tier)]
        elif args.command == "generate":
            result = generate(args.tier, args.seed, certificate=args.certificate)
        elif args.command == "pool":
            result = pool(args.tier, args.count, args.seed, certificate=args.certificate)
        else:
            with open(args.file, encoding="utf-8-sig") as handle:
                result = validate(json.load(handle))
        print(json.dumps(result, indent=2))
    except (ValueError, OSError) as exc:
        parser.exit(1, f"error: {exc}\n")


if __name__ == "__main__":
    main()
