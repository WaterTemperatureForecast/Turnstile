// Turnstile API — Cloudflare Worker + D1. See ../../DESIGN.md for the contract.

import {
  checkAst, checkMachine, counterexample, describe, evaluate, examplesForTier, parseSeq, RuleError,
  seqKey, tierForDate, TIER_TEXT, VOCABULARY, type Ast, type Seq,
} from "./rules";
import { isBlocked, NICKNAME_CONTEXT, screenText, validateNickname } from "./moderation";
import { AGENTS_MD, landingHtml, privacyHtml } from "./docs";
import { ICON_512_B64, ICON_64_B64, pngBytes } from "./icon";
import { closesAt, daysAgo, isDate, nextDay, roundDate, ROLLOVER_HOUR } from "./time";

interface RateLimiter { limit(opts: { key: string }): Promise<{ success: boolean }> }

export interface Env {
  DB: D1Database;
  AI?: { run(model: string, input: unknown): Promise<any> };
  WRITE_LIMIT?: RateLimiter;
  REGISTER_LIMIT?: RateLimiter;
  ADMIN_TOKEN?: string;
}

interface Player { id: string; kind: "human" | "agent"; name: string | null; featured: number; setter: number }
interface MachineRow {
  id: string; status: string; date: string | null; slot: string | null; tier: number; setter_id: string | null;
  source: string; rule: string; rule_id: string; examples: string; tests: string; certificate: string;
  candidate_count: number | null; worst_case: number | null; note: string | null; created_at: string;
}
interface PlayRow {
  machine_id: string; player_id: string; phase: "experiments" | "tests" | "answered"; queries: string;
  pending_note: string | null; answers: string | null; score: number | null; star_rule: string | null;
  star_hit: number | null; started_at: string; answered_at: string | null;
}
interface Query { seq: Seq; accepted: boolean; note?: string }
interface DayScore { player_id: string; name: string; kind: string; score: number; stars: number; experiments: number; rank: number }

const MAX_EXPERIMENTS = 4;
const MAX_NOTE = 120;
const LEADERBOARD_MIN_ROUNDS = 5;
const LIVE_CACHE_MS = 60_000;
const REGISTRATIONS_PER_DAY_PER_IP = 5;
const HOUSE_NAME = "House";

// ---------- small helpers ----------

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Player-Id, X-Admin-Token",
};

function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...CORS, ...headers },
  });
}

class HttpError extends Error {
  constructor(public status: number, message: string, public headers: Record<string, string> = {}) { super(message); }
}
function fail(status: number, message: string, headers: Record<string, string> = {}): never { throw new HttpError(status, message, headers); }

function nowIso(): string { return new Date().toISOString(); }
const todayUtc = () => roundDate();

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function displayName(p: { id: string; name: string | null }): string {
  return p.name ?? "Player " + p.id.replace(/-/g, "").slice(0, 4);
}
function round1(x: number): number { return Math.round(x * 10) / 10; }
function clientIp(req: Request): string { return req.headers.get("CF-Connecting-IP") ?? "0.0.0.0"; }
function parseJson<T>(s: string | null, fallback: T): T { try { return s ? JSON.parse(s) : fallback; } catch { return fallback; } }

async function readJson(req: Request): Promise<any> {
  try { return await req.json(); } catch { fail(400, "Body must be JSON."); }
}

async function enforceLimit(limiter: RateLimiter | undefined, key: string): Promise<void> {
  if (!limiter) return;
  try {
    const { success } = await limiter.limit({ key });
    if (!success) fail(429, "Too many requests. Try again in a minute.", { "Retry-After": "60" });
  } catch (e) {
    if (e instanceof HttpError) throw e;
  }
}

// ---------- identity ----------

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function identify(req: Request, env: Env, create: boolean): Promise<Player | null> {
  const auth = req.headers.get("Authorization");
  if (auth && auth.startsWith("Bearer ")) {
    const hash = await sha256Hex(auth.slice(7).trim());
    const row = await env.DB.prepare("SELECT id, kind, name, featured, setter FROM players WHERE token_hash = ?").bind(hash).first<Player>();
    if (!row) fail(401, "Unknown agent token.");
    return row;
  }
  const pid = req.headers.get("X-Player-Id");
  if (!pid) return null;
  if (!UUID_RE.test(pid)) fail(400, "X-Player-Id must be a UUID.");
  const id = pid.toLowerCase();
  const row = await env.DB.prepare("SELECT id, kind, name, featured, setter FROM players WHERE id = ?").bind(id).first<Player>();
  if (row) return row;
  if (!create) return { id, kind: "human", name: null, featured: 0, setter: 0 };
  const ts = nowIso();
  await env.DB.prepare("INSERT OR IGNORE INTO players (id, kind, created_at, last_seen) VALUES (?, 'human', ?, ?)").bind(id, ts, ts).run();
  return { id, kind: "human", name: null, featured: 0, setter: 0 };
}

async function requireViewer(req: Request, env: Env, create = true): Promise<Player> {
  const v = await identify(req, env, create);
  if (!v) fail(401, "Send X-Player-Id (humans) or an agent bearer token.");
  return v;
}

function requireAdmin(req: Request, env: Env): void {
  const t = req.headers.get("X-Admin-Token");
  if (!env.ADMIN_TOKEN || !t || t !== env.ADMIN_TOKEN) fail(403, "Admin token required.");
}

// ---------- rounds ----------

interface RoundRow { date: string; tier: number; machine_a: string; machine_b: string; finalized_at: string | null }

async function getMachine(env: Env, id: string): Promise<MachineRow | null> {
  return env.DB.prepare("SELECT * FROM machines WHERE id = ?").bind(id).first<MachineRow>();
}

/** The round for a date; assembled on first request for today from pending house machines, then the pool. */
async function roundFor(env: Env, date: string): Promise<RoundRow | null> {
  const row = await env.DB.prepare("SELECT * FROM rounds WHERE date = ?").bind(date).first<RoundRow>();
  if (row) return row;
  if (date !== todayUtc()) return null;
  const tier = tierForDate(date);
  const { results: pending } = await env.DB.prepare(
    "SELECT m.id FROM machines m JOIN players p ON p.id = m.setter_id WHERE m.status = 'pending' AND m.date = ? AND m.tier = ? ORDER BY p.name, m.created_at",
  ).bind(date, tier).all<{ id: string }>();
  const chosen = pending.slice(0, 2).map((m) => m.id);
  if (chosen.length < 2) {
    const { results: pool } = await env.DB.prepare(
      "SELECT id FROM machines WHERE status = 'pool' AND tier = ? ORDER BY random() LIMIT ?",
    ).bind(tier, 2 - chosen.length).all<{ id: string }>();
    chosen.push(...pool.map((m) => m.id));
  }
  if (chosen.length < 2) return null;
  const ts = nowIso();
  await env.DB.batch([
    env.DB.prepare("UPDATE machines SET status = 'published', date = ?, slot = 'a' WHERE id = ? AND status IN ('pending','pool')").bind(date, chosen[0]),
    env.DB.prepare("UPDATE machines SET status = 'published', date = ?, slot = 'b' WHERE id = ? AND status IN ('pending','pool')").bind(date, chosen[1]),
    env.DB.prepare("INSERT OR IGNORE INTO rounds (date, tier, machine_a, machine_b) VALUES (?, ?, ?, ?)").bind(date, tier, chosen[0], chosen[1]),
  ]);
  const final = await env.DB.prepare("SELECT * FROM rounds WHERE date = ?").bind(date).first<RoundRow>();
  if (final && (final.machine_a !== chosen[0] || final.machine_b !== chosen[1])) {
    // Lost a race: put our picks back.
    await env.DB.batch(chosen.map((id) => env.DB.prepare("UPDATE machines SET status = CASE WHEN setter_id IS NULL THEN 'pool' ELSE 'pending' END, slot = NULL, date = CASE WHEN setter_id IS NULL THEN NULL ELSE date END WHERE id = ? AND id NOT IN (?, ?)").bind(id, final.machine_a, final.machine_b)));
  }
  void ts;
  return final;
}

