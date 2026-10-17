#!/usr/bin/env python3
"""Diff the live (hyprlang) binds against the Graphite Lua binds.

usage: binddiff.py <live.json from `hyprctl -j binds`> <lua-binds.jsonl from binddump.lua> [conf dir]

hyprctl does not report the i/t/p flags (ignore_mods, transparent, dont_inhibit),
so they are recovered from the .conf sources in load order (hyprland.conf ->
hyprland/keybinds.conf -> custom/keybinds.conf -> trailing hyprland.conf binds),
applying `unbind` lines, and attached to the live binds by position.
Prints a Markdown table + summary. Exit 1 if a live bind is missing in Lua.
"""
import json
import os
import re
import sys

MODS = {"SHIFT": 1, "CAPS": 2, "CTRL": 4, "CONTROL": 4, "ALT": 8, "MOD2": 16, "MOD3": 32,
        "SUPER": 64, "WIN": 64, "LOGO": 64, "MOD4": 64, "META": 64, "MOD5": 128}
HOME = os.environ.get("HOME", "")
USER = os.environ.get("USER", "")


def norm_arg(s):
    return s.replace("${HOME}", HOME).replace("$HOME", HOME).replace("$USER", USER).strip()


def modmask(s):
    m = 0
    for p in re.split(r"[+_ ]", s.strip()):
        if p.upper() in MODS:
            m |= MODS[p.upper()]
    return m


def keyid(b):
    if b.get("catch_all"):
        return "catchall"
    if b.get("keycode"):
        return "code:%d" % b["keycode"]
    return b["key"].lower()


def conf_flags(confdir):
    """[(submap, modmask, key, flagletters)] in registration order."""
    out = []
    submap = [""]

    def parse(path, start=None, stop=None):
        with open(path) as f:
            lines = f.read().splitlines()
        for ln in lines:
            s = ln.strip()
            if not s or s.startswith("#"):
                continue
            m = re.match(r"submap\s*=\s*(\S+)", s)
            if m:
                submap[0] = "" if m.group(1) == "reset" else m.group(1)
                continue
            m = re.match(r"source\s*=\s*(\S+)", s)
            if m:
                p = os.path.join(confdir, m.group(1))
                if p.endswith("keybinds.conf") and os.path.exists(p):
                    parse(p)
                continue
            m = re.match(r"unbind\s*=\s*([^,]*),\s*([^,#]+)", s)
            if m:
                mm, k = modmask(m.group(1)), m.group(2).strip().lower()
                out[:] = [b for b in out if not (b[1] == mm and b[2] == k)]
                continue
            m = re.match(r"bind([a-z]*)\s*=\s*([^,]*),\s*([^,]+),", s)
            if m:
                k = m.group(3).strip().lower()
                out.append((submap[0], modmask(m.group(2)), k, m.group(1)))

    parse(os.path.join(confdir, "hyprland.conf"))
    return out


def main():
    live = json.load(open(sys.argv[1]))
    lua = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
    confdir = sys.argv[3] if len(sys.argv) > 3 else os.path.expanduser("~/.config/hypr")

    flags = conf_flags(confdir)
    if len(flags) == len(live) and all(f[2] == keyid(b) for f, b in zip(flags, live)):
        for f, b in zip(flags, live):
            b["ignore_mods"] = "i" in f[3]
            b["transparent"] = "t" in f[3]
            b["dont_inhibit"] = "p" in f[3]
    else:
        print("<!-- warning: could not align conf flags with live binds (%d vs %d) -->" % (len(flags), len(live)))

    used = [False] * len(lua)
    rows, missing, changed = [], 0, 0
    FL = ["locked", "release", "repeat", "non_consuming", "mouse", "ignore_mods", "transparent", "dont_inhibit"]

    def fl(b):
        return "".join(c for c, k in zip("lrenmitp", FL) if b.get(k))

    for i, b in enumerate(live):
        # catchall binds carry ignore_mods, so their modmask is irrelevant (Lua
        # cannot spell "SUPER + catchall"; hyprlang stores the Super mask)
        cand = [j for j, x in enumerate(lua) if not used[j] and x["submap"] == b["submap"]
                and (x["modmask"] == b["modmask"] or (b.get("catch_all") and x.get("catch_all")))
                and keyid(x) == keyid(b)]
        old = "%s %s" % (b["dispatcher"], norm_arg(b["arg"]))
        if not cand:
            rows.append((i, b, old, "-", "MISSING"))
            missing += 1
            continue
        # prefer an exact dispatcher+arg match among same-key binds
        exact = [j for j in cand if lua[j]["dispatcher"] == b["dispatcher"] and norm_arg(lua[j]["arg"]) == norm_arg(b["arg"])]
        j = (exact or cand)[0]
        used[j] = True
        x = lua[j]
        new = "%s %s" % (x["dispatcher"], norm_arg(x["arg"]))
        notes = []
        if new != old:
            notes.append("action")
        fb = {k: b.get(k, False) for k in FL}
        fx = {k: x.get(k, False) for k in FL}
        if "ignore_mods" not in b:
            for k in ("ignore_mods", "transparent", "dont_inhibit"):
                fx.pop(k), fb.pop(k)
        if fb != fx:
            notes.append("flags %s->%s" % (fl(b), fl(x)))
        if (b.get("description") or "") != (x.get("description") or ""):
            notes.append("desc")
        status = "same" if not notes else "changed: " + ", ".join(notes)
        if notes:
            changed += 1
        rows.append((i, b, old, new if notes and "action" in notes else "=", status))

    extra = [x for j, x in enumerate(lua) if not used[j]]

    def keys(b):
        names = [n for n, v in (("SUPER", 64), ("CTRL", 4), ("ALT", 8), ("SHIFT", 1)) if b["modmask"] & v]
        return " + ".join(names + [keyid(b) if not b.get("catch_all") else "catchall"])

    def cell(s, n=110):
        s = s.replace("|", "\\|")
        return s if len(s) <= n else s[: n - 1] + "…"

    print("| # | submap | keys | flags | current (hyprlang) | Lua (if different) | status |")
    print("|---|---|---|---|---|---|---|")
    for i, b, old, new, status in rows:
        print("| %d | %s | `%s` | %s | %s | %s | %s |" % (i, b["submap"], keys(b), fl(b), cell(old), cell(new), status))
    for x in extra:
        print("| + | %s | `%s` | %s | - | %s | NEW |" % (x["submap"], keys(x), fl(x), cell("%s %s" % (x["dispatcher"], x["arg"]))))
    print()
    print("live binds: %d, lua binds: %d, same: %d, changed: %d, missing: %d, new: %d"
          % (len(live), len(lua), len(live) - changed - missing, changed, missing, len(extra)))
    sys.exit(1 if missing else 0)


if __name__ == "__main__":
    main()
