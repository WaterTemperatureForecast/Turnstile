#!/usr/bin/env python3
"""House investigator: play machines blind through the public API, one model
call per experiment, with a written hypothesis before every query.

    python house_investigate.py gpt --pending     # crack the rival's machine for the next round (setters only)
    python house_investigate.py claude --pending
    python house_investigate.py sonnet --today    # ordinary house player on today's round
    python house_investigate.py haiku --today

The secret rule is never in the model's context: it only sees what a human
sees (examples, its own experiments and their answers, then the tests).
Idempotent: a machine already answered is skipped; a half-played one resumes.
"""
import datetime as dt
import json
import sys

from common import BRAINS, GRAMMAR_TEXT, TIER_FORMS, ask, call, first_json_object, log, read_token, rules, seq_words

MAX_EXPERIMENTS = 4


def next_round_date():
    st, h = call("GET", "/health")
    if st != 200:
        sys.exit(f"health failed: {h}")
    return (dt.date.fromisoformat(h["date"]) + dt.timedelta(days=1)).isoformat()


def intro(tier):
    return f"""You are playing Turnstile, a daily rule-induction game. A machine accepts some three-tile sequences
and rejects others according to a secret rule. {TIER_FORMS[tier]} Vocabulary: position (tile 1/2/3 has a
shape or colour), count (exactly n tiles have a shape or colour), match (two positions share shape or colour),
all same / all different (shape or colour). You may run up to {MAX_EXPERIMENTS} experiments, then you must
classify four hidden sequences (accept/reject). No penalty for experiments; choose the one that best separates
your live hypotheses. Your notes are published after the round, so write what you actually think.

{GRAMMAR_TEXT}
"""


def state_text(examples, queries):
    lines = ["Examples:"]
    for ex in examples:
        lines.append(f"  {seq_words(ex['seq'])}  ({ex['seq']})  -> {'ACCEPT' if ex['accepted'] else 'REJECT'}")
    if queries:
        lines.append("Your experiments so far:")
        for q in queries:
            note = f"  [you wrote: {q['note']}]" if q.get("note") else ""
            lines.append(f"  {seq_words(q['seq'])}  ({q['seq']})  -> {'ACCEPT' if q['accepted'] else 'REJECT'}{note}")
    return "\n".join(lines)


def experiment_prompt(tier, examples, queries):
    left = MAX_EXPERIMENTS - len(queries)
    return (intro(tier) + "\n" + state_text(examples, queries) +
            f"\n\nYou have {left} experiment(s) left. Reply with ONLY a JSON object, either\n"
            '{"note": "<your current hypotheses and what this experiment separates>", "seq": [a, b, c]}\n'
            'to run an experiment (tile ids 0-8), or {"done": true, "note": "<why you are confident>"} to stop early.')


def answer_prompt(tier, examples, queries, tests):
    lines = [f"  {i + 1}. {seq_words(t)}  ({t})" for i, t in enumerate(tests)]
    return (intro(tier) + "\n" + state_text(examples, queries) +
            "\n\nExperiments are over. Classify these four sequences:\n" + "\n".join(lines) +
            '\n\nReply with ONLY a JSON object: {"answers": [true|false, true|false, true|false, true|false], '
            '"rule": <your best guess of the rule as an AST, or null>, "note": "<one line>"}. '
            "true = the machine accepts it.")


def play_machine(brain, token, m):
    mid, tier, examples = m["id"], m["tier"], m["examples"]
    play = m.get("play") or {}
    phase = play.get("phase", "experiments")
    if phase == "answered":
        log(f"{brain}: {mid} already answered")
        return
    queries = play.get("queries", []) if isinstance(play.get("queries"), list) else []
    while phase == "experiments" and len(queries) < MAX_EXPERIMENTS:
        obj = first_json_object(ask(brain, experiment_prompt(tier, examples, queries)))
        if obj.get("done"):
            log(f"{brain}: stopping early: {obj.get('note', '')}")
            break
        seq = rules.sequence(obj["seq"])
        note = str(obj.get("note", "")).strip()[:120]
        st, res = call("POST", f"/v1/machine/{mid}/experiment", {"seq": list(seq), "note": note}, token=token)
        if st != 200:
            sys.exit(f"experiment failed ({st}): {res}")
        queries = res["queries"]
        log(f"{brain}: {seq_words(seq)} -> {'ACCEPT' if res['accepted'] else 'REJECT'}  | {note}")
    st, res = call("POST", f"/v1/machine/{mid}/tests", None, token=token)
    if st != 200:
        sys.exit(f"tests failed ({st}): {res}")
    tests = res["tests"]
    obj = first_json_object(ask(brain, answer_prompt(tier, examples, queries, tests)))
    answers = [bool(a) for a in obj["answers"]]
    if len(answers) != 4:
        raise ValueError("need four answers")
    st, res = call("POST", f"/v1/machine/{mid}/answer", {"answers": answers}, token=token)
    if st != 201:
        sys.exit(f"answer failed ({st}): {res}")
    log(f"{brain}: scored {res['score']}/4 on {mid}; rule was: {res['reveal']['rule_text']}")
    guess = obj.get("rule")
    if isinstance(guess, dict):
        st, star = call("POST", f"/v1/machine/{mid}/star", {"rule": guess}, token=token)
        log(f"{brain}: star {'HIT' if st == 201 and star.get('hit') else 'miss'} ({star.get('your_rule_text', star.get('error'))})")


def main():
    brain = sys.argv[1] if len(sys.argv) > 1 else ""
    mode = sys.argv[2] if len(sys.argv) > 2 else "--today"
    if brain not in BRAINS or mode not in ("--pending", "--today"):
        sys.exit("usage: house_investigate.py <brain> --pending|--today")
    token = read_token(brain)
    if mode == "--pending":
        date = next_round_date()
        st, res = call("GET", f"/v1/setter/pending?date={date}", token=token)
        if st != 200:
            sys.exit(f"pending failed ({st}): {res}")
        machines = res["machines"]
        if not machines:
            log(f"{brain}: nothing pending for {date}")
            return
    else:
        st, res = call("GET", "/v1/round/today", token=token)
        if st != 200:
            sys.exit(f"today failed ({st}): {res}")
        machines = res["machines"]
    for m in machines:
        play_machine(brain, token, m)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        log(f"house investigator failed: {e}")
        sys.exit(1)
