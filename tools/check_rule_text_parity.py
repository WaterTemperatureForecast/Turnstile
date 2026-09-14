#!/usr/bin/env python3
"""Prove the app words rules exactly like the server does.

The reveal shows the server's wording, but the rule builder previews the
player's own rule using RuleText in Components.swift. If the two drift, a
player sees one phrasing while building and another in the reveal. There is no
Swift compiler on this box, so this re-implements RuleText from the Swift
source's own logic and diffs it against worker/fixtures/rule_text.json, which
the server generated for all 3,000 rules.

    node worker/test/swift_parity.ts && python3 tools/check_rule_text_parity.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "engine"))
import rules  # noqa: E402

POS = ["", "first", "second", "third"]
NUM = ["no", "one", "two", "three"]


def things(attr, value, plural):
    one = f"{value} tile" if attr == "colour" else value
    return one + "s" if plural else one


def prop(ast, not_):
    op, attr, value = ast["op"], ast.get("attr"), ast.get("value")
    if op == "pos":
        where = f"the {POS[ast['i']]} tile is" + (" not" if not_ else "")
        return f"{where} {value}" if attr == "colour" else f"{where} a {value}"
    if op == "count":
        n = ast["n"]
        if not not_:
            if n == 0:
                return f"there are no {things(attr, value, True)}"
            if n == 3:
                return f"all three tiles are {value}" if attr == "colour" else f"all three tiles are {value}s"
            return f"there {'is' if n == 1 else 'are'} exactly {NUM[n]} {things(attr, value, n != 1)}"
        if n == 0:
            return f"there is at least one {things(attr, value, False)}"
        if n == 3:
            return f"the three tiles are not all {things(attr, value, True)}"
        return f"there {'is' if n == 1 else 'are'} not exactly {NUM[n]} {things(attr, value, n != 1)}"
    if op == "same":
        pair = f"the {POS[ast['i']]} and {POS[ast['j']]} tiles are"
        return f"{pair} different {attr}s" if not_ else f"{pair} the same {attr}"
    if op == "allsame":
        return f"the three tiles are not all the same {attr}" if not_ else f"all three tiles are the same {attr}"
    if op == "alldiff":
        return f"at least two tiles share a {attr}" if not_ else f"all three {attr}s are different"
    raise ValueError("not an atom: " + op)


def describe(ast):
    op = ast["op"]
    if op == "not":
        return prop(ast["a"], True)
    if op == "and":
        return prop(ast["a"], False) + " and " + prop(ast["b"], False)
    if op == "or":
        overlap = any(rules.evaluate(ast["a"], s) and rules.evaluate(ast["b"], s) for s in rules.INPUTS)
        return prop(ast["a"], False) + ", or " + prop(ast["b"], False) + (", or both" if overlap else "")
    if op == "xor":
        return prop(ast["a"], False) + ", or " + prop(ast["b"], False) + ", but not both"
    return prop(ast, False)


def swift_source_matches():
    """Cheap guard: the Swift file must still contain the phrases used here, so
    a silent edit to one side is caught."""
    src = open(os.path.join(ROOT, "Turnstile", "Components.swift"), encoding="utf-8").read()
    needed = ["there are no ", "there is at least one ", "the three tiles are not all ",
              "at least two tiles share a ", "all three \\(attr)s are different",
              ", or both", ", but not both", " and "]
    missing = [n for n in needed if n not in src]
    if missing:
        print("Components.swift no longer contains:", missing)
        return False
    return re.search(r"enum RuleText", src) is not None


expected = json.load(open(os.path.join(ROOT, "worker", "fixtures", "rule_text.json"), encoding="utf-8"))
bad = 0
for tier in rules.TIERS:
    for r in rules.enumerate_rules(tier):
        want = expected.get(r.id)
        got = describe(r.ast)
        if want is None:
            print("missing from the server dump:", r.id)
            bad += 1
        elif want != got:
            print(f"MISMATCH\n  server: {want}\n  app:    {got}")
            bad += 1
if not swift_source_matches():
    bad += 1
print(f"checked {len(expected)} rules; {bad} problems")
sys.exit(1 if bad else 0)
