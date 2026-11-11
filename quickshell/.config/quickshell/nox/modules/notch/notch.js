.pragma library
// Pure helpers for the agent notch: request summaries, risk tags, command highlighting and the
// rule "Always" will add (kept in step with always_rule() in ~/.local/lib/nox/agents).

function esc(s) {
    return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// what the request is about, in one line
function target(req) {
    const i = req?.input ?? {};
    return String(i.command ?? i.file_path ?? i.notebook_path ?? i.url ?? i.pattern ?? i.query ?? i.prompt ?? i.skill ?? "");
}

function verb(req) {
    const t = req?.tool ?? "";
    if (t === "Bash") return "Wants to run";
    if (/^(Edit|MultiEdit|NotebookEdit)$/.test(t)) return "Wants to edit";
    if (t === "Write") return "Wants to write";
    if (t === "Read") return "Wants to read";
    if (/^Web(Fetch|Search)$/.test(t)) return "Wants to open";
    if (req?.mcp) return "Wants to use " + req.mcp;
    return "Wants to use";
}

// short warning tags for commands that are hard to take back
function risks(req) {
    const c = String(req?.input?.command ?? "");
    const out = [];
    if (!c) {
        const p = String(req?.input?.file_path ?? "");
        if (/(^|\/)\.env|secret|credential|id_rsa|\.pem$/i.test(p)) out.push("sensitive file");
        return out;
    }
    if (/\brm\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r)\b|\brm\s+-r\b/i.test(c)) out.push("deletes recursively");
    else if (/\brm\b/.test(c)) out.push("deletes files");
    if (/\b(drop|truncate)\s+(table|database|schema)\b|\bdelete\s+from\b/i.test(c)) out.push("drops data");
    if (/\bgit\s+push\b.*(--force|-f\b)|\bgit\s+reset\s+--hard\b|\bgit\s+clean\s+-[a-z]*f/i.test(c)) out.push("rewrites git");
    else if (/\bgit\s+push\b/.test(c)) out.push("pushes");
    if (/\bsudo\b|\bdoas\b/.test(c)) out.push("root");
    if (/(curl|wget)[^|]*\|\s*(ba|z)?sh\b/.test(c)) out.push("runs a download");
    if (/\bchmod\s+(-R\s+)?7[0-7]7\b|\bchown\s+-R\b/.test(c)) out.push("permissions");
    if (/\b(kubectl|terraform|helm)\b.*\b(apply|delete|destroy)\b/.test(c)) out.push("infra change");
    if (/\b(npm|pnpm|yarn|cargo)\s+publish\b|\bgh\s+release\b/.test(c)) out.push("publishes");
    return out;
}

// a command line as rich text: program in accent, flags teal, strings green
function highlight(cmd, accent) {
    const s = String(cmd ?? "");
    const toks = s.match(/"(?:[^"\\]|\\.)*"|'[^']*'|\s+|[^\s"']+/g) ?? [];
    let first = true, out = "";
    for (const t of toks) {
        if (/^\s+$/.test(t)) { out += t.replace(/\n/g, "<br>").replace(/ /g, "&nbsp;"); continue; }
        if (/^["']/.test(t)) out += "<span style='color:#B7D8A8'>" + esc(t) + "</span>";
        else if (/^--?[A-Za-z]/.test(t)) out += "<span style='color:#64D2FF'>" + esc(t) + "</span>";
        else if (/^(\||&&|\|\||;|>|>>|<)$/.test(t)) { out += "<span style='color:#8A837E'>" + esc(t) + "</span>"; first = true; continue; }
        else if (first && !/=/.test(t)) out += "<span style='color:" + accent + "'>" + esc(t) + "</span>";
        else out += esc(t);
        if (!/=/.test(t)) first = false;
    }
    return out;
}

const TWO_WORD = ["git", "npm", "pnpm", "yarn", "bun", "npx", "cargo", "go", "docker", "podman", "kubectl", "gh",
    "uv", "pip", "python", "python3", "make", "just", "systemctl", "pacman", "yay", "paru", "nox", "orca"];
const BLANKET = ["Edit", "Write", "MultiEdit", "NotebookEdit", "Read", "Glob", "Grep", "WebSearch"];

// the rule "Always" will add, as Claude Code writes it ("" = Always allows once only)
function rule(req) {
    for (const sg of req?.suggestions ?? []) {
        if (sg.type === "addRules" && (sg.behavior ?? "allow") === "allow" && (sg.rules ?? []).length) {
            const r = sg.rules[0];
            return r.toolName + (r.ruleContent ? "(" + r.ruleContent + ")" : "");
        }
    }
    const t = req?.tool ?? "", i = req?.input ?? {};
    if (t === "Bash") {
        let w = String(i.command ?? "").trim().split(/\s+/).filter(x => x && (x.indexOf("=") < 0 || /^[-\/]/.test(x))).slice(0, 2);
        if (!w.length) return "";
        const pre = (TWO_WORD.indexOf(w[0]) >= 0 && w.length > 1 && w[1][0] !== "-") ? w.slice(0, 2) : w.slice(0, 1);
        return "Bash(" + pre.join(" ") + " *)";
    }
    if (t === "WebFetch" && i.url) {
        const m = String(i.url).match(/^[a-z]+:\/\/([^\/:?#]+)/i);
        return m ? "WebFetch(domain:" + m[1] + ")" : "";
    }
    if (req?.mcp || BLANKET.indexOf(t) >= 0) return t;
    return "";
}

// a few lines of what an Edit / Write would change
function diffLines(req, max) {
    const i = req?.input ?? {};
    const out = [];
    const cut = s => String(s).length > 140 ? String(s).slice(0, 139) + "…" : String(s);
    if (req?.tool === "Write" && i.content !== undefined) {
        for (const l of String(i.content).split("\n").slice(0, max)) out.push({ k: "+", t: cut(l) });
    } else if (i.old_string !== undefined || i.new_string !== undefined) {
        const o = String(i.old_string ?? "").split("\n"), n = String(i.new_string ?? "").split("\n");
        for (const l of o.slice(0, Math.ceil(max / 2))) out.push({ k: "-", t: cut(l) });
        for (const l of n.slice(0, max - Math.min(o.length, Math.ceil(max / 2)))) out.push({ k: "+", t: cut(l) });
    } else if (Array.isArray(i.edits)) {
        for (const e of i.edits.slice(0, 2)) {
            out.push({ k: "-", t: cut(String(e.old_string ?? "").split("\n")[0]) });
            out.push({ k: "+", t: cut(String(e.new_string ?? "").split("\n")[0]) });
        }
    }
    return out.slice(0, max);
}

function rel(path, base) {
    path = String(path ?? "");
    base = String(base ?? "");
    return base && path.indexOf(base + "/") === 0 ? path.slice(base.length + 1) : path.replace(/^\/home\/[^\/]+/, "~");
}

function clock(ms) {
    const d = new Date(ms);
    const p = n => (n < 10 ? "0" : "") + n;
    return p(d.getHours()) + ":" + p(d.getMinutes());
}
