// Gzowo Concierge - Face: pearl glass orb head on the shared ticker, spring-driven gaze parallax, luminous eyes, sleep, thinking orbit, light ribbons, audio-reactive mouth.
import { subscribe, onIdle } from './ui/ticker.js';

const PI = Math.PI, TAU = PI * 2;
const GX = 0, GY = 1, OPEN = 2, BLINK = 3, TILT = 4, MW = 5, MC = 6, MO = 7, SQ = 8, ERR = 9, BR = 10, SL = 11, TH = 12, WK = 13, HL = 14, RB = 15, N = 16;
const RESP = [0.15, 0.15, 0.2, 0.065, 0.24, 0.26, 0.26, 0.055, 0.2, 0.32, 0.8, 0.7, 0.6, 0.5, 0.35, 0.6];
const DAMP = [0.92, 0.92, 0.88, 0.9, 0.9, 0.92, 0.92, 0.95, 0.9, 1, 1, 1, 1, 1, 1, 1];

const ST = {
  idle: { open: 0.95, tilt: 0, mw: 0.2, mc: 0.05, sq: 0, gx: 0, gy: 0, amp: 0.05, blink: [3200, 6800], sl: 0, th: 0, wk: 0, hl: 0, rb: 0.5 },
  listening: { open: 1.08, tilt: 0, mw: 0.18, mc: 0.03, sq: 0, gx: 0, gy: 0.02, amp: 0.03, blink: [2600, 5200], sl: 0, th: 0, wk: 0, hl: 0.35, rb: 0.8 },
  thinking: { open: 0.9, tilt: 0.05, mw: 0.14, mc: 0, sq: 0.05, gx: 0.5, gy: -0.5, amp: 0.16, blink: [3800, 7000], sl: 0, th: 1, wk: 0, hl: 0.3, rb: 1 },
  speaking: { open: 1, tilt: 0, mw: 0.2, mc: 0.06, sq: 0, gx: 0, gy: 0, amp: 0.04, blink: [2800, 5600], sl: 0, th: 0, wk: 0, hl: 0.4, rb: 0.9 },
  working: { open: 0.84, tilt: 0, mw: 0.14, mc: 0, sq: 0.12, gx: 0, gy: 0.3, amp: 0.28, blink: [3000, 6000], sl: 0, th: 0, wk: 1, hl: 0.2, rb: 0.7 },
  alert: { open: 1.14, tilt: 0.05, mw: 0.15, mc: 0, sq: 0, gx: 0, gy: 0.25, amp: 0.012, blink: [4200, 8000], sl: 0, th: 0, wk: 0, hl: 0.3, rb: 0.6 },
  error: { open: 0.62, tilt: 0.2, mw: 0.2, mc: -0.1, sq: 0.25, gx: 0, gy: 0.15, amp: 0.01, blink: [5000, 9000], sl: 0, th: 0, wk: 0, hl: 0, rb: 0.2 },
  sleep: { open: 0.8, tilt: 0.02, mw: 0.12, mc: 0.05, sq: 0, gx: 0, gy: 0.12, amp: 0, blink: [1e9, 1e9], sl: 1, th: 0, wk: 0, hl: 0, rb: 0.15 },
};

const EYE_X = 0.3, EYE_W = 0.115, EYE_H = 0.3, EYE_Y = -0.06, MOUTH_Y = 0.38, SLEEP_MS = 20000;
const RIB = [[-0.32, 1.34, 0.3, 0.00031, 'rgba(150,160,255,', 1], [0.2, 1.4, 0.27, -0.00026, 'rgba(255,190,160,', 0.85], [0.74, 1.3, 0.34, 0.00021, 'rgba(140,205,255,', 0.9]];

function hex(h, a) {
  const n = parseInt((h || '#e8890c').replace('#', ''), 16);
  return 'rgba(' + (n >> 16 & 255) + ',' + (n >> 8 & 255) + ',' + (n & 255) + ',' + a + ')';
}