async function playerCount(env: Env, date: string): Promise<number> {
  const row = await env.DB.prepare("SELECT player_count FROM round_counts WHERE date = ?").bind(date).first<{ player_count: number }>();
  return row?.player_count ?? 0;
}

async function setterOf(env: Env, m: MachineRow): Promise<{ name: string; kind: string }> {
  if (!m.setter_id) return { name: HOUSE_NAME, kind: "house" };
  const p = await env.DB.prepare("SELECT id, name FROM players WHERE id = ?").bind(m.setter_id).first<{ id: string; name: string | null }>();
  return { name: p ? displayName(p) : HOUSE_NAME, kind: "agent" };
}

// ---------- plays ----------

async function getPlay(env: Env, machineId: string, playerId: string): Promise<PlayRow | null> {
  return env.DB.prepare("SELECT * FROM plays WHERE machine_id = ? AND player_id = ?").bind(machineId, playerId).first<PlayRow>();
}

async function ensurePlay(env: Env, machineId: string, playerId: string): Promise<PlayRow> {
  const existing = await getPlay(env, machineId, playerId);
  if (existing) return existing;
  const ts = nowIso();
  await env.DB.prepare("INSERT OR IGNORE INTO plays (machine_id, player_id, phase, started_at) VALUES (?, ?, 'experiments', ?)").bind(machineId, playerId, ts).run();
  return (await getPlay(env, machineId, playerId))!;
}

function playView(p: PlayRow | null, m: MachineRow) {
  if (!p) return { phase: "experiments", queries: [], tests: null, answers: null, score: null, star: null };
  const queries = parseJson<Query[]>(p.queries, []);
  return {
    phase: p.phase,
    queries,
    tests: p.phase === "experiments" ? null : parseJson<Seq[]>(m.tests, []),
    answers: parseJson<boolean[] | null>(p.answers, null),
    score: p.score,
    star: p.star_rule ? { rule: parseJson<Ast | null>(p.star_rule, null), hit: !!p.star_hit } : null,
  };
}

/** A machine the viewer may play now: published today, or pending and the viewer is a rival house setter. */
async function playableMachine(env: Env, id: string, viewer: Player): Promise<MachineRow> {
  const m = await getMachine(env, id);
  if (!m) fail(404, "No such machine.");
  if (m.status === "published" && m.date === todayUtc()) return m;
  if (m.status === "pending" && viewer.kind === "agent" && viewer.setter && m.setter_id !== viewer.id) return m;
  if (m.status === "published" && m.date && m.date < todayUtc()) fail(410, "That round is closed.");
  fail(403, "That machine is not open to you.");
}

async function machineCard(env: Env, m: MachineRow, viewer: Player | null) {
  const play = viewer ? await getPlay(env, m.id, viewer.id) : null;
  return {
    id: m.id, slot: m.slot, tier: m.tier, setter: await setterOf(env, m),
    examples: parseJson<{ seq: Seq; accepted: boolean }[]>(m.examples, []),
    example_count: examplesForTier(m.tier),
    max_experiments: MAX_EXPERIMENTS,
    play: playView(play, m),
  };
}

async function getToday(req: Request, env: Env): Promise<Response> {
  const date = todayUtc();
  const round = await roundFor(env, date);
  if (!round) fail(503, "No round is scheduled for today.");
  const viewer = await identify(req, env, false);
  const [a, b] = await Promise.all([getMachine(env, round.machine_a), getMachine(env, round.machine_b)]);
  if (!a || !b) fail(500, "Round is missing a machine.");
  const machines = [await machineCard(env, a, viewer), await machineCard(env, b, viewer)];
  return json({
    date, closes_at: closesAt(date), tier: round.tier, tier_text: TIER_TEXT[round.tier], vocabulary: VOCABULARY,
    machines, finished: machines.every((m) => m.play.phase === "answered"),
    player_count: await playerCount(env, date), sponsor: await sponsorLine(env), server_time: nowIso(),
  });
}

async function postNote(req: Request, env: Env, id: string): Promise<Response> {
  await enforceLimit(env.WRITE_LIMIT, clientIp(req));
  const viewer = await requireViewer(req, env);
  const m = await playableMachine(env, id, viewer);
  const body = await readJson(req);
  const text = String(body?.text ?? "").replace(/\s+/g, " ").trim().slice(0, MAX_NOTE);
  const play = await ensurePlay(env, m.id, viewer.id);
  if (play.phase !== "experiments") fail(409, "Experiments are over for this machine.");
  await env.DB.prepare("UPDATE plays SET pending_note = ? WHERE machine_id = ? AND player_id = ?").bind(text || null, m.id, viewer.id).run();
  return json({ ok: true, note: text });
}

async function postExperiment(req: Request, env: Env, id: string): Promise<Response> {
  await enforceLimit(env.WRITE_LIMIT, clientIp(req));
  const viewer = await requireViewer(req, env);
  const m = await playableMachine(env, id, viewer);
  const body = await readJson(req);
  let seq: Seq;
  try { seq = parseSeq(body?.seq); } catch (e) { fail(400, (e as Error).message); }
  const play = await ensurePlay(env, m.id, viewer.id);
  if (play.phase !== "experiments") fail(409, "Experiments are over for this machine.");
  const queries = parseJson<Query[]>(play.queries, []);
  if (queries.length >= MAX_EXPERIMENTS) fail(409, `You have used all ${MAX_EXPERIMENTS} experiments. Ask for the tests.`);
  const rule = parseJson<Ast>(m.rule, null as any);
  const accepted = evaluate(rule, seq);
  const noteRaw = typeof body?.note === "string" ? body.note : play.pending_note ?? "";
  const note = noteRaw.replace(/\s+/g, " ").trim().slice(0, MAX_NOTE);
  const entry: Query = note ? { seq, accepted, note } : { seq, accepted };
  queries.push(entry);
  await env.DB.prepare("UPDATE plays SET queries = ?, pending_note = NULL WHERE machine_id = ? AND player_id = ?").bind(JSON.stringify(queries), m.id, viewer.id).run();
  await env.DB.prepare("UPDATE players SET last_seen = ? WHERE id = ?").bind(nowIso(), viewer.id).run();
  return json({ accepted, queries, remaining: MAX_EXPERIMENTS - queries.length });
}

async function postTests(req: Request, env: Env, id: string): Promise<Response> {
  await enforceLimit(env.WRITE_LIMIT, clientIp(req));
  const viewer = await requireViewer(req, env);
  const m = await playableMachine(env, id, viewer);
  const play = await ensurePlay(env, m.id, viewer.id);
  if (play.phase === "experiments") {
    await env.DB.prepare("UPDATE plays SET phase = 'tests', pending_note = NULL WHERE machine_id = ? AND player_id = ?").bind(m.id, viewer.id).run();
  }
  return json({ tests: parseJson<Seq[]>(m.tests, []), queries: parseJson<Query[]>(play.queries, []) });
}

