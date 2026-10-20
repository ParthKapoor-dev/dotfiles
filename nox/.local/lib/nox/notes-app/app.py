#!/usr/bin/env python3
"""nox Notes host: one GTK window with a WebKit view running the Milkdown Crepe editor (web/).

Started by `nox notes` (../notes), which also hides / shows the window through Hyprland (parked on
special:notes, so it keeps its place and size). Single instance (GApplication "dev.nox.Notes"):
running it again forwards --new / --open PATH / --focus to the running window.

The page asks for file work over a message bridge (see web source _notes/src/main.js): list, read,
write (atomic), create, rename, remove, trash, state, init, drag, hide, openUrl, quit. Every path
must be a .md file directly inside the notes directory (~/Notes, or $NOX_NOTES_DIR).
"""
import json
import os
import re
import subprocess
import sys
import time

import gi

# WebKitGTK's DMA-BUF renderer dies with a Wayland protocol error on this NVIDIA GPU; the shared
# memory path is plenty for a text editor
os.environ.setdefault("WEBKIT_DISABLE_DMABUF_RENDERER", "1")
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gdk, Gio, GLib, Gtk, WebKit2  # noqa: E402

HERE = os.path.dirname(os.path.realpath(__file__))
WEB = os.path.join(HERE, "web", "index.html")
NOTES = os.path.realpath(os.path.expanduser(os.environ.get("NOX_NOTES_DIR", "~/Notes")))
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "nox")
STATE = os.path.join(STATE_DIR, "notes.json")            # shared with the Qt notes: {last, sidebar}
TOKENS = [os.path.join(STATE_DIR, "tokens.json"), os.path.expanduser("~/.config/nox/tokens.json")]
APP_ID = "dev.nox.Notes"


def note_path(p):
    """p resolved inside NOTES as a .md file, else ValueError."""
    p = os.path.realpath(os.path.expanduser(str(p)))
    if os.path.dirname(p) != NOTES or not p.lower().endswith(".md"):
        raise ValueError("not a note: " + p)
    return p


def preview(path):
    """first text line after the title, without markdown"""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            head = f.read(2000)
    except OSError:
        return ""
    lines = []
    for line in head.splitlines():
        line = re.sub(r"^\s*(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+|>\s*)", "", line)
        line = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", line)
        line = re.sub(r"[*_`~]|<br\s*/?>", "", line).strip()
        if line and not re.fullmatch(r"[-=*_ ]{3,}", line):
            lines.append(line)
        if len(lines) == 2:
            break
    return lines[1][:140] if len(lines) > 1 else ""