function pill(c, w, h) {
  const r = Math.min(w, h) / 2, hw = w / 2, hh = h / 2;
  c.moveTo(-hw + r, -hh);
  c.lineTo(hw - r, -hh);
  c.arc(hw - r, -hh + r, r, -PI / 2, 0);
  c.lineTo(hw, hh - r);
  c.arc(hw - r, hh - r, r, 0, PI / 2);
  c.lineTo(-hw + r, hh);
  c.arc(-hw + r, hh - r, r, PI / 2, PI);
  c.lineTo(-hw, -hh + r);
  c.arc(-hw + r, -hh + r, r, PI, PI * 1.5);
  c.closePath();
}

const sprite = (w, h) => { const c = document.createElement('canvas'); c.width = Math.max(2, Math.ceil(w)); c.height = Math.max(2, Math.ceil(h)); return c; };

export function followPointer(face) {
  if (!matchMedia('(hover: hover) and (pointer: fine)').matches) return () => {};
  let t = 0, idle = 0;
  const on = e => {
    const n = performance.now();
    if (n - t < 90) return;
    t = n;
    face.lookAt({ x: e.clientX, y: e.clientY });
    clearTimeout(idle);
    idle = setTimeout(() => face.lookAt(null), 7000);
  };
  addEventListener('pointermove', on, { passive: true });
  return () => { removeEventListener('pointermove', on); clearTimeout(idle); };
}