async function postAnswer(req: Request, env: Env, id: string): Promise<Response> {
  await enforceLimit(env.WRITE_LIMIT, clientIp(req));
  const viewer = await requireViewer(req, env);
  const m = await playableMachine(env, id, viewer);
  const play = await ensurePlay(env, m.id, viewer.id);
  if (play.phase === "experiments") fail(409, "Ask for the tests before answering.");
  if (play.phase === "answered") fail(409, "You already answered this machine.");
  const body = await readJson(req);
  const answers: unknown = body?.answers;
  if (!Array.isArray(answers) || answers.length !== 4 || !answers.every((a) => typeof a === "boolean")) fail(400, "answers must be four booleans.");
  const rule = parseJson<Ast>(m.rule, null as any);
  const tests = parseJson<Seq[]>(m.tests, []);
  const truth = tests.map((t) => evaluate(rule, t));
  const score = truth.filter((t, i) => t === answers[i]).length;
  const ts = nowIso();
  // First answered machine of this round for this player? Then count them.
  const other = m.date ? await env.DB.prepare(
    "SELECT 1 AS x FROM plays p JOIN machines mm ON mm.id = p.machine_id WHERE p.player_id = ? AND mm.date = ? AND mm.status = 'published' AND p.phase = 'answered' AND p.machine_id != ?",
  ).bind(viewer.id, m.date, m.id).first() : null;
  const stmts = [
    env.DB.prepare("UPDATE plays SET phase = 'answered', answers = ?, score = ?, answered_at = ? WHERE machine_id = ? AND player_id = ? AND phase = 'tests'")
      .bind(JSON.stringify(answers), score, ts, m.id, viewer.id),
    env.DB.prepare("UPDATE players SET last_seen = ? WHERE id = ?").bind(ts, viewer.id),
  ];
  if (!other && m.status === "published" && m.date) {
    stmts.push(env.DB.prepare("INSERT INTO round_counts (date, player_count) VALUES (?, 1) ON CONFLICT(date) DO UPDATE SET player_count = player_count + 1").bind(m.date));
  }
  await env.DB.batch(stmts);
  if (m.date) liveCache.delete(m.date);
  return json({ score, truth, answers, reveal: await buildReveal(env, m, viewer) }, 201);
}

async function postStar(req: Request, env: Env, id: string): Promise<Response> {
  await enforceLimit(env.WRITE_LIMIT, clientIp(req));
  const viewer = await requireViewer(req, env);
  const m = await getMachine(env, id);
  if (!m) fail(404, "No such machine.");
  const play = await getPlay(env, m.id, viewer.id);
  if (!play || play.phase !== "answered") fail(409, "Answer the tests before guessing the rule.");
  if (play.star_rule) fail(409, "You already guessed the rule for this machine.");
  const body = await readJson(req);
  try { checkAst(body?.rule, m.tier); } catch (e) { fail(400, e instanceof RuleError ? e.message : "Bad rule."); }
  const guess = body.rule as Ast;
  const rule = parseJson<Ast>(m.rule, null as any);
  const ce = counterexample(guess, rule);
  const hit = ce === null;
  await env.DB.prepare("UPDATE plays SET star_rule = ?, star_hit = ? WHERE machine_id = ? AND player_id = ?").bind(JSON.stringify(guess), hit ? 1 : 0, m.id, viewer.id).run();
  if (m.date) liveCache.delete(m.date);
  return json({
    hit, your_rule_text: describe(guess), rule_text: describe(rule),
    counterexample: ce ? { seq: ce, machine: evaluate(rule, ce), yours: evaluate(guess, ce) } : null,
  }, 201);
}

// ---------- reveal & results ----------

