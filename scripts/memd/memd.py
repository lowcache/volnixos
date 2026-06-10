#!/usr/bin/env python3
"""memd — agent-driven project memory curator.

Maintains ./.memory/{state,decisions,mistakes,todo}.md (+ archive/, inbox/)
across projects, CLIs (claude-code, antigravity, others), and agent swarms.

Triggers:
  - claude-code hooks: SessionStart (context brief), SessionEnd / PreCompact
    (background distill of the session transcript)
  - systemd user timer: `memd sweep` catches missed sessions, inbox notes
    from other CLIs/agents, pruning, and auto-detects new projects.

Distillation brain: headless `claude -p` (haiku by default, sonnet for large
end-of-session distills) with a curator charter prompt. memd itself enforces
the invariants the model must not be trusted with: frontmatter, append-only
mistakes.md, shrink guard, size budgets, archive overflow, git audit commits.
"""

import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CONFIG_DIR = os.path.join(HOME, ".config", "memd")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")
STATE_DIR = os.path.join(HOME, ".local", "state", "memd")
CURSORS_PATH = os.path.join(STATE_DIR, "cursors.json")
AG_INDEX_PATH = os.path.join(STATE_DIR, "ag_index.json")
META_PATH = os.path.join(STATE_DIR, "meta.json")
LOCK_DIR = os.path.join(STATE_DIR, "locks")
LOG_PATH = os.path.join(STATE_DIR, "memd.log")
CLAUDE_PROJECTS_DIR = os.path.join(HOME, ".claude", "projects")
CLAUDE_SETTINGS = os.path.join(HOME, ".claude", "settings.json")

MEMORY_FILES = ("state.md", "decisions.md", "mistakes.md", "todo.md")

DEFAULT_CONFIG = {
    "claude_bin": "claude",
    "antigravity_dir": os.path.join(HOME, ".gemini", "antigravity-cli"),
    "model_small": "haiku",
    "model_large": "sonnet",
    "escalate_chars": 15000,        # session-end digests above this go to model_large
    "digest_cap_chars": 60000,      # max transcript digest fed to the model
    "quiet_seconds": 600,           # sweep skips transcripts modified more recently
    "auto_scaffold": True,          # scaffold .memory/ in detected git-root projects
    "git_commit": True,             # commit .memory/ changes after each distill
    "budgets": {                    # active-file size budgets (chars of body)
        "state.md": 10000,
        "decisions.md": 12000,
        "todo.md": 10000,
        "mistakes.md": 22000,
    },
    "exclude": [],                  # absolute paths never auto-managed
    "projects": {},                 # path -> {"name": str, "extra_sources": [globs]}
}

# --------------------------------------------------------------------------
# curator charter — the system contract for the distillation model
# --------------------------------------------------------------------------

CHARTER = """\
You are a project-memory curator. You receive (1) the current contents of a
project's .memory/ files and (2) a digest of recent AI work sessions on that
project (possibly from several agents, CLIs, or a swarm). You produce updated
memory files. You are not a participant in the project; you are its archivist.

FILE PURPOSES
- state.md: single source of truth for CURRENT live status: configs, directory
  maps, services, ports, active workarounds, hardware facts. Present tense.
  Replace stale facts; never accumulate history here.
- decisions.md: active canonical architecture decisions and preferences.
  Each entry: what was decided, why, and what it rules out. Only decisions
  that constrain future work. Superseded decisions move to archive.
- mistakes.md: append-only audit log of configuration/implementation mistakes:
  symptom, root cause, exact prevention rule. You may only ADD entries.
- todo.md: open tasks, roadmap, pending verification loops. Completed or
  abandoned items move to archive, they do not linger.

SIGNAL VS NOISE — keep only what a FUTURE session needs:
KEEP: decisions made and their rationale; state changes (services, files,
ports, versions, paths); discovered constraints and gotchas; root causes of
failures and their fixes; open threads and explicitly deferred work; exact
commands/flags that were hard to derive; scope agreements with the user.
DISCARD: conversational chatter, tangents, abandoned exploration that taught
nothing, restated file contents, tool-call play-by-play, anything derivable
by reading the repo itself, pleasantries, duplicate statements of known facts.
When in doubt: would omitting this cause a future agent to repeat work or
repeat a mistake? If no, discard.

STYLE
- Succinct and thorough. Dense declarative prose or tight bullets.
- No meta-commentary ("in this session we..."), no praise, no hedging.
- Use absolute dates (YYYY-MM-DD), never "today"/"recently".
- Stay grounded in the project's stated scope; do not invent goals.
- Preserve existing structure and headings where they still serve.

MECHANICS
- Do NOT emit YAML frontmatter; the tool manages it.
- Do NOT rewrite mistakes.md; only supply new entries.
- If a file needs no change, return null for it.
- If files exceed their budgets (given below), move the least-current
  sections into archive_entries rather than deleting them.
- Multiple agents may have worked in parallel; merge their threads, dedupe.

OUTPUT — exactly one JSON object, no markdown fences, no prose around it:
{
  "summary": "<one line: what changed in memory>",
  "state_body": "<full new body without frontmatter, or null>",
  "decisions_body": "<full new body, or null>",
  "todo_body": "<full new body, or null>",
  "mistakes_new_entries": ["### YYYY-MM-DD — <title>\\n<symptom/cause/prevention>", ...],
  "archive_entries": [{"source": "<file it came from>", "content": "<verbatim section>"}, ...]
}
"""

