# Regenerate components/glyphs.js from the design mock: python3 tools/gen-glyphs.py components/glyphs.js [mock.html]
import re, json, sys
src = open(sys.argv[2] if len(sys.argv) > 2 else __import__('os').path.expanduser('~/code/sandbox/void/lnx/design/mock/desktop-mock.html')).read()
block = src[src.index('const P = {'):src.index('const ic = (name')]

EXTRA = {
  'wifi1': '<path d="M2.5 9a14 14 0 0 1 19 0" opacity=".3"/><path d="M5.6 12.3a9.5 9.5 0 0 1 12.8 0" opacity=".3"/><path d="M8.7 15.5a5 5 0 0 1 6.6 0"/><circle cx="12" cy="18.8" r="1.25" fill="currentColor" stroke="none"/>',
  'wifi2': '<path d="M2.5 9a14 14 0 0 1 19 0" opacity=".3"/><path d="M5.6 12.3a9.5 9.5 0 0 1 12.8 0"/><path d="M8.7 15.5a5 5 0 0 1 6.6 0"/><circle cx="12" cy="18.8" r="1.25" fill="currentColor" stroke="none"/>',
  'wifi0': '<path d="M2.5 9a14 14 0 0 1 19 0" opacity=".3"/><path d="M5.6 12.3a9.5 9.5 0 0 1 12.8 0" opacity=".3"/><path d="M8.7 15.5a5 5 0 0 1 6.6 0" opacity=".3"/><circle cx="12" cy="18.8" r="1.25" fill="currentColor" stroke="none" opacity=".3"/>',
  'mouse': '<rect x="7" y="3.5" width="10" height="17" rx="5"/><path d="M12 7.5v3"/>',
  'speaker0': '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor"/>',
  'speaker1': '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor"/><path d="M15.5 9a4 4 0 0 1 0 6"/>',
  'mic': '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/>',
  'micOff': '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/><path d="M4 4l16 16"/>',
  'lan': '<rect x="9" y="3.5" width="6" height="5" rx="1"/><rect x="3" y="15.5" width="6" height="5" rx="1"/><rect x="15" y="15.5" width="6" height="5" rx="1"/><path d="M12 8.5v3.5M6 15.5V12h12v3.5"/>',
  'eye': '<path d="M2.5 12s3.5-6.5 9.5-6.5S21.5 12 21.5 12s-3.5 6.5-9.5 6.5S2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
  'eyeOff': '<path d="M2.5 12s3.5-6.5 9.5-6.5S21.5 12 21.5 12s-3.5 6.5-9.5 6.5S2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/><path d="M4 4l16 16"/>',
  'logout': '<path d="M14 4.5H6.5a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2H14M10 12h10.5M17 8.5l3.5 3.5-3.5 3.5"/>',
  'user': '<circle cx="12" cy="8.5" r="3.8"/><path d="M4.5 20a7.5 7.5 0 0 1 15 0"/>',
  'phone': '<rect x="7" y="3" width="10" height="18" rx="2.5"/><path d="M11 17.5h2"/>',
  'trashFull': '<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13"/><path d="M10 11v5.5M14 11v5.5"/>',
  'dwindle': '<rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><path d="M11 4.5v15M11 12h9.5M15.75 12v7.5"/>',
  'master': '<rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><path d="M12.5 4.5v15M12.5 9.5h8M12.5 14.5h8"/>',
  'scrolling': '<rect x="2.5" y="5" width="6" height="14" rx="1.5"/><rect x="10.5" y="5" width="8" height="14" rx="1.5"/><path d="M21.5 7v10"/>',
  'floating': '<rect x="3.5" y="4.5" width="11" height="9" rx="2"/><rect x="9.5" y="10.5" width="11" height="9" rx="2"/>',
  'monocle': '<rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><rect x="7" y="8" width="10" height="8" rx="1"/>',
  'key': '<circle cx="8" cy="15" r="4"/><path d="M11 12l8.5-8.5M16 7l2.5 2.5M14 9l2 2"/>',
  'dots': '<path d="M6 12h.01M12 12h.01M18 12h.01" stroke-width="2.6"/>',
  'calendar': '<rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  'settings': '<circle cx="12" cy="12" r="3"/><path d="M12 3.5v2.2M12 18.3v2.2M3.5 12h2.2M18.3 12h2.2M6 6l1.6 1.6M16.4 16.4L18 18M6 18l1.6-1.6M16.4 7.6L18 6"/>',
}
entries = re.findall(r"^\s*(\w+): '(.*)',\s*$", block, re.M)
def attrs(s): return dict(re.findall(r'([\w-]+)="([^"]*)"', s))
def f(x): return float(x)
def circle(a):
    cx, cy, r = f(a['cx']), f(a['cy']), f(a['r'])
    return f"M{cx-r:g} {cy:g}a{r:g} {r:g} 0 1 0 {2*r:g} 0a{r:g} {r:g} 0 1 0 {-2*r:g} 0z"
def rect(a):
    x, y, w, h = f(a['x']), f(a['y']), f(a['width']), f(a['height'])
    rx = min(f(a.get('rx', 0)), w/2, h/2)
    if rx <= 0: return f"M{x:g} {y:g}h{w:g}v{h:g}h{-w:g}z"
    return (f"M{x+rx:g} {y:g}h{w-2*rx:g}a{rx:g} {rx:g} 0 0 1 {rx:g} {rx:g}v{h-2*rx:g}a{rx:g} {rx:g} 0 0 1 {-rx:g} {rx:g}"
            f"h{-(w-2*rx):g}a{rx:g} {rx:g} 0 0 1 {-rx:g} {-rx:g}v{-(h-2*rx):g}a{rx:g} {rx:g} 0 0 1 {rx:g} {-rx:g}z")
out = {}
entries = entries + list(EXTRA.items())
for name, body in entries:
    parts = []
    for tag, at in re.findall(r'<(path|circle|rect)\s([^>]*?)/?>', body):
        a = attrs(at)
        d = a['d'] if tag == 'path' else circle(a) if tag == 'circle' else rect(a)
        fill = a.get('fill') == 'currentColor'
        stroke = a.get('stroke') != 'none'
        p = {"d": d}
        if fill: p["f"] = 1
        if not stroke: p["s"] = 0
        if 'stroke-width' in a: p["w"] = f(a['stroke-width'])
        if 'opacity' in a: p["o"] = f(a['opacity'])
        if 'stroke-dasharray' in a: p["dash"] = 1
        parts.append(p)
    if parts: out[name] = parts
print(len(out), file=sys.stderr)
js = ".pragma library\n// Monochrome glyphs ported 1:1 from the design mock (design/mock/desktop-mock.html, const P):\n// 24x24 viewBox, stroke = currentColor 1.7 round caps/joins. Generated; parts: d = SVG path,\n// f = filled, s:0 = no stroke, w = stroke width, o = opacity.\nvar glyphs = " + json.dumps(out, separators=(',', ':')).replace('},{', '},\n{').replace(']," ', '],\n"') + ";\n"
open(sys.argv[1], 'w').write(js)
