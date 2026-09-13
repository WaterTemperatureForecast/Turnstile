#!/usr/bin/env python3
"""Shared plumbing for the Turnstile house agents: API calls, CLI brains
(`claude -p`, `codex exec`; subscriptions only, never API keys), engine import.
Standard library only."""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "engine"))
import rules  # noqa: E402

BASE = os.environ.get("TURNSTILE_URL", "https://turnstile.advancedfield.tech").rstrip("/")
TOKEN_DIR = os.path.join(os.path.expanduser("~"), ".turnstile")

# Task Scheduler runs without the interactive PATH, so resolve the shims explicitly.
CLAUDE = os.environ.get("CLAUDE_CMD") or next(
    (p for p in [os.path.expandvars(r"%APPDATA%\npm\claude.cmd"),
                 os.path.expandvars(r"%LOCALAPPDATA%\Programs\claude\claude.exe")] if os.path.exists(p)), "claude")


def find_codex():
    if os.environ.get("CODEX_EXE"):
        return os.environ["CODEX_EXE"]
    cands = sorted(glob.glob(os.path.expanduser(r"~/.vscode/extensions/openai.chatgpt-*/bin/windows-x86_64/codex.exe")))
    return cands[-1] if cands else "codex"


CODEX = find_codex()

BRAINS = {
    "claude": {"token": "claude.token", "cli": "claude", "model": os.environ.get("CLAUDE_MODEL", "opus"), "name": "Claude Opus 5", "model_id": "claude-opus-5"},
    "gpt": {"token": "gpt.token", "cli": "codex", "name": "GPT-6", "model_id": "gpt-6-astra"},
    "sonnet": {"token": "sonnet.token", "cli": "claude", "model": "sonnet", "name": "Claude Sonnet 5", "model_id": "claude-sonnet-5"},
    "haiku": {"token": "haiku.token", "cli": "claude", "model": "haiku", "name": "Claude Haiku 4.5", "model_id": "claude-haiku-4-5"},
}

TILE_NAMES = [f"{c} {s}" for s in rules.SHAPES for c in rules.COLOURS]  # index = tile id


def log(msg):
    print(msg, flush=True)


def call(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Accept", "application/json")
    req.add_header("User-Agent", "turnstile-house/1.0")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, {"error": str(e)}


def read_token(brain):
    path = os.path.join(TOKEN_DIR, BRAINS[brain]["token"])
    with open(path, encoding="utf-8") as fh:
        return fh.read().strip()


CALL_TIMEOUT = int(os.environ.get("TURNSTILE_CLI_TIMEOUT", "300"))   # a real call is ~70 s; a hung one must not eat the window


def ask(brain, prompt, attempts=2):
    """One model call through the owner's subscription CLI. Returns the reply text.

    A hung CLI is retried once with a fresh process; both CLIs occasionally
    stall for far longer than a normal call (observed 2026-09-13: 900 s with no
    output where the same prompt normally answers in ~70 s). Returns "" when
    every attempt fails, so the caller can stop cleanly and resume next run.
    """
    b = BRAINS[brain]
    for attempt in range(attempts):
        try:
            if b["cli"] == "codex":
                with tempfile.TemporaryDirectory() as tmp:
                    out = os.path.join(tmp, "answer.txt")
                    subprocess.run(
                        [CODEX, "exec", "-C", tmp, "--skip-git-repo-check", "-s", "read-only", "--color", "never", "--ephemeral", "-o", out, "-"],
                        input=prompt, text=True, capture_output=True, timeout=CALL_TIMEOUT, encoding="utf-8",
                    )
                    text = open(out, encoding="utf-8").read() if os.path.exists(out) else ""
            else:
                proc = subprocess.run(
                    [CLAUDE, "-p", "--output-format", "text", "--model", b["model"]],
                    input=prompt, text=True, capture_output=True, timeout=CALL_TIMEOUT, encoding="utf-8", shell=(os.name == "nt"),
                )
                text = proc.stdout or ""
            if text.strip():
                return text
            log(f"{brain}: empty reply on attempt {attempt + 1}")
        except subprocess.TimeoutExpired:
            log(f"{brain}: CLI timed out after {CALL_TIMEOUT}s on attempt {attempt + 1}")
    return ""


def first_json_object(text, any_of=()):
    """The first {...} in the reply that parses (CLIs write prose around it).

    `any_of` is a set of key groups; an object counts only if it has every key
    of at least one group, so a rule AST quoted mid-explanation is not mistaken
    for the answer.
    """
    if not text.strip():
        raise ValueError("empty reply from the CLI")
    depth, start, best = 0, None, None
    for i, ch in enumerate(text):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}" and depth:
            depth -= 1
            if depth == 0 and start is not None:
                try:
                    obj = json.loads(text[start:i + 1])
                except json.JSONDecodeError:
                    start = None
                    continue
                if not any_of:
                    return obj
                if any(all(k in obj for k in group) for group in any_of):
                    return obj
                best = best or obj
                start = None
    if best is not None and not any_of:
        return best
    raise ValueError("no usable JSON object in reply: " + " ".join(text[:300].split()))


def seq_words(seq):
    return ", ".join(TILE_NAMES[t] for t in seq)


def describe(ast):
    op = ast["op"]
    pos = {1: "first", 2: "second", 3: "third"}
    if op == "pos":
        return f"the {pos[ast['i']]} tile is {ast['value']}" if ast["attr"] == "colour" else f"the {pos[ast['i']]} tile is a {ast['value']}"
    if op == "count":
        return f"exactly {ast['n']} {ast['value']} tile(s)"
    if op == "same":
        return f"tiles {ast['i']} and {ast['j']} have the same {ast['attr']}"
    if op == "allsame":
        return f"all three tiles have the same {ast['attr']}"
    if op == "alldiff":
        return f"all three {ast['attr']}s are different"
    if op == "not":
        return "NOT (" + describe(ast["a"]) + ")"
    return f"({describe(ast['a'])}) {op.upper()} ({describe(ast['b'])})"


GRAMMAR_TEXT = """Tiles: shape in {circle, square, triangle} x colour in {red, blue, yellow}. Tile ids are
integers 0-8, shape-major: 0 circle red, 1 circle blue, 2 circle yellow, 3 square red, 4 square blue,
5 square yellow, 6 triangle red, 7 triangle blue, 8 triangle yellow. A sequence is three tiles (repeats allowed).

Rule atoms (JSON):
  {"op":"pos","i":1|2|3,"attr":"shape"|"colour","value":<shape or colour>}   position i has that value
  {"op":"count","attr":"shape"|"colour","value":<value>,"n":0|1|2|3}         exactly n tiles have that value
  {"op":"same","attr":"shape"|"colour","i":1,"j":2}  (i<j)                     positions i and j share the attribute
  {"op":"allsame","attr":"shape"|"colour"}                                     all three share it
  {"op":"alldiff","attr":"shape"|"colour"}                                     all three different
Connectors: {"op":"not","a":<atom>}; {"op":"and"|"or"|"xor","a":<atom>,"b":<atom>} (operands must be atoms; no nesting)."""

TIER_FORMS = {
    1: "Tier 1: the rule is a single atom, or NOT a single atom.",
    2: "Tier 2: a single atom, NOT an atom, or two atoms joined by AND or OR.",
    3: "Tier 3: a single atom, NOT an atom, or two atoms joined by AND, OR or XOR.",
}