def read_state():
    try:
        with open(STATE) as f:
            d = json.load(f)
            return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def write_atomic(path, text, mode=None):
    d, b = os.path.split(path)
    tmp = os.path.join(d, "." + b + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    if mode is not None:
        os.chmod(tmp, mode)
    elif os.path.exists(path):
        os.chmod(tmp, os.stat(path).st_mode & 0o777)
    os.replace(tmp, path)


def theme():
    """nox tokens -> the page's CSS variables"""
    t = None
    for p in TOKENS:
        try:
            with open(p) as f:
                t = json.load(f)
            break
        except (OSError, ValueError):
            continue
    if not t:
        return {}
    c, font = t.get("color", {}), t.get("font", {})

    def rgba(hexc, a=1.0):
        h = hexc.lstrip("#")
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        return f"rgba({r}, {g}, {b}, {a})"

    try:
        lab = c.get("label", "#FFFFFF")
        out = {
            "bg": c.get("bg", "#0A0A0A"),
            "surface": c.get("surface", "#141414"),
            "raised": c.get("raised", "#202020"),
            "label": rgba(lab, c.get("labelAlpha", 0.9)),
            "label2": rgba(lab, c.get("label2Alpha", 0.56)),
            "label3": rgba(lab, c.get("label3Alpha", 0.3)),
            "sep": rgba(lab, c.get("sepAlpha", 0.1) * 0.8),
            "hair": rgba(lab, c.get("hairAlpha", 0.14)),
            "fill": rgba(lab, c.get("fillAlpha", 0.06) * 0.85),
            "fill2": rgba(lab, c.get("fill2Alpha", 0.11) * 0.85),
            "fill3": rgba(lab, c.get("fill3Alpha", 0.18) * 0.85),
            "accent": c.get("accent", "#FF3B1F"),
            "accent-soft": rgba(c.get("accent", "#FF3B1F"), 0.16),
        }
    except (ValueError, TypeError, AttributeError):
        return {}
    if font.get("ui"):
        out["font-ui"] = f'"{font["ui"]}", sans-serif'
    if font.get("display"):
        out["font-display"] = f'"{font["display"]}", sans-serif'
    if font.get("mono"):
        out["font-mono"] = f'"{font["mono"]}", monospace'
    r = t.get("radius", {}).get("menu")
    if isinstance(r, (int, float)):
        out["radius"] = f"{max(4, r * 2)}px"
    return out


class Notes(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.win = None
        self.view = None
        self.ready = False
        self.pending = []             # events for the page before it has started
        self.start_args = {}
        self.quitting = False

    # ---- instance / command line ----
    def do_command_line(self, cl):
        args = cl.get_arguments()[1:]
        want = {}
        if "--new" in args:
            want["new"] = True
        if "--open" in args:
            i = args.index("--open")
            if i + 1 < len(args):
                want["open"] = args[i + 1]
        if self.win is None:
            self.start_args = want
            self.build()
        else:
            if want.get("new"):
                self.event("new")
            elif want.get("open"):
                self.event("open", want["open"])
            self.win.present()
        return 0

    def build(self):
        os.makedirs(NOTES, exist_ok=True)
        self.win = Gtk.ApplicationWindow(application=self, title="Notes")
        self.win.set_default_size(900, 600)
        self.win.set_decorated(False)
        self.win.connect("delete-event", self.on_delete)
        self.win.connect("focus-in-event", lambda *_: self.event("focus") or False)

        ctx = WebKit2.WebContext.get_default()
        ctx.set_spell_checking_enabled(True)
        ctx.set_spell_checking_languages(["en_US"])
        ctx.set_cache_model(WebKit2.CacheModel.DOCUMENT_VIEWER)
        ucm = WebKit2.UserContentManager()
        ucm.register_script_message_handler("nox")
        ucm.connect("script-message-received::nox", self.on_message)
        # page errors end up on stderr (the journal when started by nox notes)
        ucm.add_script(WebKit2.UserScript.new(
            "addEventListener('error', e => webkit.messageHandlers.nox.postMessage(JSON.stringify({op: 'log', args: {msg: e.message + ' @ ' + e.filename + ':' + e.lineno}})));"
            "addEventListener('unhandledrejection', e => webkit.messageHandlers.nox.postMessage(JSON.stringify({op: 'log', args: {msg: 'unhandled: ' + (e.reason && e.reason.stack || e.reason)}})));",
            WebKit2.UserContentInjectedFrames.TOP_FRAME, WebKit2.UserScriptInjectionTime.START, None, None))
        self.view = WebKit2.WebView.new_with_user_content_manager(ucm)
        s = self.view.get_settings()
        s.set_allow_file_access_from_file_urls(True)
        s.set_enable_developer_extras(bool(os.environ.get("NOX_NOTES_DEBUG")))
        s.set_enable_write_console_messages_to_stdout(bool(os.environ.get("NOX_NOTES_DEBUG")))
        s.set_enable_back_forward_navigation_gestures(False)
        s.set_enable_smooth_scrolling(True)
        s.set_hardware_acceleration_policy(WebKit2.HardwareAccelerationPolicy.ALWAYS)
        bg = Gdk.RGBA()
        bg.parse(theme().get("bg", "#0A0A0A"))
        self.view.set_background_color(bg)
        self.view.connect("decide-policy", self.on_policy)
        self.view.connect("context-menu", self.on_context_menu)
        self.win.add(self.view)
        self.view.load_uri("file://" + WEB)
        self.win.show_all()

    # ---- page bridge ----
    def js(self, code):
        self.view.evaluate_javascript(code, -1, None, None, None, None, None)

    def event(self, name, data=None):
        if not self.ready:
            if name != "focus":
                self.pending.append((name, data))
            return
        self.js(f"window.__noxEvent({json.dumps(name)}, {json.dumps(data)})")

    def on_message(self, _ucm, value):
        # WebKit2 4.1 wraps the value in a JavascriptResult (WebKit 6 passes the JSCValue itself)
        value = value.get_js_value() if hasattr(value, "get_js_value") else value
        try:
            msg = json.loads(value.to_string())
        except (ValueError, TypeError):
            print("nox notes: bad message from the page", file=sys.stderr)
            return
        mid, op, args = msg.get("id"), msg.get("op", ""), msg.get("args") or {}
        try:
            result, err = getattr(self, "op_" + op)(**args), None
        except AttributeError:
            result, err = None, "unknown op " + op
        except Exception as e:  # noqa: BLE001 - reported to the page
            result, err = None, str(e)
        self.js(f"window.__noxReply({json.dumps(mid)}, {json.dumps(result)}, {json.dumps(err)})")

    def op_init(self):
        a = self.start_args
        self.start_args = {}
        GLib.idle_add(self.flush_pending)
        o = a.get("open")
        if o:
            try:
                o = note_path(o)
            except ValueError:
                o = None
        return {"theme": theme(), "state": read_state(), "open": o, "new": bool(a.get("new"))}

    def flush_pending(self):
        self.ready = True
        for name, data in self.pending:
            self.event(name, data)
        self.pending = []
        return False

    def op_log(self, msg):
        print("nox notes page:", msg, file=sys.stderr, flush=True)

    def op_list(self):
        out = []
        with os.scandir(NOTES) as it:
            for e in it:
                if e.is_file() and e.name.lower().endswith(".md") and not e.name.startswith("."):
                    out.append({"path": e.path, "name": e.name[:-3], "mtime": e.stat().st_mtime * 1000, "preview": preview(e.path)})
        out.sort(key=lambda n: -n["mtime"])
        return out

    def op_read(self, path):
        with open(note_path(path), encoding="utf-8", errors="replace") as f:
            return f.read()

    def op_write(self, path, text):
        write_atomic(note_path(path), text.replace("​", ""))
        return True

    def op_create(self):
        n = 1
        while True:
            p = os.path.join(NOTES, "Untitled.md" if n == 1 else f"Untitled {n}.md")
            if not os.path.exists(p):
                open(p, "a").close()
                return p
            n += 1

    def op_rename(self, path, name):
        src = note_path(path)
        name = re.sub(r"[/\\\x00]", "-", name).strip().removesuffix(".md").strip(". ")
        if not name:
            raise ValueError("empty name")
        dst = os.path.join(NOTES, name + ".md")
        if os.path.exists(dst) and os.path.realpath(dst) != src:
            raise ValueError("A note with that name exists")
        os.rename(src, dst)
        return dst

    def op_remove(self, path):
        p = note_path(path)
        if os.path.exists(p) and os.path.getsize(p) <= 8:     # only ever an empty "Untitled"
            os.remove(p)
        return True

    def op_trash(self, path):
        Gio.File.new_for_path(note_path(path)).trash(None)
        return True

    def op_state(self, **kw):
        d = read_state()
        d.update(kw)
        os.makedirs(STATE_DIR, exist_ok=True)
        write_atomic(STATE, json.dumps(d), mode=0o600)
        return True

    def op_drag(self):
        # the press already happened in the page: start an interactive move from the pointer
        disp = Gdk.Display.get_default()
        seat = disp.get_default_seat()
        ptr = seat.get_pointer()
        _screen, x, y = ptr.get_position()
        self.win.begin_move_drag(1, x, y, Gtk.get_current_event_time() or Gdk.CURRENT_TIME)
        return True

    def op_hide(self):
        subprocess.Popen([os.path.join(os.path.dirname(HERE), "notes"), "hide"], start_new_session=True)
        return True

    def op_openUrl(self, url):
        if re.match(r"^(https?|mailto):", url):
            Gio.AppInfo.launch_default_for_uri(url, None)
        return True

    def op_quit(self):
        GLib.idle_add(self.quit)
        return True

    # ---- window ----
    def on_delete(self, *_):
        # closed (Super+Q): let the page save, then quit (or quit anyway after a moment)
        if self.quitting:
            return False
        self.quitting = True
        if self.ready:
            self.event("flush")
            GLib.timeout_add(1500, lambda: self.quit() or False)
            return True
        return False

    def on_policy(self, _view, decision, kind):
        if kind == WebKit2.PolicyDecisionType.NAVIGATION_ACTION or kind == WebKit2.PolicyDecisionType.NEW_WINDOW_ACTION:
            uri = decision.get_navigation_action().get_request().get_uri()
            if not uri.startswith("file://" + os.path.dirname(WEB)):
                decision.ignore()
                if re.match(r"^(https?|mailto):", uri):
                    Gio.AppInfo.launch_default_for_uri(uri, None)
                return True
        return False

    def on_context_menu(self, _view, menu, _event, _hit):
        # keep editing + spelling items, drop "Reload" / "Back" / "Inspect" unless debugging
        if os.environ.get("NOX_NOTES_DEBUG"):
            return False
        drop = {WebKit2.ContextMenuAction.GO_BACK, WebKit2.ContextMenuAction.GO_FORWARD, WebKit2.ContextMenuAction.STOP,
                WebKit2.ContextMenuAction.RELOAD, WebKit2.ContextMenuAction.INSPECT_ELEMENT}
        for item in list(menu.get_items()):
            if item.get_stock_action() in drop:
                menu.remove(item)
        return False


if __name__ == "__main__":
    GLib.set_prgname(APP_ID)
    sys.exit(Notes().run(sys.argv))
