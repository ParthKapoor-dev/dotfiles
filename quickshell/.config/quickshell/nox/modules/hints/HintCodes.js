.pragma library

// Hint labels: the shortest prefix-free codes over `chars` for n targets (Vimium's scheme). The
// first targets get the shortest labels; no label is the start of another, so typing a whole
// label picks it without Enter. 9 home-row letters: up to 9 single letters, 81 of two, 729 of three.
function codes(n, chars) {
    const cs = String(chars || "asdfghjkl").split("").filter((c, i, a) => a.indexOf(c) === i);
    if (n <= 0 || cs.length < 2) return [];
    const out = [""];
    let off = 0;
    while (out.length - off < n || out.length === 1) {
        const h = out[off++];
        for (const c of cs) out.push(h + c);
    }
    return out.slice(off, off + n);
}

// reading order: top to bottom in rows of ~row px, then left to right
function byReading(a, b, row) {
    const r = row || 12;
    const ay = Math.round(a.y / r), by = Math.round(b.y / r);
    return ay !== by ? ay - by : a.x - b.x;
}
