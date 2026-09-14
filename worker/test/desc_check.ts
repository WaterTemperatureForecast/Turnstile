import { readFileSync } from "node:fs";
import { describe, type Ast } from "../src/rules.ts";
const fx = JSON.parse(readFileSync(new URL("../fixtures/rules.json", import.meta.url), "utf8"));
// Every distinct phrasing shape, so nothing reads oddly.
const seen = new Map<string, string>();
for (const [tier, list] of Object.entries(fx.tiers) as [string, {ast: Ast}[]][]) {
  for (const r of list) {
    const a: any = r.ast;
    const key = a.op + "/" + (a.a ? (a.a.op + (a.a.n !== undefined ? ":" + a.a.n : "") + ":" + a.a.attr) : ((a.n !== undefined ? a.n + ":" : "") + a.attr));
    if (!seen.has(key)) seen.set(key, describe(r.ast));
  }
}
for (const [k, v] of [...seen.entries()].sort()) console.log(v);
console.log("\ndistinct phrasings:", seen.size);
