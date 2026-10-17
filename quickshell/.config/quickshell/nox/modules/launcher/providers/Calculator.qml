import QtQuick
import Quickshell
import qs.core

// Arithmetic with a small recursive-descent parser (never eval()).
// + - * / % ^ (power), parentheses, unary minus, implicit nothing; functions sqrt abs round floor ceil
// sin cos tan asin acos atan ln log exp; constants pi, e. "x" and "×" mean *, "÷" means /.
// Shown without a prefix when the query looks like maths; "=" forces it. Enter copies the result.
// options: copyCommand (argv, default wl-copy), precision (significant digits, default 12)
Item {
    id: root
    property string providerId: "calculator"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Calculator"
    property string defaultPrefix: "="
    property bool defaultPrefixOnly: false

    readonly property var fns: ({
        sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
        sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
        ln: Math.log, log: Math.log10, exp: Math.exp
    })
    readonly property var consts: ({ pi: Math.PI, e: Math.E })

    function tokenize(s) {
        const toks = [];
        let i = 0;
        while (i < s.length) {
            const c = s[i];
            if (/\s/.test(c)) { i++; continue; }
            const num = /^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/i.exec(s.slice(i));
            if (num) { toks.push({ t: "num", v: parseFloat(num[0]) }); i += num[0].length; continue; }
            const id = /^[a-z]+/i.exec(s.slice(i));
            if (id) {
                const w = id[0].toLowerCase();
                toks.push(w === "x" ? { t: "op", v: "*" } : { t: "id", v: w });
                i += id[0].length; continue;
            }
            const op = c === "×" ? "*" : c === "÷" ? "/" : c;
            if ("+-*/%^()".includes(op)) {
                if (op === "*" && s[i + 1] === "*") { toks.push({ t: "op", v: "^" }); i += 2; continue; }
                toks.push({ t: "op", v: op }); i++; continue;
            }
            throw new Error("bad char");
        }
        return toks;
    }

    // expr := term (("+"|"-") term)* ; term := unary (("*"|"/"|"%") unary)* ; unary := "-" unary | power
    // power := atom ("^" unary)? ; atom := num | const | fn "(" expr ")" | "(" expr ")"
    function evaluate(s) {
        const toks = tokenize(s);
        let p = 0;
        const peek = () => toks[p];
        const eat = v => { if (peek() && peek().v === v) { p++; return true; } return false; };
        function expr() {
            let v = term();
            for (;;) { if (eat("+")) v += term(); else if (eat("-")) v -= term(); else return v; }
        }
        function term() {
            let v = unary();
            for (;;) {
                if (eat("*")) v *= unary();
                else if (eat("/")) v /= unary();
                else if (eat("%")) v %= unary();
                else if (peek() && (peek().v === "(" || peek().t === "id")) v *= unary();   // 2pi, 3(4+1)
                else return v;
            }
        }
        function unary() { if (eat("-")) return -unary(); if (eat("+")) return unary(); return power(); }
        function power() { const b = atom(); return eat("^") ? Math.pow(b, unary()) : b; }
        function atom() {
            const tk = toks[p++];
            if (!tk) throw new Error("end");
            if (tk.t === "num") return tk.v;
            if (tk.v === "(") { const v = expr(); if (!eat(")")) throw new Error(")"); return v; }
            if (tk.t === "id") {
                if (root.consts[tk.v] !== undefined) return root.consts[tk.v];
                const f = root.fns[tk.v];
                if (f && eat("(")) { const v = expr(); if (!eat(")")) throw new Error(")"); return f(v); }
            }
            throw new Error("unexpected");
        }
        const v = expr();
        if (p !== toks.length) throw new Error("trailing");
        return v;
    }

    function format(v) {
        const r = Number(v.toPrecision(options.precision ?? 12));
        return Math.abs(r) >= 1e15 || (r !== 0 && Math.abs(r) < 1e-9) ? r.toExponential(6) : String(r);
    }

    function query(text, prefixed) {
        const q = text.trim();
        if (!q) return [];
        // without the prefix, only claim queries that contain an operator or a function call
        if (!prefixed && !/\d/.test(q)) return [];
        if (!prefixed && !/[-+*\/%^×÷(]/.test(q.replace(/^-/, ""))) return [];
        let v;
        try { v = evaluate(q); } catch (e) { return []; }
        if (typeof v !== "number" || !isFinite(v)) return [];
        const result = format(v);
        return [{
            title: result,
            big: [q, "Expression", result, "Result"],
            type: "Calculator",
            actLabel: "Copy",
            score: 1000,
            run: () => Quickshell.execDetached((options.copyCommand ?? ["wl-copy"]).concat([result]))
        }];
    }
}
