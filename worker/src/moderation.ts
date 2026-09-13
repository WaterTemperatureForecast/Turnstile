// Moderation (App Store guideline 1.2): a blocklist gate on every nickname and
// answer, plus Llama Guard (Workers AI) on anything that is about to be shown
// to other players. Human answers are only displayed once two or more players
// gave them, so a lone offensive answer is never visible to anyone but its
// author; the classifier runs exactly once per key when it crosses that line.

const BLOCKED_WORDS = [
  "fuck", "fucker", "fucking", "motherfucker", "shit", "bullshit", "cunt",
  "bitch", "asshole", "dick", "dickhead", "cock", "pussy", "twat", "wanker",
  "slut", "whore", "nigger", "nigga", "faggot", "fag", "retard", "retarded",
  "kike", "spic", "chink", "gook", "wetback", "tranny", "dyke", "paki",
  "rape", "rapist", "nazi", "hitler", "porn", "cum", "jizz", "blowjob",
  "handjob", "penis", "vagina", "tits", "boobs", "anal", "dildo",
];

// Substring patterns for the worst slurs (catch simple joins like "fuckyou").
const BLOCKED_SUBSTRINGS = ["nigg", "fagg", "fuck", "cunt", "kike"];

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s" };

function fold(s: string): string {
  return s.toLowerCase().replace(/[0134578@$]/g, (c) => LEET[c] ?? c);
}

/** True when the (normalized) text should be rejected outright. */
export function isBlocked(key: string): boolean {
  const folded = fold(key);
  const words = folded.split(" ").filter(Boolean);
  for (const w of words) if (BLOCKED_WORDS.includes(w)) return true;
  const joined = words.join("");
  for (const sub of BLOCKED_SUBSTRINGS) if (joined.includes(sub)) return true;
  return false;
}

/** Nickname rules: 2-20 chars, letters/digits/space/_/-/., not blocked. */
export function validateNickname(name: string): string | null {
  const n = name.replace(/\s+/g, " ").trim();
  if (n.length < 2) return "Nickname is too short.";
  if (n.length > 20) return "Nickname is at most 20 characters.";
  if (!/^[\p{L}\p{N} ._-]+$/u.test(n)) return "Nickname may only use letters, digits, spaces, . _ and -.";
  if (isBlocked(n.toLowerCase().replace(/[^\p{L}\p{N} ]/gu, " "))) return "Please pick a different nickname.";
  return null;
}

export type Verdict = "safe" | "unsafe" | "unknown";

interface AiBinding {
  run(model: string, input: unknown): Promise<any>;
}

/**
 * Llama Guard 3 on Workers AI. `context` tells the model what the text is
 * (a one-word game answer, a nickname). Fails open as "unknown" so an AI
 * outage never blocks play; callers decide what "unknown" means for them.
 */
export async function screenText(ai: AiBinding | undefined, text: string, context: string): Promise<Verdict> {
  if (!ai) return "unknown";
  try {
    const res = await ai.run("@cf/meta/llama-guard-3-8b", {
      messages: [{ role: "user", content: `${context}\n\n${text}` }],
    });
    const verdict = String(res?.response ?? "").trim().toLowerCase();
    if (verdict.startsWith("unsafe") || verdict.includes("\nunsafe")) return "unsafe";
    if (verdict.includes("safe")) return "safe";
    return "unknown";
  } catch {
    return "unknown";
  }
}

export const ANSWER_CONTEXT =
  "A player typed this one-or-two-word answer in a family-friendly logic game. It will be shown to other players, including children. Is it safe to display?";
export const NICKNAME_CONTEXT =
  "A player chose this nickname for a family-friendly logic game leaderboard, visible to other players including children. Is it safe to display?";