BRIEF_NOTE = (
    "Project memory is managed by memd. Read .memory/state.md, decisions.md, "
    "mistakes.md, todo.md before substantive work. To leave a note for the "
    "curator from any tool, drop a markdown file in .memory/inbox/."
)

# --------------------------------------------------------------------------
# small utilities
# --------------------------------------------------------------------------


def log(msg):
    os.makedirs(STATE_DIR, exist_ok=True)
    try:
        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > 1_000_000:
            os.replace(LOG_PATH, LOG_PATH + ".old")
    except OSError:
        pass
    stamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_PATH, "a") as f:
        f.write(f"{stamp} {msg}\n")


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return default


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def atomic_write(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def load_config():
    cfg = dict(DEFAULT_CONFIG)
    on_disk = load_json(CONFIG_PATH, {})
    for k, v in on_disk.items():
        if k == "budgets":
            cfg["budgets"] = {**DEFAULT_CONFIG["budgets"], **v}
        else:
            cfg[k] = v
    return cfg


def save_config(cfg):
    save_json(CONFIG_PATH, cfg)


def git_toplevel(path):
    try:
        out = subprocess.run(
            ["git", "-C", path, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=10,
        )
        if out.returncode == 0:
            return out.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return None


def project_lock(path):
    os.makedirs(LOCK_DIR, exist_ok=True)
    h = hashlib.sha256(path.encode()).hexdigest()[:16]
    fd = open(os.path.join(LOCK_DIR, h + ".lock"), "w")
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except OSError:
        fd.close()
        return None


def encode_claude_dir(path):
    """Mirror claude-code's project-dir encoding (non-alnum -> '-')."""
    return re.sub(r"[^A-Za-z0-9-]", "-", path)


def today():
    return dt.date.today().isoformat()


# --------------------------------------------------------------------------
# frontmatter
# --------------------------------------------------------------------------

FM_RE = re.compile(r"\A---\n(.*?)\n---\n?(.*)\Z", re.DOTALL)


def split_frontmatter(text):
    """Return (meta_dict, body). Tolerates files without frontmatter."""
    m = FM_RE.match(text)
    if not m:
        return {}, text
    meta = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip()
    return meta, m.group(2)


def render_frontmatter(meta):
    order = ["type", "project", "last_updated", "status"]
    keys = [k for k in order if k in meta] + [k for k in meta if k not in order]
    lines = [f"{k}: {meta[k]}" for k in keys]
    return "---\n" + "\n".join(lines) + "\n---\n\n"


def write_memory_file(path, body, project_name, ftype):
    meta = {}
    if os.path.exists(path):
        meta, _ = split_frontmatter(open(path).read())
    meta.setdefault("type", ftype)
    meta.setdefault("project", project_name)
    meta.setdefault("status", "active")
    meta["last_updated"] = today()
    atomic_write(path, render_frontmatter(meta) + body.strip() + "\n")


# --------------------------------------------------------------------------
# scaffolding & registry
# --------------------------------------------------------------------------

SKELETONS = {
    "state.md": "# System State\n\n_No state recorded yet. memd populates this from sessions._",
    "decisions.md": "# Architecture Decisions\n\n_No decisions recorded yet._",
    "mistakes.md": "# Mistake Audit Log (append-only)\n\n_No mistakes recorded yet._",
    "todo.md": "# Open Tasks\n\n_No tasks recorded yet._",
}

MODEL_STUB = """\
# Project Instructions

## Memory protocol (managed by memd)
Read `./.memory/state.md`, `decisions.md`, `mistakes.md`, and `todo.md` before
substantive work. They are distilled automatically after sessions — keep them
authoritative. To leave an explicit note for the memory curator (from any CLI,
agent, or swarm member), write a markdown file into `./.memory/inbox/`.
"""


def scaffold(path, name=None):
    """Create .memory/ (+ .model/ stub) for a project; safe on existing dirs."""
    name = name or os.path.basename(path.rstrip("/")) or path
    mem = os.path.join(path, ".memory")
    created = []
    for sub in ("", "archive", "inbox"):
        d = os.path.join(mem, sub)
        if not os.path.isdir(d):
            os.makedirs(d, exist_ok=True)
            created.append(d)
    for sub in ("archive", "inbox"):
        keep = os.path.join(mem, sub, ".gitkeep")
        if not os.path.exists(keep):
            open(keep, "w").close()
    for fname, skeleton in SKELETONS.items():
        fpath = os.path.join(mem, fname)
        if not os.path.exists(fpath):
            ftype = fname.split(".")[0]
            write_memory_file(fpath, skeleton, name, ftype)
            created.append(fpath)
    model_dir = os.path.join(path, ".model")
    model_md = os.path.join(model_dir, "CLAUDE.md")
    if not os.path.exists(model_md):
        os.makedirs(model_dir, exist_ok=True)
        atomic_write(model_md, MODEL_STUB)
        created.append(model_md)
    return created


def register(cfg, path, name=None):
    path = os.path.realpath(path)
    if path not in cfg["projects"]:
        cfg["projects"][path] = {
            "name": name or os.path.basename(path.rstrip("/")),
            "extra_sources": [],
        }
        save_config(cfg)
    return cfg["projects"][path]


def find_project(cfg, cwd):
    """Map a session cwd to a registered project root (longest prefix wins)."""
    cwd = os.path.realpath(cwd)
    best = None
    for p in cfg["projects"]:
        if cwd == p or cwd.startswith(p.rstrip("/") + "/"):
            if best is None or len(p) > len(best):
                best = p
    return best


# --------------------------------------------------------------------------
# transcript digestion
# --------------------------------------------------------------------------


def _flatten(content, limit):
    if isinstance(content, str):
        return content[:limit]
    if isinstance(content, list):
        parts = []
        for b in content:
            if isinstance(b, dict):
                parts.append(str(b.get("text") or b.get("content") or ""))
            else:
                parts.append(str(b))
        return " ".join(parts)[:limit]
    return str(content)[:limit]


def digest_jsonl(path, offset):
    """Digest new entries of a claude-code transcript from byte offset.

    Returns (digest_text, new_offset)."""
    lines = []
    try:
        with open(path, "rb") as f:
            f.seek(offset)
            raw = f.read()
            new_offset = f.tell()
    except OSError:
        return "", offset
    for rawline in raw.splitlines():
        try:
            e = json.loads(rawline)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if e.get("isSidechain") or e.get("isMeta"):
            continue
        etype = e.get("type")
        msg = e.get("message") or {}
        content = msg.get("content")
        if etype == "user":
            if isinstance(content, str):
                t = content.strip()
                if t and not t.startswith("<"):  # skip injected reminders
                    lines.append("U: " + t[:2500])
            elif isinstance(content, list):
                for b in content:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "text":
                        t = (b.get("text") or "").strip()
                        if t and not t.startswith("<"):
                            lines.append("U: " + t[:2500])
                    elif b.get("type") == "tool_result":
                        lines.append("R: " + _flatten(b.get("content"), 240))
        elif etype == "assistant" and isinstance(content, list):
            for b in content:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text":
                    t = (b.get("text") or "").strip()
                    if t:
                        lines.append("A: " + t[:2500])
                elif b.get("type") == "tool_use":
                    try:
                        inp = json.dumps(b.get("input", {}))[:300]
                    except (TypeError, ValueError):
                        inp = ""
                    lines.append(f"T: {b.get('name', '?')} {inp}")
    return "\n".join(lines), new_offset


# Sessions sometimes read credentials; never let them reach the curator.
REDACT_RE = re.compile(
    r"(ya29\.[\w.\-]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[\w]{20,}"
    r"|sk-[\w\-]{20,}|AKIA[0-9A-Z]{16}|xox[bap]-[\w\-]{10,}"
    r"|eyJ[\w\-]{20,}\.[\w\-]{10,}\.[\w\-]{10,}"
    r"|\"(?:access|refresh|id)_token\"\s*:\s*\"[^\"]+\")"
)


def redact(text):
    return REDACT_RE.sub("[REDACTED]", text)


# --- antigravity-cli adapter ------------------------------------------------
# Conversations live in <antigravity_dir>/conversations/*.db (SQLite, one
# trajectory per file; `steps` rows hold protobuf payloads). There is no
# published schema, so text is extracted as printable-string runs — noisy but
# the curator model tolerates it. Legacy *.pb conversations are not parsed.
# Observed step_type meanings: 14=user, 33=assistant, 15=tool call, 17=error.

_STR_RUN = re.compile(rb"[\x20-\x7e\n\t]{12,}")


def _pb_strings(blob, minlen=12):
    return [s for s in _STR_RUN.findall(blob or b"") if len(s) >= minlen]


def ag_conversations_dir(cfg):
    return os.path.join(os.path.expanduser(cfg["antigravity_dir"]), "conversations")


def _ag_connect(path):
    import sqlite3
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=5)


def ag_workspace(path):
    """Best-effort workspace dir for a conversation DB (file:// URIs in meta)."""
    try:
        con = _ag_connect(path)
        blobs = [r[0] for r in con.execute(
            "select data from trajectory_metadata_blob")]
        blobs += [r[0] for r in con.execute(
            "select step_payload from steps order by idx limit 5")]
        con.close()
    except Exception:
        return None
    candidates = set()
    for blob in blobs:
        for m in re.finditer(rb"file://(/[A-Za-z0-9_\-./]+)", blob or b""):
            p = m.group(1).decode("utf-8", "replace")
            while p and p != "/" and not os.path.isdir(p):
                p = p[:-1]  # protobuf adjacency can glue trailing bytes on
            if p and p != "/":
                candidates.add(p)
    return max(candidates, key=len) if candidates else None


def ag_max_idx(path):
    try:
        con = _ag_connect(path)
        n = con.execute("select coalesce(max(idx), 0) from steps").fetchone()[0]
        con.close()
        return n
    except Exception:
        return 0


def _ag_clean(s):
    t = s.decode("utf-8", "replace").strip().strip('"').strip()
    return re.sub(r"^[^\w#/<\[({`*-]+", "", t)


def digest_ag_db(path, last_idx):
    """Digest antigravity conversation steps with idx > last_idx.

    Returns (digest_text, new_last_idx)."""
    lines = []
    new_idx = last_idx
    try:
        con = _ag_connect(path)
        rows = list(con.execute(
            "select idx, step_type, step_payload from steps "
            "where idx > ? order by idx", (last_idx,)))
        con.close()
    except Exception as e:
        log(f"ag digest failed for {path}: {e}")
        return "", last_idx
    for idx, st, payload in rows:
        new_idx = max(new_idx, idx)
        strs = _pb_strings(payload)
        if not strs:
            continue
        if st == 14:      # user message
            lines.append("U: " + _ag_clean(max(strs, key=len))[:2500])
        elif st == 33:    # assistant text
            lines.append("A: " + _ag_clean(max(strs, key=len))[:2500])
        elif st == 15:    # tool call descriptor (json with toolAction/Summary)
            for s in strs:
                t = s.decode("utf-8", "replace")
                start = t.find('{"')
                if start < 0:
                    continue
                try:
                    obj, _ = json.JSONDecoder().raw_decode(t[start:])
                    summary = obj.get("toolSummary") or obj.get("toolAction")
                    if summary:
                        lines.append("T: " + str(summary)[:200])
                        break
                except (json.JSONDecodeError, AttributeError):
                    continue
        elif st == 17:    # error
            lines.append("E: " + _ag_clean(max(strs, key=len))[:300])
    return "\n".join(lines), new_idx


def _ag_assign_project(db, roots):
    """Antigravity records the launch dir, not the project, as workspace —
    so attribute a conversation to the registered root its payloads
    reference most (>=3 mentions to avoid drive-by matches)."""
    hits = dict.fromkeys(roots, 0)
    try:
        con = _ag_connect(db)
        for (payload,) in con.execute("select step_payload from steps"):
            for r in roots:
                hits[r] += (payload or b"").count(r.encode())
        con.close()
    except Exception:
        return None
    best = max(hits, key=hits.get) if hits else None
    return best if best and hits[best] >= 3 else None


def project_ag_dbs(cfg, project_path):
    """Conversation DBs attributed to this project (cached in ag_index)."""
    import glob as _glob
    conv = ag_conversations_dir(cfg)
    if not os.path.isdir(conv):
        return []
    roots = sorted(os.path.realpath(p) for p in cfg["projects"])
    index = load_json(AG_INDEX_PATH, {})
    changed = False
    out = []
    root = os.path.realpath(project_path)
    for db in _glob.glob(os.path.join(conv, "*.db")):
        e = index.get(db)
        if not isinstance(e, dict):
            e = {"project": "", "scanned_idx": -1}
        maxidx = ag_max_idx(db)
        # unattributed conversations get rescanned as they grow
        if not e["project"] and maxidx > e.get("scanned_idx", -1):
            proj = None
            ws = ag_workspace(db)
            if ws:
                inside = [r for r in roots
                          if ws == r or ws.startswith(r.rstrip("/") + "/")]
                proj = max(inside, key=len, default=None)
            if not proj:
                proj = _ag_assign_project(db, roots)
            e = {"project": proj or "", "scanned_idx": maxidx}
            index[db] = e
            changed = True
        if e["project"] == root:
            out.append(db)
    if changed:
        save_json(AG_INDEX_PATH, index)
    return sorted(out)


def source_pending(src, cursors):
    """Does a transcript source have content beyond its cursor?"""
    try:
        if src.endswith(".db"):
            return ag_max_idx(src) > cursors.get(src, 0)
        return os.path.getsize(src) > cursors.get(src, 0)
    except OSError:
        return False


def digest_source(src, cursor):
    """Dispatch to the right digester. Returns (text, new_cursor)."""
    if src.endswith(".db"):
        return digest_ag_db(src, cursor)
    return digest_jsonl(src, cursor)


def baseline_cursor(src):
    return ag_max_idx(src) if src.endswith(".db") else os.path.getsize(src)


def cap_digest(text, cap):
    if len(text) <= cap:
        return text
    head = int(cap * 0.3)
    tail = cap - head
    return text[:head] + "\n[... digest truncated ...]\n" + text[-tail:]


def transcript_files(cfg, project_path):
    """All transcript sources for a project: claude dirs + extra globs."""
    import glob as _glob
    files = []
    enc = encode_claude_dir(os.path.realpath(project_path))
    for d in _glob.glob(os.path.join(CLAUDE_PROJECTS_DIR, "*")):
        base = os.path.basename(d)
        if base == enc or base.startswith(enc + "-"):
            files.extend(_glob.glob(os.path.join(d, "*.jsonl")))
    for pattern in cfg["projects"].get(project_path, {}).get("extra_sources", []):
        files.extend(_glob.glob(os.path.expanduser(pattern)))
    files.extend(project_ag_dbs(cfg, project_path))
    return sorted(set(files))


def collect_inbox(project_path):
    inbox = os.path.join(project_path, ".memory", "inbox")
    notes, paths = [], []
    if os.path.isdir(inbox):
        for fn in sorted(os.listdir(inbox)):
            if fn.startswith(".") or not fn.endswith((".md", ".txt")):
                continue
            p = os.path.join(inbox, fn)
            try:
                notes.append(f"INBOX NOTE ({fn}):\n{open(p).read()[:4000]}")
                paths.append(p)
            except OSError:
                continue
    return notes, paths


# --------------------------------------------------------------------------
# the distill: prompt -> claude -p -> validated apply
# --------------------------------------------------------------------------


def read_memory(project_path):
    mem = os.path.join(project_path, ".memory")
    out = {}
    for fname in MEMORY_FILES:
        p = os.path.join(mem, fname)
        if os.path.exists(p):
            _, body = split_frontmatter(open(p).read())
            out[fname] = body.strip()
        else:
            out[fname] = ""
    return out


def build_prompt(cfg, project_path, name, memory, digest, inbox_notes):
    budgets = cfg["budgets"]
    parts = [
        CHARTER,
        f"\nPROJECT: {name}  (root: {project_path})",
        f"DATE: {today()}",
        "BUDGETS (chars of body): "
        + ", ".join(f"{k}={v}" for k, v in budgets.items()),
        "\n===== CURRENT state.md =====\n" + (memory["state.md"] or "(empty)"),
        "\n===== CURRENT decisions.md =====\n" + (memory["decisions.md"] or "(empty)"),
        "\n===== CURRENT mistakes.md (append-only; for reference) =====\n"
        + (memory["mistakes.md"] or "(empty)"),
        "\n===== CURRENT todo.md =====\n" + (memory["todo.md"] or "(empty)"),
    ]
    if inbox_notes:
        parts.append("\n===== CURATOR INBOX =====\n" + "\n\n".join(inbox_notes))
    parts.append(
        "\n===== SESSION DIGEST (U=user, A=assistant, T=tool call, R=result) =====\n"
        + (digest or "(no new transcript content)")
    )
    parts.append("\nProduce the JSON object now.")
    return "\n".join(parts)


def call_curator(cfg, prompt, model):
    bin_ = cfg["claude_bin"]
    if not shutil.which(bin_):
        for cand in (os.path.join(HOME, ".local", "bin", "claude"),):
            if os.path.exists(cand):
                bin_ = cand
                break
    cmd = [bin_, "-p", "--model", model, "--output-format", "json", "--max-turns", "1"]
    env = dict(os.environ)
    env.pop("CLAUDECODE", None)  # allow nested invocation from inside a session
    try:
        proc = subprocess.run(
            cmd, input=prompt, capture_output=True, text=True,
            timeout=600, cwd=STATE_DIR, env=env,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError("curator call timed out")
    if proc.returncode != 0:
        raise RuntimeError(f"claude -p failed rc={proc.returncode}: {proc.stderr[:400]}")
    try:
        envelope = json.loads(proc.stdout)
        text = envelope.get("result", "")
    except json.JSONDecodeError:
        text = proc.stdout
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text.strip())
    start = text.find("{")
    if start < 0:
        raise RuntimeError(f"no JSON in curator output: {text[:300]}")
    obj, _ = json.JSONDecoder().raw_decode(text[start:])
    return obj


def validate(result, memory):
    """Reject obviously destructive or malformed curator output."""
    if not isinstance(result, dict):
        raise RuntimeError("curator output is not an object")
    for key in ("state_body", "decisions_body", "todo_body"):
        v = result.get(key)
        if v is None:
            continue
        if not isinstance(v, str):
            raise RuntimeError(f"{key} is not a string")
        old = memory[key.replace("_body", "") + ".md"]
        archived = sum(
            len(a.get("content", "")) for a in result.get("archive_entries", [])
            if isinstance(a, dict)
        )
        if len(old) > 800 and len(v) + archived < len(old) * 0.4:
            raise RuntimeError(f"shrink guard tripped on {key} "
                               f"({len(old)} -> {len(v)} chars, {archived} archived)")
    for e in result.get("mistakes_new_entries", []):
        if not isinstance(e, str):
            raise RuntimeError("mistakes_new_entries contains a non-string")
    return result


def archive_path(project_path):
    return os.path.join(
        project_path, ".memory", "archive", dt.date.today().strftime("%Y-%m") + ".md"
    )


def append_archive(project_path, entries, reason):
    if not entries:
        return
    p = archive_path(project_path)
    header = not os.path.exists(p)
    with open(p, "a") as f:
        if header:
            f.write(f"---\ntype: archive\nlast_updated: {today()}\nstatus: archived\n---\n")
        f.write(f"\n<!-- archived {today()} ({reason}) -->\n")
        for e in entries:
            src = e.get("source", "?") if isinstance(e, dict) else "?"
            content = e.get("content", "") if isinstance(e, dict) else str(e)
            f.write(f"\n## from {src}\n\n{content.strip()}\n")


def enforce_budget_mistakes(project_path, name, budget):
    """Deterministic overflow: move oldest H3 sections of mistakes.md to archive."""
    p = os.path.join(project_path, ".memory", "mistakes.md")
    if not os.path.exists(p):
        return
    meta, body = split_frontmatter(open(p).read())
    if len(body) <= budget:
        return
    sections = re.split(r"(?m)^(?=### )", body)
    head, entries = sections[0], sections[1:]
    moved = []
    while entries and len(head) + sum(len(s) for s in entries) > budget:
        moved.append(entries.pop(0))
    if moved:
        append_archive(project_path, [{"source": "mistakes.md", "content": s} for s in moved],
                       "size budget overflow")
        write_memory_file(p, head + "".join(entries), name, "mistakes")
        log(f"pruned {len(moved)} mistakes.md sections to archive in {project_path}")


def git_commit_memory(project_path, message):
    top = git_toplevel(project_path)
    if not top:
        return
    rel = os.path.relpath(os.path.join(project_path, ".memory"), top)
    try:
        subprocess.run(["git", "-C", top, "add", "--", rel],
                       capture_output=True, timeout=30)
        diff = subprocess.run(["git", "-C", top, "diff", "--cached", "--quiet", "--", rel],
                              timeout=30)
        if diff.returncode == 0:
            return
        r = subprocess.run(
            ["git", "-C", top, "commit", "-m", message, "--", rel],
            capture_output=True, text=True, timeout=30,
        )
        if r.returncode != 0:
            log(f"git commit failed in {top}: {r.stderr.strip()[:200]}")
    except (OSError, subprocess.TimeoutExpired) as e:
        log(f"git commit error in {top}: {e}")


def sync_project(cfg, project_path, trigger="manual", transcript=None, dry_run=False):
    project_path = os.path.realpath(project_path)
    entry = cfg["projects"].get(project_path)
    name = entry["name"] if entry else os.path.basename(project_path)
    if not os.path.isdir(os.path.join(project_path, ".memory")):
        scaffold(project_path, name)

    lock = project_lock(project_path)
    if lock is None:
        log(f"sync skipped (locked): {project_path}")
        return False

    try:
        cursors = load_json(CURSORS_PATH, {})
        sources = [transcript] if transcript else transcript_files(cfg, project_path)
        digests, new_cursors = [], {}
        for src in sources:
            if not src or not os.path.exists(src):
                continue
            if not source_pending(src, cursors):
                continue
            d, new_off = digest_source(src, cursors.get(src, 0))
            if d.strip():
                digests.append(d)
            new_cursors[src] = new_off
        inbox_notes, inbox_paths = collect_inbox(project_path)

        if not digests and not inbox_notes:
            log(f"sync {project_path}: nothing new ({trigger})")
            return False

        digest = redact(cap_digest(
            "\n\n--- next session span ---\n\n".join(digests),
            cfg["digest_cap_chars"]))
        inbox_notes = [redact(n) for n in inbox_notes]
        model = cfg["model_small"]
        if trigger in ("session-end", "manual") and len(digest) > cfg["escalate_chars"]:
            model = cfg["model_large"]

        memory = read_memory(project_path)
        prompt = build_prompt(cfg, project_path, name, memory, digest, inbox_notes)

        if dry_run:
            print(f"[dry-run] project={project_path} trigger={trigger} model={model}")
            print(f"[dry-run] digest={len(digest)} chars from {len(digests)} span(s), "
                  f"{len(inbox_notes)} inbox note(s), prompt={len(prompt)} chars")
            print(prompt[:1500])
            return True

        log(f"distill start {project_path} trigger={trigger} model={model} "
            f"digest={len(digest)}c inbox={len(inbox_notes)}")
        result = validate(call_curator(cfg, prompt, model), memory)

        mem = os.path.join(project_path, ".memory")
        for key, fname in (("state_body", "state.md"),
                           ("decisions_body", "decisions.md"),
                           ("todo_body", "todo.md")):
            body = result.get(key)
            if isinstance(body, str) and body.strip() and body.strip() != memory[fname]:
                write_memory_file(os.path.join(mem, fname), body, name,
                                  fname.split(".")[0])
        new_mistakes = [e for e in result.get("mistakes_new_entries", []) if e.strip()]
        if new_mistakes:
            mpath = os.path.join(mem, "mistakes.md")
            body = memory["mistakes.md"]
            body = (body + "\n\n" if body else "") + "\n\n".join(
                e.strip() for e in new_mistakes)
            write_memory_file(mpath, body, name, "mistakes")
        append_archive(project_path, result.get("archive_entries", []),
                       f"curator distill, trigger={trigger}")
        enforce_budget_mistakes(project_path, name, cfg["budgets"]["mistakes.md"])

        # advance cursors and clear inbox only after a successful apply
        cursors.update(new_cursors)
        save_json(CURSORS_PATH, cursors)
        for p in inbox_paths:
            try:
                os.remove(p)
            except OSError:
                pass

        meta = load_json(META_PATH, {})
        meta[project_path] = {
            "last_sync": dt.datetime.now().isoformat(timespec="seconds"),
            "trigger": trigger,
            "model": model,
            "summary": str(result.get("summary", ""))[:300],
        }
        save_json(META_PATH, meta)

        if cfg["git_commit"]:
            git_commit_memory(
                project_path,
                f"Update project memory ({trigger} distill)\n\n"
                f"{result.get('summary', '')}".strip(),
            )
        log(f"distill done {project_path}: {result.get('summary', '')[:160]}")
        return True
    except RuntimeError as e:
        log(f"distill FAILED {project_path} ({trigger}): {e}")
        return False
    finally:
        lock.close()


# --------------------------------------------------------------------------
# brief (session-start context)
# --------------------------------------------------------------------------


def make_brief(cfg, project_path):
    project_path = os.path.realpath(project_path)
    mem = os.path.join(project_path, ".memory")
    if not os.path.isdir(mem):
        return None
    parts = [BRIEF_NOTE]
    meta = load_json(META_PATH, {}).get(project_path)
    if meta:
        parts.append(f"Last memory distill: {meta['last_sync']} "
                     f"({meta['trigger']}) — {meta['summary']}")
    state_p = os.path.join(mem, "state.md")
    if os.path.exists(state_p):
        fm, _ = split_frontmatter(open(state_p).read())
        if fm:
            parts.append(f"Project: {fm.get('project', '?')} | state.md updated "
                         f"{fm.get('last_updated', '?')} | status {fm.get('status', '?')}")
    todo_p = os.path.join(mem, "todo.md")
    if os.path.exists(todo_p):
        _, body = split_frontmatter(open(todo_p).read())
        open_items = re.findall(r"(?m)^\s*[-*] \[ \] (.+)$", body)[:8]
        if open_items:
            parts.append("Open todo items:\n" + "\n".join(f"- {i}" for i in open_items))
    _, inbox_paths = collect_inbox(project_path)
    if inbox_paths:
        parts.append(f"{len(inbox_paths)} unprocessed curator inbox note(s).")
    return "\n\n".join(parts)


# --------------------------------------------------------------------------
# hooks (claude-code)
# --------------------------------------------------------------------------


def self_invocation():
    """Command used to re-invoke memd in detached children and hooks."""
    return [sys.executable or "python3", os.path.abspath(__file__)]


def detach(args):
    logf = open(LOG_PATH, "a")
    subprocess.Popen(self_invocation() + args, stdout=logf, stderr=logf,
                     stdin=subprocess.DEVNULL, start_new_session=True)


def cmd_hook(cfg, event):
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        payload = {}
    cwd = payload.get("cwd") or os.getcwd()
    transcript = payload.get("transcript_path")
    root = find_project(cfg, cwd)

    if event == "session-start":
        if root is None:
            top = git_toplevel(cwd)
            if top and cfg["auto_scaffold"] and top not in cfg["exclude"]:
                scaffold(top)
                register(cfg, top)
                root = top
                log(f"auto-scaffolded memory for {top}")
        if root:
            brief = make_brief(cfg, root)
            if brief:
                print(json.dumps({"hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": brief,
                }}))
        return 0

    if event in ("session-end", "pre-compact"):
        if root is None:
            return 0
        args = ["sync", "--project", root, "--trigger", event]
        if transcript:
            args += ["--transcript", transcript]
        detach(args)
        return 0
    return 0


