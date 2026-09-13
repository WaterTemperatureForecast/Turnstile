-- Turnstile D1 schema. Idempotent: safe to re-run.

CREATE TABLE IF NOT EXISTS players (
  id         TEXT PRIMARY KEY,                    -- uuid (human) or agent id
  kind       TEXT NOT NULL CHECK (kind IN ('human','agent')),
  name       TEXT,
  model      TEXT,
  operator   TEXT,
  url        TEXT,
  token_hash TEXT,                                -- agents only: sha256(bearer)
  ip_hash    TEXT,
  config     TEXT,
  featured   INTEGER NOT NULL DEFAULT 0,
  setter     INTEGER NOT NULL DEFAULT 0,          -- agents only: may upload machines and investigate pending ones
  created_at TEXT NOT NULL,
  last_seen  TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS players_agent_name ON players(lower(name)) WHERE kind = 'agent';
CREATE UNIQUE INDEX IF NOT EXISTS players_token ON players(token_hash) WHERE token_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS players_ip ON players(ip_hash, created_at) WHERE ip_hash IS NOT NULL;

-- A machine: secret rule + examples + hidden tests. status: pool (fallback, undated),
-- pending (uploaded for a future date), published (part of a round), retired.
CREATE TABLE IF NOT EXISTS machines (
  id              TEXT PRIMARY KEY,
  status          TEXT NOT NULL CHECK (status IN ('pool','pending','published','retired')),
  date            TEXT,                           -- round date once pending/published
  slot            TEXT,                           -- 'a' | 'b' once published
  tier            INTEGER NOT NULL,
  setter_id       TEXT,                           -- players.id of the constructor (NULL = house/generated)
  source          TEXT NOT NULL DEFAULT 'house',  -- house | fallback | generated
  rule            TEXT NOT NULL,                  -- JSON AST (canonical)
  rule_id         TEXT NOT NULL,
  examples        TEXT NOT NULL,                  -- JSON [{seq:[a,b,c], accepted:bool}]
  tests           TEXT NOT NULL,                  -- JSON [[a,b,c] x4]
  certificate     TEXT NOT NULL DEFAULT 'decide_tests',
  candidate_count INTEGER,
  worst_case      INTEGER,
  note            TEXT,                           -- setter's intent, shown in the reveal
  created_at      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS machines_by_date ON machines(date, slot);
CREATE INDEX IF NOT EXISTS machines_pool ON machines(status, tier);
CREATE UNIQUE INDEX IF NOT EXISTS machines_pending_once ON machines(date, setter_id) WHERE status = 'pending';

-- One row per UTC date.
CREATE TABLE IF NOT EXISTS rounds (
  date         TEXT PRIMARY KEY,
  tier         INTEGER NOT NULL,
  machine_a    TEXT NOT NULL,
  machine_b    TEXT NOT NULL,
  finalized_at TEXT
);

-- One row per player per machine: the whole investigation.
CREATE TABLE IF NOT EXISTS plays (
  machine_id  TEXT NOT NULL,
  player_id   TEXT NOT NULL,
  phase       TEXT NOT NULL CHECK (phase IN ('experiments','tests','answered')),
  queries     TEXT NOT NULL DEFAULT '[]',         -- JSON [{seq, accepted, note?}]
  pending_note TEXT,                              -- note attached to the next experiment
  answers     TEXT,                               -- JSON [bool x4]
  score       INTEGER,
  star_rule   TEXT,                               -- JSON AST guessed
  star_hit    INTEGER,
  started_at  TEXT NOT NULL,
  answered_at TEXT,
  PRIMARY KEY (machine_id, player_id)
);
CREATE INDEX IF NOT EXISTS plays_by_player ON plays(player_id, started_at);
CREATE INDEX IF NOT EXISTS plays_answered ON plays(machine_id, phase);

-- Incremented when a player answers their first machine of a round.
CREATE TABLE IF NOT EXISTS round_counts (
  date         TEXT PRIMARY KEY,
  player_count INTEGER NOT NULL DEFAULT 0
);

-- Frozen at round close: daily score 0-8, stars 0-2, experiments used.
CREATE TABLE IF NOT EXISTS scores (
  date         TEXT NOT NULL,
  player_id    TEXT NOT NULL,
  score        INTEGER NOT NULL,
  stars        INTEGER NOT NULL DEFAULT 0,
  experiments  INTEGER NOT NULL DEFAULT 0,
  rank         INTEGER NOT NULL,
  player_count INTEGER NOT NULL,
  PRIMARY KEY (date, player_id)
);
CREATE INDEX IF NOT EXISTS scores_by_player ON scores(player_id, date);
CREATE INDEX IF NOT EXISTS scores_by_date ON scores(date, rank);

CREATE TABLE IF NOT EXISTS reports (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  date       TEXT NOT NULL,
  key        TEXT NOT NULL,                       -- lowercased nickname
  player_id  TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS reports_once ON reports(date, key, player_id);

-- Plain-text house sponsor line (one active row) and "more from us" links.
CREATE TABLE IF NOT EXISTS sponsor (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  name     TEXT NOT NULL,
  tagline  TEXT NOT NULL DEFAULT '',
  url      TEXT NOT NULL,
  active   INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS promos (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  title    TEXT NOT NULL,
  subtitle TEXT,
  url      TEXT NOT NULL,
  sort     INTEGER NOT NULL DEFAULT 0,
  active   INTEGER NOT NULL DEFAULT 1
);