async function machineStats(env: Env, m: MachineRow) {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS finished, SUM(score = 4) AS solved, AVG(score) AS mean_score, SUM(star_hit = 1) AS stars,
            AVG(json_array_length(queries)) AS mean_experiments
       FROM plays p JOIN players pl ON pl.id = p.player_id
      WHERE p.machine_id = ? AND p.phase = 'answered' AND pl.kind = 'human'`,
  ).bind(m.id).first<{ finished: number; solved: number | null; mean_score: number | null; stars: number | null; mean_experiments: number | null }>();
  const finished = row?.finished ?? 0;
  return {
    finished,
    solved_pct: finished ? round1(((row?.solved ?? 0) / finished) * 100) : null,
    mean_score: finished ? round1(row?.mean_score ?? 0) : null,
    star_pct: finished ? round1(((row?.stars ?? 0) / finished) * 100) : null,
    mean_experiments: finished ? round1(row?.mean_experiments ?? 0) : null,
  };
}

async function agentTranscripts(env: Env, m: MachineRow) {
  const { results } = await env.DB.prepare(
    `SELECT p.queries, p.answers, p.score, p.star_rule, p.star_hit, pl.name, pl.model
       FROM plays p JOIN players pl ON pl.id = p.player_id
      WHERE p.machine_id = ? AND p.phase = 'answered' AND pl.kind = 'agent' AND (pl.featured = 1 OR pl.setter = 1)
      ORDER BY pl.name`,
  ).bind(m.id).all<{ queries: string; answers: string; score: number; star_rule: string | null; star_hit: number | null; name: string; model: string }>();
  return results.map((r) => ({
    name: r.name, model: r.model,
    queries: parseJson<Query[]>(r.queries, []),
    answers: parseJson<boolean[]>(r.answers, []),
    score: r.score,
    star: r.star_rule ? { rule_text: describe(parseJson<Ast>(r.star_rule, null as any)), hit: !!r.star_hit } : null,
  }));
}

async function buildReveal(env: Env, m: MachineRow, viewer: Player | null) {
  const rule = parseJson<Ast>(m.rule, null as any);
  const tests = parseJson<Seq[]>(m.tests, []);
  const play = viewer ? await getPlay(env, m.id, viewer.id) : null;
  return {
    machine_id: m.id, slot: m.slot, tier: m.tier, date: m.date, setter: await setterOf(env, m),
    rule, rule_text: describe(rule), certificate: m.certificate, candidate_count: m.candidate_count,
    setter_note: m.note, tests, truth: tests.map((t) => evaluate(rule, t)),
    stats: await machineStats(env, m),
    agents: await agentTranscripts(env, m),
    you: play ? playView(play, m) : null,
  };
}

async function getReveal(req: Request, env: Env, id: string): Promise<Response> {
  const viewer = await identify(req, env, false);
  const m = await getMachine(env, id);
  if (!m || m.status !== "published" || !m.date) fail(404, "No such machine.");
  const closed = m.date < todayUtc();
  if (!closed) {
    if (!viewer) fail(401, "Send X-Player-Id or an agent bearer token.");
    const play = await getPlay(env, m.id, viewer.id);
    if (!play || play.phase !== "answered") fail(403, "Answer the tests before looking at the reveal.");
  }
  return json(await buildReveal(env, m, viewer));
}

const liveCache = new Map<string, { at: number; scores: DayScore[] }>();

async function dayScores(env: Env, date: string, fresh = false): Promise<DayScore[]> {
  const hit = liveCache.get(date);
  if (!fresh && hit && Date.now() - hit.at < LIVE_CACHE_MS) return hit.scores;
  const { results } = await env.DB.prepare(
    `SELECT p.player_id, pl.name, pl.kind, SUM(p.score) AS score, SUM(COALESCE(p.star_hit, 0)) AS stars,
            SUM(json_array_length(p.queries)) AS experiments
       FROM plays p JOIN machines m ON m.id = p.machine_id JOIN players pl ON pl.id = p.player_id
      WHERE m.date = ? AND m.status = 'published' AND p.phase = 'answered'
      GROUP BY p.player_id`,
  ).bind(date).all<{ player_id: string; name: string | null; kind: string; score: number; stars: number; experiments: number }>();
  const scores: DayScore[] = results.map((r) => ({
    player_id: r.player_id, name: displayName({ id: r.player_id, name: r.name }), kind: r.kind,
    score: r.score, stars: r.stars, experiments: r.experiments, rank: 0,
  }));
  scores.sort((a, b) => b.score - a.score || b.stars - a.stars || a.experiments - b.experiments || a.name.localeCompare(b.name));
  let rank = 0;
  scores.forEach((s, i) => {
    const prev = scores[i - 1];
    if (i === 0 || s.score !== prev.score || s.stars !== prev.stars || s.experiments !== prev.experiments) rank = i + 1;
    s.rank = rank;
  });
  liveCache.set(date, { at: Date.now(), scores });
  return scores;
}

async function isFinalized(env: Env, date: string): Promise<boolean> {
  const row = await env.DB.prepare("SELECT finalized_at FROM rounds WHERE date = ?").bind(date).first<{ finalized_at: string | null }>();
  return !!row?.finalized_at;
}

async function finalize(env: Env, date: string): Promise<number> {
  if (date >= todayUtc()) fail(400, "Round is still open.");
  const round = await env.DB.prepare("SELECT date FROM rounds WHERE date = ?").bind(date).first();
  if (!round) fail(404, "No round for that date.");
  const scores = await dayScores(env, date, true);
  const n = await playerCount(env, date);
  const stmts: D1PreparedStatement[] = [env.DB.prepare("DELETE FROM scores WHERE date = ?").bind(date)];
  for (const s of scores) {
    stmts.push(env.DB.prepare("INSERT INTO scores (date, player_id, score, stars, experiments, rank, player_count) VALUES (?, ?, ?, ?, ?, ?, ?)").bind(date, s.player_id, s.score, s.stars, s.experiments, s.rank, n));
  }
  stmts.push(env.DB.prepare("UPDATE rounds SET finalized_at = ? WHERE date = ?").bind(nowIso(), date));
  for (let i = 0; i < stmts.length; i += 100) await env.DB.batch(stmts.slice(i, i + 100));
  liveCache.delete(date);
  return scores.length;
}

async function scoresFor(env: Env, date: string): Promise<{ final: boolean; scores: DayScore[] }> {
  if (await isFinalized(env, date)) {
    const { results } = await env.DB.prepare(
      "SELECT s.player_id, p.name, p.kind, s.score, s.stars, s.experiments, s.rank FROM scores s JOIN players p ON p.id = s.player_id WHERE s.date = ? ORDER BY s.rank, p.name",
    ).bind(date).all<{ player_id: string; name: string | null; kind: string; score: number; stars: number; experiments: number; rank: number }>();
    return { final: true, scores: results.map((r) => ({ ...r, name: displayName({ id: r.player_id, name: r.name }) })) };
  }
  return { final: false, scores: await dayScores(env, date) };
}

async function buildResults(env: Env, date: string, viewer: Player | null) {
  const round = await roundFor(env, date);
  if (!round) fail(404, "No round for that date.");
  const closed = date < todayUtc();
  const [a, b] = await Promise.all([getMachine(env, round.machine_a), getMachine(env, round.machine_b)]);
  if (!a || !b) fail(500, "Round is missing a machine.");
  const { final, scores } = await scoresFor(env, date);
  const machines = [];
  for (const m of [a, b]) {
    const play = viewer ? await getPlay(env, m.id, viewer.id) : null;
    const answered = play?.phase === "answered";
    machines.push({
      id: m.id, slot: m.slot, tier: m.tier, setter: await setterOf(env, m),
      stats: await machineStats(env, m),
      // The rule is public once the round is closed, or once this viewer has answered.
      rule_text: closed || answered ? describe(parseJson<Ast>(m.rule, null as any)) : null,
      you: play ? { phase: play.phase, score: play.score, experiments: parseJson<Query[]>(play.queries, []).length, star: play.star_hit === 1 } : null,
    });
  }
  const me = viewer ? scores.find((s) => s.player_id === viewer.id) : undefined;
  return {
    date, final, closed, closes_at: closesAt(date), tier: round.tier, player_count: await playerCount(env, date),
    server_time: nowIso(), sponsor: await sponsorLine(env),
    you: me ? { score: me.score, stars: me.stars, experiments: me.experiments, rank: me.rank } : null,
    machines,
    leaderboard: scores.slice(0, 10).map((s) => ({ name: s.name, kind: s.kind, score: s.score, stars: s.stars, experiments: s.experiments, rank: s.rank })),
  };
}

async function getResults(req: Request, env: Env, date: string): Promise<Response> {
  if (!isDate(date)) fail(400, "Bad date.");
  const viewer = await identify(req, env, false);
  if (date > todayUtc()) fail(404, "That round has not opened.");
  const closed = date < todayUtc();
  if (closed && !(await isFinalized(env, date))) { try { await finalize(env, date); } catch { /* no round */ } }
  return json(await buildResults(env, date, viewer), 200, closed ? { "Cache-Control": "public, max-age=300" } : {});
}

// ---------- me, leaderboard, agents ----------

async function checkNickname(env: Env, nickname: string): Promise<void> {
  const problem = validateNickname(nickname);
  if (problem) fail(400, problem);
  const clash = await env.DB.prepare("SELECT 1 AS x FROM players WHERE kind = 'agent' AND lower(name) = lower(?)").bind(nickname).first();
  if (clash) fail(400, "That name belongs to an agent. Please pick another.");
  if (nickname.toLowerCase() === HOUSE_NAME.toLowerCase()) fail(400, "Please pick a different nickname.");
  if ((await screenText(env.AI, nickname, NICKNAME_CONTEXT)) === "unsafe") fail(400, "Please pick a different nickname.");
}

async function getMe(req: Request, env: Env): Promise<Response> {
  const viewer = await requireViewer(req, env, false);
  const [finals, played] = await Promise.all([
    env.DB.prepare("SELECT date, score, stars, experiments, rank, player_count FROM scores WHERE player_id = ? ORDER BY date DESC LIMIT 400").bind(viewer.id)
      .all<{ date: string; score: number; stars: number; experiments: number; rank: number; player_count: number }>(),
    env.DB.prepare(
      "SELECT m.date, COUNT(*) AS answered FROM plays p JOIN machines m ON m.id = p.machine_id WHERE p.player_id = ? AND p.phase = 'answered' AND m.status = 'published' GROUP BY m.date ORDER BY m.date DESC LIMIT 400",
    ).bind(viewer.id).all<{ date: string; answered: number }>(),
  ]);
  const rounds = finals.results.map((r) => ({ ...r, final: true }));
  const today = todayUtc();
  const playedToday = played.results.find((p) => p.date === today);
  if (playedToday) {
    const live = await dayScores(env, today);
    const me = live.find((s) => s.player_id === viewer.id);
    if (me) rounds.unshift({ date: today, score: me.score, stars: me.stars, experiments: me.experiments, rank: me.rank, player_count: await playerCount(env, today), final: false });
  }
  const complete = new Set(played.results.filter((p) => p.answered >= 2).map((p) => p.date));
  let streak = 0;
  let cursor = complete.has(today) ? today : daysAgo(1);
  while (complete.has(cursor)) { streak++; cursor = daysAgo(1, new Date(Date.parse(cursor + "T12:00:00Z"))); }
  const lifetime = finals.results.length ? round1(finals.results.reduce((a, r) => a + r.score, 0) / finals.results.length) : null;
  const totalStars = rounds.reduce((a, r) => a + r.stars, 0); // includes today's live stars
  let setter: unknown = null;
  if (viewer.kind === "agent" && viewer.setter) setter = await setterSummary(env, viewer.id);
  return json({
    id: viewer.id, kind: viewer.kind, name: displayName(viewer), nickname: viewer.name,
    lifetime_score: lifetime, rounds_played: played.results.length, streak, stars: totalStars, setter, rounds,
  });
}

async function putMe(req: Request, env: Env): Promise<Response> {
  await enforceLimit(env.WRITE_LIMIT, clientIp(req));
  const viewer = await requireViewer(req, env);
  if (viewer.kind !== "human") fail(400, "Agents rename by re-registering.");
  const body = await readJson(req);
  const raw = typeof body?.nickname === "string" ? body.nickname : "";
  let nickname: string | null = null;
  if (raw.trim()) {
    nickname = raw.replace(/\s+/g, " ").trim();
    if (nickname !== viewer.name) await checkNickname(env, nickname as string);
  }
  await env.DB.prepare("UPDATE players SET name = ?, last_seen = ? WHERE id = ?").bind(nickname, nowIso(), viewer.id).run();
  liveCache.clear();
  return json({ id: viewer.id, name: displayName({ ...viewer, name: nickname }), nickname });
}

/** Privacy deletion: anonymise plays (strip notes and guesses), drop the player, scores and reports. */
async function deleteMe(req: Request, env: Env): Promise<Response> {
  await enforceLimit(env.WRITE_LIMIT, clientIp(req));
  const viewer = await requireViewer(req, env, false);
  const { results } = await env.DB.prepare("SELECT machine_id, queries FROM plays WHERE player_id = ?").bind(viewer.id).all<{ machine_id: string; queries: string }>();
  const stmts: D1PreparedStatement[] = [];
  for (const p of results) {
    const stripped = parseJson<Query[]>(p.queries, []).map((q) => ({ seq: q.seq, accepted: q.accepted }));
    stmts.push(env.DB.prepare("UPDATE plays SET player_id = 'deleted-' || lower(hex(randomblob(8))), queries = ?, pending_note = NULL, star_rule = NULL WHERE machine_id = ? AND player_id = ?").bind(JSON.stringify(stripped), p.machine_id, viewer.id));
  }
  stmts.push(
    env.DB.prepare("DELETE FROM scores WHERE player_id = ?").bind(viewer.id),
    env.DB.prepare("DELETE FROM reports WHERE player_id = ?").bind(viewer.id),
    env.DB.prepare("DELETE FROM players WHERE id = ?").bind(viewer.id),
  );
  for (let i = 0; i < stmts.length; i += 100) await env.DB.batch(stmts.slice(i, i + 100));
  liveCache.clear();
  return json({ ok: true, message: "Your player record, nickname, scores, notes and history are gone. Past plays remain only as anonymous counts." });
}

async function setterSummary(env: Env, setterId: string) {
  const { results } = await env.DB.prepare(
    `SELECT m.id, m.date, m.slot, m.tier,
            (SELECT COUNT(*) FROM plays p JOIN players pl ON pl.id = p.player_id WHERE p.machine_id = m.id AND p.phase = 'answered' AND pl.kind = 'human') AS finished,
            (SELECT SUM(p.score = 4) FROM plays p JOIN players pl ON pl.id = p.player_id WHERE p.machine_id = m.id AND p.phase = 'answered' AND pl.kind = 'human') AS solved,
            (SELECT AVG(p.score) FROM plays p JOIN players pl ON pl.id = p.player_id WHERE p.machine_id = m.id AND p.phase = 'answered' AND pl.kind = 'human') AS mean_score,
            (SELECT MIN(p.score) FROM plays p JOIN players pl ON pl.id = p.player_id WHERE p.machine_id = m.id AND p.phase = 'answered' AND pl.kind = 'agent' AND pl.setter = 1) AS rival_score
       FROM machines m WHERE m.setter_id = ? AND m.status = 'published' AND m.date < ? ORDER BY m.date DESC LIMIT 60`,
  ).bind(setterId, todayUtc()).all<{ id: string; date: string; slot: string; tier: number; finished: number; solved: number | null; mean_score: number | null; rival_score: number | null }>();
  const rows = results.map((r) => {
    const solvedPct = r.finished ? ((r.solved ?? 0) / r.finished) * 100 : null;
    let points = 0;
    if (solvedPct !== null && r.finished >= 5) {
      if (solvedPct >= 40 && solvedPct <= 70) points = 2;
      else if (solvedPct >= 30 && solvedPct <= 80) points = 1;
      if (r.rival_score !== null && r.rival_score < 4 && solvedPct >= 40) points += 1;
    }
    return { machine_id: r.id, date: r.date, slot: r.slot, tier: r.tier, finished: r.finished, solved_pct: solvedPct === null ? null : round1(solvedPct), mean_score: r.mean_score === null ? null : round1(r.mean_score), rival_score: r.rival_score, points };
  });
  return { machines: rows.length, points: rows.reduce((a, r) => a + r.points, 0), recent: rows.slice(0, 14) };
}

async function getLeaderboard(req: Request, env: Env): Promise<Response> {
  const period = new URL(req.url).searchParams.get("period") ?? "today";
  if (period === "today") {
    const date = todayUtc();
    const { final, scores } = await scoresFor(env, date);
    return json({ period, date, final, player_count: await playerCount(env, date), players: scores.slice(0, 100).map((s) => ({ name: s.name, kind: s.kind, score: s.score, stars: s.stars, experiments: s.experiments, rank: s.rank })) });
  }
  if (period === "setters") {
    const { results } = await env.DB.prepare("SELECT id, name, model FROM players WHERE kind = 'agent' AND setter = 1 ORDER BY name").all<{ id: string; name: string; model: string }>();
    const setters = [];
    for (const s of results) setters.push({ name: s.name, model: s.model, ...(await setterSummary(env, s.id)) });
    setters.sort((a, b) => b.points - a.points);
    return json({ period, setters }, 200, { "Cache-Control": "public, max-age=300" });
  }
  if (period !== "30d") fail(400, "period must be today, 30d or setters.");
  const { results } = await env.DB.prepare(
    `SELECT s.player_id, p.name, p.kind, AVG(s.score) AS score, SUM(s.stars) AS stars, COUNT(*) AS rounds
       FROM scores s JOIN players p ON p.id = s.player_id
      WHERE s.date >= ? GROUP BY s.player_id HAVING COUNT(*) >= ?
      ORDER BY score DESC, stars DESC LIMIT 100`,
  ).bind(daysAgo(30), LEADERBOARD_MIN_ROUNDS).all<{ player_id: string; name: string | null; kind: string; score: number; stars: number; rounds: number }>();
  let rank = 0;
  const players = results.map((r, i) => {
    const score = round1(r.score);
    if (i === 0 || score < round1(results[i - 1].score)) rank = i + 1;
    return { name: displayName({ id: r.player_id, name: r.name }), kind: r.kind, score, stars: r.stars, rounds: r.rounds, rank };
  });
  return json({ period, since: daysAgo(30), min_rounds: LEADERBOARD_MIN_ROUNDS, players }, 200, { "Cache-Control": "public, max-age=300" });
}

async function registerAgent(req: Request, env: Env): Promise<Response> {
  const ip = clientIp(req);
  await enforceLimit(env.REGISTER_LIMIT, ip);
  const ipHash = (await sha256Hex("reg:" + ip)).slice(0, 32);
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM players WHERE kind = 'agent' AND ip_hash = ? AND created_at >= ?").bind(ipHash, new Date(Date.now() - 86_400_000).toISOString()).first<{ n: number }>();
  if ((recent?.n ?? 0) >= REGISTRATIONS_PER_DAY_PER_IP) fail(429, "Registration limit reached for today.", { "Retry-After": "86400" });
  const body = await readJson(req);
  const name = String(body?.name ?? "").replace(/\s+/g, " ").trim();
  const model = String(body?.model ?? "").trim().slice(0, 80);
  const operator = String(body?.operator ?? "").trim().slice(0, 80);
  const url = body?.url ? String(body.url).trim().slice(0, 200) : null;
  if (name.length < 2 || name.length > 40) fail(400, "name must be 2-40 characters.");
  if (!/^[\p{L}\p{N} ._-]+$/u.test(name)) fail(400, "name may use letters, digits, spaces, . _ -");
  if (isBlocked(name.toLowerCase()) || name.toLowerCase() === HOUSE_NAME.toLowerCase()) fail(400, "Please pick a different name.");
  if (!model) fail(400, "model is required (e.g. claude-fable-5-1).");
  if (url && !/^https?:\/\//.test(url)) fail(400, "url must be http(s).");
  const modelVersion = body?.model_version ? String(body.model_version).trim().slice(0, 60) : null;
  let settings: unknown = body?.settings ?? null;
  if (settings !== null && typeof settings !== "object") settings = String(settings).slice(0, 300);
  const config = modelVersion || settings ? JSON.stringify({ model_version: modelVersion, settings }).slice(0, 1000) : null;
  if ((await screenText(env.AI, `${name} (${model}, ${operator})`, NICKNAME_CONTEXT)) === "unsafe") fail(400, "Please pick a different name.");
  const id = "agent-" + crypto.randomUUID();
  const token = randomToken();
  const ts = nowIso();
  try {
    await env.DB.prepare(
      "INSERT INTO players (id, kind, name, model, operator, url, token_hash, ip_hash, config, created_at, last_seen) VALUES (?, 'agent', ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    ).bind(id, name, model, operator, url, await sha256Hex(token), ipHash, config, ts, ts).run();
  } catch (e: any) {
    if (String(e?.message ?? e).includes("UNIQUE")) fail(409, "An agent with that name already exists.");
    throw e;
  }
  return json({ agent_id: id, name, token, note: "Store the token; it is not shown again. Send it as 'Authorization: Bearer <token>'." }, 201);
}

async function listAgents(env: Env): Promise<Response> {
  const { results } = await env.DB.prepare(
    `SELECT p.id, p.name, p.model, p.operator, p.url, p.featured, p.setter, p.config, p.created_at,
            (SELECT COUNT(DISTINCT m.date) FROM plays pl JOIN machines m ON m.id = pl.machine_id WHERE pl.player_id = p.id AND pl.phase = 'answered') AS rounds,
            (SELECT AVG(score) FROM scores sc WHERE sc.player_id = p.id AND sc.date >= ?) AS score_30d
       FROM players p WHERE p.kind = 'agent' ORDER BY p.setter DESC, p.featured DESC, rounds DESC, p.name`,
  ).bind(daysAgo(30)).all<any>();
  const parse = (c: string | null) => { try { return c ? JSON.parse(c) : null; } catch { return c; } };
  return json({ agents: results.map((a) => ({ ...a, config: parse(a.config), featured: !!a.featured, setter: !!a.setter, score_30d: a.score_30d == null ? null : round1(a.score_30d) })) }, 200, { "Cache-Control": "public, max-age=300" });
}

async function postReport(req: Request, env: Env): Promise<Response> {
  await enforceLimit(env.WRITE_LIMIT, clientIp(req));
  const viewer = await requireViewer(req, env, false);
  const body = await readJson(req);
  const name = String(body?.nickname ?? "").replace(/\s+/g, " ").trim();
  if (!name) fail(400, "nickname is required.");
  const exists = await env.DB.prepare("SELECT 1 AS x FROM players WHERE lower(name) = lower(?)").bind(name).first();
  if (!exists) fail(400, "No player has that nickname.");
  await env.DB.prepare("INSERT OR IGNORE INTO reports (date, key, player_id, created_at) VALUES (?, ?, ?, ?)").bind(todayUtc(), name.toLowerCase(), viewer.id, nowIso()).run();
  return json({ ok: true, message: "Thanks. A human will look at it." }, 201);
}

// ---------- setters (house constructors) ----------

function requireSetter(viewer: Player): void {
  if (viewer.kind !== "agent" || !viewer.setter) fail(403, "Only house setters can do that.");
}

async function postSetterMachine(req: Request, env: Env): Promise<Response> {
  await enforceLimit(env.WRITE_LIMIT, clientIp(req));
  const viewer = await requireViewer(req, env, false);
  requireSetter(viewer);
  const body = await readJson(req);
  const forDate = String(body?.for_date ?? nextDay(todayUtc()));
  if (!isDate(forDate)) fail(400, "for_date must be YYYY-MM-DD.");
  if (forDate <= todayUtc()) fail(400, "for_date must be a round that has not opened yet.");
  let m;
  try { m = checkMachine(body?.machine ?? body); } catch (e) { fail(400, e instanceof RuleError ? e.message : "Bad machine."); }
  if (m.tier !== tierForDate(forDate)) fail(400, `${forDate} is a tier ${tierForDate(forDate)} day.`);
  const id = "m-" + crypto.randomUUID();
  const worst = typeof m.validation?.worst_case === "number" ? m.validation.worst_case : null;
  await env.DB.batch([
    env.DB.prepare("DELETE FROM machines WHERE status = 'pending' AND date = ? AND setter_id = ?").bind(forDate, viewer.id),
    env.DB.prepare(
      "INSERT INTO machines (id, status, date, tier, setter_id, source, rule, rule_id, examples, tests, certificate, candidate_count, worst_case, note, created_at) VALUES (?, 'pending', ?, ?, ?, 'house', ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    ).bind(id, forDate, m.tier, viewer.id, JSON.stringify(m.rule), m.rule_id ?? "", JSON.stringify(m.examples), JSON.stringify(m.tests), m.certificate ?? "identify", m.validation?.candidate_count ?? null, worst, m.note ?? null, nowIso()),
  ]);
  return json({ ok: true, machine_id: id, date: forDate, tier: m.tier, rule_text: describe(m.rule) }, 201);
}

async function getSetterPending(req: Request, env: Env): Promise<Response> {
  const viewer = await requireViewer(req, env, false);
  requireSetter(viewer);
  const date = new URL(req.url).searchParams.get("date") ?? nextDay(todayUtc());
  if (!isDate(date)) fail(400, "Bad date.");
  const { results } = await env.DB.prepare(
    "SELECT m.id, m.tier, m.examples, p.name AS setter FROM machines m JOIN players p ON p.id = m.setter_id WHERE m.status = 'pending' AND m.date = ? AND m.setter_id != ? ORDER BY p.name",
  ).bind(date, viewer.id).all<{ id: string; tier: number; examples: string; setter: string }>();
  const out = [];
  for (const m of results) {
    const play = await getPlay(env, m.id, viewer.id);
    out.push({ id: m.id, tier: m.tier, tier_text: TIER_TEXT[m.tier], vocabulary: VOCABULARY, setter: m.setter, examples: parseJson(m.examples, []), play: play ? { phase: play.phase, queries: parseJson<Query[]>(play.queries, []).length } : null });
  }
  return json({ date, machines: out });
}

// ---------- sponsor, promos, dataset ----------

async function sponsorLine(env: Env): Promise<{ name: string; tagline: string; url: string } | null> {
  const row = await env.DB.prepare("SELECT name, tagline, url FROM sponsor WHERE active = 1 ORDER BY id DESC LIMIT 1").first<{ name: string; tagline: string; url: string }>();
  return row ?? null;
}

async function getPromos(env: Env): Promise<Response> {
  const { results } = await env.DB.prepare("SELECT id, title, subtitle, url FROM promos WHERE active = 1 ORDER BY sort, id").all();
  return json({ promos: results }, 200, { "Cache-Control": "public, max-age=600" });
}

const DATASET_SCHEMA_VERSION = 1;

async function datasetIndex(env: Env): Promise<Response> {
  const { results } = await env.DB.prepare("SELECT date FROM rounds WHERE finalized_at IS NOT NULL ORDER BY date").all<{ date: string }>();
  return json({
    schema_version: DATASET_SCHEMA_VERSION, license: "CC-BY-4.0", attribution: "Turnstile (turnstile.advancedfield.tech)",
    url_template: "/v1/dataset/{date}.json",
    notes: "One file per finalized round: both machines with rules, examples and tests; aggregate human results; every agent's full transcript.",
    dates: results.map((r) => r.date),
  }, 200, { "Cache-Control": "public, max-age=600" });
}

async function datasetDay(env: Env, date: string): Promise<Response> {
  if (!isDate(date)) fail(400, "Bad date.");
  if (date >= todayUtc()) fail(404, "That round is not final yet.");
  if (!(await isFinalized(env, date))) { try { await finalize(env, date); } catch { fail(404, "No round for that date."); } }
  const round = await env.DB.prepare("SELECT * FROM rounds WHERE date = ?").bind(date).first<RoundRow>();
  if (!round) fail(404, "No round for that date.");
  const machines = [];
  for (const id of [round.machine_a, round.machine_b]) {
    const m = await getMachine(env, id);
    if (!m) continue;
    const rule = parseJson<Ast>(m.rule, null as any);
    const { results: agents } = await env.DB.prepare(
      "SELECT p.queries, p.answers, p.score, p.star_rule, p.star_hit, pl.id, pl.name, pl.model, pl.config FROM plays p JOIN players pl ON pl.id = p.player_id WHERE p.machine_id = ? AND p.phase = 'answered' AND pl.kind = 'agent' ORDER BY pl.name",
    ).bind(m.id).all<any>();
    machines.push({
      id: m.id, slot: m.slot, tier: m.tier, setter: await setterOf(env, m), source: m.source, certificate: m.certificate, candidate_count: m.candidate_count,
      rule, rule_text: describe(rule), setter_note: m.note,
      examples: parseJson(m.examples, []), tests: parseJson<Seq[]>(m.tests, []).map((t) => ({ seq: t, accepted: evaluate(rule, t) })),
      human_stats: await machineStats(env, m),
      agents: agents.map((a) => ({ agent_id: a.id, name: a.name, model: a.model, config: parseJson(a.config, null), queries: parseJson(a.queries, []), answers: parseJson(a.answers, []), score: a.score, star: a.star_rule ? { rule: parseJson(a.star_rule, null), hit: !!a.star_hit } : null })),
    });
  }
  return json({ date, schema_version: DATASET_SCHEMA_VERSION, license: "CC-BY-4.0", finalized_at: round.finalized_at, tier: round.tier, player_count: await playerCount(env, date), machines }, 200, { "Cache-Control": "public, max-age=86400, immutable" });
}

// ---------- admin ----------

async function admin(req: Request, env: Env, path: string): Promise<Response> {
  requireAdmin(req, env);
  let m: RegExpMatchArray | null;
  if (req.method === "POST" && path === "/v1/admin/pool") {
    const body = await readJson(req);
    const list: any[] = Array.isArray(body?.machines) ? body.machines : [];
    const stmts: D1PreparedStatement[] = [];
    const ids: string[] = [];
    for (const raw of list) {
      let mj;
      try { mj = checkMachine(raw); } catch (e) { fail(400, `machine ${ids.length + 1}: ${(e as Error).message}`); }
      const id = "m-" + crypto.randomUUID();
      ids.push(id);
      stmts.push(env.DB.prepare(
        "INSERT INTO machines (id, status, tier, setter_id, source, rule, rule_id, examples, tests, certificate, candidate_count, worst_case, note, created_at) VALUES (?, 'pool', ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      ).bind(id, mj.tier, raw?.source === "generated" ? "generated" : "fallback", JSON.stringify(mj.rule), mj.rule_id ?? "", JSON.stringify(mj.examples), JSON.stringify(mj.tests), mj.certificate ?? "identify", mj.validation?.candidate_count ?? null, typeof mj.validation?.worst_case === "number" ? mj.validation.worst_case : null, mj.note ?? null, nowIso()));
    }
    for (let i = 0; i < stmts.length; i += 50) await env.DB.batch(stmts.slice(i, i + 50));
    return json({ ok: true, added: ids.length, ids }, 201);
  }
  if (req.method === "GET" && path === "/v1/admin/pool") {
    const { results } = await env.DB.prepare("SELECT tier, COUNT(*) AS n FROM machines WHERE status = 'pool' GROUP BY tier").all();
    return json({ pool: results });
  }
  if (req.method === "POST" && (m = path.match(/^\/v1\/admin\/agents\/([^/]+)\/flags$/))) {
    const body = await readJson(req);
    const sets: string[] = []; const binds: unknown[] = [];
    if (body?.featured !== undefined) { sets.push("featured = ?"); binds.push(body.featured ? 1 : 0); }
    if (body?.setter !== undefined) { sets.push("setter = ?"); binds.push(body.setter ? 1 : 0); }
    if (!sets.length) fail(400, "featured and/or setter required.");
    const r = await env.DB.prepare(`UPDATE players SET ${sets.join(", ")} WHERE id = ? AND kind = 'agent'`).bind(...binds, decodeURIComponent(m[1])).run();
    return json({ ok: true, changed: r.meta.changes });
  }
  if (req.method === "GET" && path === "/v1/admin/agents") {
    const { results } = await env.DB.prepare("SELECT id, name, model, operator, url, featured, setter, created_at, last_seen FROM players WHERE kind = 'agent' ORDER BY created_at").all();
    return json({ agents: results });
  }
  if (req.method === "GET" && path === "/v1/admin/machines") {
    const date = new URL(req.url).searchParams.get("date") ?? todayUtc();
    const { results } = await env.DB.prepare("SELECT * FROM machines WHERE date = ? OR (status = 'pending' AND date >= ?) ORDER BY date, slot").bind(date, todayUtc()).all<MachineRow>();
    return json({ machines: results.map((r) => ({ ...r, rule: parseJson(r.rule, null), rule_text: describe(parseJson<Ast>(r.rule, null as any)), examples: parseJson(r.examples, []), tests: parseJson(r.tests, []) })) });
  }
  if (req.method === "POST" && (m = path.match(/^\/v1\/admin\/finalize\/(\d{4}-\d{2}-\d{2})$/))) {
    return json({ ok: true, date: m[1], players: await finalize(env, m[1]) });
  }
  if (req.method === "GET" && path === "/v1/admin/reports") {
    const { results } = await env.DB.prepare("SELECT id, date, key, player_id, created_at FROM reports ORDER BY id DESC LIMIT 200").all();
    return json({ reports: results });
  }
  if (req.method === "POST" && path === "/v1/admin/nickname/clear") {
    const body = await readJson(req);
    const name = String(body?.nickname ?? "").trim();
    if (!name) fail(400, "nickname is required.");
    const r = await env.DB.prepare("UPDATE players SET name = NULL WHERE kind = 'human' AND lower(name) = lower(?)").bind(name).run();
    liveCache.clear();
    return json({ ok: true, cleared: r.meta.changes });
  }
  if (req.method === "POST" && path === "/v1/admin/sponsor") {
    const body = await readJson(req);
    const name = String(body?.name ?? "").trim(), tagline = String(body?.tagline ?? "").trim(), url = String(body?.url ?? "").trim();
    if (body?.clear) { await env.DB.prepare("UPDATE sponsor SET active = 0").run(); return json({ ok: true, cleared: true }); }
    if (!name || !/^https?:\/\//.test(url)) fail(400, "name and an http(s) url are required.");
    await env.DB.batch([
      env.DB.prepare("UPDATE sponsor SET active = 0"),
      env.DB.prepare("INSERT INTO sponsor (name, tagline, url, active) VALUES (?, ?, ?, 1)").bind(name, tagline, url),
    ]);
    return json({ ok: true }, 201);
  }
  if (req.method === "POST" && path === "/v1/admin/promos") {
    const body = await readJson(req);
    const list: any[] = Array.isArray(body?.promos) ? body.promos : [];
    const stmts = [env.DB.prepare("DELETE FROM promos")];
    list.forEach((p, i) => {
      const title = String(p?.title ?? "").trim(), url = String(p?.url ?? "").trim();
      if (!title || !/^https?:\/\//.test(url)) fail(400, `promo ${i + 1} needs a title and an http(s) url.`);
      stmts.push(env.DB.prepare("INSERT INTO promos (title, subtitle, url, sort, active) VALUES (?, ?, ?, ?, 1)").bind(title, p?.subtitle ? String(p.subtitle).trim() : null, url, i));
    });
    await env.DB.batch(stmts);
    return json({ ok: true, count: list.length });
  }
  fail(404, "Unknown admin route.");
}

// ---------- router ----------

async function route(req: Request, env: Env): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const method = req.method;
  const html = (body: string) => new Response(body, { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=3600" } });

  if (method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (path === "/" && method === "GET") return html(landingHtml());
  if (path === "/privacy" && method === "GET") return html(privacyHtml());
  if ((path === "/icon.png" || path === "/favicon.png" || path === "/favicon.ico") && method === "GET") {
    const bytes = pngBytes(path === "/icon.png" ? ICON_512_B64 : ICON_64_B64);
    return new Response(bytes, { headers: { "Content-Type": "image/png", "Cache-Control": "public, max-age=86400" } });
  }
  if ((path === "/agents.md" || path === "/llms.txt") && method === "GET") return new Response(AGENTS_MD, { headers: { "Content-Type": "text/markdown; charset=utf-8", "Cache-Control": "public, max-age=3600", ...CORS } });
  if (path === "/health") return json({ ok: true, date: todayUtc(), tier: tierForDate(todayUtc()), time: nowIso(), rollover_utc_hour: ROLLOVER_HOUR, closes_at: closesAt(todayUtc()) });

  if (path.startsWith("/v1/admin/")) return admin(req, env, path);

  if (path === "/v1/promos" && method === "GET") return getPromos(env);
  if (path === "/v1/dataset" && method === "GET") return datasetIndex(env);

  let m: RegExpMatchArray | null;
  if ((m = path.match(/^\/v1\/dataset\/(\d{4}-\d{2}-\d{2})(?:\.json)?$/)) && method === "GET") return datasetDay(env, m[1]);
  if (path === "/v1/round/today" && method === "GET") return getToday(req, env);
  if ((m = path.match(/^\/v1\/round\/([^/]+)\/results$/)) && method === "GET") return getResults(req, env, m[1]);
  if ((m = path.match(/^\/v1\/machine\/([^/]+)\/note$/)) && method === "POST") return postNote(req, env, m[1]);
  if ((m = path.match(/^\/v1\/machine\/([^/]+)\/experiment$/)) && method === "POST") return postExperiment(req, env, m[1]);
  if ((m = path.match(/^\/v1\/machine\/([^/]+)\/tests$/)) && method === "POST") return postTests(req, env, m[1]);
  if ((m = path.match(/^\/v1\/machine\/([^/]+)\/answer$/)) && method === "POST") return postAnswer(req, env, m[1]);
  if ((m = path.match(/^\/v1\/machine\/([^/]+)\/star$/)) && method === "POST") return postStar(req, env, m[1]);
  if ((m = path.match(/^\/v1\/machine\/([^/]+)\/reveal$/)) && method === "GET") return getReveal(req, env, m[1]);
  if (path === "/v1/me" && method === "GET") return getMe(req, env);
  if (path === "/v1/me" && method === "PUT") return putMe(req, env);
  if (path === "/v1/me" && method === "DELETE") return deleteMe(req, env);
  if (path === "/v1/leaderboard" && method === "GET") return getLeaderboard(req, env);
  if (path === "/v1/agents" && method === "POST") return registerAgent(req, env);
  if (path === "/v1/agents" && method === "GET") return listAgents(env);
  if (path === "/v1/report" && method === "POST") return postReport(req, env);
  if (path === "/v1/setter/machines" && method === "POST") return postSetterMachine(req, env);
  if (path === "/v1/setter/pending" && method === "GET") return getSetterPending(req, env);
  fail(404, "Not found.");
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    try {
      return await route(req, env);
    } catch (e: any) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status, e.headers);
      console.error("unhandled", e?.stack ?? e);
      return json({ error: "Something went wrong on our side." }, 500);
    }
  },

  // Finalize every closed round from the last week that is not frozen yet.
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    const { results } = await env.DB.prepare(
      "SELECT date FROM rounds WHERE date < ? AND date >= ? AND finalized_at IS NULL ORDER BY date",
    ).bind(todayUtc(), daysAgo(7)).all<{ date: string }>();
    for (const r of results) {
      const n = await finalize(env, r.date);
      console.log(`finalized ${r.date}: ${n} players`);
    }
    // Also make sure today's round exists even before anyone opens the app.
    await roundFor(env, todayUtc());
  },
} satisfies ExportedHandler<Env>;
