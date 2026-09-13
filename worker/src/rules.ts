// Turnstile rule interpreter (TypeScript port of engine/rules.py, cross-checked
// by test/crosscheck.ts on all rules x all 729 inputs). The Worker only ever
// evaluates stored rules and checks cheap invariants; enumeration and
// certificate search live in the Python engine.

export const SHAPES = ["circle", "square", "triangle"] as const;
export const COLOURS = ["red", "blue", "yellow"] as const;
export type Attr = "shape" | "colour";
export type Seq = [number, number, number];

export type Ast =
  | { op: "pos"; i: number; attr: Attr; value: string }
  | { op: "count"; attr: Attr; value: string; n: number }
  | { op: "same"; attr: Attr; i: number; j: number }
  | { op: "allsame"; attr: Attr }
  | { op: "alldiff"; attr: Attr }
  | { op: "not"; a: Ast }
  | { op: "and" | "or" | "xor"; a: Ast; b: Ast };

const FIELDS: Record<string, string[]> = {
  pos: ["op", "i", "attr", "value"],
  count: ["op", "attr", "value", "n"],
  same: ["op", "attr", "i", "j"],
  allsame: ["op", "attr"],
  alldiff: ["op", "attr"],
  not: ["op", "a"],
  and: ["op", "a", "b"],
  or: ["op", "a", "b"],
  xor: ["op", "a", "b"],
};
const ATOM_OPS = new Set(["pos", "count", "same", "allsame", "alldiff"]);

export class RuleError extends Error {}

export function tileShape(t: number): string { return SHAPES[Math.floor(t / 3)]; }
export function tileColour(t: number): string { return COLOURS[t % 3]; }
export function tileLabel(t: number): string { return `${tileColour(t)} ${tileShape(t)}`; }
export function seqLabel(seq: Seq): string { return seq.map(tileLabel).join(", "); }

export function parseSeq(value: unknown): Seq {
  if (!Array.isArray(value) || value.length !== 3) throw new RuleError("A sequence is exactly three tiles.");
  const out = value.map((x) => {
    if (typeof x !== "number" || !Number.isInteger(x) || x < 0 || x > 8) throw new RuleError("Tiles are integers 0-8.");
    return x;
  });
  return [out[0], out[1], out[2]];
}

export function seqKey(seq: Seq): string { return seq.join(","); }

/** Structural validation. With `tier`, also enforces the tier's allowed forms (operands must be atoms). */
export function checkAst(ast: unknown, tier?: number): asserts ast is Ast {
  if (!ast || typeof ast !== "object" || Array.isArray(ast)) throw new RuleError("Rule must be an object.");
  const a = ast as Record<string, unknown>;
  const op = a.op;
  if (typeof op !== "string" || !(op in FIELDS)) throw new RuleError("Unknown rule op.");
  const keys = Object.keys(a).sort().join(",");
  if (keys !== [...FIELDS[op]].sort().join(",")) throw new RuleError(`Wrong fields for ${op}.`);
  if (op === "not" || op === "and" || op === "or" || op === "xor") {
    if (tier !== undefined) {
      if (op === "not" && !ATOM_OPS.has((a.a as any)?.op)) throw new RuleError("NOT applies to a single property.");
      if ((op === "and" || op === "or") && tier < 2) throw new RuleError("AND/OR are not allowed in tier 1.");
      if (op === "xor" && tier < 3) throw new RuleError("XOR is only allowed in tier 3.");
      if (op !== "not" && (!ATOM_OPS.has((a.a as any)?.op) || !ATOM_OPS.has((a.b as any)?.op))) throw new RuleError("Connectors join two single properties.");
    }
    checkAst(a.a);
    if (op !== "not") checkAst(a.b);
    return;
  }
  const attr = a.attr;
  if (attr !== "shape" && attr !== "colour") throw new RuleError("attr must be shape or colour.");
  const values: readonly string[] = attr === "shape" ? SHAPES : COLOURS;
  if ("value" in a && !values.includes(a.value as string)) throw new RuleError("Unknown attribute value.");
  for (const k of ["i", "j", "n"]) {
    if (k in a) {
      const v = a[k];
      const [lo, hi] = k === "n" ? [0, 3] : [1, 3];
      if (typeof v !== "number" || !Number.isInteger(v) || v < lo || v > hi) throw new RuleError(`Invalid ${k}.`);
    }
  }
  if (op === "same" && (a.i as number) >= (a.j as number)) throw new RuleError("same requires i < j.");
}

function ev(ast: Ast, seq: Seq): boolean {
  switch (ast.op) {
    case "not": return !ev(ast.a, seq);
    case "and": return ev(ast.a, seq) && ev(ast.b, seq);
    case "or": return ev(ast.a, seq) || ev(ast.b, seq);
    case "xor": return ev(ast.a, seq) !== ev(ast.b, seq);
  }
  const vals = seq.map((t) => (ast.attr === "shape" ? tileShape(t) : tileColour(t)));
  switch (ast.op) {
    case "pos": return vals[ast.i - 1] === ast.value;
    case "count": return vals.filter((v) => v === ast.value).length === ast.n;
    case "same": return vals[ast.i - 1] === vals[ast.j - 1];
    case "allsame": return new Set(vals).size === 1;
    case "alldiff": return new Set(vals).size === 3;
  }
}

export function evaluate(ast: Ast, seq: Seq): boolean { return ev(ast, seq); }

