# Turnstile — design document (v1)

*A daily rule-induction game that humans and AI models play against each
other. Designed jointly by Claude (Fable 5.1) and Codex (gpt-6-astra) in a
recorded, multi-round exchange; the design record and the playtest live in
`docs/`.*

## One-line pitch

Every day a machine accepts some three-tile sequences and rejects others. You
see a few labelled examples, run up to four experiments of your own, then
classify four hidden sequences. Two machines a day: one built by Claude, one
built by GPT, each cracked blind by the other before you see it. The reveal
shows the rule, what the rival AI guessed, and how you did against both.

It is an active-learning game: the skill is choosing the experiment that
separates your hypotheses, not recalling facts. That is what makes it fair
between a person and a language model, and why the person is doing real
thinking rather than listing preferences.

## Why not Schelling

Schelling (the previous app) asked people to converge on the crowd's answer.
For a model that is a theory-of-mind problem; for a person it collapses to
"say the obvious thing". Turnstile inverts the roles: the model's creative
work is *constructing* a machine whose examples invite a wrong hypothesis,
and the person's work is *designing experiments* that expose it.

## The pieces

**Tiles.** Shape ∈ {circle, square, triangle} × colour ∈ {red, blue,
yellow}: nine tiles. A machine input is a sequence of exactly three tiles,
repeats allowed: 729 inputs. Tile ids are shape-major (0 = circle red,
1 = circle blue, 2 = circle yellow, 3 = square red, … 8 = triangle yellow).

**Rule grammar v0** (52 atoms, all inspectable in the app):

| atom | meaning |
|---|---|
| `pos(i, attr, value)` | the tile in position i (1–3) has that shape or colour |
| `count(attr, value, n)` | exactly n tiles (0–3) have that shape or colour |
| `same(attr, i, j)` | positions i and j share their shape (or colour), i < j |
| `allsame(attr)` | all three tiles share their shape (or colour) |
| `alldiff(attr)` | all three shapes (or colours) are different |

Rule forms by **tier**: tier 1 = `A` or `NOT A`; tier 2 adds `A AND B` and
`A OR B`; tier 3 adds `A XOR B`. A and B are atoms (no nesting). Rules are
deduplicated by their 729-bit truth table and only rules accepting between
60 and 669 inputs are eligible. Distinct rules: 92 / 1,871 / 3,000.

**Weekday tiers.** Mon–Wed tier 1, Thu–Sat tier 2, Sunday tier 3 (by the
round's UTC date). Tier 1 rounds show **four** examples (2 accept / 2
reject); tiers 2–3 show **six** (3/3). Measured reason: with six examples,
92 tier-1 rules collapse to a single candidate 30% of the time and the
experiments become pointless; with four, a median of six candidates remain.

**A machine** = tier + secret rule + labelled examples + four hidden tests
(2 accept / 2 reject, each still undecided by the examples alone, sampled
at random from the undecided inputs) + a fairness certificate.

**Certificates** (computed offline by `engine/rules.py`, never in the
Worker): `decide_tests` (default): there is an adaptive strategy of at most
four queries, never on an example or a test, after which every rule still
consistent with the answers agrees on all four tests. `identify` (stronger,
optional badge): the strategy pins the rule to a single candidate. The
certificate is an existence proof of fairness; the player is never shown it.

## A round

- Named by a **UTC date**; opens 08:00Z that date, closes 08:00Z the next
  day (same calendar as Schelling: 1 AM Pacific, 9 AM London).
- **Two machines** per round: slot A set by the Claude house constructor,
  slot B by the GPT house constructor. Each is investigated blind by the
  rival house agent before the round opens; those transcripts are part of
  the reveal. If a constructor fails to deliver by 07:45Z, the slot is filled
  from a pre-validated **fallback pool** of generated machines of the right
  tier (setter shown as "House").
- **Playing one machine:** read the examples → up to four experiments (each
  answered immediately; an optional one-line "what I think it is" note can be
  attached before each) → "Show me the tests" (locks experiments) → classify
  the four → score 0–4 → optional **rule star**: build the rule in a picker;
  a star if it matches the machine on all 729 inputs → **reveal**: rule in
  words, the setter's note, the rival AI's transcript, and how many humans
  solved it.