HOOK_DEFS = {
    "SessionStart": "hook session-start",
    "SessionEnd": "hook session-end",
    "PreCompact": "hook pre-compact",
}


def cmd_install_hooks():
    settings = load_json(CLAUDE_SETTINGS, {})
    hooks = settings.setdefault("hooks", {})
    changed = False
    for event, sub in HOOK_DEFS.items():
        cmdstr = f"memd {sub}"
        entries = hooks.setdefault(event, [])
        present = any(
            cmdstr in h.get("command", "")
            for e in entries for h in e.get("hooks", [])
        )
        if not present:
            entries.append({"hooks": [{"type": "command", "command": cmdstr}]})
            changed = True
    if changed:
        save_json(CLAUDE_SETTINGS, settings)
        print(f"hooks installed into {CLAUDE_SETTINGS}")
    else:
        print("hooks already installed")


# --------------------------------------------------------------------------
# sweep (timer entry): missed sessions, inbox, auto-detect, prune
# --------------------------------------------------------------------------


def detect_new_projects(cfg):
    """Find git-root projects with recent claude sessions but no registration."""
    import glob as _glob
    found = set()
    cutoff = time.time() - 30 * 86400
    for jl in _glob.glob(os.path.join(CLAUDE_PROJECTS_DIR, "*", "*.jsonl")):
        try:
            if os.path.getmtime(jl) < cutoff:
                continue
            with open(jl) as f:
                for line in f:
                    try:
                        cwd = json.loads(line).get("cwd")
                    except json.JSONDecodeError:
                        continue
                    if cwd:
                        found.add(os.path.realpath(cwd))
                        break
        except OSError:
            continue
    new = []
    for cwd in found:
        if not os.path.isdir(cwd) or cwd in cfg["exclude"]:
            continue
        top = git_toplevel(cwd)
        if not top or top in cfg["exclude"] or top == HOME:
            continue
        if find_project(cfg, top) is None:
            new.append(top)
    return sorted(set(new))


