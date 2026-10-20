pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

// Voice typing (mock C2 #voice): hold Super+Shift+Space (or `nox voice toggle`), speak, release;
// whisper.cpp transcribes on the GPU (nox voice transcribe -> whisper-server, kept warm only
// while in use), optional tidy, then the text is pasted into the focused window the same way the
// launcher's pins/emoji paste (clipboard + Ctrl+V / Ctrl+Shift+V in terminals, Pins.sendPaste).
// The clipboard is put back afterwards. Audio lives in $XDG_RUNTIME_DIR/nox-voice only until it
// is transcribed; transcripts are never written anywhere (the last one stays in memory: copyLast).
// shell.json voice.{enabled, language, prompt, model, tidy, smartTidy, source, maxSeconds,
// restoreClipboard, offset}; the runtime tidy toggle is kept in ~/.local/state/nox/voice.json.
Singleton {
    id: root
    readonly property var opts: Config.opt.voice ?? ({})

    // idle | rec | tx (transcribing) | tidy (smart tidy) | done | error
    property string phase: "idle"
    property string mode: "hold"          // hold (key) | toggle (nox voice toggle)
    property real level: 0                // smoothed 0..1, drives the waveform
    property var hist: []                 // last 40 levels, pushed every 42 ms (mock)
    property real startedAt: 0
    property int elapsed: 0               // ms while recording
    property bool micLive: false
    property real recSeconds: 0
    property string backend: ""           // gpu | cpu | gpu-cli | cpu-cli
    property int words: 0
    property var removed: []              // fillers tidy took out (for the pill preview)
    property string message: ""           // error / no-speech line
    property string detail: ""
    property string lastText: ""
    property string file: ""
    property bool smartFailed: false

    readonly property bool tidy: state.data.tidy ?? opts.tidy ?? true
    readonly property bool smartTidy: opts.smartTidy ?? false
    readonly property bool busy: phase === "tx" || phase === "tidy"
    readonly property string sourceLabel: {
        const n = String(opts.source || (Audio.source?.name ?? "")).toLowerCase();
        return n.startsWith("bluez") ? "BT" : n.indexOf("usb") !== -1 ? "USB" : "MIC";
    }

    function setTidy(on) { state.data = Object.assign({}, state.data, { tidy: !!on }); state.save(); }

    // ---- hold key (GlobalShortcut voiceHold: press + release; voiceRelease: Space came up) ----
    function press() {
        if (phase === "rec") { stop(); return; }    // second press = stop (a missed release too)
        start("hold");
    }
    function release() {
        if (phase !== "rec" || mode !== "hold") return;
        if (Date.now() - startedAt < 300) cancel(); else stop();
    }
    function toggle() { if (phase === "rec") stop(); else start("toggle"); }

    function start(m) {
        if (phase === "rec" || busy) return;
        if (opts.enabled === false) return;
        mode = m ?? "toggle";
        hist = []; level = 0; elapsed = 0; micLive = false; removed = []; message = ""; detail = ""; smartFailed = false;
        const dir = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nox-voice";
        file = dir + "/rec-" + Date.now() + ".wav";
        const cmd = ["nox", "voice", "rec", file, "--max", String((opts.maxSeconds ?? 120) + 2)];
        if (opts.source) cmd.push("--target", String(opts.source));
        rec.command = cmd;
        rec.peak = -120; rec.secs = 0; rec.err = "";
        rec.running = true;
        // load the model while the user talks (no-op when the server is up)
        Quickshell.execDetached(["nox", "voice", "warm"]);
        startedAt = Date.now();
        phase = "rec";
    }
    function stop() {
        if (phase !== "rec") return;
        phase = "tx";
        recSeconds = (Date.now() - startedAt) / 1000;
        if (rec.running) rec.signal(15); else rec.finished();
    }
    function cancel() {
        const was = phase;
        phase = "idle";
        if (rec.running) { rec.discard = true; rec.signal(15); }
        if (tx.running) tx.signal(15);
        if (smart.running) smart.signal(15);
        if (was === "rec" || was === "tx") removeFile();
    }
    function removeFile() { if (file) Quickshell.execDetached(["rm", "-f", "--", file]); file = ""; }
    function fail(msg, det) { message = msg; detail = det ?? ""; phase = "error"; hideTimer.interval = 2600; hideTimer.restart(); }

    // ---- recording: nox voice rec (pw-record 16 kHz mono -> wav; levels on stdout) ----
    Process {
        id: rec
        property real peak: -120
        property real secs: 0
        property string err: ""
        property bool discard: false
        function finished() {
            const d = discard; discard = false;
            if (d || root.phase !== "tx") { root.removeFile(); return; }
            if (err && secs <= 0) { root.removeFile(); root.fail("Mic unavailable", err); return; }
            if (secs < 0.3 || peak < (root.opts.silenceDb ?? -50)) { root.removeFile(); root.fail("No speech", secs < 0.3 ? "too short" : "silence"); return; }
            tx.command = ["nox", "voice", "transcribe", root.file];
            tx.arm();
        }
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("L ")) {
                    const v = Number(line.slice(2));
                    root.level += (v - root.level) * 0.5;
                } else if (line === "READY") root.micLive = true;
                else if (line === "MAX") root.stop();
                else if (line.startsWith("END ")) { const p = line.split(" "); rec.secs = Number(p[1]); rec.peak = Number(p[2]); }
                else if (line.startsWith("ERR ")) rec.err = line.slice(4);
            }
        }
        onExited: (code, status) => {
            if (root.phase === "rec") { root.phase = "tx"; root.recSeconds = (Date.now() - root.startedAt) / 1000; }
            finished();
        }
    }
    // waveform history + timer (mock: push every 42 ms, keep 80)
    Timer {
        interval: 42; repeat: true; running: root.phase === "rec"
        onTriggered: {
            const h = root.hist.slice(-39);
            h.push(root.micLive ? root.level : 0.02);
            root.hist = h;
            root.elapsed = Date.now() - root.startedAt;
            if (root.elapsed > (root.opts.maxSeconds ?? 120) * 1000) root.stop();   // stuck-key guard
        }
    }

    // ---- transcription ----
    // (exit and end-of-stdout can arrive in either order: act once both are in)
    Process {
        id: tx
        property string buf: ""
        property int waits: 0
        function arm() { buf = ""; waits = 2; running = true; }
        function step() { if (--waits === 0) done(); }
        stdout: StdioCollector { onStreamFinished: { tx.buf = text; tx.step(); } }
        onExited: (code, status) => { root.file = ""; step(); }    // transcribe deleted the wav
        function done() {
            if (root.phase !== "tx") return;
            let r = null;
            try { r = JSON.parse(tx.buf); } catch (e) { r = null; }
            tx.buf = "";
            if (!r) { root.fail("Transcription failed", "nox voice doctor"); return; }
            root.backend = r.backend ?? "";
            root.process(r.text ?? "");
        }
    }

    // whisper's non-speech tags and blank-audio hallucinations
    function clean(s) {
        s = String(s).replace(/\[(BLANK_AUDIO|MUSIC|NOISE|SILENCE|INAUDIBLE|Music|Silence|Applause|Laughter)[^\]]*\]|\((silence|music|inaudible|blank audio)[^)]*\)/gi, " ");
        return s.replace(/\s+/g, " ").trim();
    }
    // rule-based tidy: fillers (anywhere), "you know" / "I mean" / "so yeah" at sentence edges,
    // repeated words. Returns { text, removed }. Latin script only; other scripts pass through.
    function ruleTidy(s) {
        const removed = [];
        const cut = m => { removed.push(m.replace(/[,.…\s]+$/, "").trim().toLowerCase()); return ""; };
        const F = "u+m+|u+h+m*|e+r+m+|e+r{2,}|h+m{2,}|m{2,}";
        // ", uh," between words: both commas were only there for the filler
        s = s.replace(new RegExp(",\\s*(" + F + "),(?=\\s)", "gi"), (m, w) => { cut(w); return ""; });
        // a whole "So yeah." / "You know." sentence
        s = s.replace(/(^|[.!?])\s*(so yeah|you know|i mean)[.!?](?=\s|$)/gi, (m, pre, w) => { cut(w); return pre; });
        // standalone fillers + their comma: "um,", "uh", "erm", "hmm"
        s = s.replace(/(^|[\s,.;:!?…-])(u+m+|u+h+m*|e+r+m+|e+r{2,}|h+m{2,}|m{2,})(?=[\s,.;:!?…]|$)[,…]?/gi, (m, pre, w) => { cut(w); return pre; });
        // sentence-initial / final hedges
        s = s.replace(/(^|[.!?]\s+)(you know|i mean|so yeah|like),?\s+/gi, (m, pre, w) => { cut(w); return pre; });
        s = s.replace(/,?\s+(you know|i mean|so yeah|or something like that)(?=[.!?]|$)/gi, (m, w) => { cut(w); return ""; });
        // stutters: "the the" / "I, I" (not "had had", "that that")
        s = s.replace(/\b([A-Za-z']+)(?:,?\s+\1\b)+/gi, (m, w) => { if (/^(had|that)$/i.test(w)) return m; cut(w); return w; });
        // punctuation / spacing / capitals left behind
        s = s.replace(/\s+([,.;:!?])/g, "$1").replace(/([,;:])(?:\s*[,;:])+/g, "$1").replace(/,\s*([.!?])/g, "$1")
             .replace(/^[\s,;:.]+/, "").replace(/\s{2,}/g, " ").trim();
        s = s.replace(/(^|[.!?]\s+)([a-z])/g, (m, pre, c) => pre + c.toUpperCase());
        return { text: s, removed };
    }

    function process(raw) {
        let text = clean(raw);
        if (!text || /^[.\s…-]*$/.test(text)) { fail("No speech", "nothing recognised"); return; }
        if (tidy) { const t = ruleTidy(text); text = t.text; removed = t.removed; }
        if (!text) { fail("No speech", "only fillers"); return; }
        if (tidy && smartTidy) {
            phase = "tidy";
            smart.input = text;
            smart.arm();
            return;
        }
        insert(text);
    }
    Process {
        id: smart
        property string input: ""
        property string buf: ""
        command: ["nox", "voice", "smart-tidy"]
        property int waits: 0
        property int code: 0
        function arm() { buf = ""; waits = 2; stdinEnabled = true; running = true; }
        function step() { if (--waits === 0) done(); }
        stdout: StdioCollector { onStreamFinished: { smart.buf = text; smart.step(); } }
        onStarted: { write(input); stdinEnabled = false; }
        onExited: (code, status) => { smart.code = code; step(); }
        function done() {
            if (root.phase !== "tidy") return;
            const out = smart.buf.trim();
            root.smartFailed = code !== 0 || !out;
            root.insert(out || smart.input);
            smart.input = ""; smart.buf = "";
        }
    }

    // ---- insertion: clipboard + paste shortcut into the focused window, then restore ----
    function insert(text) {
        lastText = text;
        words = text.split(/\s+/).filter(w => w.length > 0).length;
        const t = Hyprland.activeToplevel;
        const cls = t?.lastIpcObject?.class ?? t?.wayland?.appId ?? "";
        paste.addr = t?.address ?? "";
        paste.term = Pins.terminals.test(cls);
        paste.text = text;
        paste.target = !!(paste.addr || t);
        copy.pasteAfter = true;
        // no focused window: the text just stays on the clipboard (nothing to save / restore)
        if (paste.target && opts.restoreClipboard !== false) clipSave.running = true; else copy.go();
    }
    Process {
        id: clipSave
        command: ["nox", "voice", "clip-save"]
        onExited: copy.go()
    }
    QtObject {
        id: paste
        property string addr: ""
        property bool term: false
        property bool target: false
        property string text: ""
    }
    Process {
        id: copy
        // --sensitive: cliphist skips it (the transcript stays out of clipboard history)
        command: ["wl-copy", "--sensitive", "--type", "text/plain;charset=utf-8"]
        property bool pasteAfter: true
        function go() { stdinEnabled = true; running = true; }
        onStarted: { write(paste.text); stdinEnabled = false; }
        // wl-copy returns once it owns the selection (then serves it from a background fork)
        onExited: (code, status) => {
            if (!copy.pasteAfter) { paste.text = ""; Panels.hud("Copied last dictation", "clip"); return; }
            if (code !== 0) { root.fail("Paste failed", "wl-copy"); return; }
            const target = paste.target;
            if (target) Pins.sendPaste(paste.addr, paste.term);
            root.phase = "done";
            hideTimer.interval = root.removed.length ? 2300 : 1700;
            hideTimer.restart();
            if (target && root.opts.restoreClipboard !== false) restoreTimer.restart();
        }
    }
    Timer { id: restoreTimer; interval: root.opts.restoreDelay ?? 900; onTriggered: { clipRestore.stdinEnabled = true; clipRestore.running = true; } }
    Process {
        id: clipRestore
        command: ["nox", "voice", "clip-restore"]
        onStarted: { write(paste.text); stdinEnabled = false; paste.text = ""; }
    }
    // nox voice last: the previous transcript back on the clipboard (if a paste landed nowhere)
    function copyLast() { if (!lastText || copy.running || busy) return; paste.text = lastText; copy.pasteAfter = false; copy.go(); }

    Timer { id: hideTimer; interval: 1700; onTriggered: if (root.phase === "done" || root.phase === "error") root.phase = "idle" }

    function status() {
        return "phase=" + phase + " mode=" + mode + " tidy=" + tidy + " smartTidy=" + smartTidy + " source=" + sourceLabel
            + (backend ? " backend=" + backend : "");
    }

    JsonState { id: state; path: Paths.state("voice") }
}
