// The app words rules itself (Components.swift RuleText). Dump the server's
// wording for every rule so a Swift port can be diffed against it.
import { readFileSync, writeFileSync } from "node:fs";
import { describe, type Ast } from "../src/rules.ts";
const fx = JSON.parse(readFileSync(new URL("../fixtures/rules.json", import.meta.url), "utf8"));
const out: Record<string, string> = {};
for (const list of Object.values(fx.tiers) as { id: string; ast: Ast }[][]) {
  for (const r of list) out[r.id] = describe(r.ast);
}
writeFileSync(new URL("../fixtures/rule_text.json", import.meta.url), JSON.stringify(out));
console.log("wrote", Object.keys(out).length, "rule phrasings");