def cmd_sweep(cfg):
    if cfg["auto_scaffold"]:
        for path in detect_new_projects(cfg):
            scaffold(path)
            register(cfg, path)
            log(f"sweep: auto-scaffolded + registered {path}")
    cursors = load_json(CURSORS_PATH, {})
    quiet = cfg["quiet_seconds"]
    now = time.time()
    for path, entry in sorted(cfg["projects"].items()):
        if not os.path.isdir(path):
            continue
        pending = False
        for src in transcript_files(cfg, path):
            try:
                if source_pending(src, cursors) \
                        and now - os.path.getmtime(src) > quiet:
                    pending = True
                    break
            except OSError:
                continue
        if not pending and collect_inbox(path)[0]:
            pending = True
        if pending:
            sync_project(cfg, path, trigger="sweep")
        else:
            enforce_budget_mistakes(path, entry["name"], cfg["budgets"]["mistakes.md"])
    log("sweep complete")


# --------------------------------------------------------------------------
# status / CLI plumbing
# --------------------------------------------------------------------------


def cmd_status(cfg):
    meta = load_json(META_PATH, {})
    cursors = load_json(CURSORS_PATH, {})
    if not cfg["projects"]:
        print("no projects registered (run: memd init [path])")
        return
    for path, entry in sorted(cfg["projects"].items()):
        m = meta.get(path, {})
        srcs = transcript_files(cfg, path)
        pending = [s for s in srcs if source_pending(s, cursors)]
        ag = sum(1 for s in srcs if s.endswith(".db"))
        inbox = len(collect_inbox(path)[1])
        print(f"{entry['name']}  ({path})")
        print(f"  last distill : {m.get('last_sync', 'never')}"
              + (f"  [{m.get('trigger')}/{m.get('model')}]" if m else ""))
        if m.get("summary"):
            print(f"  summary      : {m['summary']}")
        print(f"  sources      : {len(srcs)} ({ag} antigravity), "
              f"{len(pending)} with pending content, {inbox} inbox note(s)")


