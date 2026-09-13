#!/usr/bin/env python3
"""Turnstile playtest oracle. The only program that reads secret machines.

Secrets:     playtest/<author>/secret/machine_<n>.json   (author = claude | codex)
Transcripts: playtest/transcripts/<author>_<n>.json      (investigator = the other one)

  python playtest/oracle.py show   codex 1                # tier, vocabulary, six examples
  python playtest/oracle.py note   codex 1 "hypothesis"   # record thinking BEFORE a query
  python playtest/oracle.py query  codex 1 Cr,Sb,Ty       # experiment (4 max) -> ACCEPT / REJECT
  python playtest/oracle.py tests  codex 1                # end experiments, reveal the 4 tests
  python playtest/oracle.py answer codex 1 A,R,R,A        # classify the tests -> score 0-4 + rule
  python playtest/oracle.py star   codex 1 '{"op":...}'   # optional rule guess (extension match)
  python playtest/oracle.py report codex 1                # print the transcript

Tiles: shape initial + colour initial, e.g. Cr = circle red, Sb = square blue,
Ty = triangle yellow (C/S/T x r/b/y). Integers 0-8 are accepted too.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "engine"))
import rules  # noqa: E402

SHAPE_CODE = {"C": "circle", "S": "square", "T": "triangle"}
COLOUR_CODE = {"r": "red", "b": "blue", "y": "yellow"}
BUDGET = 4

VOCAB = {
    1: "Today's rule is ONE property, or NOT one property.",
    2: "Today's rule is one property, NOT one property, or two properties joined by AND or OR.",
    3: "Today's rule is one property, NOT one property, or two properties joined by AND, OR, or XOR (exactly one of the two).",
}
PROPERTIES = (
    "Properties a rule can use:\n"
    "  - position: the tile in position 1, 2 or 3 has a given shape or colour\n"
    "  - count: exactly N tiles (0-3) have a given shape or colour\n"
    "  - match: two given positions share their shape (or their colour)\n"
    "  - all same / all different: the three shapes (or colours) are all the same / all different\n"
    "Tiles: circle, square, triangle  x  red, blue, yellow.  A sequence is three tiles, repeats allowed."
)


def tile_code(t):
    return "CST"[t // 3] + "rby"[t % 3]


def seq_str(seq):
    return " ".join(tile_code(t) for t in seq)


def parse_seq(text):
    parts = [p for p in text.replace(",", " ").split() if p]
    if len(parts) != 3:
        raise SystemExit("a sequence is three tiles, e.g. Cr,Sb,Ty")
    out = []
    for p in parts:
        if p.isdigit():
            out.append(int(p))
        elif len(p) == 2 and p[0].upper() in SHAPE_CODE and p[1].lower() in COLOUR_CODE:
            out.append("CST".index(p[0].upper()) * 3 + "rby".index(p[1].lower()))
        else:
            raise SystemExit(f"bad tile {p!r}: use Cr/Sb/Ty style or 0-8")
    return out


def describe(ast):
    """English rendering of a canonical AST (used by the reveal)."""
    op = ast["op"]
    pos = {1: "first", 2: "second", 3: "third"}
    if op == "pos":
        return f"the {pos[ast['i']]} tile is {ast['value']}" if ast["attr"] == "colour" else f"the {pos[ast['i']]} tile is a {ast['value']}"
    if op == "count":
        n, v = ast["n"], ast["value"]
        noun = v if ast["attr"] == "colour" else v + ("s" if n != 1 else "")
        if ast["attr"] == "colour":
            return f"exactly {n} tile{'s' if n != 1 else ''} {'are' if n != 1 else 'is'} {noun}"
        return f"there {'are' if n != 1 else 'is'} exactly {n} {noun}"
    if op == "same":
        return f"the {pos[ast['i']]} and {pos[ast['j']]} tiles have the same {ast['attr']}"
    if op == "allsame":
        return f"all three tiles have the same {ast['attr']}"
    if op == "alldiff":
        return f"all three {ast['attr']}s are different"
    if op == "not":
        return "NOT (" + describe(ast["a"]) + ")"
    joiner = {"and": " AND ", "or": " OR ", "xor": " XOR "}[op]
    return "(" + describe(ast["a"]) + ")" + joiner + "(" + describe(ast["b"]) + ")"


def secret_path(author, n):
    return os.path.join(HERE, author, "secret", f"machine_{n}.json")


def transcript_path(author, n):
    return os.path.join(HERE, "transcripts", f"{author}_{n}.json")


def load_secret(author, n):
    with open(secret_path(author, n), encoding="utf-8-sig") as fh:
        m = json.load(fh)
    rules.validate(m)  # never trust a tampered secret
    return m


def load_transcript(author, n):
    p = transcript_path(author, n)
    if os.path.exists(p):
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    return {"author": author, "machine": n, "investigator": "codex" if author == "claude" else "claude",
            "phase": "experiments", "events": [], "queries": [], "answers": None, "score": None, "star": None}


def save_transcript(t):
    os.makedirs(os.path.dirname(transcript_path(t["author"], t["machine"])), exist_ok=True)
    with open(transcript_path(t["author"], t["machine"]), "w", encoding="utf-8") as fh:
        json.dump(t, fh, indent=2)


def cmd_show(author, n):
    m = load_secret(author, n)
    t = load_transcript(author, n)
    save_transcript(t)
    print(f"Machine {author}/{n}  tier {m['tier']}")
    print(VOCAB[m["tier"]])
    print(PROPERTIES)
    print("\nExamples:")
    for ex in m["examples"]:
        print(f"  {seq_str(ex['seq']):<12} {'ACCEPT' if ex['accepted'] else 'REJECT'}")
    print(f"\nExperiments used: {len(t['queries'])}/{BUDGET}   phase: {t['phase']}")
    for q in t["queries"]:
        print(f"  {seq_str(q['seq']):<12} {'ACCEPT' if q['accepted'] else 'REJECT'}")


def cmd_note(author, n, text):
    t = load_transcript(author, n)
    t["events"].append({"note": text, "after_queries": len(t["queries"])})
    save_transcript(t)
    print("noted.")


def cmd_query(author, n, text):
    m = load_secret(author, n)
    t = load_transcript(author, n)
    if t["phase"] != "experiments":
        raise SystemExit("experiments are over for this machine")
    if len(t["queries"]) >= BUDGET:
        raise SystemExit("no experiments left; run `tests`")
    seq = parse_seq(text)
    accepted = rules.evaluate(m["rule"], seq)
    t["queries"].append({"seq": seq, "accepted": accepted})
    t["events"].append({"query": seq, "accepted": accepted})
    save_transcript(t)
    print(f"{seq_str(seq)} -> {'ACCEPT' if accepted else 'REJECT'}   ({len(t['queries'])}/{BUDGET} used)")


def cmd_tests(author, n):
    m = load_secret(author, n)
    t = load_transcript(author, n)
    if t["phase"] == "experiments":
        t["phase"] = "tests"
        t["events"].append({"tests_revealed_after_queries": len(t["queries"])})
        save_transcript(t)
    print("Classify these four (A = accept, R = reject), in order:")
    for i, s in enumerate(m["tests"], 1):
        print(f"  {i}. {seq_str(s)}")


def cmd_answer(author, n, text):
    m = load_secret(author, n)
    t = load_transcript(author, n)
    if t["phase"] == "experiments":
        raise SystemExit("run `tests` first")
    if t["answers"] is not None:
        raise SystemExit("already answered")
    letters = [c.strip().upper() for c in text.replace(",", " ").split()]
    if len(letters) != 4 or any(c not in ("A", "R") for c in letters):
        raise SystemExit("answer with four letters A/R, e.g. A,R,R,A")
    truth = [rules.evaluate(m["rule"], s) for s in m["tests"]]
    guesses = [c == "A" for c in letters]
    score = sum(g == tr for g, tr in zip(guesses, truth))
    t["answers"], t["score"], t["phase"] = guesses, score, "answered"
    t["events"].append({"answers": letters, "score": score})
    save_transcript(t)
    print(f"Score {score}/4  (experiments used: {len(t['queries'])})")
    for s, g, tr in zip(m["tests"], guesses, truth):
        mark = "ok " if g == tr else "XX "
        print(f"  {mark}{seq_str(s):<12} you: {'A' if g else 'R'}  truth: {'A' if tr else 'R'}")
    print(f"\nThe rule was: {describe(m['rule'])}")
    print(f"Candidates consistent with the six examples: {m['validation']['candidate_count']}")


def cmd_star(author, n, text):
    m = load_secret(author, n)
    t = load_transcript(author, n)
    if t["phase"] != "answered":
        raise SystemExit("answer the tests first")
    ast = json.loads(text)
    hit = rules.equivalent(ast, m["rule"])
    t["star"] = {"ast": ast, "hit": hit}
    t["events"].append({"star": ast, "hit": hit})
    save_transcript(t)
    if hit:
        print("STAR: your rule matches the machine on all 729 inputs.")
    else:
        for seq in rules.INPUTS:
            if rules.evaluate(ast, seq) != rules.evaluate(m["rule"], seq):
                print(f"no star. Counterexample: {seq_str(seq)} -> machine {'ACCEPT' if rules.evaluate(m['rule'], seq) else 'REJECT'}, yours {'ACCEPT' if rules.evaluate(ast, seq) else 'REJECT'}")
                break


def cmd_report(author, n):
    t = load_transcript(author, n)
    print(json.dumps(t, indent=2))


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    cmd, author, n = sys.argv[1], sys.argv[2], sys.argv[3]
    if author not in ("claude", "codex") or n not in ("1", "2", "3"):
        raise SystemExit("author must be claude|codex and machine 1|2|3")
    rest = " ".join(sys.argv[4:])
    if cmd == "show":
        cmd_show(author, n)
    elif cmd == "note":
        cmd_note(author, n, rest)
    elif cmd == "query":
        cmd_query(author, n, rest)
    elif cmd == "tests":
        cmd_tests(author, n)
    elif cmd == "answer":
        cmd_answer(author, n, rest)
    elif cmd == "star":
        cmd_star(author, n, rest)
    elif cmd == "report":
        cmd_report(author, n)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
