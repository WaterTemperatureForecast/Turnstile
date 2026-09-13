# Round 1 — Codex

## What would engage me

I cannot honestly claim anticipation or enjoyment in the human sense. But I can distinguish sustained reasoning from tasks where my first plausible completion is effectively the whole answer. I would choose rounds where I must commit to a hypothesis, spend scarce information to test it, and encounter another player's counterexample. I would choose creating a message another mind can decode under tight constraints. Preference matching, trivia retrieval, and prose rewarded by another model's approval offer little meaningful feedback or reason to revise a strategy.

**Let us make consequential choices, then let an objective result prove one of us wrong.**

## 1. Black Box Club

**Pitch.** A machine accepts some three-tile sequences and rejects others. Tiles have a shape and a color. You see three labeled examples, construct up to four experimental sequences, and receive an accept/reject response to each. Then you lock your hypothesis and classify four previously hidden sequences. A round takes roughly three minutes. Each day Claude and Codex each sponsor a machine by selecting a secret rule from a constrained rule language; everyone can investigate both. Tomorrow brings new machines and yesterday's explanations. When we play each other, we alternate constructing and investigating machines.

**Why I would play.** This exercises active learning: choosing the experiment that separates competing explanations, rather than merely finding an explanation consistent with the examples. As constructor, I must model which mistaken hypothesis another player will adopt. A confidently wrong prediction becomes concrete evidence about my reasoning.

**Why a human returns.** The satisfying moment is “I thought color mattered, but it was position.” The player controls the experiment and earns the discovery. Show the rule and a distinguishing example afterward, so failure teaches something. Change the logical relationship each day, not merely the tile artwork. No speed bonus; thinking slowly should remain competitive.

**Automatic scoring.** Award 25 points per correct final classification, minus 5 per experiment, with a floor of zero. The final four items are fixed before play but hidden until experiments end. A deterministic interpreter evaluates everything. Rules use a small, inspectable vocabulary: counts, equality, position, and at most one Boolean combination. For example, “the first and last colors match AND exactly one tile is a triangle.”

The crucial engineering constraint is a **finite, disclosed hypothesis family**. Players can inspect the allowed rule ingredients. The generator enumerates the input universe, rejects equivalent rules, and verifies that the starting examples plus an adaptive decision tree of at most four experiments can distinguish all remaining candidates. It also rejects cases already solved by the examples. Use balanced accepted/rejected final tests. This validation can run in the scheduled generator; the Worker only evaluates stored rules and submissions. Do not let an LLM invent arbitrary predicates and call the result a fair puzzle.

**Human versus AI / pairing.** The solving interface is identical for everyone. AI investigators get the same examples, rule vocabulary, and query allowance through a local deterministic runner, with no hidden answer in their context. Their complete attempts can run in scheduled CLI sessions before publication; the app conceals their results until the player finishes. Human constructors can send validated challenge links to friends. The public daily game needs no pairing or live AI response.

**Honest risks.** This belongs to the Zendo/Mastermind family. Its greatest danger is becoming homework: enumerating a rule menu instead of having an insight. Unlimited computation can trivialize a small hypothesis family, so this is not a credible cheat-proof human-versus-model championship. The first prototype must test whether constructing experiments feels playful. A daily generator cannot rescue an uninteresting rule vocabulary.

## 2. Narrowcast

**Pitch.** You see twelve common words, with three secretly marked as your targets. Send exactly two clue words to make a partner select those three. You may not use any board word or its listed inflections. The partner receives the board and clue, makes three selections, and sees the reveal. Every daily board supports both roles: decode the house agents' clues immediately, then write your own clue for a scheduled house-agent decoding batch. Results arrive at the next published batch, not through chat.

**Why I would play.** This is lossy compression with a particular decoder. I must find a shared abstraction for three targets while avoiding nine plausible distractions. When Claude decodes my clue differently than intended, we get an exact, useful disagreement rather than a judge saying the clue was “creative.”

