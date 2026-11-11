"""agent_data: the data side of the nox agent notch (imported lazily by `nox agents`).

  replay   the numbered steps of a session's turn(s), parsed from its transcript
           (Claude Code JSONL or a Codex rollout); a per-transcript prompt index makes a
           turn a seek, not a scan
  laps     a day as lanes per session: working segments, waits, the moments you stepped in,
           agent time vs wall time, what shipped (commits, PRs opened)
  receipts the log of what the notch did for you (~/.local/state/nox/agents/receipts.jsonl),
           with undo for "always" rules and undelivered steers
  races    one task on N agents in N git worktrees: status, diff, tests, merge, clean up
  overlap  files edited by 2+ live sessions in the same repo in the last 15 min
  codex    `nox agents hook install --codex`: the status hook in ~/.codex/hooks.json

Read-only and fast unless a command says otherwise. Every metric that can't be computed is
null, never guessed. Python stdlib only. Private text (prompts, transcripts, commands) only ever
goes to stdout for the shell, or to 0600 files under $XDG_RUNTIME_DIR / ~/.local/state.
"""
import json, os, sys, glob, re, time, subprocess, datetime, shlex

HOME = os.path.expanduser("~")
RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "nox", "agents")
STATE = os.environ.get("NOX_AGENTS_STATE") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "nox", "agents")
RECEIPTS = os.path.join(STATE, "receipts.jsonl")
RACES = os.path.join(STATE, "races")
CODEX_HOME = os.environ.get("CODEX_HOME") or os.path.join(HOME, ".codex")
TMUX_SOCK = "nox-agents"

GAP = 5 * 60 * 1000          # idle gap that ends a working segment
STUCK = 60 * 60 * 1000       # a tool "running" longer than this is treated as lost
MAX_STEPS = 400
PR_RE = re.compile(rb"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+")
PR_CREATE = re.compile(r"\bpr\s+create\b|create_pull_request")
DENIED = re.compile(r"doesn.t want to proceed|rejected|denied by the user|user denied|the user denied|declined", re.I)
NOISE_TOOLS = {"TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet", "ToolSearch", "TaskStop", "TaskOutput"}
EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")


# ---- small helpers (re-implemented, so `agents` and this module don't import each other) ----
def emit(obj, code=0):
    print(json.dumps(obj))
    return code


def run(argv, timeout=5, cwd=None, inp=None):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, cwd=cwd, input=inp)
        return r.returncode, r.stdout, r.stderr
    except Exception as e:
        return 127, "", str(e)


def git(root, *args, timeout=8):
    return run(["git", "-C", root, "--no-optional-locks"] + list(args), timeout=timeout)


def shell_opts():
    try:
        with open(os.path.join(HOME, ".config/nox/shell.json")) as f:
            return json.load(f).get("agents") or {}
    except Exception:
        return {}


def sessions():
    out = []
    for p in glob.glob(os.path.join(RUN, "*.json")):
        try:
            with open(p) as f:
                s = json.load(f)
            if isinstance(s, dict) and s.get("id"):
                out.append(s)
        except Exception:
            pass
    return out


def alive(s):
    pid = s.get("pid")
    if not pid:
        return True
    try:
        with open(f"/proc/{pid}/stat") as f:
            st = f.read()
        return not s.get("pidStart") or st.rsplit(")", 1)[1].split()[19] == str(s["pidStart"])
    except Exception:
        return False


def live_status(s):
    return (s.get("status") or "?") if alive(s) else "ended"


def now_ms():
    return int(time.time() * 1000)


def ts_ms(ts):
    if not ts:
        return None
    try:
        return int(datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp() * 1000)
    except Exception:
        return None


def cut(s, n):
    s = re.sub(r"\s+", " ", str(s or "")).strip()
    return s if len(s) <= n else s[:n - 1] + "…"


def firstline(s):
    return next((l.strip() for l in str(s or "").splitlines() if l.strip()), "")


def lastline(s):
    return next((l.strip() for l in reversed(str(s or "").splitlines()) if l.strip()), "")


def rel(p, cwd):
    p = str(p or "")
    if cwd and p.startswith(cwd.rstrip("/") + "/"):
        return p[len(cwd.rstrip("/")) + 1:]
    return p.replace(HOME, "~", 1) if p.startswith(HOME + "/") else p


def git_root(d):
    """The repo (or worktree) top above d, from the filesystem only (no git process)."""
    d = os.path.realpath(d or "")
    while d and d != "/":
        if os.path.exists(os.path.join(d, ".git")):
            return d
        d = os.path.dirname(d)
    return None


def slug(task, n=4):
    w = [x for x in re.sub(r"[^a-z0-9 ]+", " ", task.lower()).split()
         if x not in ("the", "a", "an", "in", "on", "of", "to", "for", "and")]
    return ("-".join(w[:n]) or "task")[:40]


def write_json(path, obj, mode=0o600):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = "%s.%d.tmp" % (path, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


# ---- transcripts: where they are ----
def project_dirs():
    """~/.claude/projects plus other homes seen in the state (expai: .agent-home)."""
    out = [os.path.join(HOME, ".claude", "projects")]
    for s in sessions():
        tp = s.get("transcript") or ""
        i = tp.find("/.claude/projects/")
        if i > 0:
            out.append(tp[:i] + "/.claude/projects")
    for h in (os.environ.get("NOX_EXPAI_HOME"), os.path.join(HOME, "code/sandbox/expai/.agent-home")):
        if h:
            out.append(os.path.join(h, ".claude", "projects"))
    seen, uniq = set(), []
    for d in out:
        r = os.path.realpath(d)
        if r not in seen and os.path.isdir(r):
            seen.add(r)
            uniq.append(d)
    return uniq


def claude_files():
    return [p for d in project_dirs() for p in glob.glob(os.path.join(d, "*", "*.jsonl"))]


def codex_files():
    return glob.glob(os.path.join(CODEX_HOME, "sessions", "*", "*", "*", "*.jsonl"))


def is_codex(path):
    return os.path.basename(path).startswith("rollout-") or "/.codex/" in path


def sid_of(path):
    b = os.path.basename(path)[:-6]
    if b.startswith("rollout-"):
        m = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", b)
        return m.group(1) if m else b
    return b


def find_transcript(sid):
    """(path, state-or-None) for a session id or unique prefix."""
    ss = sessions()
    s = next((x for x in ss if x["id"] == sid), None) or next((x for x in ss if x["id"].startswith(sid)), None)
    if s and s.get("transcript") and os.path.exists(s["transcript"]):
        return s["transcript"], s
    if not re.fullmatch(r"[A-Za-z0-9_.-]{4,}", sid):
        return None, s
    for d in project_dirs():
        hits = glob.glob(os.path.join(d, "*", sid + "*.jsonl"))
        if hits:
            return max(hits, key=os.path.getmtime), s
    hits = glob.glob(os.path.join(CODEX_HOME, "sessions", "*", "*", "*", "*" + sid + "*.jsonl"))
    if hits:
        return max(hits, key=os.path.getmtime), s
    return None, s


# ---- transcript parsing: Claude Code ----
def claude_prompt(e):
    """The user's prompt text of a transcript entry, or None (tool results, meta, commands, noise)."""
    if e.get("type") != "user" or e.get("isSidechain") or e.get("isMeta") or e.get("isCompactSummary"):
        return None
    o = e.get("origin")
    if isinstance(o, dict) and o.get("kind") not in (None, "human"):
        return None
    if e.get("promptSource") == "system":
        return None
    c = (e.get("message") or {}).get("content")
    img = False
    if isinstance(c, list):
        if any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c):
            return None
        img = any(isinstance(x, dict) and x.get("type") == "image" for x in c)
        c = "\n".join(x.get("text") or "" for x in c if isinstance(x, dict) and x.get("type") == "text")
    s = str(c or "").strip()
    if "<command-message>" in s:                   # a skill / custom slash command: what was typed
        m = re.search(r"<command-name>(.*?)</command-name>", s)
        a = re.search(r"<command-args>(.*?)</command-args>", s, re.S)
        return ((m.group(1) if m else "/command") + " " + (a.group(1).strip() if a else "")).strip()
    if not s:
        return "[image]" if img else None
    if s.startswith(("<", "[Request interrupted", "Caveat:", "This session is being continued")):
        return None
    return s


