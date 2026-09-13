#!/usr/bin/env python3
"""House constructor: build tomorrow's machine for one house setter.

    python house_construct.py claude     # rule + decoy chosen by `claude -p`
    python house_construct.py gpt        # rule + decoy chosen by `codex exec`

The model chooses the secret rule, the wrong hypothesis (decoy) it wants the
examples to invite, and a one-line note. This script does the fairness work:
it searches for balanced examples that keep the decoy alive and pass the
engine's decide_tests certificate, then uploads the machine for the next round
date. If the model or the search fails, a fallback machine from
rules.pool() is uploaded instead, so the round never lacks a machine.
Scheduled at 06:30Z (see install_house_agents.ps1); rounds open at 08:00Z.
"""
import datetime as dt
import json
import random
import sys

from common import BRAINS, GRAMMAR_TEXT, TIER_FORMS, ask, call, describe, first_json_object, log, read_token, rules, seq_words


def next_round_date(token):
    st, h = call("GET", "/health")
    if st != 200:
        sys.exit(f"health failed: {h}")
    return (dt.date.fromisoformat(h["date"]) + dt.timedelta(days=1)).isoformat()


def tier_for(date):
    wd = dt.date.fromisoformat(date).weekday()  # Mon=0 .. Sun=6
    return 3 if wd == 6 else (1 if wd <= 2 else 2)


def build_prompt(tier, date, feedback):
    n = rules.EXAMPLES_PER_TIER[tier]
    return f"""You are the constructor for Turnstile, a daily rule-induction game (like Zendo/Eleusis) played by
humans and AI models. A machine accepts some three-tile sequences and rejects others according to a secret
rule. Players see {n} labelled examples ({n // 2} accepted, {n // 2} rejected), may run up to four experiments
(they submit a sequence and learn accept/reject), then classify four hidden sequences. Your job today is to
design the machine for {date} ({TIER_FORMS[tier]}). The rival AI will try to crack it blind before publication,
and hundreds of humans after. A good machine is one whose examples invite a plausible WRONG hypothesis (the
decoy) that a careful experimenter can still rule out; a machine that is trivially obvious or effectively
unguessable is a bad one. Fairness is enforced by code: a program will pick examples that keep your decoy
alive and verify that the hidden tests are decidable in four experiments, so you do not choose the examples.

{GRAMMAR_TEXT}

Reply with ONLY a JSON object:
{{"rule": <rule AST in the tier's allowed form>,
  "decoy": <a DIFFERENT rule AST, the wrong hypothesis you want the examples to suggest; it must differ from the rule on some inputs but agree with it on many>,
  "note": "<one sentence, shown to players after they finish, about the trap you set>"}}
{feedback}"""


def craft(tier, rule_ast, decoy_ast, seed=0, samples=3000, max_candidates=None):
    """Random search for balanced examples that keep the decoy alive, then the
    largest candidate set that passes the decide_tests certificate."""
    rmask, dmask = rules.extension(rule_ast), rules.extension(decoy_ast)
    by_mask = {r.mask: r for r in rules.enumerate_rules(tier)}
    if rmask not in by_mask:
        raise ValueError("rule is not an eligible rule of this tier (lopsided or wrong form)")
    if rmask == dmask:
        raise ValueError("decoy is the same rule as the secret rule")
    rid = by_mask[rmask].id
    half = rules.EXAMPLES_PER_TIER[tier] // 2
    agree_yes = [i for i in range(729) if (rmask >> i & 1) and (dmask >> i & 1)]
    agree_no = [i for i in range(729) if not (rmask >> i & 1) and not (dmask >> i & 1)]
    if len(agree_yes) < half or len(agree_no) < half:
        raise ValueError("decoy agrees with the rule on too few inputs")
    cols = rules.columns(tier)
    n_rules = len(rules.enumerate_rules(tier))
    hi = max_candidates or (16 if tier == 1 else 40)
    rng = random.Random(seed)
    scored, seen = [], set()
    for _ in range(samples):
        ys, ns = rng.sample(agree_yes, half), rng.sample(agree_no, half)
        key = tuple(sorted(ys)) + tuple(sorted(ns))
        if key in seen:
            continue
        seen.add(key)
        state = (1 << n_rules) - 1
        for i in ys:
            state &= cols[i]
        for i in ns:
            state &= ~cols[i]
        c = state.bit_count()
        if 3 <= c <= hi:
            scored.append((c, ys, ns))
    scored.sort(key=lambda x: -x[0])
    for c, ys, ns in scored[:300]:
        examples = [{"seq": list(rules.INPUTS[i]), "accepted": True} for i in ys] + \
                   [{"seq": list(rules.INPUTS[i]), "accepted": False} for i in ns]
        rng.shuffle(examples)
        try:
            return rules.construct(tier, rid, examples, certificate="decide_tests")
        except ValueError:
            continue
    raise ValueError("no fair example set keeps that decoy alive; pick a decoy closer to the rule")


def main():
    brain = sys.argv[1] if len(sys.argv) > 1 else ""
    if brain not in BRAINS:
        sys.exit("usage: house_construct.py claude|gpt")
    token = read_token(brain)
    date = next_round_date(token)
    tier = tier_for(date)
    machine, feedback = None, ""
    for attempt in range(3):
        reply = ask(brain, build_prompt(tier, date, feedback))
        try:
            obj = first_json_object(reply)
            rule_ast, decoy_ast = obj["rule"], obj["decoy"]
            rules.check_ast(rule_ast)
            rules.check_ast(decoy_ast)
            m = craft(tier, rule_ast, decoy_ast, seed=attempt)
            m["note"] = str(obj.get("note", "")).strip()[:200]
            machine = m
            log(f"{brain}: {date} tier {tier}: rule '{describe(m['rule'])}', decoy '{describe(decoy_ast)}', "
                f"{m['validation']['candidate_count']} candidates")
            break
        except (ValueError, KeyError, TypeError) as e:
            feedback = f"\nYour previous answer failed validation: {e}. Try again with a different rule or decoy."
            log(f"{brain}: attempt {attempt + 1} failed: {e}")
    if machine is None:
        machine = rules.pool(tier, count=1, seed=int(date.replace("-", "")) + len(brain))[0]
        machine["note"] = "Fallback machine: the constructor was unavailable today."
        log(f"{brain}: using a fallback machine")
    st, res = call("POST", "/v1/setter/machines", {"for_date": date, "machine": machine}, token=token)
    if st != 201:
        sys.exit(f"upload failed ({st}): {res}")
    log(f"{brain}: uploaded {res['machine_id']} for {date}: {res['rule_text']}")
    for ex in machine["examples"]:
        log(f"   {seq_words(ex['seq'])}: {'accept' if ex['accepted'] else 'reject'}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        log(f"house constructor failed: {e}")
        sys.exit(1)