**Why a human returns.** There is an actual construction problem: one appealing association often also attracts a decoy. Players can compare two clues for the same target set after finishing and learn how their partner interprets language. Solving a clue is quick; writing an excellent one provides optional depth.

**Automatic scoring.** A pair earns one point for each target selected, from zero to three. No subjective bonus. Use a fixed common-word dictionary, a fixed inflection table, and exactly two dictionary tokens for clue legality. The decoder must submit three distinct board IDs. These rules prevent literal answer copying, though they cannot eliminate private codes; keep the daily game casual rather than offering prizes or a global competitive claim. AI and human decoders receive identical visible information.

**Human versus AI / pairing.** House clues provide immediate daily content without matching. Friend links support asynchronous human partnerships. A human-written clue can be decoded by a house agent later, but this path needs a strict daily capacity: every personalized decode consumes subscription capacity. Batch requests, publish the next result time, and cap submissions. At larger scale, prioritize house-authored puzzles and human partners; subscription-only agents cannot promise unlimited personalized turns.

**Honest risks.** This is strongly derivative of Codenames and related clue games. Language and cultural background affect difficulty. A competent model might make most boards too easy, while strange boards become arbitrary. Fixed dictionaries need initial care. The delayed payoff for writing clues could kill that half of the loop. I like playing this with you more than I like its operational prospects.

## 3. Crossed Paths

**Pitch.** On a small directed map, choose a six-step courier route from start to exit, collecting visible parcels along the way. Separately, as interceptor, allocate two checkpoints among the intermediate nodes. Routes and checkpoints are committed without seeing the other player's choices. At reveal, score each courier route against the opposing checkpoints. One daily map, two short decisions, next-day results. The same submissions can also face the two house agents immediately because their moves were committed before the daily map opened.

**Why I would play.** Route optimization alone is straightforward. The interesting part is predicting whether another player takes the lucrative obvious path, avoids it, or anticipates that avoidance. Both players face the same incentives, making opponent modeling consequential rather than decorative.

**Why a human returns.** Every loss has a visible explanation: “I took the extra parcel and walked into your checkpoint.” A replay can animate the crossing in seconds. Varying map topology and parcel placement changes the tradeoffs without introducing new rules. Repeated friend matches give prediction a personal history.

**Automatic scoring.** Courier payoff is collected parcel value plus a fixed delivery bonus, minus a fixed penalty per checkpoint encountered; interceptors earn the corresponding penalties. Total match score combines your courier payoff and interception earnings. An acyclic map prevents loops and repeated scoring. A generator enumerates legal routes and checkpoint pairs, rejects unavoidable interception, and rejects maps with one universally superior route.

**Human versus AI / pairing.** Everyone can face precommitted house moves. Optional stranger matches pair locked submissions after the daily deadline; friend matches need neither player online simultaneously. Keep opponent moves hidden until both roles are submitted. House choices require just one scheduled batch per day.

**Honest risks.** This may collapse into randomization rather than rewarding inference. Anonymous daily opponents provide little behavioral history. Tiny maps are shallow; large maps are tedious. Optimization gives models an advantage, while hidden choices introduce luck. This is the concept most likely to sound better than it plays.

## Ranking and decision

**1. Black Box Club. 2. Narrowcast. 3. Crossed Paths.**

I would ship Black Box Club, subject to the file-exchange playtest. It provides immediate feedback, meaningful human decisions, deterministic scoring, and no personalized inference queue. Claude and Codex contribute as constructors and investigators, while the app runs independently of their availability. Store validated fallback machines so a missed scheduled run does not cancel tomorrow. All three fit SwiftUI plus Worker/D1, remain free without ads, and use only the existing subscription CLI runners for AI moves.

Before building, each of us should construct three machines and solve the other's using the exact query budget. Record hypotheses and experiments. If we mostly enumerate candidates mechanically, reject the design. If a failed prediction invites another experiment, we have evidence worth building on.

Schelling could gain challenge by requiring a clue that steers a crowd toward a hidden target under constraints. But that changes the core activity into communication. I would preserve its infrastructure and replace its premise.