def tool_arg(name, inp, cwd):
    """Mirrors agent-hook's arg(): command first line / relative path / pattern / ..."""
    if not isinstance(inp, dict):
        return cut(firstline(inp), 110)
    if inp.get("command") and isinstance(inp["command"], str):
        v = firstline(inp["command"])
    elif inp.get("file_path") or inp.get("notebook_path"):
        v = rel(inp.get("file_path") or inp.get("notebook_path"), cwd)
    elif name == "Grep":
        v = '"%s"' % inp.get("pattern", "") + (" in " + rel(inp["path"], cwd) if inp.get("path") else "")
    else:
        v = next((inp[k] for k in ("pattern", "url", "query", "description") if inp.get(k)), None)
        if v is None and inp.get("prompt"):
            v = firstline(inp["prompt"])
        if v is None:
            v = inp.get("skill") or next((x for x in inp.values() if isinstance(x, str)), "")
    return cut(v, 110)


def content_text(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(x.get("text") or "" for x in c if isinstance(x, dict) and x.get("type") == "text")
    return ""


def patch_lines(hunks):
    out = []
    for h in hunks or []:
        for l in (h or {}).get("lines") or []:
            if l[:1] in ("+", "-"):
                out.append(l)
    return out


def edit_diff(name, inp, tur):
    """(preview ≤12 lines, add, del) for an edit tool, or (None, None, None)."""
    if isinstance(tur, dict) and tur.get("structuredPatch"):
        ls = patch_lines(tur["structuredPatch"])
        a = sum(1 for l in ls if l[0] == "+")
        return [l[:200] for l in ls[:12]], a, len(ls) - a
    if not isinstance(inp, dict):
        return None, None, None
    pairs = []
    if name == "MultiEdit":
        pairs = [(x.get("old_string") or "", x.get("new_string") or "") for x in inp.get("edits") or [] if isinstance(x, dict)]
    elif name == "Edit":
        pairs = [(inp.get("old_string") or "", inp.get("new_string") or "")]
    elif name == "Write" and isinstance(inp.get("content"), str):
        ls = inp["content"].splitlines()
        return ["+" + l[:199] for l in ls[:12]], len(ls), 0
    if not pairs:
        return None, None, None
    prev, a, d = [], 0, 0
    for old, new in pairs:
        o, n = old.splitlines(), new.splitlines()
        a, d = a + len(n), d + len(o)
        room = 12 - len(prev)
        if room <= 0:
            continue
        ko = min(len(o), max(room // 2, room - len(n)))
        prev += ["-" + l[:199] for l in o[:ko]] + ["+" + l[:199] for l in n[:room - ko]]
    return prev[:12], a, d


def claude_result(name, tur, content, is_error):
    """(short result, state ok|error|denied)."""
    text = content_text(content)
    if is_error:
        if DENIED.search(text):
            return cut(firstline(text), 110), "denied"
        return cut(firstline(text) or "failed", 110), "error"
    r = tur
    if isinstance(r, str):
        return cut(firstline(r), 110), "ok"
    if isinstance(r, dict):
        if name == "Read" and isinstance(r.get("file"), dict) and r["file"].get("numLines"):
            return "Read %d lines" % r["file"]["numLines"], "ok"
        if name == "Bash":
            if r.get("interrupted"):
                return "interrupted", "error"
            v = lastline(r.get("stdout")) or lastline(r.get("stderr")) or "done"
            return cut(v, 110), "ok"
        if name in EDIT_TOOLS:
            ls = patch_lines(r.get("structuredPatch"))
            if ls:
                a = sum(1 for l in ls if l[0] == "+")
                return "+%d −%d" % (a, len(ls) - a), "ok"
            if name == "Write":
                return "+%d lines" % len(str(r.get("content") or "").splitlines()), "ok"
            return "edited", "ok"
        if name == "Grep":
            if r.get("numFiles") is not None:
                return "Found %s files" % r["numFiles"], "ok"
            if r.get("numLines") is not None:
                return "Found %s lines" % r["numLines"], "ok"
        if name == "Glob":
            return "Found %s files" % (r.get("numFiles") if r.get("numFiles") is not None else len(r.get("filenames") or [])), "ok"
        if name == "WebFetch" and r.get("code"):
            return cut("%s %s" % (r.get("code"), r.get("codeText") or ""), 110), "ok"
    return cut(firstline(text) or "done", 110), "ok"


def claude_steps(lines, cwd=""):
    """Steps from Claude transcript lines (bytes)."""
    steps, pend = [], {}
    for line in lines:
        if b'"type":"user"' not in line and b'"type":"assistant"' not in line:
            continue
        try:
            e = json.loads(line)
        except Exception:
            continue
        if e.get("isSidechain"):
            continue
        at = ts_ms(e.get("timestamp"))
        cwd = e.get("cwd") or cwd
        t = e.get("type")
        if t == "user":
            p = claude_prompt(e)
            if p is not None:
                steps.append({"k": "you", "at": at, "a": cut(p, 240)})
                continue
            c = (e.get("message") or {}).get("content")
            if not isinstance(c, list):
                continue
            for x in c:
                if not isinstance(x, dict) or x.get("type") != "tool_result":
                    continue
                st = pend.pop(x.get("tool_use_id"), None)
                if not st:
                    continue
                tur = e.get("toolUseResult")
                st["r"], st["s"] = claude_result(st["name"], tur, x.get("content"), bool(x.get("is_error")))
                if at and st.get("at"):
                    st["dur"] = max(0, at - st["at"])
                if st["name"] in EDIT_TOOLS and st["s"] == "ok" and isinstance(tur, dict) and tur.get("structuredPatch"):
                    st["diff"], st["add"], st["del"] = edit_diff(st["name"], None, tur)
        elif t == "assistant":
            m = e.get("message") or {}
            if str(m.get("model") or "").startswith("<"):
                continue
            for x in m.get("content") or []:
                if not isinstance(x, dict):
                    continue
                xt = x.get("type")
                if xt == "text" and (x.get("text") or "").strip():
                    steps.append({"k": "say", "at": at, "a": cut(firstline(x["text"]), 160)})
                elif xt == "tool_use":
                    name, inp = x.get("name") or "?", x.get("input") or {}
                    if name == "ExitPlanMode":
                        steps.append({"k": "decide", "at": at, "a": cut("Plan: " + firstline(re.sub(r"^#+\s*", "", str(inp.get("plan") or ""), flags=re.M)), 160)})
                        continue
                    if name == "TodoWrite":
                        todos = inp.get("todos") or []
                        cur = next((t_ for t_ in todos if isinstance(t_, dict) and t_.get("status") == "in_progress"), None)
                        if cur:
                            steps.append({"k": "decide", "at": at, "a": cut("Next: " + str(cur.get("activeForm") or cur.get("content") or ""), 160)})
                        continue
                    if name in NOISE_TOOLS:
                        continue
                    st = {"k": "tool", "at": at, "name": name, "a": tool_arg(name, inp, cwd), "r": None, "s": "run"}
                    if name in EDIT_TOOLS:
                        st["diff"], st["add"], st["del"] = edit_diff(name, inp, None)
                    steps.append(st)
                    if x.get("id"):
                        pend[x["id"]] = st
                # thinking / redacted_thinking: never (signed, not plain text)
    return steps


# ---- transcript parsing: Codex rollouts ----
def codex_user_text(p):
    for c in p.get("content") or []:
        tx = (c or {}).get("text") or ""
        s = tx.strip()
        if not s or s.startswith(("<", "# AGENTS.md")):
            continue
        return s
    return None


def codex_args(p):
    if p.get("type") == "custom_tool_call":
        return p.get("input") or ""
    try:
        a = json.loads(p.get("arguments") or "{}")
    except Exception:
        a = p.get("arguments") or ""
    return a


PATCH_FILE = re.compile(r"^\*\*\* (Add|Update|Delete) File: (.+)$", re.M)


def codex_patch(text, cwd):
    fs = PATCH_FILE.findall(text or "")
    ls = [l for l in (text or "").splitlines() if l[:1] in ("+", "-") and not l.startswith(("+++", "---"))]
    a = sum(1 for l in ls if l[0] == "+")
    arg = rel(fs[0][1].strip(), cwd) if fs else "patch"
    if len(fs) > 1:
        arg += " +%d more" % (len(fs) - 1)
    return cut(arg, 110), [l[:200] for l in ls[:12]], a, len(ls) - a, [(op, f.strip()) for op, f in fs]


def codex_output(o):
    """(short result, ok|error|denied) from a function_call_output / custom_tool_call_output."""
    if isinstance(o, list):
        o = "\n".join(str((x or {}).get("text") or "") for x in o if isinstance(x, dict))
    o = str(o or "")
    code = None
    if o.startswith("{"):
        try:
            j = json.loads(o)
            code = ((j.get("metadata") or {}).get("exit_code"))
            o = str(j.get("output") or "")
        except Exception:
            pass
    m = re.search(r"Process exited with code (-?\d+)", o) or re.search(r"^Exit code: (-?\d+)", o, re.M)
    if m:
        code = int(m.group(1))
    body = o.split("\nOutput:\n", 1)[1] if "\nOutput:\n" in o else o
    if o.strip() in ("aborted",) or o.startswith("aborted"):
        return "aborted", "error"
    if DENIED.search(o[:400]) and code is None:
        return cut(firstline(o), 110), "denied"
    r = cut(lastline(body) or ("exit %s" % code if code is not None else "done"), 110)
    return r, ("error" if code not in (None, 0) else "ok")


def codex_steps(lines, cwd=""):
    steps, pend = [], {}
    for line in lines:
        if b'"response_item"' not in line and b'"session_meta"' not in line and b'"turn_context"' not in line:
            continue
        try:
            e = json.loads(line)
        except Exception:
            continue
        p = e.get("payload") if isinstance(e.get("payload"), dict) else {}
        if e.get("type") in ("session_meta", "turn_context"):
            cwd = p.get("cwd") or cwd
            continue
        at = ts_ms(e.get("timestamp"))
        t = p.get("type")
        if t == "message" and p.get("role") == "user":
            s = codex_user_text(p)
            if s:
                steps.append({"k": "you", "at": at, "a": cut(s, 240)})
        elif t == "message" and p.get("role") == "assistant":
            tx = "\n".join((c or {}).get("text") or "" for c in p.get("content") or [])
            if tx.strip():
                steps.append({"k": "say", "at": at, "a": cut(firstline(tx), 160)})
        elif t == "reasoning":
            sm = " ".join((x or {}).get("text") or "" for x in p.get("summary") or [] if isinstance(x, dict))
            if sm.strip():                       # the plain-text summary only, never encrypted_content
                steps.append({"k": "decide", "at": at, "a": cut(firstline(sm).strip("* "), 160)})
        elif t in ("function_call", "custom_tool_call", "local_shell_call"):
            name, a = p.get("name") or "shell", codex_args(p)
            st = {"k": "tool", "at": at, "name": name, "a": "", "r": None, "s": "run"}
            if name == "apply_patch":
                txt = a if isinstance(a, str) else str((a or {}).get("input") or (a or {}).get("patch") or "")
                st["name"] = "Patch"
                st["a"], st["diff"], st["add"], st["del"], _ = codex_patch(txt, cwd)
            elif name in ("exec_command", "shell_command", "shell", "local_shell"):
                c = a.get("cmd") or a.get("command") if isinstance(a, dict) else a
                if not c and t == "local_shell_call":
                    c = (p.get("action") or {}).get("command")
                st["name"] = "Bash"
                st["a"] = cut(firstline(" ".join(c) if isinstance(c, list) else c), 110)
            elif name == "update_plan" and isinstance(a, dict):
                cur = next((x for x in a.get("plan") or [] if isinstance(x, dict) and x.get("status") == "in_progress"), None)
                txt = a.get("explanation") or (cur or {}).get("step")
                if txt:
                    steps.append({"k": "decide", "at": at, "a": cut("Plan: " + firstline(txt), 160)})
                continue
            elif name in ("write_stdin", "wait", "wait_agent", "list_agents"):
                continue
            else:
                st["a"] = tool_arg(name, a, cwd) if isinstance(a, dict) else cut(firstline(a), 110)
            steps.append(st)
            if p.get("call_id"):
                pend[p["call_id"]] = st
        elif t in ("function_call_output", "custom_tool_call_output", "local_shell_call_output"):
            st = pend.pop(p.get("call_id"), None)
            if st:
                st["r"], st["s"] = codex_output(p.get("output"))
                if st["name"] == "Patch" and st["s"] == "ok":
                    st["r"] = "+%d −%d" % (st.get("add") or 0, st.get("del") or 0)
                if at and st.get("at"):
                    st["dur"] = max(0, at - st["at"])
    return steps


# ---- replay: prompt index (byte offsets per turn) ----
IDX = os.path.join(RUN, ".replay-idx.json")


def read_lines(path, start=0, end=None):
    with open(path, "rb") as f:
        f.seek(start)
        data = f.read() if end is None else f.read(max(0, end - start))
    stop = data.rfind(b"\n") + 1
    return data[:stop].split(b"\n")[:-1] if stop else [], start + stop


def index_turns(path, codex):
    """[[byte offset, ms, prompt≤160]] per prompt, cached (incremental) in .replay-idx.json."""
    cache = read_json(IDX, {}) or {}
    st = os.stat(path)
    ent = cache.get(path) or {}
    if ent.get("ino") != st.st_ino or st.st_size < ent.get("off", 0):
        ent = {"ino": st.st_ino, "off": 0, "turns": []}
    if st.st_size > ent["off"]:
        lines, end = read_lines(path, ent["off"])
        pos = ent["off"]
        for line in lines:
            here = pos
            pos += len(line) + 1
            if codex:
                if b'"role":"user"' not in line:
                    continue
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                p = e.get("payload") if isinstance(e.get("payload"), dict) else {}
                s = codex_user_text(p) if e.get("type") == "response_item" and p.get("type") == "message" else None
            else:
                if b'"type":"user"' not in line:
                    continue
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                s = claude_prompt(e)
            if s:
                ent["turns"].append([here, ts_ms(e.get("timestamp")), cut(s, 160)])
        ent["off"] = end
        cache[path] = ent
        # keep the index small: the 40 most recently indexed transcripts
        if len(cache) > 40:
            for k in sorted(cache, key=lambda k: cache[k].get("t", 0))[:len(cache) - 40]:
                cache.pop(k, None)
        ent["t"] = now_ms()
        try:
            write_json(IDX, cache)
        except OSError:
            pass
    return ent["turns"], ent["off"]


def replay(argv):
    a = [x for x in argv if x not in ("--json", "--all")]
    want_all = "--all" in argv
    turn = None
    if "--turn" in a:
        i = a.index("--turn")
        try:
            turn = int(a[i + 1])
        except (IndexError, ValueError):
            print("usage: nox agents replay <session-id> [--turn N|--all] --json", file=sys.stderr)
            return 2
        del a[i:i + 2]
    if not a:
        print("usage: nox agents replay <session-id> [--turn N|--all] --json", file=sys.stderr)
        return 2
    path, s = find_transcript(a[0])
    if not path:
        return emit({"ok": False, "error": "no transcript for this session"}, 1)
    codex = is_codex(path)
    turns, end = index_turns(path, codex)
    n = len(turns)
    if want_all or not turns:
        lo, hi, sel = 0, end, None
    else:
        sel = turn if turn is not None else n
        if turn is not None and turn < 0:
            sel = n + 1 + turn                     # --turn -1 = the last one
        if not 1 <= sel <= n:
            return emit({"ok": False, "error": "no turn %s (1..%d)" % (turn, n)}, 1)
        lo = turns[sel - 1][0]
        hi = turns[sel][0] if sel < n else end
    # the cwd in force at lo (for relative paths): from the state, else the transcript head
    cwd = (s or {}).get("cwd") or ""
    lines, _ = read_lines(path, lo, hi)
    steps = (codex_steps if codex else claude_steps)(lines, cwd)
    total = len(steps)
    dropped = max(0, total - MAX_STEPS)
    steps = steps[dropped:]
    for i, st in enumerate(steps):
        st["n"] = dropped + i + 1
        if "diff" in st and not st["diff"]:
            st.pop("diff")
    sid = (s or {}).get("id") or sid_of(path)
    return emit({"ok": True, "sid": sid, "kind": "codex" if codex else ((s or {}).get("kind") or "claude"),
                 "project": (s or {}).get("project") or os.path.basename(git_root(cwd) or cwd or "") or None,
                 "turn": sel, "nturns": n, "turns": [{"n": i + 1, "at": t[1], "prompt": t[2]} for i, t in enumerate(turns)],
                 "total": total, "truncated": dropped, "steps": steps})


# ---- laps: per-transcript working segments, cached by (size, mtime), read incrementally ----
LAPS = os.path.join(RUN, ".laps-cache.json")


def laps_scan(path, ent, codex):
    st = os.stat(path)
    if ent.get("size") == st.st_size and ent.get("mtime") == st.st_mtime and ent.get("v") == 3:
        return ent
    if ent.get("v") != 3 or ent.get("ino") != st.st_ino or st.st_size < ent.get("off", 0):
        ent = {"v": 3, "ino": st.st_ino, "off": 0, "segs": [], "last": None, "pend": {}, "prompts": [], "prs": [],
               "cwd": "", "branch": ""}
    lines, end = read_lines(path, ent["off"])
    segs, pend, prompts, prs = ent["segs"], ent["pend"], ent["prompts"], ent["prs"]

    def event(ms, prompt=False):
        last = ent["last"]
        gap = ms - last if last is not None else None
        if prompt or last is None or (gap > GAP and (not pend or gap > STUCK)):
            if prompt:
                pend.clear()
            segs.append([ms, ms])
        else:
            segs[-1][1] = max(segs[-1][1], ms)
        ent["last"] = max(ms, last or 0)

    for line in lines:
        if codex:
            if b'"response_item"' not in line and b'"turn_context"' not in line and b'"session_meta"' not in line:
                continue
        elif b'"type":"user"' not in line and b'"type":"assistant"' not in line:
            continue
        try:
            e = json.loads(line)
        except Exception:
            continue
        ms = ts_ms(e.get("timestamp"))
        if codex:
            p = e.get("payload") if isinstance(e.get("payload"), dict) else {}
            if e.get("type") in ("session_meta", "turn_context"):
                ent["cwd"] = p.get("cwd") or ent["cwd"]
                if (p.get("git") or {}).get("branch"):
                    ent["branch"] = p["git"]["branch"]
                continue
            if ms is None:
                continue
            t = p.get("type")
            if t == "message" and p.get("role") == "user":
                if codex_user_text(p):
                    prompts.append(ms)
                    event(ms, True)
                continue
            event(ms)                              # before pend changes: a running tool keeps the segment open
            if t in ("function_call", "custom_tool_call", "local_shell_call"):
                a = codex_args(p)
                pend[p.get("call_id") or str(ms)] = bool(PR_CREATE.search(json.dumps(a) if not isinstance(a, str) else a[:2000]))
            if t in ("function_call_output", "custom_tool_call_output", "local_shell_call_output"):
                if pend.pop(p.get("call_id"), False):
                    for u in set(PR_RE.findall(line)):
                        prs.append([ms, u.decode()])
            continue
        if e.get("isSidechain") or ms is None:
            continue
        ent["cwd"] = e.get("cwd") or ent["cwd"]
        ent["branch"] = e.get("gitBranch") or ent["branch"]
        if e.get("type") == "user":
            if claude_prompt(e) is not None:
                prompts.append(ms)
                event(ms, True)
                continue
            c = (e.get("message") or {}).get("content")
            if isinstance(c, list) and any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c):
                event(ms)                          # before the pop: a running tool keeps the segment open
                pr = False
                for x in c:
                    if isinstance(x, dict) and x.get("type") == "tool_result":
                        pr = pend.pop(x.get("tool_use_id"), False) or pr
                if pr:
                    for u in set(PR_RE.findall(line)):
                        prs.append([ms, u.decode()])
            continue
        m = e.get("message") or {}
        if str(m.get("model") or "").startswith("<"):
            continue
        event(ms)
        for x in m.get("content") or []:
            if isinstance(x, dict) and x.get("type") == "tool_use" and x.get("id"):
                inp = x.get("input") or {}
                pend[x["id"]] = bool(PR_CREATE.search(str(inp.get("command") or "") + " " + str(x.get("name") or "")))
    if len(pend) > 200:
        ent["pend"] = dict(list(pend.items())[-200:])
    ent.update(off=end, size=st.st_size, mtime=st.st_mtime)
    return ent


def day_bounds(date):
    d = datetime.datetime.strptime(date, "%Y-%m-%d") if date else datetime.datetime.combine(datetime.date.today(), datetime.time())
    d0 = d.replace(hour=0, minute=0, second=0, microsecond=0)
    d1 = d0 + datetime.timedelta(days=1)
    return d0, d1, int(d0.timestamp() * 1000), int(d1.timestamp() * 1000)


def union(segs):
    out = []
    for a, b in sorted(segs):
        if out and a <= out[-1][1]:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def peak(segs):
    ev = sorted([(a, 1) for a, b in segs] + [(b, -1) for a, b in segs], key=lambda x: (x[0], x[1]))
    cur = best = 0
    for _, d in ev:
        cur += d
        best = max(best, cur)
    return best


def receipts_all():
    out = []
    try:
        with open(RECEIPTS) as f:
            for l in f:
                try:
                    r = json.loads(l)
                    if isinstance(r, dict) and r.get("id"):
                        out.append(r)
                except Exception:
                    pass
    except OSError:
        pass
    undone = {r.get("ref"): r.get("at") for r in out if r.get("kind") == "undo" and r.get("ref")}
    for r in out:
        if r["id"] in undone:
            r["undone"], r["undoneAt"] = True, undone[r["id"]]
    return out


def laps(argv):
    date = None
    if "--date" in argv:
        i = argv.index("--date")
        date = argv[i + 1] if i + 1 < len(argv) else None
        try:
            datetime.datetime.strptime(date or "", "%Y-%m-%d")
        except ValueError:
            return emit({"ok": False, "error": "--date wants YYYY-MM-DD"}, 2)
    d0, d1, m0, m1 = day_bounds(date)
    cache = read_json(LAPS, {}) or {}
    state = {s["id"]: s for s in sessions()}
    files = [(p, False) for p in claude_files()] + [(p, True) for p in codex_files()]
    keep, lanes = {}, []
    for path, codex in files:
        try:
            mt = os.path.getmtime(path)
        except OSError:
            continue
        if mt * 1000 < m0:                         # untouched since before that day
            if path in cache and mt * 1000 > now_ms() - 30 * 86400_000:
                keep[path] = cache[path]
            continue
        try:
            ent = laps_scan(path, cache.get(path) or {}, codex)
        except OSError:
            continue
        keep[path] = ent
        segs = [[max(a, m0), min(b, m1)] for a, b in ent["segs"] if b > m0 and a < m1 and b > a]
        pr_day = [p for p in ent["prompts"] if m0 <= p < m1]
        if not segs and not pr_day:
            continue
        sid = sid_of(path)
        s = state.get(sid) or {}
        root = s.get("root") or git_root(ent.get("cwd")) or ent.get("cwd") or ""
        first = ent["prompts"][0] if ent["prompts"] else None
        lanes.append({"sid": sid, "project": s.get("project") or os.path.basename(root) or None,
                      "branch": s.get("branch") or ent.get("branch") or None, "root": root or None,
                      "kind": "codex" if codex else (s.get("kind") or ("expai" if "/.agent-home/" in path else "claude")),
                      "live": bool(s) and live_status(s) != "ended",
                      "segs": segs, "waits": [], "marks": [p for p in pr_day if p != first],
                      "prs": sorted({u for ms, u in ent["prs"] if m0 <= ms < m1})})
    try:
        write_json(LAPS, keep)
    except OSError:
        pass
    # receipts: waits (requests answered from the notch) and steer / deny marks
    rc = [r for r in receipts_all() if r.get("at") and m0 <= r["at"] < m1]
    by_sid = {l["sid"]: l for l in lanes}
    answers = 0
    for r in rc:
        l = by_sid.get(r.get("sid"))
        if r.get("kind") in ("allow", "always", "deny"):
            answers += 1
            if l and r.get("requestedAt") and r["requestedAt"] <= r["at"]:
                l["waits"].append([max(r["requestedAt"], m0), r["at"]])
        if l and r.get("kind") in ("steer", "deny"):
            l["marks"].append(r["at"])
    for l in lanes:
        l["marks"].sort()
        l["agentMs"] = sum(b - a for a, b in l["segs"])
    lanes.sort(key=lambda l: (l["segs"][0][0] if l["segs"] else l["marks"][0] if l["marks"] else 0))
    allsegs = [sg for l in lanes for sg in l["segs"]]
    agent = sum(b - a for a, b in allsegs)
    wall = sum(b - a for a, b in union(allsegs))
    shipped = shipped_for(lanes, d0, d1)
    return emit({"ok": True, "date": d0.strftime("%Y-%m-%d"), "from": m0, "to": m1, "now": now_ms(),
                 "metrics": {"agentMs": agent, "wallMs": wall, "parallelPeak": peak(allsegs) if allsegs else 0,
                             "interventions": sum(len(l["marks"]) for l in lanes),
                             "answers": answers, "waitMs": sum(b - a for l in lanes for a, b in l["waits"]),
                             "leverage": round(agent / max(wall, 1), 2) if lanes else None},
                 "lanes": lanes, "shipped": shipped})


def shipped_for(lanes, d0, d1):
    roots = []
    for l in lanes:
        r = l.get("root")
        if r and os.path.isdir(r) and r not in roots:
            roots.append(r)
    seen, repos = set(), []
    for r in roots[:20]:
        code, out, _ = git(r, "log", "--since=" + d0.astimezone().isoformat(), "--until=" + d1.astimezone().isoformat(),
                           "--format=%H%x09%s", timeout=6)
        if code != 0:
            continue
        rows = [x.split("\t", 1) for x in out.splitlines() if "\t" in x]
        new = [x for x in rows if x[0] not in seen]
        seen.update(x[0] for x in rows)
        if rows:
            repos.append({"root": r, "project": os.path.basename(r), "count": len(rows),
                          "subjects": [x[1][:120] for x in rows[:3]]})
    prs = sorted({u for l in lanes for u in l["prs"]})
    return {"commits": len(seen), "repos": repos, "prs": prs}


# ---- receipts ----
FIELDS = ("kind", "sid", "project", "tool", "cmd", "text", "rule", "requestedAt", "undoable", "undone")


def receipt_add(entry):
    """Append one receipt (fills id + at). One O_APPEND write, so concurrent writers don't interleave."""
    e = {k: None for k in FIELDS}
    e.update(undoable=False, undone=False)
    e.update(entry or {})
    e["at"] = e.get("at") or now_ms()
    e["id"] = e.get("id") or "%x-%s" % (e["at"], os.urandom(3).hex())
    os.makedirs(STATE, mode=0o700, exist_ok=True)
    try:
        os.chmod(STATE, 0o700)
    except OSError:
        pass
    data = (json.dumps(e, separators=(",", ":")) + "\n").encode()
    fd = os.open(RECEIPTS, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)
    return e


def receipts(argv):
    limit = 100
    if "--limit" in argv:
        try:
            limit = int(argv[argv.index("--limit") + 1])
        except (IndexError, ValueError):
            return emit({"ok": False, "error": "--limit wants a number"}, 2)
    rs = receipts_all()
    if "--all" not in argv:
        rs = [r for r in rs if r.get("kind") != "undo"]
    rs.sort(key=lambda r: -(r.get("at") or 0))
    return emit(rs[:max(0, limit)])


def rule_string(rule):
    if rule.get("str"):
        return rule["str"]
    return rule.get("toolName", "") + ("(" + rule["ruleContent"] + ")" if rule.get("ruleContent") else "")


def edit_json_file(path, fn):
    """read -> fn(cfg) -> temp file + rename, same mode, symlinks followed. fn returns an error or None."""
    real = os.path.realpath(path)
    with open(real) as f:
        cfg = json.load(f)
    err = fn(cfg)
    if err:
        return err
    mode = os.stat(real).st_mode & 0o777
    tmp = real + ".nox-tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    os.replace(tmp, real)
    return None


def undo(argv):
    dry = "--dry-run" in argv
    a = [x for x in argv if x != "--dry-run"]
    if not a:
        print("usage: nox agents undo <receipt-id> [--dry-run]", file=sys.stderr)
        return 2
    rs = receipts_all()
    r = next((x for x in rs if x["id"] == a[0]), None)
    if not r:
        return emit({"ok": False, "error": "no such receipt"}, 1)
    if r.get("undone"):
        return emit({"ok": False, "error": "already undone"}, 4)
    if r.get("kind") not in ("always", "steer") or not r.get("undoable"):
        return emit({"ok": False, "error": "not undoable"}, 4)
    detail = ""
    if r["kind"] == "always":
        rule = r.get("rule") or {}
        path, rs_ = rule.get("file"), rule_string(rule)
        if not path or not rs_:
            return emit({"ok": False, "error": "the receipt has no rule"}, 4)
        if not os.path.exists(path):
            return emit({"ok": False, "error": "the settings file is gone"}, 4)

        def drop(cfg):
            allow = ((cfg.get("permissions") or {}).get("allow"))
            if not isinstance(allow, list) or rs_ not in allow:
                return "the rule isn't in permissions.allow any more"
            if not dry:
                cfg["permissions"]["allow"] = [x for x in allow if x != rs_]
            return "dry" if dry else None
        try:
            err = edit_json_file(path, drop)
        except (OSError, ValueError) as e:
            return emit({"ok": False, "error": "can't edit the settings file: %s" % e.__class__.__name__}, 1)
        if err and err != "dry":
            return emit({"ok": False, "error": err}, 4)
        detail = "removed %s from %s" % (rs_, path)
    else:
        p = os.path.join(RUN, str(r.get("sid")) + ".steer")
        try:
            with open(p) as f:
                cur = f.read()
        except OSError:
            return emit({"ok": False, "error": "already delivered"}, 4)
        text = (r.get("text") or "").strip()
        lines = cur.strip().split("\n")
        if cur.strip() == text:
            rest = ""
        elif text and text in lines:
            lines.remove(text)
            rest = "\n".join(lines).strip()
        else:
            return emit({"ok": False, "error": "already delivered (or changed)"}, 4)
        if not dry:
            if rest:
                tmp = p + ".tmp"
                fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w") as f:
                    f.write(rest)
                os.replace(tmp, p)
            else:
                os.unlink(p)
        detail = "steer withdrawn"
    if dry:
        return emit({"ok": True, "dryRun": True, "id": r["id"], "kind": r["kind"], "would": detail})
    u = receipt_add({"kind": "undo", "ref": r["id"], "sid": r.get("sid"), "project": r.get("project"),
                     "tool": r.get("tool"), "cmd": r.get("cmd"), "text": r["kind"], "undoable": False})
    return emit({"ok": True, "id": r["id"], "kind": r["kind"], "undo": u["id"], "detail": detail})


# ---- worktrees + races ----
def make_worktree(d, task, dry=False):
    """git worktree add -b nox/<slug>-<rand> <repo-parent>/.nox-worktrees/<repo>/<slug>-<rand> HEAD."""
    code, top, _ = git(d, "rev-parse", "--show-toplevel")
    top = top.strip()
    if code != 0 or not top:
        return {"ok": False, "error": "not a git repo"}
    code, sha, _ = git(top, "rev-parse", "HEAD")
    if code != 0:
        return {"ok": False, "error": "the repo has no commits"}
    code, br, _ = git(top, "symbolic-ref", "--short", "-q", "HEAD")
    name = slug(task) + "-" + os.urandom(2).hex()
    path = os.path.join(os.path.dirname(top), ".nox-worktrees", os.path.basename(top), name)
    branch = "nox/" + name
    argv = ["git", "-C", top, "worktree", "add", "-b", branch, path, sha.strip()]
    res = {"ok": True, "root": top, "path": path, "branch": branch,
           "base": {"branch": br.strip() or None, "sha": sha.strip()}}
    if dry:
        return dict(res, dryRun=True, argv=argv)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    code, out, err = run(argv, timeout=60)
    if code != 0:
        return {"ok": False, "error": "git worktree add failed: " + cut(lastline(err or out), 160)}
    return res


def race_path(rid):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", rid or ""):
        return None
    return os.path.join(RACES, rid + ".json")


def load_race(rid):
    p = race_path(rid)
    return read_json(p) if p else None


def save_race(r):
    write_json(race_path(r["id"]), r)


def race(argv, start):
    """nox agents race [--models a,b,c | -n N] [--dry-run] <dir> TASK: N worktrees + N background agents.
    start: `agents`.start (prints JSON; captured here)."""
    import io, contextlib
    dry = "--dry-run" in argv
    a = [x for x in argv if x != "--dry-run"]
    models, n = None, None
    if "--models" in a:
        i = a.index("--models")
        models = [m.strip() for m in (a[i + 1] if i + 1 < len(a) else "").split(",") if m.strip()]
        del a[i:i + 2]
    if "-n" in a:
        i = a.index("-n")
        try:
            n = int(a[i + 1])
        except (IndexError, ValueError):
            n = None
        del a[i:i + 2]
    if len(a) < 2:
        print("usage: nox agents race [--models opus,sonnet,haiku | -n 3] [--dry-run] <dir> TASK...", file=sys.stderr)
        return 2
    d, task = os.path.realpath(os.path.expanduser(a[0])), " ".join(a[1:]).strip()
    if not os.path.isdir(d) or not task:
        return emit({"ok": False, "error": "no such directory" if not os.path.isdir(d) else "empty task"}, 1)
    if not models:
        models = [None] * n if n else (shell_opts().get("raceModels") or ["opus", "sonnet", "haiku"])
    if not 1 <= len(models) <= 6:
        return emit({"ok": False, "error": "1..6 agents"}, 2)
    rid = datetime.datetime.now().strftime("r%Y%m%d-%H%M%S-") + os.urandom(2).hex()
    rec = {"id": rid, "task": task, "root": None, "base": None, "at": now_ms(), "entries": []}
    errors = []
    for m in models:
        wt = make_worktree(d, task, dry)
        if not wt["ok"]:
            errors.append(wt["error"])
            break
        rec["root"], rec["base"] = wt["root"], wt["base"]
        sargv = ["--mode", "background"] + (["--model", m] if m else []) + (["--dry-run"] if dry else []) + \
                [wt["root"] if dry else wt["path"], task]
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = start(sargv)
        try:
            res = json.loads(buf.getvalue().strip().splitlines()[-1])
        except Exception:
            res = {"ok": False, "error": "start printed nothing"}
        ent = {"model": m, "branch": wt["branch"], "path": wt["path"], "tmux": res.get("session")}
        if dry:
            argv_ = [wt["path"] if x == wt["root"] else x for x in (res.get("argv") or [])]
            ent.update(worktreeArgv=wt["argv"], startArgv=argv_)
            ent["tmux"] = argv_[4] if len(argv_) > 4 else None
        if not res.get("ok"):
            errors.append(res.get("error") or "start failed")
        rec["entries"].append(ent)
    if dry:
        return emit({"ok": not errors, "dryRun": True, "race": rec, "errors": errors})
    if rec["entries"]:
        save_race(rec)
        receipt_add({"kind": "race", "sid": None, "project": os.path.basename(rec["root"] or d),
                     "text": task[:300], "cmd": rid, "undoable": False})
    return emit({"ok": not errors, "race": rec, "errors": errors}, 0 if not errors else 1)


def tmux_has(name):
    if not name:
        return False
    code, _, _ = run(["tmux", "-L", TMUX_SOCK, "has-session", "-t", "=" + name], timeout=3)
    return code == 0


def entry_session(path, ss):
    rp = os.path.realpath(path)
    hits = [s for s in ss if os.path.realpath(s.get("root") or s.get("cwd") or "/nonexistent") == rp
            or os.path.realpath(s.get("cwd") or "/nonexistent").startswith(rp + "/")]
    return max(hits, key=lambda s: s.get("updated", 0)) if hits else None


def wt_diff(path, base):
    """Committed + uncommitted changes of a worktree vs the race base (files, +/-)."""
    files = {}
    code, out, _ = git(path, "diff", "--numstat", "-z", "--no-renames", base, "--")
    if code == 0:
        for p in out.split("\0"):
            f = p.split("\t", 2)
            if len(f) == 3:
                files[f[2]] = [int(f[0]) if f[0].isdigit() else 0, int(f[1]) if f[1].isdigit() else 0]
    code, out, _ = git(path, "ls-files", "--others", "--exclude-standard", "-z")
    for u in [x for x in out.split("\0") if x][:300]:
        n = 0
        try:
            fp = os.path.join(path, u)
            if os.path.getsize(fp) < 2_000_000:
                with open(fp, "rb") as fh:
                    b = fh.read()
                n = 0 if b"\0" in b[:8000] else b.count(b"\n") + (0 if b.endswith(b"\n") or not b else 1)
        except OSError:
            pass
        files[u] = [n, 0]
    c, o, _ = git(path, "rev-list", "--count", base + "..HEAD")
    c2, o2, _ = git(path, "status", "--porcelain")
    return {"files": len(files), "add": sum(v[0] for v in files.values()), "del": sum(v[1] for v in files.values()),
            "paths": sorted(files, key=lambda k: -sum(files[k]))[:30], "commits": int(o.strip() or 0) if c == 0 else None,
            "dirty": bool(o2.strip()) if c2 == 0 else None}


def races(argv):
    os.makedirs(RACES, mode=0o700, exist_ok=True)
    ss = sessions()
    test_on = bool(os.environ.get("NOX_RACE_TEST") or shell_opts().get("raceTest"))
    out = []
    for p in sorted(glob.glob(os.path.join(RACES, "*.json")), key=os.path.getmtime, reverse=True)[:20]:
        r = read_json(p)
        if not isinstance(r, dict) or not r.get("entries"):
            continue
        base = (r.get("base") or {}).get("sha") or "HEAD"
        ents = []
        for i, e in enumerate(r["entries"]):
            s = entry_session(e["path"], ss)
            present = os.path.isdir(e["path"])
            if s:
                status = live_status(s)
            elif not present:
                status = "removed"
            else:
                status = "starting" if tmux_has(e.get("tmux")) else "stopped"
            ents.append({"i": i, "model": e.get("model"), "branch": e.get("branch"), "path": e["path"], "tmux": e.get("tmux"),
                         "sid": s["id"] if s else None, "status": status, "present": present,
                         "diff": wt_diff(e["path"], base) if present else None,
                         "test": e.get("test") if test_on else None})
        out.append({"id": r["id"], "task": r.get("task"), "root": r.get("root"), "base": r.get("base"), "at": r.get("at"),
                    "merged": r.get("merged"), "testConfigured": test_on, "entries": ents})
    return emit(out)


def race_test(argv):
    import threading
    dry = "--dry-run" in argv
    a = [x for x in argv if x != "--dry-run"]
    r = load_race(a[0]) if a else None
    if not r:
        return emit({"ok": False, "error": "no such race"}, 1)
    opts = shell_opts()
    cmd = os.environ.get("NOX_RACE_TEST") or opts.get("raceTest")
    if not cmd:
        return emit({"ok": False, "error": "no test command (shell.json agents.raceTest)"}, 3)
    tmo = int(opts.get("raceTestTimeout") or 600)
    ents = [(i, e) for i, e in enumerate(r["entries"]) if os.path.isdir(e["path"])]
    if dry:
        return emit({"ok": True, "dryRun": True, "argv": ["bash", "-c", cmd], "timeout": tmo,
                     "cwds": [e["path"] for _, e in ents]})
    res = {}

    def one(i, e):
        t0 = time.time()
        env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE", "ORCA_"))}
        try:
            p = subprocess.run(["bash", "-c", cmd], cwd=e["path"], capture_output=True, text=True, timeout=tmo, env=env,
                               stdin=subprocess.DEVNULL)
            code, txt = p.returncode, (p.stdout or "") + "\n" + (p.stderr or "")
            summ = lastline(p.stdout) or lastline(p.stderr) or ("exit %d" % code)
        except subprocess.TimeoutExpired:
            code, summ = None, "timed out after %ds" % tmo
        except Exception as ex:
            code, summ = None, "couldn't run: %s" % ex.__class__.__name__
        c, sha, _ = git(e["path"], "rev-parse", "--short", "HEAD")
        res[i] = {"pass": code == 0, "code": code, "summary": cut(summ, 160), "at": now_ms(),
                  "ms": int((time.time() - t0) * 1000), "head": sha.strip() or None}

    th = [threading.Thread(target=one, args=x) for x in ents]
    for t in th:
        t.start()
    for t in th:
        t.join()
    r = load_race(r["id"]) or r                    # re-read: merge may have run meanwhile
    for i, v in res.items():
        r["entries"][i]["test"] = v
    save_race(r)
    return emit({"ok": True, "id": r["id"], "results": [dict(v, i=i) for i, v in sorted(res.items())]})


def merge(argv):
    dry = "--dry-run" in argv
    a = [x for x in argv if x != "--dry-run"]
    if len(a) < 2:
        print("usage: nox agents merge <race-id> <entry-index> [--dry-run]", file=sys.stderr)
        return 2
    r = load_race(a[0])
    if not r:
        return emit({"ok": False, "error": "no such race"}, 1)
    try:
        idx = int(a[1])
        e = r["entries"][idx]
    except (ValueError, IndexError):
        return emit({"ok": False, "error": "no such entry"}, 1)
    if r.get("merged"):
        return emit({"ok": False, "error": "this race was already merged (entry %s)" % r["merged"].get("index")}, 4)
    root, base = r.get("root"), (r.get("base") or {}).get("branch")
    if not base:
        return emit({"ok": False, "error": "the race started on a detached HEAD: merge it by hand"}, 4)
    if not os.path.isdir(e["path"]):
        return emit({"ok": False, "error": "the winner's worktree is gone"}, 4)
    code, cur, _ = git(root, "symbolic-ref", "--short", "-q", "HEAD")
    if cur.strip() != base:
        return emit({"ok": False, "error": "the main worktree is on %s, not %s" % (cur.strip() or "a detached HEAD", base)}, 4)
    code, dirty, _ = git(root, "status", "--porcelain", "--untracked-files=no")
    if code != 0 or dirty.strip():
        return emit({"ok": False, "error": "the main worktree has uncommitted changes"}, 4)
    s = entry_session(e["path"], sessions())
    if s and live_status(s) in ("working", "needs-you"):
        return emit({"ok": False, "error": "that agent is still %s" % live_status(s)}, 4)
    code, wdirty, _ = git(e["path"], "status", "--porcelain")
    msg = "nox race: " + r.get("task", "")
    steps = []
    if wdirty.strip():
        steps += [["git", "-C", e["path"], "add", "-A"], ["git", "-C", e["path"], "commit", "-q", "-m", msg]]
    c, ahead, _ = git(e["path"], "rev-list", "--count", (r.get("base") or {}).get("sha", base) + "..HEAD")
    if not wdirty.strip() and c == 0 and ahead.strip() == "0":
        return emit({"ok": False, "error": "nothing to merge: the entry made no changes"}, 4)
    steps.append(["git", "-C", root, "merge", "--no-ff", "--no-edit", e["branch"]])
    if dry:
        return emit({"ok": True, "dryRun": True, "steps": steps})
    commit = None
    for st in steps[:-1]:
        code, out, err = run(st, timeout=120)
        if code != 0:
            return emit({"ok": False, "error": "commit failed: " + cut(lastline(err or out), 200), "step": st[3]}, 1)
    if len(steps) > 1:
        commit = git(e["path"], "rev-parse", "HEAD")[1].strip()
    code, out, err = run(steps[-1], timeout=120)
    if code != 0:
        c2, conf, _ = git(root, "diff", "--name-only", "--diff-filter=U")
        git(root, "merge", "--abort")              # back to the clean state it had: nothing is lost
        return emit({"ok": False, "error": "merge failed: " + cut(lastline(err or out), 200),
                     "conflicts": conf.split()[:30], "aborted": True, "commit": commit}, 1)
    sha = git(root, "rev-parse", "HEAD")[1].strip()
    r = load_race(r["id"]) or r
    r["merged"] = {"index": idx, "at": now_ms(), "sha": sha, "commit": commit, "branch": e["branch"]}
    save_race(r)
    receipt_add({"kind": "merge", "project": os.path.basename(root), "text": r.get("task", "")[:300],
                 "cmd": "%s → %s" % (e["branch"], base), "undoable": False})
    return emit({"ok": True, "id": r["id"], "index": idx, "branch": e["branch"], "into": base, "sha": sha, "commit": commit})


def race_clean(argv):
    dry = "--dry-run" in argv
    discard = "--discard" in argv
    a = [x for x in argv if x not in ("--dry-run", "--discard")]
    r = load_race(a[0]) if a else None
    if not r:
        return emit({"ok": False, "error": "no such race"}, 1)
    root, base = r.get("root"), (r.get("base") or {}).get("branch")
    win = (r.get("merged") or {}).get("index")
    ss = sessions()
    out = []
    for i, e in enumerate(r["entries"]):
        row = {"i": i, "path": e["path"], "branch": e["branch"], "worktree": None, "branchAction": None, "why": None}
        if i == win:
            row.update(worktree="kept", branchAction="kept", why="the winner (merged)")
            out.append(row)
            continue
        s = entry_session(e["path"], ss)
        if not os.path.isdir(e["path"]):
            row["worktree"] = "gone"
        elif s and live_status(s) != "ended" or tmux_has(e.get("tmux")):
            row.update(worktree="kept", why="its agent session is still open (exit it first)")
        else:
            code, st, _ = git(e["path"], "status", "--porcelain")
            if code != 0 or st.strip():
                row.update(worktree="kept", why="uncommitted changes")
            elif dry:
                row["worktree"] = "would remove"
            else:
                code, o, err = git(root, "worktree", "remove", e["path"], timeout=30)
                row["worktree"] = "removed" if code == 0 else "kept"
                if code != 0:
                    row["why"] = cut(lastline(err or o), 160)
        if row["worktree"] in ("removed", "gone", "would remove"):
            code, _, _ = git(root, "rev-parse", "--verify", "-q", "refs/heads/" + e["branch"])
            if code != 0:
                row["branchAction"] = "gone"
            else:
                merged = base and git(root, "merge-base", "--is-ancestor", e["branch"], base)[0] == 0
                if merged or discard:
                    if dry:
                        row["branchAction"] = "would delete"
                    else:
                        code, o, err = git(root, "branch", "-d" if merged else "-D", e["branch"])
                        row["branchAction"] = "deleted" if code == 0 else "kept"
                        if code != 0:
                            row["why"] = cut(lastline(err or o), 160)
                else:
                    row.update(branchAction="kept", why=row["why"] or "unmerged commits (pass --discard to drop them)")
        else:
            row["branchAction"] = "kept"
        out.append(row)
    return emit({"ok": True, "dryRun": dry, "id": r["id"], "entries": out})


# ---- overlap ----
def overlap(argv):
    cut_ms = now_ms() - 15 * 60 * 1000
    by = {}
    for s in sessions():
        if live_status(s) == "ended":
            continue
        root = s.get("root") or s.get("cwd")
        cwd = s.get("cwd") or root
        if not root:
            continue
        paths = set()
        for x in s.get("activity") or []:
            if x.get("k") == "tool" and x.get("n") in EDIT_TOOLS + ("apply_patch",) and (x.get("ts") or 0) >= cut_ms \
                    and x.get("s") != "er" and x.get("a") and not x["a"].endswith("…"):
                paths.add(x["a"].split(" +")[0] if x.get("n") == "apply_patch" else x["a"])
        t = s.get("turn") or {}
        if (t.get("at") or 0) >= cut_ms:
            paths.update(t.get("files") or [])
        for p in paths:
            full = os.path.normpath(p if p.startswith("/") else os.path.join(cwd, p))
            rp = os.path.relpath(full, root) if full.startswith(root.rstrip("/") + "/") else full
            by.setdefault((root, rp), set()).add(s["id"])
    return emit([{"root": k[0], "file": k[1], "sessions": sorted(v)} for k, v in sorted(by.items()) if len(v) > 1])


# ---- Codex: the status hook in ~/.codex/hooks.json ----
CODEX_EVENTS = ("SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop",
                "SubagentStart", "SubagentStop", "Interrupt", "SessionEnd")
CODEX_TIMEOUTS = {"SessionEnd": 3, "Interrupt": 3}


def codex_hook(action, hook_path, dry=False):
    """status | install | uninstall our entry in ~/.codex/hooks.json ($NOX_CODEX_HOOKS for tests).
    Our group is APPENDED per event: Codex keys hook trust by position (event:group:handler), so the
    other tools' entries keep their indexes and their trust. New entries run only after you trust
    them in Codex (/hooks)."""
    path = os.environ.get("NOX_CODEX_HOOKS") or os.path.join(CODEX_HOME, "hooks.json")
    cmd = shlex.quote(hook_path)
    try:
        with open(path) as f:
            cfg = json.load(f)
    except FileNotFoundError:
        cfg = {}
    except ValueError:
        print("nox agents: %s isn't valid JSON; not touching it" % path, file=sys.stderr)
        return 1
    hooks = cfg.get("hooks") or {}

    def ours(h):
        return h.get("command") in (cmd, hook_path)
    have = [ev for ev in CODEX_EVENTS if any(ours(h) for g in hooks.get(ev, []) for h in (g.get("hooks") or []))]
    if action == "status":
        ok = len(have) == len(CODEX_EVENTS)
        print(("installed: %s on all %d Codex events (%s); trust them once in Codex: /hooks" % (hook_path, len(CODEX_EVENTS), path))
              if ok else "not installed: %d/%d Codex events (%s); fix: nox agents hook install --codex" % (len(have), len(CODEX_EVENTS), path))
        return 0 if ok else 1
    if action not in ("install", "uninstall"):
        print("usage: nox agents hook [status|install|uninstall] --codex", file=sys.stderr)
        return 2
    for ev in (CODEX_EVENTS if action == "install" else list(hooks)):
        groups = hooks.get(ev, [])
        if action == "install":
            if any(ours(h) for g in groups for h in (g.get("hooks") or [])):
                continue
            groups = groups + [{"hooks": [{"type": "command", "command": cmd, "timeout": CODEX_TIMEOUTS.get(ev, 5)}]}]
        else:
            groups = [dict(g, hooks=[h for h in (g.get("hooks") or []) if not ours(h)]) for g in groups]
            groups = [g for g in groups if g["hooks"]]
        if groups:
            hooks[ev] = groups
        else:
            hooks.pop(ev, None)
    if hooks:
        cfg["hooks"] = hooks
    else:
        cfg.pop("hooks", None)
    if dry:
        print(json.dumps(cfg, indent=2))
        return 0
    real = os.path.realpath(path)
    os.makedirs(os.path.dirname(real), exist_ok=True)
    mode = 0o600
    if os.path.exists(real):
        mode = os.stat(real).st_mode & 0o777
        bak = real + ".bak-nox-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        with open(real) as a, open(bak, "w") as b:
            b.write(a.read())
        os.chmod(bak, mode)
        print("backup:", bak)
    tmp = real + ".nox-tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    os.replace(tmp, real)
    print(("installed " if action == "install" else "removed ") + hook_path, "in", path)
    if action == "install":
        print("Codex runs new hooks only once trusted: open codex, /hooks, trust the nox entries "
              "(and keep [features] hooks = true in config.toml)")
    return 0


def main(cmd, argv, start=None, hook_path=None):
    """Dispatch for `nox agents <cmd>` (called from `agents`)."""
    if cmd == "replay":
        return replay(argv)
    if cmd == "laps":
        return laps(argv)
    if cmd == "receipts":
        return receipts(argv)
    if cmd == "undo":
        return undo(argv)
    if cmd == "race":
        return race(argv, start)
    if cmd == "races":
        return races(argv)
    if cmd == "race-test":
        return race_test(argv)
    if cmd == "merge":
        return merge(argv)
    if cmd == "race-clean":
        return race_clean(argv)
    if cmd == "overlap":
        return overlap(argv)
    if cmd == "codex-hook":
        act = next((x for x in argv if x in ("status", "install", "uninstall")), "status")
        return codex_hook(act, hook_path, "--dry-run" in argv)
    return 2
