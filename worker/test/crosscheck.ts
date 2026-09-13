// Cross-check the TypeScript interpreter against the Python engine's truth tables.
//   npm run fixtures && npm test
import { readFileSync } from "node:fs";
import { ALL_INPUTS, checkAst, checkMachine, counterexample, describe, evaluate, tierForDate, type Ast } from "../src/rules.ts";

const fx = JSON.parse(readFileSync(new URL("../fixtures/rules.json", import.meta.url), "utf8"));
if (fx.inputs !== 729 || ALL_INPUTS.length !== 729) throw new Error("input universe mismatch");

let checked = 0;
for (const [tier, list] of Object.entries(fx.tiers) as [string, { id: string; ast: Ast; mask: string }[]][]) {
  const t = Number(tier);
  for (const r of list) {
    checkAst(r.ast, t);
    let mask = 0n;
    ALL_INPUTS.forEach((seq, i) => { if (evaluate(r.ast, seq)) mask |= 1n << BigInt(i); });
    if (mask.toString(16) !== r.mask) throw new Error(`tier ${tier} rule ${r.id} disagrees: ${describe(r.ast)}`);
    if (!describe(r.ast)) throw new Error("empty description");
    checked++;
  }
  // Python's index is 81*a + 9*b + c, which is ALL_INPUTS order: verified implicitly by the mask compare above.
  console.log(`tier ${tier}: ${list.length} rules agree on all 729 inputs`);
}

// Tier gating: an XOR rule must be rejected as tier 2, AND as tier 1.
const xorRule = fx.tiers["3"].find((r: any) => r.ast.op === "xor").ast;
let threw = false; try { checkAst(xorRule, 2); } catch { threw = true; }
if (!threw) throw new Error("xor accepted in tier 2");
const andRule = fx.tiers["2"].find((r: any) => r.ast.op === "and").ast;
threw = false; try { checkAst(andRule, 1); } catch { threw = true; }
if (!threw) throw new Error("and accepted in tier 1");

// counterexample: a rule differs from its negation on the first input; equals itself nowhere.
if (counterexample(andRule, andRule) !== null) throw new Error("self counterexample");
if (counterexample(andRule, { op: "not", a: andRule }) === null) throw new Error("negation has no counterexample");

// Weekday tiers (2026-09-13 is a Sunday).
if (tierForDate("2026-09-13") !== 3 || tierForDate("2026-09-14") !== 1 || tierForDate("2026-09-17") !== 2) throw new Error("tier calendar");

// checkMachine: a hand-built tier 1 machine with four examples.
const rule: Ast = { op: "count", attr: "colour", value: "red", n: 1 };
const m = checkMachine({
  tier: 1, rule, certificate: "decide_tests",
  examples: [
    { seq: [0, 4, 8], accepted: true }, { seq: [3, 1, 2], accepted: true },
    { seq: [1, 4, 8], accepted: false }, { seq: [0, 3, 2], accepted: false },
  ],
  tests: [[0, 1, 4], [1, 1, 5], [0, 0, 5], [3, 4, 4]],
});
if (m.examples.length !== 4 || m.tests.length !== 4) throw new Error("checkMachine shape");
threw = false; try { checkMachine({ ...m, examples: [...m.examples.slice(0, 3), { seq: [8, 8, 8], accepted: true }] }); } catch { threw = true; }
if (!threw) throw new Error("contradicting example accepted");

console.log(`PASS: ${checked} rules cross-checked; tier gating, counterexample, calendar and machine checks ok.`);