def main():
    ap = argparse.ArgumentParser(prog="memd", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init", help="scaffold .memory/ and register a project")
    p.add_argument("path", nargs="?", default=".")
    p.add_argument("--name")

    p = sub.add_parser("sync", help="distill new session content into memory")
    p.add_argument("--project", default=".")
    p.add_argument("--transcript")
    p.add_argument("--trigger", default="manual")
    p.add_argument("--dry-run", action="store_true")

    sub.add_parser("sweep", help="timer entry: catch up all projects, prune, detect")
    sub.add_parser("status", help="show registry, backlog, last distills")
    sub.add_parser("install-hooks", help="wire memd into ~/.claude/settings.json")

    p = sub.add_parser("brief", help="print session-start memory brief")
    p.add_argument("path", nargs="?", default=".")

    p = sub.add_parser("hook", help="claude-code hook entry (reads JSON on stdin)")
    p.add_argument("event", choices=["session-start", "session-end", "pre-compact"])

    p = sub.add_parser("exclude", help="never auto-manage a path")
    p.add_argument("path")

    args = ap.parse_args()
    cfg = load_config()

    if args.cmd == "init":
        path = os.path.realpath(args.path)
        created = scaffold(path, args.name)
        register(cfg, path, args.name)
        # Baseline: start memory from now. Pre-existing transcripts are
        # presumed covered by existing memory (or not worth back-filling).
        cursors = load_json(CURSORS_PATH, {})
        skipped = 0
        for src in transcript_files(cfg, path):
            if src not in cursors:
                cursors[src] = baseline_cursor(src)
                skipped += 1
        save_json(CURSORS_PATH, cursors)
        print(f"registered {path}"
              + (f", created {len(created)} file(s)" if created else "")
              + (f", baselined {skipped} existing transcript(s)" if skipped else ""))
    elif args.cmd == "sync":
        ok = sync_project(cfg, args.project, trigger=args.trigger,
                          transcript=args.transcript, dry_run=args.dry_run)
        sys.exit(0 if ok or args.dry_run else 1)
    elif args.cmd == "sweep":
        cmd_sweep(cfg)
    elif args.cmd == "status":
        cmd_status(cfg)
    elif args.cmd == "install-hooks":
        cmd_install_hooks()
    elif args.cmd == "brief":
        brief = make_brief(cfg, args.path)
        print(brief or "(no .memory directory here)")
    elif args.cmd == "hook":
        sys.exit(cmd_hook(cfg, args.event))
    elif args.cmd == "exclude":
        path = os.path.realpath(args.path)
        if path not in cfg["exclude"]:
            cfg["exclude"].append(path)
        cfg["projects"].pop(path, None)
        save_config(cfg)
        print(f"excluded {path}")


if __name__ == "__main__":
    main()
