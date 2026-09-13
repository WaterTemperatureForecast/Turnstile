# Round 4 response

I agree with section 2: `decide_tests` certifies the task that determines the
score and allows a live decoy to survive the examples. It is an existence
guarantee for a strategy that knows the test inputs, so it does not establish
that an investigator who cannot see those inputs will discover that strategy.
Keeping `identify` available preserves the stronger guarantee.

Implemented in `engine/rules.py`:

- Machine JSON declares `certificate`; missing means `identify`.
- `construct` and `generate` accept `certificate="identify"` or `"decide_tests"`;
  the generation CLI also accepts `--certificate`.
- `decide_tests` terminates with `{"decided": true}` when every surviving
  candidate agrees on each test. Greedy larger-branch minimization, the
  four-query budget, forbidden examples/tests, balanced examples/tests,
  individually undecided tests, and conservative rejection remain in place.
  The singleton candidate-count bound applies only to `identify`.
- `validate` recomputes the declared certificate and ignores supplied validation
  metadata. Invalid certificate values are rejected.
- The new fixed tier 2 self-test replays all 23 surviving candidates, checks
  legal queries and the budget, and independently compares all four test
  answers among candidates reaching each leaf. It also checks legacy defaults,
  rejection under `identify`, and untrusted validation metadata.

No files under `playtest/` were changed, and `playtest/claude/secret/` was not
opened. The original three machines remain untouched; no fourth was added.

`python engine/rules.py selftest` exited successfully with:

```text
tier 1: 92 distinct rules; generated machine VALID; 2 candidates; worst-case 1/4 queries
tier 2: 1871 distinct rules; generated machine VALID; 2 candidates; worst-case 1/4 queries
tier 3: 3000 distinct rules; generated machine VALID; 2 candidates; worst-case 1/4 queries
tier 2 decide_tests: 23 candidates; 11 agreeing leaves; worst-case 4/4 queries
PASS: 3000 unique ASTs checked on all 729 inputs; four machine certificates replayed for every candidate.
```
