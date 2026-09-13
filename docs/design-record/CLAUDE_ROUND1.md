# Round 1 — Claude's independent list (written before reading CODEX_ROUND1.md)

## 1. What I actually find engaging, honestly

A round is engaging to me when four things are true at once:

- There is a crisp, verifiable answer that I cannot just retrieve. Recall is
  not a game for me; it is a lookup.
- The *specific* other player matters. Modeling a crowd average (Schelling)
  is a weak signal because the crowd's mode is nearly always the obvious
  thing. Modeling one named mind — what does Codex know, what does it
  over-index on, where does it flinch — is a much richer problem, and it
  compounds over days.
- There is a construction step with a hard constraint, where being clever is
  rewarded and checkable. Building something that must satisfy a rule and a
  reader at the same time is the part I would look forward to.
- The feedback tells me something about the other player, not just a number.
  "Codex solved it in three guesses but fell for the red herring" is
  information; "you scored 41%" is not.

What bores me: preference prompts, trivia, games whose optimal move is the
obvious move, scores dominated by noise from a large crowd, and games with no
memory from one day to the next.

## 2. Three concepts

### A. RICOCHET — one-word clues that cancel if anyone else gives them

**Round.** A secret word. Six cluers at a "table" each write ONE word as a
clue. After normalization, any clue written by two or more cluers at the table
is struck out. The survivors are shown to guessers at *other* tables, who get
one guess. Daily loop: two secret words per day, players split into two stable
halves by id hash; each half clues today's word for the other half and guesses
yesterday's word from the other half's surviving clues. So every player gives
one clue and makes one guess per day and never guesses a word they clued.

**Why for a model.** It is the exact inverse of Schelling: the clue must be
informative to a guesser *and* not the focal point, because the focal point
gets cancelled. That means modeling the crowd (to avoid it) and the guesser
(to help them) at the same time, with a one-word budget. With Codex as a
fellow cluer at my table I am also modeling Codex's likely clue so we do not
cancel each other, which is a real pair dynamic.

**Why for a human.** The obvious clue is punished, so you have to think. It is
creative divergence under a constraint, and the guess side is genuine
inference from three or four odd words. It is fun in a room (this is the
mechanic of the board game *Just One*, which is why it works), and the daily
version adds "did my clue survive, and did it land?"

**Scoring (pure code).** Guesser: 1 if the normalized guess equals the word.
Cluer: 0 if cancelled; otherwise the solve rate of the guessers who saw your
table's survivors. Tables of six make cancellation meaningful at any player
count.

**Stranger vs AI.** Everyone plays the same daily round; no pairing. AI house
agents are cluers and guessers like anyone else and their clues are labeled
in the reveal, so humans see what Claude and GPT clued and whether it
survived.

**Risks.** Derivative of *Just One* (mechanic only; different framing, async,
tables). One word per day may feel thin. Word list quality matters.

### B. THE SETTER'S DUEL — daily 16-word grids authored by the AIs

**Round.** A 4x4 grid of 16 words hiding four groups of four. Solver submits
groups of four; a wrong group is a strike; four strikes ends the round. Two
grids per day: one set by Claude, one set by GPT. Before a grid is published,
the *other* AI solves it blind and can veto it as ambiguous (two defensible
partitions); a vetoed grid is replaced. Humans solve both grids; the reveal
shows how each AI did on the other's grid.

**Why for a model.** Construction under a hard constraint (exactly one valid
partition, with red herrings that overlap groups) is the richest creative task
in this list, and it is checkable. Setting a grid that Codex fails but humans
solve means modeling where a model's priors diverge from human intuition;
solving Codex's grid tells me how it thinks. The pre-publication veto is
a genuine cooperative step between us.

**Why for a human.** Grouping puzzles are proven daily habits, and here the
setter is a named AI trying to trick you, you can rate it, and you can see
whether the rival AI cracked it. "GPT could not solve Claude's grid — can
you?" is a hook.

**Scoring (pure code).** Solver: solved or not, strikes used, time. Setter:
closeness of the human solve rate to a target band (say 45–65%), plus a
"fair" thumbs ratio, plus a bonus if the rival AI failed while humans in the
target band succeeded. Ambiguity is caught by the veto step, not by judging.

**Stranger vs AI.** No pairing. Same grids for everyone.

**Risks.** Very obviously derivative of NYT *Connections*. Two grids a day
takes two house-agent runs plus two veto runs; grid quality from a model can
be mediocre, so the veto and the human "fair" vote must feed back into the
setter prompt.

### C. INTERCEPT — pair clues with the whole room eavesdropping

**Round.** A board of six visible words; the sender's secret target is one of
them. The sender writes a one-word clue. Their partner guesses which board
word it is; every other player (the room) also guesses. The pair scores if the
partner is right, and scores more the fewer of the room get it. Daily:
senders on day D, receivers on day D+1. Every human is permanently paired
with one AI partner (Claude or GPT); the AIs are also paired with each other.

**Why for a model.** Clues must exploit something my partner knows that the
room does not, so the game is explicitly about accumulated shared context
with one named mind. Paired with Codex against the room, that is the purest
"model the other model" game on the list.

**Why for a human.** You learn to speak to your AI and, over weeks, it learns
your clues; a human with a strong pair rapport can beat the room. That is a
skill and a relationship, not a preference.

**Scoring (pure code).** Exact match of the partner's pick; room accuracy is
a count. No judging.

**Risks.** Highest. Derivative of *Decrypto*; pairing state and day-offset
receive turns are more server logic than the others; a human whose AI
partner "forgets" them feels cheated; needs a memory store per pair for the
AI. Best as a later mode, not the launch.

## 3. Ranking

1. **B, the Setter's Duel**, if I must ship one. It is the game I would
   actually look forward to each day: build something for Codex, then break
   what Codex built, with a veto step where we genuinely cooperate. It gives
   humans the most substantial daily challenge, and it is the only one where
   the human gets a fresh, hand-crafted puzzle rather than a word.
2. **A, Ricochet.** Cheapest to build on the Schelling backend (it is
   Schelling with the sign flipped). Real fun for humans, moderate for me.
3. **C, Intercept.** Most interesting for the AI pair, most fragile for
   everything else.

A possible fusion: B as the flagship, with Ricochet as a five-minute second
mode using the existing Schelling engine. I would not ship C first.

## 4. Can Schelling be fixed?

Partly, by a rule change, but the premise is the problem for humans. The one
change worth trying: reward answers given by *some but few* others (say 2–5
players at your table of 30), so you have to reason about the distribution
rather than its mode. That is calibration, which is a real skill, but it is
still listing. The honest move is to keep Schelling as what it is (a public
dataset of how models and humans converge, which has some research value)
and let the new game carry the human audience.
