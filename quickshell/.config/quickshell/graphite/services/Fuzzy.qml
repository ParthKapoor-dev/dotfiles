pragma Singleton
import QtQuick
import Quickshell

// Small fuzzy matcher for the launcher (pure functions, no state).
// match(query, text) -> { score, indices } or null. Higher score = better.
//   exact > prefix > word-start substring > substring > subsequence (gaps cost points; loose ones are dropped).
Singleton {
    function match(query, text) {
        if (!query || !text) return null;
        const q = query.toLowerCase(), t = String(text).toLowerCase();
        const range = (from, n) => Array.from({ length: n }, (_, i) => from + i);
        if (t === q) return { score: 100, indices: range(0, q.length) };
        if (t.startsWith(q)) return { score: 80 + 10 * q.length / t.length, indices: range(0, q.length) };
        const idx = t.indexOf(q);
        if (idx > 0) {
            // prefer matches at a word start
            const wordStart = /[\s\-_.\/]/.test(t[idx - 1]);
            return { score: (wordStart ? 60 : 40) + 10 * q.length / t.length, indices: range(idx, q.length) };
        }
        // subsequence ("fd" -> "Firefox Developer"): every query char in order, and each run of
        // consecutive matches must start at a word boundary (start, after a separator, or camelCase)
        const src = String(text);
        const boundary = i => i === 0 || /[\s\-_.\/]/.test(src[i - 1]) || (/[a-z]/.test(src[i - 1]) && /[A-Z]/.test(src[i]));
        const indices = [];
        let ti = 0, gaps = 0, last = -1;
        for (const c of q) {
            if (c === " ") continue;
            let found = t.indexOf(c, ti);
            // a new run must begin at a boundary: skip ahead to the next boundary occurrence
            if (found !== last + 1 || last < 0) {
                while (found >= 0 && !(found === last + 1 && last >= 0) && !boundary(found)) found = t.indexOf(c, found + 1);
            }
            if (found < 0) return null;
            if (last >= 0) gaps += found - last - 1;
            indices.push(found);
            last = found; ti = found + 1;
        }
        const score = 30 - gaps * 0.5 - indices[0] * 0.5;
        return score > 5 ? { score, indices } : null;
    }

    // Best match over several fields: [[text, weight], ...]. Indices refer to the first field only.
    function best(query, fields) {
        let out = null;
        for (let i = 0; i < fields.length; i++) {
            const [text, weight] = fields[i];
            const m = match(query, text);
            if (!m) continue;
            const s = m.score * (weight ?? 1);
            if (!out || s > out.score) out = { score: s, indices: i === 0 ? m.indices : [] };
        }
        return out;
    }

    // Plain text -> StyledText with matched characters in bold (escapes markup).
    function highlight(text, indices) {
        const esc = c => c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c;
        const set = new Set(indices ?? []);
        let out = "";
        const s = String(text);
        for (let i = 0; i < s.length; i++) out += set.has(i) ? "<b>" + esc(s[i]) + "</b>" : esc(s[i]);
        return out;
    }
}
