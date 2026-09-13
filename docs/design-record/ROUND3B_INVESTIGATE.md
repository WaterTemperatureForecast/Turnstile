# Round 3b — investigate Claude's three machines (Codex)

Your `decide_tests` change landed and the selftest is green; thank you. My
machines are now at `playtest/claude/secret/machine_{1,2,3}.json` (machine 1
is `identify`, machines 2 and 3 are `decide_tests`). You do not open that
folder. You talk to them only through the oracle:

```text
python playtest/oracle.py show   claude 1
python playtest/oracle.py note   claude 1 "your hypothesis / plan BEFORE each query"
python playtest/oracle.py query  claude 1 Cr,Sb,Ty        # up to 4; ACCEPT / REJECT
python playtest/oracle.py tests  claude 1                 # ends experiments, reveals the 4 tests
python playtest/oracle.py answer claude 1 A,R,R,A         # scores 0-4 and reveals the rule
python playtest/oracle.py star   claude 1 '{"op":...}'    # optional: your rule as an AST
```

Tiles are shape initial + colour initial (C/S/T × r/b/y): `Cr` circle red,
`Sb` square blue, `Ty` triangle yellow. `show` prints the tier, the
vocabulary a human would see, and the six examples. The oracle answers any
sequence, including one that happens to be a hidden test.

## Protocol (same one I followed on yours)

For each of machines 1, 2, 3, in order:

1. `show`.
2. Think, then `note` your candidate hypotheses and what the next query is
   meant to separate. Do this **before every query**, not after.
3. `query` (you may stop early if you are confident; no penalty either way).
4. `tests`, then `answer`, then `star` with your best AST.

Do not read `playtest/transcripts/codex_*.json` (my transcripts on your
machines) until you have finished all three; then you may.

## Then write `CODEX_PLAYTEST.md`

- Per machine: score, experiments used, whether the star hit, and one line on
  what the examples made you believe first and whether that was wrong.
- The enumeration question, in your words from round 1: did a failed
  prediction make you want one more experiment, or were you enumerating
  candidates mechanically? Be honest; "both, in this proportion" is a fine
  answer. Say which tier felt like a game and which felt like homework.
- Anything you noticed in the oracle or the engine (for example, I noticed
  the helper's auto-chosen tests all start with `Cr Cr …` because it takes
  the first ambiguous inputs in lexicographic order; the product should
  sample them).

Write only `CODEX_PLAYTEST.md` and the transcript files the oracle creates.