export const ALL_INPUTS: Seq[] = (() => {
  const out: Seq[] = [];
  for (let a = 0; a < 9; a++) for (let b = 0; b < 9; b++) for (let c = 0; c < 9; c++) out.push([a, b, c]);
  return out;
})();

/** First input on which two rules disagree, or null when they are the same rule. */
export function counterexample(a: Ast, b: Ast): Seq | null {
  for (const s of ALL_INPUTS) if (ev(a, s) !== ev(b, s)) return s;
  return null;
}

const POS = ["", "first", "second", "third"];

/** English rendering of a rule, matching playtest/oracle.py describe(). */
export function describe(ast: Ast): string {
  switch (ast.op) {
    case "pos":
      return ast.attr === "colour" ? `the ${POS[ast.i]} tile is ${ast.value}` : `the ${POS[ast.i]} tile is a ${ast.value}`;
    case "count": {
      const n = ast.n;
      if (ast.attr === "colour") return `exactly ${n} tile${n !== 1 ? "s" : ""} ${n !== 1 ? "are" : "is"} ${ast.value}`;
      return `there ${n !== 1 ? "are" : "is"} exactly ${n} ${ast.value}${n !== 1 ? "s" : ""}`;
    }
    case "same": return `the ${POS[ast.i]} and ${POS[ast.j]} tiles have the same ${ast.attr}`;
    case "allsame": return `all three tiles have the same ${ast.attr}`;
    case "alldiff": return `all three ${ast.attr}s are different`;
    case "not": return `NOT (${describe(ast.a)})`;
    case "and": return `(${describe(ast.a)}) AND (${describe(ast.b)})`;
    case "or": return `(${describe(ast.a)}) OR (${describe(ast.b)})`;
    case "xor": return `(${describe(ast.a)}) XOR (${describe(ast.b)})`;
  }
}

/** Weekday tiers by the round's UTC date: Mon-Wed 1, Thu-Sat 2, Sun 3. */
export function tierForDate(date: string): number {
  const day = new Date(date + "T00:00:00Z").getUTCDay(); // 0 = Sunday
  if (day === 0) return 3;
  return day <= 3 ? 1 : 2;
}

export function examplesForTier(tier: number): number { return tier === 1 ? 4 : 6; }

export const TIER_TEXT: Record<number, string> = {
  1: "Today's rule is one property, or NOT one property.",
  2: "Today's rule is one property, NOT one property, or two properties joined by AND or OR.",
  3: "Today's rule is one property, NOT one property, or two properties joined by AND, OR, or XOR (exactly one of the two).",
};

export const VOCABULARY = [
  "Position: the tile in position 1, 2 or 3 has a given shape or colour.",
  "Count: exactly N tiles (0 to 3) have a given shape or colour.",
  "Match: two given positions share their shape, or share their colour.",
  "All same / all different: the three shapes (or colours) are all the same, or all different.",
];

export interface MachineJson {
  tier: number;
  rule: Ast;
  rule_id?: string;
  examples: { seq: Seq; accepted: boolean }[];
  tests: Seq[];
  certificate?: string;
  validation?: { candidate_count?: number; strategy?: unknown; worst_case?: number };
  note?: string;
}

/** Cheap invariants only; the fairness certificate is trusted from the offline engine. */
export function checkMachine(m: any): MachineJson {
  const tier = Number(m?.tier);
  if (![1, 2, 3].includes(tier)) throw new RuleError("tier must be 1, 2 or 3.");
  checkAst(m?.rule, tier);
  const rule = m.rule as Ast;
  const want = examplesForTier(tier);
  if (!Array.isArray(m?.examples) || m.examples.length !== want) throw new RuleError(`Tier ${tier} machines need ${want} examples.`);
  const seen = new Set<string>();
  let accepted = 0;
  const examples = m.examples.map((e: any) => {
    const seq = parseSeq(e?.seq);
    if (typeof e?.accepted !== "boolean") throw new RuleError("Example labels must be booleans.");
    if (ev(rule, seq) !== e.accepted) throw new RuleError("An example label contradicts the rule.");
    if (seen.has(seqKey(seq))) throw new RuleError("Examples must be distinct.");
    seen.add(seqKey(seq));
    if (e.accepted) accepted++;
    return { seq, accepted: e.accepted as boolean };
  });
  if (accepted * 2 !== want) throw new RuleError("Examples must be half accepted, half rejected.");
  if (!Array.isArray(m?.tests) || m.tests.length !== 4) throw new RuleError("Four tests are required.");
  let testYes = 0;
  const tests: Seq[] = m.tests.map((t: any) => {
    const seq = parseSeq(t);
    if (seen.has(seqKey(seq))) throw new RuleError("Tests must be distinct and not examples.");
    seen.add(seqKey(seq));
    if (ev(rule, seq)) testYes++;
    return seq;
  });
  if (testYes !== 2) throw new RuleError("Tests must be two accepted, two rejected.");
  const certificate = m?.certificate ?? "identify";
  if (certificate !== "identify" && certificate !== "decide_tests") throw new RuleError("Unknown certificate.");
  const note = typeof m?.note === "string" ? m.note.trim().slice(0, 200) : undefined;
  return { tier, rule, rule_id: typeof m?.rule_id === "string" ? m.rule_id : undefined, examples, tests, certificate, validation: m?.validation, note };
}
