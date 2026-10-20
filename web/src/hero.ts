// Hero: a dot-matrix "nox" over a topographic contour field. The pointer is a lamp:
// contours light up under it, dots it passes heat to signal red and drift away, then cool.
import { reduced, visibility } from "./util";

type Dot = { hx: number; hy: number; x: number; y: number; vx: number; vy: number; r: number; heat: number; delay: number; sx: number; sy: number; dx: number; dy: number };

function hash(x: number, y: number) {
  const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
  return s - Math.floor(s);
}
function vnoise(x: number, y: number) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = x - xi, yf = y - yi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
  const a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
function fbm(x: number, y: number) {
  let s = 0, a = 0.5, f = 1;
  for (let i = 0; i < 5; i++) { s += a * vnoise(x * f, y * f); f *= 2.02; a *= 0.5; }
  return s;
}

export function initHero(canvas: HTMLCanvasElement) {
  const ctx = canvas.getContext("2d")!;
  const topo = document.createElement("canvas");
  const topoHot = document.createElement("canvas");
  const lamp = document.createElement("canvas");
  let W = 0, H = 0, dpr = 1;
  let dots: Dot[] = [];
  let pitch = 8;
  const ptr = { x: -9999, y: -9999, tx: -9999, ty: -9999, active: false, last: 0 };
  let progress = 0; // scroll-out 0..1
  let t0 = performance.now();
  let running = false;
  let raf = 0;
  let onScreen = true;
  let built = false;
  let ready = false;
  let lastNow = 0;

  function buildTopo() {
    for (const [c, alpha, width] of [[topo, 0.22, 1], [topoHot, 0.9, 1.15]] as const) {
      c.width = W * dpr; c.height = H * dpr;
      const g = c.getContext("2d")!;
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, W, H);
      const cell = W < 700 ? 9 : 11;
      const cols = Math.ceil(W / cell) + 2, rows = Math.ceil(H / cell) + 2;
      const f = new Float32Array(cols * rows);
      const sc = 1 / 260;
      for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
        const x = i * cell, y = j * cell;
        f[j * cols + i] = fbm(x * sc + 3.1, y * sc * 1.15 + 7.7) + (y / H) * 0.12;
      }
      const grad = g.createLinearGradient(0, 0, 0, H);
      grad.addColorStop(0, `rgba(255,59,31,${alpha * 0.35})`);
      grad.addColorStop(0.55, `rgba(255,59,31,${alpha * 0.7})`);
      grad.addColorStop(1, `rgba(255,80,40,${alpha})`);
      g.strokeStyle = grad;
      g.lineWidth = width;
      g.lineCap = "round";
      g.beginPath();
      for (let l = 0.28; l < 0.86; l += 0.032) {
        for (let j = 0; j < rows - 1; j++) for (let i = 0; i < cols - 1; i++) {
          const a = f[j * cols + i], b = f[j * cols + i + 1], c2 = f[(j + 1) * cols + i + 1], d = f[(j + 1) * cols + i];
          const idx = (a > l ? 8 : 0) | (b > l ? 4 : 0) | (c2 > l ? 2 : 0) | (d > l ? 1 : 0);
          if (idx === 0 || idx === 15) continue;
          const x = i * cell, y = j * cell;
          const lerp = (p: number, q: number) => (l - p) / (q - p);
          const T = [x + cell * lerp(a, b), y];
          const R = [x + cell, y + cell * lerp(b, c2)];
          const B = [x + cell * lerp(d, c2), y + cell];
          const L = [x, y + cell * lerp(a, d)];
          const seg = (p: number[], q: number[]) => { g.moveTo(p[0], p[1]); g.lineTo(q[0], q[1]); };
          switch (idx) {
            case 1: case 14: seg(L, B); break;
            case 2: case 13: seg(B, R); break;
            case 3: case 12: seg(L, R); break;
            case 4: case 11: seg(T, R); break;
            case 5: seg(L, T); seg(B, R); break;
            case 6: case 9: seg(T, B); break;
            case 7: case 8: seg(L, T); break;
            case 10: seg(T, R); seg(L, B); break;
          }
        }
      }
      g.stroke();
    }
    lamp.width = W * dpr; lamp.height = H * dpr;
  }

  function buildDots() {
    const mobile = W < 700;
    const tw = Math.min(W * (mobile ? 0.88 : 0.84), 1240);
    const fs = tw / 1.62;
    const off = document.createElement("canvas");
    const oh = Math.ceil(fs * 1.05);
    off.width = Math.ceil(tw); off.height = oh;
    const o = off.getContext("2d", { willReadFrequently: true })!;
    o.fillStyle = "#fff";
    o.font = `700 ${fs}px Geist, sans-serif`;
    (o as any).letterSpacing = `${-fs * 0.055}px`;
    o.textBaseline = "alphabetic";
    o.textAlign = "center";
    o.fillText("nox", tw / 2, oh * 0.8);
    const img = o.getImageData(0, 0, off.width, off.height).data;
    pitch = Math.max(mobile ? 5.2 : 7, tw / (mobile ? 74 : 132));
    // where the word sits: centered, slightly above the middle
    const cx = W / 2, cy = H * (mobile ? 0.43 : 0.45);
    const ox = cx - tw / 2, oy = cy - oh * 0.52;
    const again = built;
    built = true;
    dots = [];
    for (let y = pitch / 2; y < oh; y += pitch) {
      for (let x = pitch / 2; x < tw; x += pitch) {
        // coverage: 3x3 samples in the cell
        let cov = 0;
        for (let sy = -1; sy <= 1; sy++) for (let sx = -1; sx <= 1; sx++) {
          const px = Math.min(off.width - 1, Math.max(0, Math.round(x + sx * pitch * 0.3)));
          const py = Math.min(oh - 1, Math.max(0, Math.round(y + sy * pitch * 0.3)));
          cov += img[(py * off.width + px) * 4 + 3] / 255;
        }
        cov /= 9;
        if (cov < 0.18) continue;
        const hx = ox + x, hy = oy + y;
        const ang = Math.random() * Math.PI * 2;
        const dist = 40 + Math.random() * 220;
        dots.push({
          hx, hy,
          x: hx + Math.cos(ang) * dist, y: hy + Math.sin(ang) * dist * 0.6,
          vx: 0, vy: 0,
          r: pitch * 0.36 * Math.sqrt(Math.min(1, cov * 1.1)),
          heat: 0,
          delay: (x / tw) * 700 + Math.random() * 380,
          sx: 0, sy: 0,
          dx: (Math.random() - 0.5) * 2, dy: -0.4 - Math.random() * 1.2,
        });
      }
    }
    if (again) { // resize after intro: no re-assembly
      for (const d of dots) { d.x = d.hx; d.y = d.hy; d.delay = 0; }
    }
  }

  function resize() {
    const r = canvas.getBoundingClientRect();
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = Math.max(1, r.width); H = Math.max(1, r.height);
    canvas.width = W * dpr; canvas.height = H * dpr;
    buildTopo();
    buildDots();
    if (reduced) { for (const d of dots) { d.x = d.hx; d.y = d.hy; } frame(performance.now()); }
  }

  function frame(now: number) {
    const t = now - t0;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);

    // ease pointer
    ptr.x += (ptr.tx - ptr.x) * 0.18;
    ptr.y += (ptr.ty - ptr.y) * 0.18;

    // ambient scan: when idle, a soft lamp drifts along the word
    const idle = now - ptr.last > 2600;
    let lx = ptr.x, ly = ptr.y, lr = Math.min(W, H) * 0.32;
    if (idle) {
      const s = (t / 5200) % 1;
      lx = W * (0.15 + 0.7 * (0.5 - 0.5 * Math.cos(s * Math.PI * 2)));
      ly = H * (0.5 + 0.12 * Math.sin(t / 2300));
      lr *= 0.9;
    }

    // topo: base + lamp-lit copy
    const par = reduced ? 0 : Math.sin(t / 9000) * 8;
    const pxo = (ptr.active ? (ptr.x / W - 0.5) * -14 : 0) + par;
    const pyo = (ptr.active ? (ptr.y / H - 0.5) * -10 : 0) - progress * 60;
    ctx.globalAlpha = 1 - progress * 0.6;
    ctx.drawImage(topo, pxo, pyo, W, H);
    const lg = lamp.getContext("2d")!;
    lg.setTransform(dpr, 0, 0, dpr, 0, 0);
    lg.globalCompositeOperation = "source-over";
    lg.clearRect(0, 0, W, H);
    const rg = lg.createRadialGradient(lx, ly, 0, lx, ly, lr);
    rg.addColorStop(0, "rgba(0,0,0,1)");
    rg.addColorStop(0.45, "rgba(0,0,0,.45)");
    rg.addColorStop(1, "rgba(0,0,0,0)");
    lg.fillStyle = rg;
    lg.fillRect(0, 0, W, H);
    lg.globalCompositeOperation = "source-in";
    lg.drawImage(topoHot, pxo, pyo, W, H);
    ctx.globalAlpha = (idle ? 0.55 : 1) * (1 - progress);
    ctx.drawImage(lamp, 0, 0, W, H);
    ctx.globalAlpha = 1;

    // dots
    const R = Math.max(90, pitch * 13);
    const R2 = R * R;
    const fade = 1 - progress;
    const steps = Math.min(4, Math.max(1, Math.round((now - lastNow) / 16.7)));
    lastNow = now;
    ctx.fillStyle = "rgb(236,231,226)";
    const hot: Dot[] = [];
    for (const d of dots) {
      if (!reduced) {
        if (t > d.delay) for (let st = 0; st < steps; st++) {
          // spring home
          d.vx += (d.hx - d.x) * 0.06; d.vy += (d.hy - d.y) * 0.06;
          if (ptr.active) {
            const ex = d.x - ptr.x, ey = d.y - ptr.y;
            const e2 = ex * ex + ey * ey;
            if (e2 < R2) {
              const k = 1 - e2 / R2;
              const inv = 1 / (Math.sqrt(e2) + 0.01);
              d.vx += ex * inv * k * 2.2; d.vy += ey * inv * k * 2.2;
              d.heat = Math.min(1, d.heat + k * 0.16);
            }
          }
          if (idle) {
            const ex = d.hx - lx, ey = d.hy - ly;
            const e2 = ex * ex + ey * ey;
            if (e2 < lr * lr * 0.25) d.heat = Math.min(0.55, d.heat + 0.012);
          }
          d.vx *= 0.78; d.vy *= 0.78;
          d.x += d.vx; d.y += d.vy;
        }
        d.heat *= Math.pow(0.972, steps);
      }
      const sx = d.x + d.dx * progress * 140;
      const sy = d.y + d.dy * progress * 220;
      d.sx = sx; d.sy = sy;
      if (d.heat > 0.04) { hot.push(d); continue; }
      ctx.globalAlpha = fade * (reduced ? 1 : Math.min(1, Math.max(0, (t - d.delay) / 500)));
      ctx.beginPath();
      ctx.arc(sx, sy, d.r, 0, 6.2832);
      ctx.fill();
    }
    // hot dots: ember, bigger, glow pass
    for (const d of hot) {
      const k = d.heat;
      const g = Math.round(231 - 172 * k), b = Math.round(226 - 195 * k);
      ctx.globalAlpha = fade;
      ctx.fillStyle = `rgb(${255 - Math.round(19 * (1 - k))},${g},${b})`;
      ctx.beginPath();
      ctx.arc(d.sx, d.sy, d.r * (1 + k * 0.35), 0, 6.2832);
      ctx.fill();
    }
    if (hot.length) {
      ctx.globalCompositeOperation = "lighter";
      for (const d of hot) {
        ctx.globalAlpha = d.heat * 0.22 * fade;
        ctx.fillStyle = "rgb(255,59,31)";
        ctx.beginPath();
        ctx.arc(d.sx, d.sy, d.r * 3.2, 0, 6.2832);
        ctx.fill();
      }
      ctx.globalCompositeOperation = "source-over";
    }
    ctx.globalAlpha = 1;
  }

  function loop(now: number) {
    frame(now);
    raf = requestAnimationFrame(loop);
  }
  function start() {
    if (running || reduced) return;
    running = true;
    raf = requestAnimationFrame(loop);
  }
  function stop() {
    running = false;
    cancelAnimationFrame(raf);
  }

  const setPtr = (e: PointerEvent) => {
    const r = canvas.getBoundingClientRect();
    ptr.tx = e.clientX - r.left; ptr.ty = e.clientY - r.top;
    if (!ptr.active) { ptr.x = ptr.tx; ptr.y = ptr.ty; }
    ptr.active = true; ptr.last = performance.now();
  };
  // listen on the whole hero so text over the canvas still feeds the lamp
  const host = canvas.parentElement!;
  host.addEventListener("pointermove", setPtr, { passive: true });
  host.addEventListener("pointerdown", setPtr, { passive: true });
  host.addEventListener("pointerleave", () => { ptr.active = false; ptr.tx = ptr.ty = -9999; ptr.last = 0; });

  let rz = 0;
  const ro = new ResizeObserver(() => { if (!ready) return; cancelAnimationFrame(rz); rz = requestAnimationFrame(resize); });
  ro.observe(canvas);

  visibility(host, (on) => { onScreen = on; if (on) start(); else stop(); });
  document.addEventListener("visibilitychange", () => { if (document.hidden) stop(); else if (onScreen) start(); });

  const go = () => { if (ready) return; ready = true; resize(); t0 = performance.now(); start(); };
  document.fonts.load("700 100px Geist").then(go, go);
  setTimeout(go, 2500); // fonts blocked or slow: draw with the fallback

  return {
    setProgress(p: number) {
      progress = p;
      if (reduced) frame(performance.now());
    },
  };
}