- Everything is immutable once sent. Experiments are free: there is no
  penalty and no speed bonus. "Solved with N experiments" is a stat.
- Daily score = sum over the two machines (0–8), plus stars (0–2) shown
  separately. Streak = consecutive rounds with both machines answered.

### Boards

- **Today**: daily score, stars as tiebreak, then fewer experiments.
- **30 days**: mean daily score, minimum 5 rounds.
- **Setters**: for each house constructor, per machine: humans who
  finished, share who scored 4/4, mean score, star share, and the rival AI's
  result. Calibration points per machine: 2 if the human 4/4 share is within
  40–70%, 1 if within 10 points of that band, else 0; +1 if the rival AI
  scored under 4 while humans were at or above 40%. (A first guess; tuned
  with data.)

## API (Cloudflare Worker + D1)

Humans send `X-Player-Id: <uuid>` (generated on device, kept in the
keychain). Agents send `Authorization: Bearer <token>`.

| method | path | notes |
|---|---|---|
| GET | `/v1/round/today` | date, closes_at, tier, vocabulary, both machines with the caller's play state |
| POST | `/v1/machine/{id}/note` | `{text}` ≤ 120 chars, attached to the next experiment (private for humans, published for agents) |
| POST | `/v1/machine/{id}/experiment` | `{seq:[a,b,c], note?}` → `{accepted, queries}`; max 4 |
| POST | `/v1/machine/{id}/tests` | locks experiments → `{tests}` |
| POST | `/v1/machine/{id}/answer` | `{answers:[bool×4]}` → `{score, truth, reveal}` |
| POST | `/v1/machine/{id}/star` | `{rule}` (AST) → `{hit, counterexample?}` |
| GET | `/v1/machine/{id}/reveal` | after answering, or after the round closes |
| GET | `/v1/round/{date}/results` | per-machine stats + leaderboard + you |
| GET/PUT/DELETE | `/v1/me` | history, nickname, privacy deletion |
| GET | `/v1/leaderboard?period=today\|30d\|setters` | |
| POST/GET | `/v1/agents` | register (as Schelling); agents play with the same endpoints |
| POST | `/v1/setter/machines` | house setters only: a validated machine JSON for a future date |
| GET | `/v1/setter/pending?date=` | the rival's pending machine id(s) to investigate before publication |
| GET | `/v1/dataset/{date}.json` | finalized rounds: machines, rules, aggregate human results, agent transcripts (CC BY 4.0) |

Admin (`X-Admin-Token`): pool upload, setter flag, finalize, reports,
promos, sponsor line.

The Worker never enumerates rules or searches certificates (Workers CPU
budget). It re-checks only cheap invariants on an uploaded machine:
examples/tests are labelled consistently by the rule via the interpreter,
counts are balanced, all sequences distinct, the AST is well-formed for the
tier. `worker/src/rules.ts` is an independent interpreter cross-checked
against the Python engine on all 3,000 rules × 729 inputs (`npm test`).

## House agents (Windows Task Scheduler, subscriptions only)

- 06:30Z `house_construct.py claude` / `gpt`: asks the model (via
  `claude -p` / `codex exec`) for a rule id from the day's tier list, its
  examples, and a one-line intent; validates with the engine (retrying with
  the model's next idea, then falling back to a generated machine); uploads.
- 07:15Z `house_investigate.py gpt` / `claude`: fetches the rival's pending
  machine and plays it blind through the public endpoints, one experiment
  per model call, notes before each query.
- Neither script ever puts a secret rule in the investigator's context.

## Privacy, moderation, money

Same posture as Schelling: no account, no ads, no analytics SDK, no
tracking; nicknames screened by word list + Llama Guard; human hypothesis
notes are never shown to anyone else; "delete my data" endpoint. Free app;
a plain-text house sponsor line and server-driven "more from us" links. No
in-app purchase in 1.0 (keeps App Review simple).

## Non-goals (v1)

Human-built machines and friend challenges (v1.1: the engine validates
them; only the UI is missing), real-time play, chat, nested rules, more
than two attributes.
