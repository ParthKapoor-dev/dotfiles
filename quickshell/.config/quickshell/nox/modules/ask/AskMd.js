.pragma library
// Tiny markdown -> blocks for the Circle to Ask card (modules/ask). Handles what the system prompt
// asks Claude for: paragraphs, "-"/"1." lists, fenced code (```diff path:line gets the diff look),
// `inline code`, **bold**, *italic*, [links](url). Headings render as bold paragraphs.
// Works on half-streamed text: an unclosed fence is an open code block, an unclosed ` or ** is
// closed at the end, so tokens never flash as raw markdown.
//
// parse(text) -> [{ t: "p", html } | { t: "li", html, mark } | { t: "code", lang, file, diff, open, lines: [{ g, s }] }]
// opts for inline(): { mono, codeBg, codeFg, linkFg }

function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// inline markdown -> Qt rich text (spans only; the caller wraps the block)
function inline(src, o) {
    let s = String(src);
    // close what the stream left open so a half-arrived token never shows as raw markdown
    if (((s.match(/`/g) || []).length) % 2 === 1) s += "`";
    const parts = s.split(/(`[^`]*`)/);
    const isCode = p => p.length >= 2 && p[0] === "`" && p[p.length - 1] === "`";
    for (let i = parts.length - 1; i >= 0; i--) {
        if (isCode(parts[i])) continue;
        if (((parts[i].match(/\*\*/g) || []).length) % 2 === 1) parts[i] += "**";
        break;
    }
    let out = "";
    for (const part of parts) {
        if (isCode(part)) {
            const code = part.slice(1, -1);
            if (code === "") continue;
            // nbsp padding stands in for the mock's 1px 5px chip padding
            out += "<span style=\"font-family:'" + o.mono + "'; font-size:" + (o.codePx || 11.5) + "px; background-color:" + o.codeBg
                + "; color:" + o.codeFg + "\">&#8201;" + esc(code).replace(/ /g, "&nbsp;") + "&#8201;</span>";
            continue;
        }
        let t = esc(part);
        t = t.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
        t = t.replace(/__([^_]+)__/g, "<b>$1</b>");
        t = t.replace(/(^|[^*\w])\*([^*\s][^*]*?)\*(?!\w)/g, "$1<i>$2</i>");
        t = t.replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, "<span style=\"color:" + o.linkFg + "\">$1</span>");
        out += t;
    }
    return out;
}

// fence info: "diff src/a.tsx:40" | "tsx" | "diff" | "csv stack.csv"
function fenceInfo(info) {
    const words = String(info || "").trim().split(/\s+/).filter(w => w !== "");
    let lang = "", file = "";
    if (words.length) {
        // a lone path-ish word is a file, not a language
        if (words.length === 1 && /[\/.]/.test(words[0]) && !/^[a-z+#-]+$/i.test(words[0])) file = words[0];
        else { lang = words[0].toLowerCase(); file = words.slice(1).join(" "); }
    }
    return { lang, file };
}

function parse(text) {
    const lines = String(text || "").replace(/\r/g, "").split("\n");
    const out = [];
    let para = [];
    let code = null;
    const flush = () => {
        if (para.length) out.push({ t: "p", md: para.join(" ") });
        para = [];
    };
    for (let i = 0; i < lines.length; i++) {
        const raw = lines[i];
        if (code) {
            if (/^\s*```\s*$/.test(raw)) { code.open = false; out.push(code); code = null; continue; }
            code.lines.push(raw);
            continue;
        }
        const fence = raw.match(/^\s*```(.*)$/);
        if (fence) {
            flush();
            const f = fenceInfo(fence[1]);
            code = { t: "code", lang: f.lang, file: f.file, open: true, lines: [] };
            continue;
        }
        if (/^\s*$/.test(raw)) { flush(); continue; }
        const li = raw.match(/^\s*([-*•]|\d+[.)])\s+(.*)$/);
        if (li) { flush(); out.push({ t: "li", mark: /\d/.test(li[1]) ? li[1].replace(")", ".") : "", md: li[2] }); continue; }
        const h = raw.match(/^\s*#{1,6}\s+(.*)$/);
        if (h) { flush(); out.push({ t: "p", md: "**" + h[1].replace(/\*\*/g, "") + "**" }); continue; }
        para.push(raw.trim());
    }
    if (code) out.push(code);        // still streaming: open block
    flush();
    // code lines -> diff gutter
    for (const b of out) {
        if (b.t !== "code") continue;
        const isDiff = b.lang === "diff" || b.lang === "patch"
            || (b.lang === "" && b.lines.length > 0 && b.lines.every(l => /^[-+ ]/.test(l) || l === "") && b.lines.some(l => /^[-+]/.test(l)));
        b.diff = isDiff;
        // a half-arrived last line of an open block may be empty: drop it so no blank row flashes
        let ls = b.lines;
        if (b.open && ls.length && ls[ls.length - 1] === "") ls = ls.slice(0, -1);
        b.lines = ls.filter(l => !/^(---|\+\+\+) /.test(l) && !/^@@/.test(l)).map(l => {
            if (!isDiff) return { g: "", s: l };
            const g = l.charAt(0);
            return (g === "+" || g === "-") ? { g: g, s: l.slice(1) } : { g: "", s: l.charAt(0) === " " ? l.slice(1) : l };
        });
        if (!b.file && b.lang && !isDiff) b.file = b.lang;
    }
    return out;
}

// the code inside the first fenced block (Table -> CSV copies this)
function firstCode(text, lang) {
    const blocks = parse(text);
    for (const b of blocks) if (b.t === "code" && (!lang || b.lang === lang || b.lang === "")) return b.lines.map(l => l.s).join("\n");
    for (const b of blocks) if (b.t === "code") return b.lines.map(l => l.s).join("\n");
    return "";
}

// plain text (for the agent hand-off prompt)
function plain(text) {
    return String(text || "").replace(/```[^\n]*\n?/g, "").replace(/`/g, "").replace(/\*\*/g, "").trim();
}
