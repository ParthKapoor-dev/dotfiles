pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "AskMd.js" as Md

// Circle to Ask, the conversation half (no UI): crop + OCR the selection, ask the Claude Code CLI,
// stream the answer, run the chips. The overlay (AskStage / AskCard) only draws what is here.
//
// Claude: ONE headless `claude -p` per circle, talking stream-json both ways. It is started
// ("pre-warmed") the moment the screen freezes, so the CLI's ~0.7 s boot overlaps the drawing; the
// first message (the crop as an inline image + the question) goes in when the loop closes, and
// follow-ups / chips are more messages on the same stdin (same conversation, no --resume needed).
// Fast + private: --safe-mode (no hooks, plugins, MCP, CLAUDE.md), --setting-sources "" (no
// user/project settings, so no global hooks), --strict-mcp-config, --tools "" (it only looks),
// --no-session-persistence (nothing written under ~/.claude/projects), NOX_ASK=1 in its env (agent
// dashboards ignore it). Nothing from the selection, the OCR text or the answers is ever logged.
// Files: $XDG_RUNTIME_DIR/nox-ask (tmpfs) - frame + crop, deleted on close; only "Send to agent"
// copies the crop to nox-ask/keep (the agent reads it; pruned after a day, tmpfs = gone at logout).
//
// shell.json "ask": { model ("sonnet"), claude (CLI path, default ~/.local/bin/claude),
//   extraArgs ([]), timeout (ms to first token, 45000), systemPrompt (replaces the built-in one),
//   agent (Send to agent: "claude" | "codex" | "gemini" | "opencode" | [command with {prompt} {image}
//   {keep}]), agentDir (where it starts; default ~/code/sandbox/void, "auto" = from the window title) }
Item {
    id: root
    visible: false

    readonly property var opts: Config.opt.ask ?? ({})
    readonly property string model: opts.model ?? "sonnet"
    readonly property string home: Quickshell.env("HOME")
    property string claudeBin: String(opts.claude ?? (home + "/.local/bin/claude")).replace(/^~(?=\/|$)/, home)
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nox-ask"
    readonly property string keepDir: dir + "/keep"
    // "claude-sonnet-5-5" -> "sonnet 5.5"; aliases ("sonnet") stay as they are
    readonly property string modelLabel: String(model).replace(/^claude-/, "").replace(/-(\d+)-(\d+)(-\d{8})?$/, " $1.$2").replace(/-(\d+)(-\d{8})?$/, " $1")
    readonly property string systemPrompt: opts.systemPrompt ?? [
        "You are Circle to Ask on the user's Linux desktop. The user circled part of their screen; the image is that region, cropped. Answer about what is in it.",
        "- Lead with the answer. No preamble, no restating the question, no sign-off.",
        "- Short: 1-4 sentences unless the user asks for more.",
        "- Errors: name the cause, then the fix. Code fixes are a fenced diff whose info string is diff plus the file path and line when visible, e.g. ```diff src/app.ts:40, with every line starting with -, + or a space. Keep diffs minimal.",
        "- Use `inline code` for identifiers, paths and commands, **bold** sparingly. No headings, no tables (CSV in a ```csv block if asked for a table).",
        "- If the image is unreadable or ambiguous, say what you see and ask one short question."
    ].join("\n")

    // ---- the selection ----
    property string app: ""          // "Ghostty"
    property string title: ""        // window title under the loop
    property string crop: ""         // full-resolution crop (png)
    property string b64: ""          // the crop for the API (long edge <= 1568 px)
    property int ocrLines: -1        // -1 = still reading
    property string ocrText: ""
    property bool cropFailed: false

    // ---- conversation ----
    // turns: [{ kind: "answer" | "you" | "label" | "error", text, live }]; the live answer's text is liveText
    property var turns: []
    property string received: ""     // current answer as streamed
    property int shownLen: 0         // how much of it is on screen (smoothed typing)
    readonly property string liveText: received.slice(0, shownLen)
    property bool live: false        // the last turn is streaming
    property bool waiting: false     // asked, no token yet
    property bool done: false        // result event for the current answer
    property string waitText: "Reading the selection"
    readonly property bool busy: waiting || live
    property bool answered: false    // first answer finished (chips show)
    property real tAsk: 0            // loop closed (ms epoch)
    property real firstMs: -1        // loop closed -> first token, first answer
    property var used: ({})          // chip id -> label after use ("" = plain check)
    property string pending: ""      // what to do with the answer when it ends: "csv"
    property string lastQuestion: ""
    property string lastAnswer: ""
    property string agentName: ""

    // claude process state
    property bool ready: false       // process started
    property bool sent: false        // first message went to this process
    property var queue: []
    property string lastErr: ""
    property bool quitting: false

    // clipboard argv (text appended); tests swap it for ["true"] so nothing reaches the live clipboard
    property var clipboard: ["wl-copy", "--"]
    function copy(text) { Quickshell.execDetached(clipboard.concat([text])); }

    signal toast(string text, string glyph)
    signal closeRequested()

    function stamp() { return new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14) + "-" + Math.floor(Math.random() * 1e4); }

    // ---- lifecycle ----
    // boot the CLI now (no message yet): its startup overlaps the drawing
    function prewarm() {
        want = true;
        if (claude.running && !quitting) return;
        if (quitting) return;          // the old one is still exiting: onRunningChanged starts the new one
        ready = false; sent = false; queue = []; lastErr = ""; everStarted = false;
        claude.running = true;
        watchdog.restart();
    }
    // a missing / broken CLI never emits `started`: say so instead of waiting for the timeout
    Timer {
        id: watchdog
        interval: 4000
        onTriggered: if (root.want && !root.ready && !claude.running) root.fail("ENOENT")
    }
    function stopClaude() {
        want = false; ready = false; sent = false; queue = [];
        if (claude.running) { quitting = true; claude.running = false; }
    }
    property bool want: false        // a process should be running (restart after a kill)
    property bool everStarted: false // this process got as far as `started` (else: not found / not executable)
    // a new circle: forget the conversation; a used process is replaced by a fresh pre-warmed one
    function reset() {
        cropper.running = false; ocr.running = false;
        if (sent) stopClaude();
        turns = []; received = ""; shownLen = 0; live = false; waiting = false; done = false;
        answered = false; firstMs = -1; used = ({}); pending = ""; lastQuestion = ""; lastAnswer = "";
        app = ""; title = ""; b64 = ""; ocrLines = -1; ocrText = ""; cropFailed = false;
        if (crop !== "") Quickshell.execDetached(["rm", "-f", "--", crop]);
        crop = "";
    }
    // the overlay closed: stop everything, delete the frame and the crop (keep/ stays)
    function shutdown(frame) {
        reset();
        stopClaude();
        Quickshell.execDetached(["sh", "-c", "rm -f -- \"$1\"; find \"$2\" -maxdepth 1 -type f -name 'crop-*' -delete 2>/dev/null; :", "sh", frame ?? "", dir]);
    }

    // ---- ask: geom = "WxH+X+Y" in frame pixels ----
    function ask(frame, geom, appName, winTitle) {
        reset();
        prewarm();
        app = appName ?? ""; title = winTitle ?? "";
        tAsk = Date.now();
        waiting = true; waitText = "Reading the selection";
        crop = dir + "/crop-" + stamp() + ".png";
        cropper.command = ["sh", "-c",
            "mkdir -p -m 700 \"${3%/*}\" && magick \"$1\" -crop \"$2\" +repage -write \"$3\" -resize '1568x1568>' png:- | base64 -w0",
            "sh", frame, geom, crop];
        cropper.running = true;
    }
    Process {
        id: cropper
        stdout: StdioCollector {
            onStreamFinished: {
                const data = text.trim();
                if (data === "") { root.cropFailed = true; root.fail("Could not read the selection (magick failed)."); return; }
                root.b64 = data;
                ocr.command = ["sh", "-c",
                    "l=$(tesseract --list-langs 2>/dev/null | awk 'NR>1 && $1 != \"osd\" {print $1}' | paste -sd+); exec tesseract \"$1\" stdout ${l:+-l \"$l\"} 2>/dev/null",
                    "sh", root.crop];
                ocr.running = true;
                const ctx = root.app ? "Window: " + root.app + (root.title ? " — " + root.title : "") + "\n" : "";
                root.lastQuestion = "What is this? Help me with it.";
                if (root.turns.some(t => t.kind === "error")) return;   // the CLI already failed: said once
                root.send([
                    { type: "image", source: { type: "base64", media_type: "image/png", data: data } },
                    { type: "text", text: ctx + root.lastQuestion }
                ]);
            }
        }
    }
    Process {
        id: ocr
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.replace(/\f/g, "").replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
                root.ocrText = t;
                root.ocrLines = t === "" ? 0 : t.split("\n").filter(l => l.trim() !== "").length;
            }
        }
    }

    // ---- talking to claude ----
    function send(content) {
        if (!claude.running) {
            // the process is gone (an error stopped it): a new one gets the image again + the last answer
            if (b64 !== "" && !content.some(c => c.type === "image")) {
                const recap = lastAnswer ? "Your earlier answer:\n" + lastAnswer + "\n\n" : "";
                content = [{ type: "image", source: { type: "base64", media_type: "image/png", data: b64 } }]
                    .concat(content.map(c => c.type === "text" ? { type: "text", text: recap + c.text } : c));
            }
            prewarm();
        }
        const msg = JSON.stringify({ type: "user", message: { role: "user", content: content } }) + "\n";
        received = ""; shownLen = 0; done = false; live = false; waiting = true;
        tSent = Date.now();
        sent = true;
        if (ready) claude.write(msg);
        else queue = queue.concat([msg]);
    }
    property real tSent: 0
    function followUp(q, label, action) {
        if (busy || !answered && turns.length === 0) return false;
        const t = String(q).trim();
        if (t === "") return false;
        if (label) turns = turns.concat([{ kind: "label", text: label }]);
        else turns = turns.concat([{ kind: "you", text: t }]);
        pending = action ?? "";
        lastQuestion = t;
        waitText = "Thinking";
        send([{ type: "text", text: t }]);
        return true;
    }

    Process {
        id: claude
        stdinEnabled: true
        // cwd: always exists (nox-ask/ may not yet); nothing is written there (no tools, no session files)
        workingDirectory: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
        environment: ({ NOX_ASK: "1" })
        command: [root.claudeBin, "-p",
            "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--model", root.model, "--system-prompt", root.systemPrompt,
            "--tools", "", "--no-session-persistence",
            "--safe-mode", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands"
        ].concat(root.opts.extraArgs ?? [])
        stdout: SplitParser { onRead: data => root.onLine(data) }
        stderr: StdioCollector { id: claudeErr }
        onStarted: {
            root.ready = true;
            root.everStarted = true;
            const q = root.queue;
            root.queue = [];
            for (const m of q) claude.write(m);
        }
        onRunningChanged: {
            if (running) return;
            root.ready = false;
            if (root.quitting) {
                root.quitting = false;
                // killed on purpose; a new circle may already want a fresh one
                if (root.want) { root.lastErr = ""; Qt.callLater(() => { if (root.want && !claude.running) { claude.running = true; watchdog.restart(); } }); }
                return;
            }
            // died while we wait on it: say why (stderr is the CLI's own message, never the answer)
            if (root.busy) {
                const why = (claudeErr.text || root.lastErr || "").trim().split("\n").pop();
                root.fail(!root.everStarted ? "ENOENT" : why === "" ? "Claude Code exited unexpectedly." : why);
            }
        }
    }

    function onLine(line) {
        let e;
        try { e = JSON.parse(line); } catch (err) { return; }
        if (e.type === "stream_event") {
            const ev = e.event;
            if (ev && ev.type === "content_block_delta" && ev.delta && ev.delta.type === "text_delta") gotText(ev.delta.text ?? "");
        } else if (e.type === "system" && e.subtype === "api_retry") {
            if (!waiting) return;
            const st = e.error_status;
            if (st === null || st === undefined) {
                if ((e.attempt ?? 0) >= 2) fail("offline");
                else waitText = "Connecting";
            } else if (st === 429 || st === 529 || st >= 500) {
                waitText = "Claude is busy · retry " + e.attempt + "/" + e.max_retries;
            } else if (st === 401 || st === 403) {
                fail("auth");
            }
        } else if (e.type === "assistant") {
            if (e.error) lastErr = String(e.error);
        } else if (e.type === "result") {
            if (e.is_error) { fail(String(e.result ?? lastErr ?? "error")); return; }
            if (received === "" && typeof e.result === "string" && e.result !== "") gotText(e.result);
            done = true;
            if (!live) finish();
        }
    }
    function gotText(t) {
        if (t === "") return;
        if (waiting) {
            waiting = false; live = true;
            if (firstMs < 0) firstMs = Date.now() - tAsk;
            turns = turns.concat([{ kind: "answer", text: "", live: true }]);
        }
        received += t;
    }
    // smooth typing: the on-screen text eases toward what has arrived (chunks come in bursts)
    Timer {
        interval: 16
        repeat: true
        running: root.live
        onTriggered: {
            const left = root.received.length - root.shownLen;
            if (left > 0) root.shownLen += Math.max(1, Math.ceil(left / 7));
            else if (root.done) root.finish();
        }
    }
    function finish() {
        const text = received;
        live = false; waiting = false;
        const t = turns.slice();
        if (t.length && t[t.length - 1].live) t[t.length - 1] = { kind: "answer", text: text, live: false };
        turns = t;
        lastAnswer = text;
        answered = true;
        if (pending === "csv") {
            const csv = Md.firstCode(text, "csv");
            if (csv !== "") { copy(csv); toast("CSV copied", "check"); }
        }
        pending = "";
    }
    function fail(why) {
        const w = String(why);
        const msg = w === "offline" ? "Can't reach Claude. Check your connection and try again."
            : w === "timeout" ? "No answer after " + Math.round((opts.timeout ?? 45000) / 1000) + " s. Try again, or circle less."
            : w === "auth" || /not logged in|authenticat|\/login|401|oauth/i.test(w) ? "Claude Code isn't logged in. Run `claude` in a terminal, use `/login`, then circle again."
            : /ENOENT|not found|No such file/i.test(w) ? "Claude Code CLI not found at `" + claudeBin + "`. Set `ask.claude` in shell.json."
            : w;
        const t = turns.slice();
        if (!busy && t.length && t[t.length - 1].kind === "error") { stopClaude(); return; }   // already said
        if (t.length && t[t.length - 1].live) t[t.length - 1] = { kind: "answer", text: received, live: false };
        t.push({ kind: "error", text: msg });
        turns = t;
        live = false; waiting = false; pending = "";
        answered = answered || received !== "";
        stopClaude();
    }
    Timer {
        interval: root.opts.timeout ?? 45000
        running: root.waiting
        onTriggered: root.fail("timeout")
    }

    // ---- chips ----
    function englishish(t) {
        const w = (String(t).toLowerCase().match(/[a-z]+/g) || []);
        const common = ["the", "is", "of", "and", "to", "in", "a", "for", "on", "with", "that", "this", "it", "are", "not", "you", "be", "at", "by", "from", "or", "as", "an", "can", "cannot", "read", "error", "if", "was", "your", "we", "i"];
        return w.filter(x => common.indexOf(x) !== -1).length >= 2;
    }
    function mark(id, label) { const u = Object.assign({}, used); u[id] = label ?? ""; used = u; }
    function unmark(id) { const u = Object.assign({}, used); delete u[id]; used = u; }
    function chip(id) {
        if (busy && id !== "copy" && id !== "lens") return;
        switch (id) {
        case "copy":
            if (ocrLines < 0) { toast("Still reading the text", "clip"); return; }
            if (ocrText === "") { toast("No text in the selection", "x"); return; }
            copy(ocrText);
            toast("Copied text · " + ocrLines + (ocrLines === 1 ? " line" : " lines"), "check");
            mark("copy", "Copied");
            copyReset.restart();
            return;
        case "more":
            if (used.more !== undefined) return;
            mark("more");
            followUp("Explain that in more depth: what is going on and why. Still concise, under 120 words.", "More detail");
            return;
        case "tr": {
            // foreign text on screen -> English; English already -> your answer in Hindi (as in the mock)
            if (used.tr !== undefined) return;
            mark("tr");
            const en = ocrLines < 0 || ocrLines > 0 && englishish(ocrText);
            followUp(en ? "Translate your first answer into Hindi (Devanagari). Keep code, identifiers, paths and numbers unchanged in `inline code`. Reply with only the translation."
                        : "Translate the text in the image into English. Keep code, identifiers and numbers unchanged. Reply with only the translation.",
                     en ? "Translated · English → हिन्दी" : "Translated · → English");
            return;
        }
        case "csv":
            if (used.csv !== undefined) return;
            mark("csv");
            followUp("Extract the table in the image as CSV: reply with one ```csv block (put a short file name after csv on the fence line, e.g. ```csv prices.csv) and nothing else. If there is no table, start with one short line saying so, then turn the most structured part into CSV.", "Table → CSV", "csv");
            return;
        case "send":
            if (used.send !== undefined || crop === "") return;
            sendToAgent();
            return;
        case "lens":
            if (crop === "") return;
            lens();
            return;
        }
    }
    Timer { id: copyReset; interval: 1600; onTriggered: root.unmark("copy") }

    // Send to agent: the configured agent (ask.agent: claude by default, codex, gemini, opencode or a
    // command) in a new terminal, in ask.agentDir (~/code/sandbox/void; "auto" = a path in the window
    // title, else ~). The crop is copied to keep/ so it outlives the overlay; the prompt goes through
    // a file, so no terminal ever re-parses it. `nox ask agent` starts it with a clean env.
    function sendToAgent() {
        const kept = keepDir + "/" + crop.replace(/^.*\//, "").replace(/^crop-/, "ask-");
        const auto = String(opts.agentDir ?? "") === "auto";
        const m = auto ? (title || "").match(/(~\/[^\s—–|:"']*|\/(?:home|tmp|srv|opt|mnt|var|etc|usr)\/[^\s—–|:"']*|~(?=\s|$))/) : null;
        const guess = m ? m[1].replace(/\/+$/, "") : "";
        const fallback = auto ? home : String(opts.agentDir ?? "~/code/sandbox/void").replace(/^~(?=\/|$)/, home);
        const ctx = app ? " (" + app + (title ? " — " + title : "") + ")" : "";
        const prompt = "I circled this on my screen" + ctx + ": " + kept + "\n\n"
            + (lastQuestion && !/^Explain that|^Translate the|^Extract the table/.test(lastQuestion) ? lastQuestion : "What is this? Help me with it.")
            + (lastAnswer ? "\n\nA quick look (Circle to Ask) said:\n" + Md.plain(lastAnswer) : "");
        resolver.kept = kept;
        resolver.command = ["sh", "-c",
            "mkdir -p \"$1\" && chmod 700 \"$1\" && cp -f -- \"$2\" \"$3\" || exit 1\n"
            + "umask 077; printf '%s' \"$6\" > \"$3.prompt\" || exit 1\n"
            + "d=$4; case \"$d\" in '~') d=$HOME ;; '~/'*) d=$HOME/${d#\\~/} ;; esac\n"
            + "[ -n \"$d\" ] && [ -d \"$d\" ] || d=$5\n[ -d \"$d\" ] || d=$HOME\nprintf '%s' \"$d\"",
            "sh", keepDir, crop, kept, guess, fallback, prompt];
        resolver.running = true;
    }
    Process {
        id: resolver
        property string kept: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const d = text.trim();
                if (d === "") { root.toast("Couldn't hand off to the agent", "x"); return; }
                const term = Config.opt.terminal ?? ["ghostty"];
                const ghostty = /ghostty/.test(String(term[0]));
                Quickshell.execDetached({
                    command: term.concat(ghostty ? ["--working-directory=" + d] : [])
                        .concat(["-e", root.home + "/.local/bin/nox", "ask", "agent", d, resolver.kept + ".prompt", resolver.kept]),
                    workingDirectory: d
                });
                const name = d === root.home ? "~" : d.replace(/^.*\//, "");
                const who = typeof root.opts.agent === "string" ? root.opts.agent : (Array.isArray(root.opts.agent) ? String(root.opts.agent[0]).replace(/^.*\//, "") : "claude");
                root.agentName = name;
                root.mark("send", "Sent to " + name);
                root.toast("Sent to " + who.charAt(0).toUpperCase() + who.slice(1) + " · " + name, "sparkle");
                closeSoon.restart();
            }
        }
    }
    // the new terminal opens under the overlay: get out of its way once the check has shown
    Timer { id: closeSoon; interval: 700; onTriggered: root.closeRequested() }

    // Lens: the old Super+Shift+A, unchanged (`nox ask lens` = hypr scripts/snip_to_search.sh). It
    // selects with slurp itself, so the overlay gets out of the way first; the crop is not passed on.
    function lens() {
        mark("lens", "Opening Lens");
        toast("Google Lens: select the region again", "search");
        closeRequested();
        lensLater.restart();
    }
    Timer { id: lensLater; interval: 650; onTriggered: Quickshell.execDetached(["nox", "ask", "lens"]) }
}
