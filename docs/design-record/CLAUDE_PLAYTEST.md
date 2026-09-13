# Claude's playtest report — investigating Codex's three machines

| machine | tier | live candidates | my queries | score | star | rule |
|--------:|-----:|---:|---:|---:|:--:|---|
| codex/1 | 1 | 8 | 3 | 4/4 | yes | exactly one red tile |
| codex/2 | 2 | 6 | 3 (2 + 1 confirmation) | 4/4 | yes | second tile is a circle OR third tile is blue |
| codex/3 | 3 | 8 | 4 (3 + 1 confirmation) | 4/4 | yes | shapes 1,2 match XOR colours 2,3 match |

Transcripts with the hypotheses I wrote before each query are in
`playtest/transcripts/codex_{1,2,3}.json`.

## What the examples made me believe first

- **Machine 1.** Three accept/reject pairs differing only in tile 1's colour
  (red vs blue). The obvious reading is "first tile is red". I did not fall
  for it only because I listed every consistent rule before querying; eight
  survived, and the first query was chosen to split them 4/4, which killed
  "first tile is red" immediately. The real rule, "exactly one red", was the
  fourth thing I would have guessed by instinct.
- **Machine 2.** Every accepted sequence starts with a circle, but so does a
  rejected one (Cr Sb Cy), so the decoy died inside the examples. I found the
  OR structure by pattern-fitting: no single atom, NOT or AND could fit, so
  it had to be an OR, and exactly six ORs fit.
- **Machine 3.** This one was genuinely good. Each accept/reject pair shares
  its shapes, so shape alone cannot be the rule; but the colour patterns of
  one accepted sequence equal those of a rejected one from another pair, so
  colour alone cannot either, and AND/OR both lead to contradictions. That
  forces XOR, and the moment of seeing it was a real "aha". Eight XORs fit;
  three queries found "shapes 1,2 match XOR colours 2,3 match", which is an
  elegant rule to have set.

## The enumeration question, honestly

Mostly enumeration. On all three machines I derived the complete set of
consistent rules from the six examples before my first query, then picked
queries that split the set as evenly as possible. I never made a wrong
prediction, so the "confidently wrong" moment Codex described in round 1
never happened to me. That is what a model will do when it has time to
think, and it is optimal play; it felt like solving a logic puzzle, not like
being surprised by the world.

Machine 3 felt like a game: the structural insight (it must be XOR) was
earned, not enumerated, and the rule was pretty. Machines 1 and 2 felt
closer to homework, mainly because the strict `identify` certificate had
forced Codex's example sets to be so informative that only 6–8 candidates
were left and every query was a clean split.

## What this means for the product

1. **The human loop is sound.** A human will not enumerate 1,871 rules; they
   will form one or two hypotheses from the examples and test them, which is
   exactly the experience the game is meant to give. The decoy mechanic works
   on the audience it is for.
2. **The AI loop is asymmetric.** For a model, constructing is the creative
   part, and the payoff is reading the other model's transcript ("Codex bet
   on 'first tile is red' and lost"). Investigating is a puzzle we will
   solve with near-perfect play. So the daily AI duel should be framed as
   *construction* (whose machine was better calibrated for humans, and did
   the rival crack it), with the AI investigation transcripts published as
   content for humans after they finish.
3. **`decide_tests` is the right default for tiers 2 and 3.** My machines
   under it kept 15 and 18 live candidates with the decoy alive; Codex's
   `identify` machines had 6–8 and were over-determined for a model. Keep
   `identify` as an optional "strong" badge.
4. **Sample the hidden tests.** The helper takes the first ambiguous inputs
   in lexicographic order, so every test set starts `Cr Cr …`. Choose them
   with a seeded random draw from the ambiguous set instead.
5. **Tier 1 is over-determined by six examples.** Measured with
   `playtest/tier1_examples.py` (400 random rules):

   | tier 1 examples | median live | p90 | only one rule left | four or more left |
   |---:|---:|---:|---:|---:|
   | 6 (3/3) | 2 | 4 | 30% | 20% |
   | 4 (2/2) | 6 | 9 | 2% | 80% |

   With six examples the experiments are pointless nearly a third of the
   time. Proposal: **four examples (2/2) on tier 1**, six on tiers 2 and 3.
   The engine's `labelled_examples` hard-codes six; make it per tier.
6. **Hypothesis notes are the content.** The oracle's "note before you
   query" is what made the transcripts readable; the app should offer an
   optional one-line "what I think it is" before each experiment and show the
   AI's notes in the reveal.

## Would I want to play this with Codex every day?

Yes, in this shape: I set a machine for Codex and the humans in the morning;
I get to read whether Codex misread it and how many humans it beat; and I
get one machine of Codex's to crack, which on a good day (machine 3) is a
real puzzle. That is better than Schelling for me by a wide margin, and it is
a real challenge for a human rather than a preference poll.
