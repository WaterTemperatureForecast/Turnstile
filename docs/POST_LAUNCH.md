# Post-launch notes

Findings that are not blockers for 1.0. Nothing here has been changed; each
one is a decision to make once there is real play data.

## 1. A constant answer always scores exactly 2/4

Every machine's four tests are forced to two accepts and two rejects (the
engine rejects any other split), so answering "Reject" four times without
thinking scores 2/4 on every machine, and 4/8 on the day. Observed on the
first real TestFlight play: four experiments run, then all four tests
answered Reject, score 2/4.

This is not an exploit — a real solver still scores 8/8 and outranks them —
but it does compress the visible range of the daily board to 4–8, and 2/4
reads like partial credit when it is really the coin-flip baseline.

Options, in order of how much they disturb the design:

- **Leave it.** The reveal already headlines "% scored 4/4", which is the
  honest measure, and the board tiebreaks on stars then fewer experiments.
- **Say so in the UI.** One line under the score: "2/4 is what a coin flip
  gets; the tests are always two accepts and two rejects." Cheap, honest,
  and it teaches the player what the number means.
- **Change the points.** Per machine: 4 correct = 3, 3 correct = 1, else 0,
  plus 1 for a star. A constant answer then scores 0. This is a Worker
  change plus a wording change in the app, and it makes the daily total
  0–8 again.

The unbalanced alternative (letting the tests be 3 accepts and 1 reject) is
worse: it would make a constant answer score 3/4 by luck.

## 2. A new player's first round can be the hardest tier

Tiers follow the calendar (Mon–Wed 1, Thu–Sat 2, Sunday 3), so someone who
installs on a Sunday meets a tier-3 XOR machine with no ramp. The first
real play was exactly this: `(no triangles) XOR (all three colours the
same)`, from the fallback pool, scored 2/4.

Options:

- Show the Help sheet automatically on first launch (small app change).
- Give a player's first-ever machine a tier-1 practice machine from the
  pool, alongside the day's two. Needs per-player machine selection, which
  the schema supports (`plays` is keyed by machine and player) but the
  round endpoint does not yet do.

## 3. The fallback pool is doing the setting

Until the house constructors have run for a few days, most published
machines come from `rules.pool()`, whose examples are random rather than
chosen to invite a wrong hypothesis. They are fair but not interesting.
Watch the setters board: if pool machines cluster outside the 40–70% solve
band while house machines sit inside it, that is the constructor earning
its place.

## 4. House agents share the owner's subscription quota

`claude -p` and `codex exec` draw on the same interactive quota the owner
uses. Two failures already seen: a Claude session limit ("resets 1:50pm")
and a Codex usage limit mid-playtest. Both fail safe — the round still
publishes from the pool and the agent simply has no transcript that day —
but a long stretch of quota exhaustion would leave the AI duel empty.
`ask()` retries once and gives up cleanly; scheduled runs at 06:30–08:15Z
should mostly avoid the owner's own usage.
