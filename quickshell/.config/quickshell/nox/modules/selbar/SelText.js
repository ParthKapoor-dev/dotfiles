.pragma library
// Selection bar text helpers (modules/selbar): what the selected text is (a link, maths) and the
// case cycle. Pure functions, no state; nothing here logs or keeps the text.
// Unit-tested with synthetic strings in the offscreen harness.

// ---- links ----
// "https://…" / "www.…" / "localhost:3000" / an IP / "name.tld[/path]" with a common TLD -> URL,
// else "" (the launcher's web provider rule, plus surrounding <> / quotes / a trailing full stop)
var tlds = ["com", "org", "net", "io", "dev", "app", "ai", "co", "me", "gg", "sh", "xyz", "info", "edu", "gov",
    "uk", "de", "in", "us", "ca", "fr", "jp", "nl", "eu", "ch", "au", "se", "no", "fi", "es", "it", "pl", "ru", "br", "tv",
    "fm", "so", "to", "ly", "is", "page", "site", "blog", "wiki", "news", "tech", "cloud", "run", "build", "zone", "social"];
function urlOf(text) {
    var t = String(text || "").trim().replace(/^[<("'“]+|[>)"'”]+$/g, "").replace(/[.,;:!?]+$/, "");
    if (!t || t.length > 4000 || /\s/.test(t)) return "";
    if (/^(https?|ftp|file):\/\/\S+$/i.test(t)) return t;
    if (/^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)(\/\S*)?$/i.test(t)) return "http://" + t;
    var m = t.match(/^(?:www\.)?(?:[a-z0-9-]+\.)+([a-z]{2,})(:\d+)?([\/?#]\S*)?$/i);
    return m && (tlds.indexOf(m[1].toLowerCase()) !== -1 || /^www\./i.test(t)) ? "https://" + t : "";
}
function hostOf(url) {
    var m = /^[a-z]+:\/\/([^/?#]+)/i.exec(String(url));
    return m ? m[1].replace(/^www\./, "") : "";
}

// ---- maths ----
// A small expression parser (no eval): + - * / ^ % ( ), × ÷ · −, implicit nothing, unary minus,
// "x% of y", constants pi / e, functions sqrt abs round floor ceil ln log sin cos tan, and the
// postfix "!" for factorials. Thousands separators ("1,234.5") and "_" are accepted. Returns the
// number, or NaN when the text is not maths. A lone number, a date ("2026-10-26") or a version
// ("1.2.3") is not maths.
var fns = {
    sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
    ln: Math.log, log: function (x) { return Math.log(x) / Math.LN10; },
    sin: Math.sin, cos: Math.cos, tan: Math.tan
};
function tokenize(s) {
    var out = [], i = 0, m;
    while (i < s.length) {
        var c = s[i];
        if (c === " " || c === "\t") { i++; continue; }
        if ((m = /^(\d{1,3}(?:,\d{3})+|\d[\d_]*)(\.\d+)?(e[+-]?\d+)?|^\.\d+/i.exec(s.slice(i)))) {
            out.push({ t: "n", v: parseFloat(m[0].replace(/[,_]/g, "")) });
            i += m[0].length;
            continue;
        }
        if ((m = /^[a-z]+/i.exec(s.slice(i)))) {
            var w = m[0].toLowerCase();
            if (w === "pi") out.push({ t: "n", v: Math.PI });
            else if (w === "e") out.push({ t: "n", v: Math.E });
            else if (w === "of") out.push({ t: "of" });
            else if (w === "x") out.push({ t: "op", v: "*" });
            else if (fns[w]) out.push({ t: "fn", v: w });
            else return null;
            i += m[0].length;
            continue;
        }
        if ("+-*/^%()!".indexOf(c) !== -1) { out.push({ t: c === "(" || c === ")" ? c : "op", v: c }); i++; continue; }
        if (c === "×" || c === "·") { out.push({ t: "op", v: "*" }); i++; continue; }
        if (c === "÷") { out.push({ t: "op", v: "/" }); i++; continue; }
        if (c === "−") { out.push({ t: "op", v: "-" }); i++; continue; }
        return null;
    }
    return out;
}
// expr := term (('+'|'-') term)* ; term := unary (('*'|'/') unary)* ; unary := '-' unary | pow
// pow := post ('^' unary)? ; post := atom ('!' | '%' ['of' unary])* ; atom := n | fn atom | '(' expr ')'
function parse(toks) {
    var p = 0;
    function peek() { return toks[p]; }
    function isOp(v) { var k = toks[p]; return k && k.t === "op" && k.v === v; }
    function expr() {
        var v = term();
        while (isOp("+") || isOp("-")) { var o = toks[p++].v, r = term(); v = o === "+" ? v + r : v - r; }
        return v;
    }
    function term() {
        var v = unary();
        while (isOp("*") || isOp("/")) { var o = toks[p++].v, r = unary(); v = o === "*" ? v * r : v / r; }
        return v;
    }
    function unary() {
        if (isOp("-")) { p++; return -unary(); }
        if (isOp("+")) { p++; return unary(); }
        return pow();
    }
    function pow() {
        var b = post();
        if (isOp("^")) { p++; return Math.pow(b, unary()); }
        return b;
    }
    function post() {
        var v = atom();
        for (;;) {
            if (isOp("!")) {
                p++;
                if (v < 0 || v > 170 || v !== Math.floor(v)) throw "bad";
                var f = 1; for (var i = 2; i <= v; i++) f *= i;
                v = f;
            } else if (isOp("%")) {
                p++;
                if (peek() && peek().t === "of") { p++; v = v / 100 * unary(); }
                else v = v / 100;
            } else return v;
        }
    }
    function atom() {
        var k = toks[p++];
        if (!k) throw "end";
        if (k.t === "n") return k.v;
        if (k.t === "fn") return fns[k.v](atom());
        if (k.t === "(") { var v = expr(); if (!toks[p] || toks[p].t !== ")") throw "paren"; p++; return v; }
        throw "token";
    }
    var v = expr();
    if (p !== toks.length) throw "trailing";
    return v;
}
function calc(text) {
    var s = String(text || "").trim().replace(/\s*=\s*$/, "");
    if (!s || s.length > 200 || /\n/.test(s)) return NaN;
    // dates, times, phone-style numbers and versions read as maths otherwise
    if (/^\d{1,4}([-/.])\d{1,2}\1\d{1,4}$/.test(s) || /^\d{1,2}:\d{2}/.test(s) || /^\d+(\.\d+){2,}$/.test(s)) return NaN;
    if (/^\+\d/.test(s) || /^\(?\d{2,4}\)?(-\d{2,4}){2,}$/.test(s)) return NaN;
    var toks = tokenize(s);
    if (!toks || toks.length < 2) return NaN;
    // needs an operator or a function: "42" or "(42)" is a number, not a sum
    var ops = 0;
    for (var i = 0; i < toks.length; i++) if (toks[i].t === "op" || toks[i].t === "fn" || toks[i].t === "of") ops++;
    if (!ops || (ops === 1 && toks[0].t === "op" && toks[0].v === "-" && toks.length === 2)) return NaN;
    try {
        var v = parse(toks);
        return typeof v === "number" && isFinite(v) ? v : NaN;
    } catch (e) {
        return NaN;
    }
}
// 1234.5 -> "1,234.5"; up to 10 significant decimals, no float noise (0.1 + 0.2 -> "0.3")
function fmt(v) {
    if (!isFinite(v)) return "";
    if (Math.abs(v) >= 1e15 || (Math.abs(v) < 1e-6 && v !== 0)) return v.toExponential(6).replace(/\.?0+e/, "e");
    var r = parseFloat(v.toPrecision(12));
    var parts = String(Math.abs(r)).split(".");
    var int = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return (r < 0 ? "−" : "") + int + (parts[1] ? "." + parts[1] : "");
}
// the plain form for the clipboard ("1234.5", ASCII minus, no separators)
function plain(v) { return isFinite(v) ? String(parseFloat(v.toPrecision(12))) : ""; }

// ---- case ----
// the cycle: UPPER -> lower -> Title -> Sentence -> UPPER ... starting after the text's own case
var cases = ["upper", "lower", "title", "sentence"];
var caseNames = { upper: "UPPERCASE", lower: "lowercase", title: "Title Case", sentence: "Sentence case" };
function hasLetters(t) { return /[A-Za-zÀ-ÖØ-öø-ÿĀ-žА-я]/.test(String(t)); }
function toCase(t, k) {
    t = String(t);
    if (k === "upper") return t.toUpperCase();
    if (k === "lower") return t.toLowerCase();
    if (k === "title") return t.toLowerCase().replace(/(^|[\s\-_/("“])(\S)/g, function (m, a, b) { return a + b.toUpperCase(); });
    // sentence: first letter of the text and after . ! ? upper, the rest lower
    return t.toLowerCase().replace(/(^\s*|[.!?]\s+)(\S)/g, function (m, a, b) { return a + b.toUpperCase(); });
}
function caseOf(t) {
    t = String(t);
    if (!hasLetters(t)) return "";
    if (t === t.toUpperCase()) return "upper";
    if (t === t.toLowerCase()) return "lower";
    if (t === toCase(t, "title")) return "title";
    if (t === toCase(t, "sentence")) return "sentence";
    return "";
}
// the next case in the cycle after `cur` ("" = after the text's own case), skipping a case that
// would look the same as what is showing now ("Hello" is both Title and Sentence case)
function nextCase(t, cur) {
    t = String(t);
    var from = cur || caseOf(t), shown = cur ? toCase(t, cur) : t;
    var i = cases.indexOf(from);
    for (var n = 1; n <= cases.length; n++) {
        var k = cases[(i + n + cases.length) % cases.length];
        if (toCase(t, k) !== shown) return k;
    }
    return cases[(i + 1 + cases.length) % cases.length];
}

// ---- summary for the bar ----
// { url, host, isUrl, math (number | NaN), isMath, words, letters }
function classify(text) {
    var t = String(text || "").trim();
    var url = urlOf(t);
    var math = url ? NaN : calc(t);
    return {
        url: url,
        host: url ? hostOf(url) : "",
        isUrl: url !== "",
        math: math,
        isMath: !isNaN(math),
        words: t ? t.split(/\s+/).length : 0,
        letters: hasLetters(t)
    };
}
