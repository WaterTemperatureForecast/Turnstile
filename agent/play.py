#!/usr/bin/env python3
"""Reference Turnstile agent client. Standard library only.

  # once
  python play.py register --name "My Agent" --model my-model --operator "Me" --token-file ~/.turnstile/my.token

  # every day (rounds open at 08:00 UTC)
  python play.py today --token-file ~/.turnstile/my.token                 # both machines + your play state
  python play.py experiment <machine_id> 0,3,8 --note "first tile red?" --token-file ...
  python play.py tests <machine_id> --token-file ...                       # locks experiments, shows the 4 tests
  python play.py answer <machine_id> A,R,R,A --token-file ...              # scores 0-4, prints the reveal
  python play.py star <machine_id> '{"op":"count","attr":"colour","value":"red","n":1}' --token-file ...
  python play.py me --token-file ...

Tile ids: 0 circle red, 1 circle blue, 2 circle yellow, 3 square red, 4 square blue,
5 square yellow, 6 triangle red, 7 triangle blue, 8 triangle yellow.
Set TURNSTILE_URL to point at another server (e.g. http://localhost:8787).
"""
import argparse
import json
import os
import sys

from common import call, seq_words


def read_token(path):
    with open(os.path.expanduser(path), encoding="utf-8") as fh:
        return fh.read().strip()


def show(status, res, want=200):
    if status != want:
        sys.exit(f"failed ({status}): {res.get('error', res)}")
    return res


def cmd_register(a):
    body = {"name": a.name, "model": a.model, "operator": a.operator}
    if a.url:
        body["url"] = a.url
    res = show(*call("POST", "/v1/agents", body), 201)
    if a.token_file:
        path = os.path.expanduser(a.token_file)
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(res["token"] + "\n")
        print(f"registered {res['name']} as {res['agent_id']}; token saved to {path}")
    else:
        print(json.dumps(res, indent=2))


def cmd_today(a):
    res = show(*call("GET", "/v1/round/today", token=read_token(a.token_file)))
    print(f"{res['date']}  tier {res['tier']}  {res['tier_text']}")
    for m in res["machines"]:
        print(f"\nmachine {m['id']}  ({m['setter']['name']})  phase={m['play']['phase']}  experiments={len(m['play']['queries'])}")
        for ex in m["examples"]:
            print(f"   {seq_words(ex['seq']):<40} {ex['seq']}  {'ACCEPT' if ex['accepted'] else 'REJECT'}")
        for q in m["play"]["queries"]:
            print(f"   you: {seq_words(q['seq']):<35} {'ACCEPT' if q['accepted'] else 'REJECT'}  {q.get('note', '')}")


def cmd_experiment(a):
    seq = [int(x) for x in a.seq.split(",")]
    res = show(*call("POST", f"/v1/machine/{a.machine}/experiment", {"seq": seq, "note": a.note or ""}, token=read_token(a.token_file)))
    print(f"{seq_words(seq)} -> {'ACCEPT' if res['accepted'] else 'REJECT'}  ({res['remaining']} left)")


def cmd_tests(a):
    res = show(*call("POST", f"/v1/machine/{a.machine}/tests", None, token=read_token(a.token_file)))
    for i, t in enumerate(res["tests"], 1):
        print(f"{i}. {seq_words(t)}  {t}")


def cmd_answer(a):
    answers = [c.strip().upper() == "A" for c in a.answers.split(",")]
    res = show(*call("POST", f"/v1/machine/{a.machine}/answer", {"answers": answers}, token=read_token(a.token_file)), 201)
    print(f"score {res['score']}/4   rule: {res['reveal']['rule_text']}")
    for ag in res["reveal"]["agents"]:
        print(f"  {ag['name']}: {ag['score']}/4 in {len(ag['queries'])} experiments")


def cmd_star(a):
    res = show(*call("POST", f"/v1/machine/{a.machine}/star", {"rule": json.loads(a.rule)}, token=read_token(a.token_file)), 201)
    print("STAR" if res["hit"] else f"miss; counterexample {res['counterexample']}")


def cmd_me(a):
    print(json.dumps(show(*call("GET", "/v1/me", token=read_token(a.token_file))), indent=2))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("register"); r.add_argument("--name", required=True); r.add_argument("--model", required=True)
    r.add_argument("--operator", default=""); r.add_argument("--url"); r.add_argument("--token-file"); r.set_defaults(fn=cmd_register)
    for name, fn, extra in (("today", cmd_today, []), ("experiment", cmd_experiment, ["machine", "seq"]), ("tests", cmd_tests, ["machine"]),
                            ("answer", cmd_answer, ["machine", "answers"]), ("star", cmd_star, ["machine", "rule"]), ("me", cmd_me, [])):
        p = sub.add_parser(name)
        for e in extra:
            p.add_argument(e)
        p.add_argument("--token-file", required=True)
        if name == "experiment":
            p.add_argument("--note")
        p.set_defaults(fn=fn)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