export function createFace(host, opts = {}) {
  const canvas = host.tagName === 'CANVAS' ? host : (() => { const c = document.createElement('canvas'); c.style.cssText = 'display:block;width:100%;height:100%'; host.appendChild(c); return c; })();
  const ctx = canvas.getContext('2d');
  const mq = matchMedia('(prefers-reduced-motion: reduce)');
  const dark = matchMedia('(prefers-color-scheme: dark)');
  const ribbons = !!opts.ribbons;
  let reduce = opts.reduceMotion ?? mq.matches;

  const X = new Float64Array(N), V = new Float64Array(N), T = new Float64Array(N), K = new Float64Array(N), C = new Float64Array(N);
  let state = 'idle', ret = 'idle', errUntil = 0, asleep = false, lastActive = performance.now();
  let mic = 0, out = 0, micS = 0, outS = 0;
  let running = false, unsub = null, unIdle = null, last = 0, cw = 1, ch = 1, dpr = 1, R = 50, ro = null;
  let nextBlink = 0, blinkRelease = 0, doubleBlink = false, nextSac = 0, sx = 0, sy = 0, side = 1;
  let lookMode = 0, lookEl = null, lookX = 0, lookY = 0, vx = 0, vy = 0, hasVec = false, lastMeasure = 0;
  let pUntil = 0, pOpen = 0, pTilt = 0, pMC = 0, pSQ = 0, pErr = 0;
  let ink = '#1b2133', errc = '#d11a2a', live = '#e8890c', sp = null;

  function colors() {
    const cs = getComputedStyle(canvas);
    live = cs.getPropertyValue('--live').trim() || '#e8890c';
    errc = cs.getPropertyValue('--err').trim() || '#d11a2a';
    ink = opts.ink || (dark.matches ? '#f4f7ff' : '#1b2133');
    build();
  }

  function build() {
    const r = Math.round(R * dpr), d = dark.matches;
    if (r < 6) { sp = null; return; }
    const body = sprite(r * 2.2, r * 2.2), b = body.getContext('2d'), c0 = body.width / 2;
    b.translate(c0, c0);
    const g = b.createRadialGradient(-r * 0.3, -r * 0.38, 0, 0, 0, r * 1.08);
    if (d) { g.addColorStop(0, 'rgba(112,126,184,.96)'); g.addColorStop(0.45, 'rgba(48,56,98,.96)'); g.addColorStop(1, 'rgba(14,18,38,.98)'); }
    else { g.addColorStop(0, 'rgba(255,255,255,.98)'); g.addColorStop(0.38, 'rgba(249,248,255,.95)'); g.addColorStop(0.72, 'rgba(225,228,250,.93)'); g.addColorStop(1, 'rgba(194,205,242,.96)'); }
    b.fillStyle = g; b.beginPath(); b.arc(0, 0, r, 0, TAU); b.fill();
    b.save(); b.beginPath(); b.arc(0, 0, r, 0, TAU); b.clip();
    const cg = b.createRadialGradient(0, r * 1.05, 0, 0, r * 1.05, r * 0.95);
    if (d) { cg.addColorStop(0, 'rgba(150,172,255,.38)'); cg.addColorStop(1, 'rgba(150,172,255,0)'); }
    else { cg.addColorStop(0, 'rgba(255,208,182,.62)'); cg.addColorStop(1, 'rgba(255,208,182,0)'); }
    b.fillStyle = cg; b.fillRect(-r, -r, r * 2, r * 2);
    const eg = b.createRadialGradient(0, 0, r * 0.7, 0, 0, r);
    eg.addColorStop(0, 'rgba(110,120,200,0)'); eg.addColorStop(1, d ? 'rgba(0,0,10,.38)' : 'rgba(112,124,206,.26)');
    b.fillStyle = eg; b.fillRect(-r, -r, r * 2, r * 2);
    b.restore();
    const rg = b.createLinearGradient(-r, -r, r, r);
    rg.addColorStop(0, d ? 'rgba(255,255,255,.7)' : 'rgba(255,255,255,1)'); rg.addColorStop(0.4, 'rgba(255,255,255,.1)'); rg.addColorStop(0.62, 'rgba(255,255,255,.08)'); rg.addColorStop(1, d ? 'rgba(255,255,255,.4)' : 'rgba(255,255,255,.85)');
    b.lineWidth = Math.max(1.5, r * 0.03); b.strokeStyle = rg; b.beginPath(); b.arc(0, 0, r - b.lineWidth / 2, 0, TAU); b.stroke();
    b.lineWidth = 1; b.strokeStyle = d ? 'rgba(255,255,255,.14)' : 'rgba(84,98,170,.2)'; b.beginPath(); b.arc(0, 0, r + 0.5, 0, TAU); b.stroke();

    const spec = sprite(r * 1.3, r * 1.3), s = spec.getContext('2d');
    s.translate(spec.width / 2, spec.height / 2);
    s.save(); s.rotate(-0.56); s.scale(1, 0.46);
    const sg = s.createRadialGradient(0, 0, 0, 0, 0, r * 0.52);
    sg.addColorStop(0, 'rgba(255,255,255,' + (d ? 0.7 : 0.98) + ')'); sg.addColorStop(0.6, 'rgba(255,255,255,' + (d ? 0.18 : 0.34) + ')'); sg.addColorStop(1, 'rgba(255,255,255,0)');
    s.fillStyle = sg; s.beginPath(); s.arc(0, 0, r * 0.52, 0, TAU); s.fill(); s.restore();

    const glow = sprite(128, 128), gl = glow.getContext('2d');
    const gg = gl.createRadialGradient(64, 64, 0, 64, 64, 64);
    gg.addColorStop(0, hex(live, 0.95)); gg.addColorStop(0.35, hex(live, 0.38)); gg.addColorStop(1, hex(live, 0));
    gl.fillStyle = gg; gl.fillRect(0, 0, 128, 128);

    const eye = sprite(128, 128), ey = eye.getContext('2d');
    const eg2 = ey.createRadialGradient(64, 64, 0, 64, 64, 64);
    if (d) { eg2.addColorStop(0, 'rgba(206,218,255,.8)'); eg2.addColorStop(0.4, 'rgba(160,180,255,.28)'); eg2.addColorStop(1, 'rgba(160,180,255,0)'); }
    else { eg2.addColorStop(0, 'rgba(130,140,230,.34)'); eg2.addColorStop(0.5, 'rgba(130,140,230,.1)'); eg2.addColorStop(1, 'rgba(130,140,230,0)'); }
    ey.fillStyle = eg2; ey.fillRect(0, 0, 128, 128);

    const sh = sprite(256, 64), sc = sh.getContext('2d');
    sc.translate(128, 32); sc.scale(1, 0.25);
    const shg = sc.createRadialGradient(0, 0, 0, 0, 0, 128);
    shg.addColorStop(0, d ? 'rgba(0,0,0,.6)' : 'rgba(60,72,140,.34)'); shg.addColorStop(1, 'rgba(60,72,140,0)');
    sc.fillStyle = shg; sc.beginPath(); sc.arc(0, 0, 128, 0, TAU); sc.fill();

    sp = { body, spec, glow, eye, sh, r };
  }

  function springs() {
    const slow = reduce ? 1.9 : 1;
    for (let i = 0; i < N; i++) {
      const rs = RESP[i] * (i === BLINK || i === MO ? 1 : slow);
      K[i] = (2 * PI / rs) ** 2;
      C[i] = 4 * PI * DAMP[i] / rs;
    }
  }

  function resize() {
    const r = canvas.getBoundingClientRect();
    cw = Math.max(1, r.width); ch = Math.max(1, r.height);
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(cw * dpr); canvas.height = Math.round(ch * dpr);
    R = Math.min(cw, ch) * (ribbons ? 0.25 : 0.33);
    build();
    if (!running) draw(performance.now());
  }

  function measure() {
    const r = canvas.getBoundingClientRect();
    const fx = r.left + r.width / 2, fy = r.top + r.height * 0.5;
    let tx = lookX, ty = lookY;
    if (lookMode === 1) {
      if (!lookEl || !lookEl.isConnected) { lookMode = 0; lookEl = null; hasVec = false; return; }
      const e = lookEl.getBoundingClientRect();
      tx = e.left + e.width / 2; ty = e.top + e.height / 2;
    }
    const dx = tx - fx, dy = ty - fy, d = Math.hypot(dx, dy) || 1;
    const m = Math.min(1, d / Math.max(160, r.width * 0.6));
    vx = dx / d * m; vy = Math.max(-0.8, Math.min(0.85, dy / d * m));
    hasVec = true;
  }

  const eff = () => (state === 'idle' && asleep ? 'sleep' : state);

  function scheduleBlink(now) {
    const b = ST[eff()].blink;
    nextBlink = now + b[0] + Math.random() * (b[1] - b[0]);
  }

  function wake(now) {
    lastActive = now;
    if (asleep) { asleep = false; scheduleBlink(now); nextSac = 0; if (!reduce) { V[OPEN] += 1.2; V[GY] -= 0.5; } }
  }

  function frameLogic(now, dt) {
    const e = eff(), s = ST[e];
    if (state === 'error' && errUntil && now > errUntil) { errUntil = 0; setState(ret); return; }
    if (pUntil && now > pUntil) { pUntil = 0; pOpen = pTilt = pMC = pSQ = pErr = 0; }
    if (state === 'idle' && !asleep && opts.autoSleep !== false && now - lastActive > SLEEP_MS) { asleep = true; blinkRelease = 0; }

    if (e === 'sleep') T[BLINK] = 1;
    else if (!reduce || state !== 'idle') {
      if (blinkRelease) { if (now > blinkRelease) { blinkRelease = 0; T[BLINK] = 0; if (doubleBlink) { doubleBlink = false; nextBlink = now + 140; } else scheduleBlink(now); } }
      else if (now > nextBlink) { T[BLINK] = 1; blinkRelease = now + (state === 'idle' ? 170 : 110); doubleBlink = !reduce && Math.random() < 0.16; }
    } else T[BLINK] = 0;

    if (lookMode && now - lastMeasure > 140) { lastMeasure = now; measure(); }

    if (now >= nextSac) {
      const amp = reduce ? 0 : (lookMode ? s.amp * 0.3 : s.amp);
      sx = (Math.random() * 2 - 1) * amp; sy = (Math.random() * 2 - 1) * amp * 0.7;
      if (state === 'thinking') side = -side;
      nextSac = now + (state === 'thinking' ? 1500 + Math.random() * 1700 : state === 'working' ? 900 + Math.random() * 1200 : 700 + Math.random() * 1900);
    }

    let bx = s.gx, by = s.gy;
    if (state === 'thinking' && !lookMode) bx = s.gx * side;
    if (lookMode && hasVec && e !== 'sleep') { bx = vx; by = vy; }
    const gs = reduce ? 0.35 : 1;
    T[GX] = Math.max(-1, Math.min(1, bx + sx)) * gs;
    T[GY] = Math.max(-1, Math.min(1, by + sy)) * gs;

    const k = Math.min(1, dt * 14);
    micS += (mic - micS) * k;
    outS += (out - outS) * Math.min(1, dt * (out > outS ? 30 : 12));
    if (mic > 0.08 || out > 0.04) lastActive = now;

    const L = e === 'listening', P = e === 'speaking';
    T[OPEN] = s.open + (L ? 0.14 * micS : 0) + pOpen;
    T[TILT] = s.tilt + pTilt;
    T[MW] = s.mw + (L ? 0.05 * micS : P ? 0.06 * outS : 0);
    T[MC] = s.mc + pMC;
    T[MO] = P ? Math.min(1, outS * 1.15) * 0.1 : L ? micS * 0.02 : 0;
    T[SQ] = s.sq + pSQ;
    T[ERR] = (state === 'error' ? 1 : 0) + pErr;
    T[BR] = reduce ? 0 : (e === 'sleep' ? 0.022 : 0.012) * Math.sin(now * (e === 'sleep' ? 0.0007 : 0.0012)) + (P ? outS * 0.05 : L ? micS * 0.05 : 0);
    T[SL] = s.sl;
    T[TH] = s.th;
    T[WK] = s.wk;
    T[HL] = s.hl + (e === 'alert' ? 0.18 * Math.sin(now * 0.004) : 0) + (L ? micS * 0.45 : P ? outS * 0.5 : 0);
    T[RB] = s.rb + (L ? micS * 0.9 : P ? outS * 1.1 : 0);
  }

  function integrate(dt) {
    const n = Math.max(1, Math.ceil(dt / 0.008)), h = dt / n;
    for (let s = 0; s < n; s++) {
      for (let i = 0; i < N; i++) {
        V[i] += (-K[i] * (X[i] - T[i]) - C[i] * V[i]) * h;
        X[i] += V[i] * h;
      }
    }
  }

  function ribbon(c, now, front, cx, cy, Rp) {
    const amp = Math.max(0, Math.min(1.6, X[RB]));
    if (amp < 0.03) return;
    for (let i = 0; i < 3; i++) {
      const d = RIB[i];
      const rot = d[0] + (reduce ? 0 : now * d[3]) + X[GX] * 0.08;
      const rx = Rp * d[1], ry = Rp * (d[2] + 0.1 * amp) * (1 + 0.1 * Math.sin(now * 0.0009 + i * 2));
      const ph = (reduce ? i * 2 : now * 0.0006 * (i % 2 ? -1 : 1)) + i * 2.1;
      const a0 = front ? 0 : PI;
      const SEG = 30, step = PI / SEG;
      c.lineCap = 'butt';
      for (let s = 0; s < SEG; s++) {
        const th = a0 + s * step;
        const w = 0.5 + 0.5 * Math.cos(th * 2 - ph * 2.2);
        const al = (0.12 + 0.88 * w * w) * Math.min(1, amp) * d[5] * (front ? 1 : 0.5);
        if (al < 0.03) continue;
        c.strokeStyle = d[4] + al.toFixed(2) + ')';
        c.lineWidth = Rp * (0.012 + 0.03 * w) * (1 + 0.5 * Math.min(1, amp));
        c.beginPath();
        c.ellipse(cx, cy, rx, ry, rot, th, th + step * 1.04);
        c.stroke();
      }
    }
  }

  function orbit(c, now, front, cx, cy, Rp, th) {
    for (let i = 0; i < 3; i++) {
      const a = (reduce ? 0.7 : now * 0.0011) + i * TAU / 3;
      const px = Math.cos(a) * 1.36 * Rp, py = Math.sin(a) * 0.4 * Rp;
      if ((py > 0) !== front) continue;
      const rot = -0.24, ox = px * Math.cos(rot) - py * Math.sin(rot), oy = px * Math.sin(rot) + py * Math.cos(rot);
      const s = Rp * (0.3 + (py / Rp) * 0.1);
      c.globalAlpha = th * (front ? 0.95 : 0.5);
      c.drawImage(sp.glow, cx + ox - s / 2, cy + oy - s / 2, s, s);
      c.globalAlpha = th * (front ? 0.9 : 0.4);
      c.fillStyle = '#fff';
      c.beginPath(); c.arc(cx + ox, cy + oy, Rp * 0.032, 0, TAU); c.fill();
    }
    c.globalAlpha = 1;
  }

  function draw(now) {
    if (!sp) return;
    const c = ctx, Rp = sp.r;
    c.setTransform(1, 0, 0, 1, 0, 0);
    c.clearRect(0, 0, canvas.width, canvas.height);
    const bob = reduce ? 0 : Math.sin(now * 0.0014) * 0.018 * Rp;
    const cx = canvas.width / 2, cy = canvas.height * 0.5 + bob;
    const bs = 1 + X[BR];
    const gx = X[GX], gy = X[GY];

    if (opts.shadow !== false) {
      c.globalAlpha = 0.9 - (bob / Rp) * 4;
      const sw = Rp * 2.3 * (1 - bob / Rp * 2);
      c.drawImage(sp.sh, cx - sw / 2, cy + Rp * 1.18 - bob, sw, sw / 4);
      c.globalAlpha = 1;
    }
    const hl = Math.max(0, Math.min(1.2, X[HL]));
    if (hl > 0.02) { c.globalAlpha = Math.min(1, hl) * 0.5; const g = Rp * 3.1; c.drawImage(sp.glow, cx - g / 2, cy - g / 2, g, g); c.globalAlpha = 1; }
    if (ribbons) ribbon(c, now, false, cx, cy, Rp);
    const th = Math.max(0, Math.min(1, X[TH]));
    if (th > 0.02) orbit(c, now, false, cx, cy, Rp, th);

    const bw = sp.body.width * bs;
    c.drawImage(sp.body, cx + gx * Rp * 0.025 - bw / 2, cy - bw / 2, bw, bw);

    const wk = Math.max(0, Math.min(1, X[WK]));
    if (wk > 0.02) {
      const a = reduce ? 0.5 : now * 0.0022;
      c.globalAlpha = wk * 0.95; c.strokeStyle = live; c.lineWidth = Rp * 0.05; c.lineCap = 'round';
      c.beginPath(); c.arc(cx, cy, Rp * 1.07 * bs, a, a + 1.15); c.stroke();
      c.globalAlpha = wk * 0.4;
      c.beginPath(); c.arc(cx, cy, Rp * 1.07 * bs, a + PI, a + PI + 0.55); c.stroke();
      c.globalAlpha = 1;
    }

    const blink = Math.max(0, Math.min(1, X[BLINK]));
    const open = Math.max(0.05, X[OPEN]), sq = Math.max(0, X[SQ]);
    const ew = EYE_W * (1 + sq * 0.15 + blink * 0.22);
    const eh = Math.max(0.018, EYE_H * open * (1 - 0.93 * blink) * (1 - sq * 0.5));
    const tilt = X[TILT], err = Math.max(0, Math.min(1, X[ERR]));
    const fx = gx * 0.17, fy = gy * 0.12;
    const squeeze = 1 - 0.1 * Math.abs(gx);
    const sl = Math.max(0, Math.min(1, X[SL])), arcT = Math.max(0, Math.min(1, (blink - 0.8) / 0.2));
    const eyeGlowA = (dark.matches ? 0.95 : 0.7) * (1 - sl * 0.8);
    const k = Rp * bs;
    for (let i = 0; i < 2; i++) {
      const sg = i ? 1 : -1, a = -sg * tilt, co = Math.cos(a), si = Math.sin(a);
      const ex = cx + (sg * EYE_X * squeeze + fx) * k, ey = cy + (EYE_Y + fy) * k;
      if (eyeGlowA > 0.05 && arcT < 1) { const g = k * 0.78; c.globalAlpha = eyeGlowA * (1 - arcT); c.drawImage(sp.eye, ex - g / 2, ey - g / 2, g, g); c.globalAlpha = 1; }
      c.setTransform(k * co, k * si, -k * si, k * co, ex, ey);
      c.fillStyle = ink;
      if (arcT < 1) {
        c.globalAlpha = 1 - arcT;
        c.beginPath(); pill(c, ew * squeeze, eh); c.fill();
        if (err > 0.02) { c.globalAlpha = err * (1 - arcT); c.fillStyle = errc; c.fill(); c.fillStyle = ink; }
        c.globalAlpha = (1 - arcT) * 0.8 * (1 - blink);
        c.fillStyle = '#fff';
        c.beginPath(); c.ellipse(-ew * 0.12, -eh * 0.27, ew * 0.2, eh * 0.09, 0, 0, TAU); c.fill();
        c.globalAlpha = 1;
      }
      if (arcT > 0) {
        c.globalAlpha = arcT; c.strokeStyle = ink; c.lineWidth = ew * 0.5; c.lineCap = 'round';
        c.beginPath(); c.moveTo(-ew * 1.05, 0); c.quadraticCurveTo(0, sl * ew * 1.5, ew * 1.05, 0); c.stroke();
        c.globalAlpha = 1;
      }
    }
    const mw = Math.max(0.04, X[MW]), mo = Math.max(0, X[MO]), mc = X[MC];
    c.setTransform(k, 0, 0, k, cx + fx * 0.8 * k, cy + (MOUTH_Y + fy * 0.8) * k);
    const mth = 0.016 + mo;
    c.fillStyle = ink;
    c.beginPath();
    c.moveTo(-mw / 2, 0);
    c.quadraticCurveTo(0, mc * 2.2 - mth, mw / 2, 0);
    c.quadraticCurveTo(0, mc * 2.2 + mth, -mw / 2, 0);
    c.closePath();
    c.fill();
    if (err > 0.02) { c.globalAlpha = err; c.fillStyle = errc; c.fill(); c.globalAlpha = 1; }

    c.setTransform(1, 0, 0, 1, 0, 0);
    const sw2 = sp.spec.width * bs;
    c.drawImage(sp.spec, cx - Rp * 0.34 - gx * Rp * 0.035 - sw2 / 2, cy - Rp * 0.42 - gy * Rp * 0.03 - sw2 / 2, sw2, sw2);
    c.globalAlpha = dark.matches ? 0.3 : 0.5;
    c.fillStyle = '#fff';
    c.beginPath(); c.arc(cx + Rp * 0.5 - gx * Rp * 0.02, cy + Rp * 0.5, Rp * 0.045, 0, TAU); c.fill();
    c.globalAlpha = 1;

    if (th > 0.02) orbit(c, now, true, cx, cy, Rp, th);
    if (ribbons) ribbon(c, now, true, cx, cy, Rp);
  }

  function tick(now, dtS) {
    if (!running) return;
    const slowFrame = reduce || eff() === 'idle' || eff() === 'sleep';
    if (now - last < (slowFrame ? 66 : 15)) return;
    const dt = Math.min((now - last) / 1000, 0.066);
    last = now;
    frameLogic(now, dt);
    integrate(dt);
    draw(now);
  }

  function setState(name) {
    if (!ST[name] || name === state) return;
    const now = performance.now();
    if (name === 'error') { ret = state === 'error' ? ret : state; errUntil = now + 1500; }
    state = name;
    if (name !== 'idle') wake(now);
    scheduleBlink(now);
    nextSac = 0;
    if (name === 'thinking') V[GY] -= 0.5;
  }

  function lookAt(target) {
    if (!target) { lookMode = 0; lookEl = null; hasVec = false; return; }
    wake(performance.now());
    if (target.nodeType === 1) { lookMode = 1; lookEl = target; }
    else { lookMode = 2; lookEl = null; lookX = target.x; lookY = target.y; }
    lastMeasure = performance.now(); measure();
  }

  function pulse(kind) {
    const now = performance.now();
    wake(now);
    if (kind === 'blink') { T[BLINK] = 1; blinkRelease = now + 110; return; }
    if (kind === 'nod') { if (!reduce) V[GY] += 0.9; pOpen = -0.08; pUntil = now + 380; return; }
    if (kind === 'ok') { pOpen = -0.1; pMC = 0.04; pUntil = now + 1500; if (!reduce) V[GY] += 0.4; return; }
    if (kind === 'wince') { pTilt = 0.24; pOpen = -0.4; pSQ = 0.3; pMC = -0.12; pErr = 0; pUntil = now + 1000; return; }
    if (kind === 'error') { pTilt = 0.24; pOpen = -0.4; pSQ = 0.3; pMC = -0.12; pErr = 1; pUntil = now + 1100; return; }
    if (kind === 'startle') { pOpen = 0.3; pUntil = now + 320; if (!reduce) V[GY] -= 0.6; }
  }

  function start() {
    if (running) return;
    running = true;
    colors(); springs(); resize();
    const s = ST[eff()];
    for (const [i, v] of [[OPEN, s.open], [MW, s.mw], [MC, s.mc], [SL, s.sl], [BLINK, eff() === 'sleep' ? 1 : 0], [RB, s.rb], [TH, s.th], [WK, s.wk]]) { if (!hasVec) X[i] = T[i] = v; }
    last = performance.now(); lastActive = last; scheduleBlink(last);
    unsub = subscribe(tick);
    if (opts.autoSleep !== false) unIdle = onIdle(() => { asleep = true; blinkRelease = 0; }, () => wake(performance.now()));
  }

  function stop() { running = false; if (unsub) { unsub(); unsub = null; } if (unIdle) { unIdle(); unIdle = null; } }

  function destroy() {
    stop();
    ro?.disconnect();
    mq.removeEventListener('change', onMq);
    dark.removeEventListener('change', colors);
  }

  function onMq() { reduce = opts.reduceMotion ?? mq.matches; springs(); }

  mq.addEventListener('change', onMq);
  dark.addEventListener('change', colors);
  if (typeof ResizeObserver === 'function') { ro = new ResizeObserver(resize); ro.observe(canvas); }
  colors(); springs();
  X[OPEN] = T[OPEN] = ST.idle.open; X[MW] = T[MW] = ST.idle.mw; X[MC] = T[MC] = ST.idle.mc; X[RB] = T[RB] = ST.idle.rb;
  resize();

  return {
    setState,
    setLevel(m, o) { mic = Math.max(0, Math.min(1, m || 0)); out = Math.max(0, Math.min(1, o || 0)); },
    lookAt,
    pulse,
    start, stop, destroy, resize,
    sleep() { asleep = true; },
    get state() { return state; },
    get running() { return running; },
  };
}
