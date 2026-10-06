// Gzowo Concierge - Face: minimal canvas assistant face with spring-driven expressions, gaze, blink and audio-reactive speech.
const PI = Math.PI;
const GX = 0, GY = 1, HX = 2, HY = 3, OPEN = 4, BLINK = 5, TILT = 6, MW = 7, MC = 8, MO = 9, SQ = 10, ERR = 11, BR = 12, N = 13;
const RESP = [0.15, 0.15, 0.6, 0.6, 0.2, 0.065, 0.24, 0.26, 0.26, 0.055, 0.2, 0.32, 0.8];
const DAMP = [0.92, 0.92, 0.95, 0.78, 0.88, 0.9, 0.9, 0.92, 0.92, 0.95, 0.9, 1, 1];

const ST = {
  idle: { open: 0.95, tilt: 0, mw: 0.15, mc: 0.004, sq: 0, gx: 0, gy: 0, amp: 0.05, blink: [3200, 6800] },
  listening: { open: 1.06, tilt: 0, mw: 0.13, mc: 0, sq: 0, gx: 0, gy: 0.02, amp: 0.025, blink: [2600, 5200] },
  thinking: { open: 0.9, tilt: 0.04, mw: 0.11, mc: 0, sq: 0.04, gx: 0.5, gy: -0.55, amp: 0.16, blink: [3800, 7000] },
  speaking: { open: 1, tilt: 0, mw: 0.16, mc: 0.01, sq: 0, gx: 0, gy: 0, amp: 0.04, blink: [2800, 5600] },
  working: { open: 0.86, tilt: 0, mw: 0.12, mc: 0, sq: 0.1, gx: 0, gy: 0.3, amp: 0.3, blink: [3000, 6000] },
  alert: { open: 1.12, tilt: 0.045, mw: 0.12, mc: 0, sq: 0, gx: 0, gy: 0.28, amp: 0.012, blink: [4200, 8000] },
  error: { open: 0.62, tilt: 0.2, mw: 0.17, mc: -0.1, sq: 0.25, gx: 0, gy: 0.15, amp: 0.01, blink: [5000, 9000] },
};

const EYE_X = 0.19, EYE_W = 0.072, EYE_H = 0.185, EYE_Y = -0.07, MOUTH_Y = 0.3;

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

export function createFace(host, opts = {}) {
  const canvas = host.tagName === 'CANVAS' ? host : (() => { const c = document.createElement('canvas'); c.style.cssText = 'display:block;width:100%;height:100%'; host.appendChild(c); return c; })();
  const ctx = canvas.getContext('2d');
  const mq = matchMedia('(prefers-reduced-motion: reduce)');
  const dark = matchMedia('(prefers-color-scheme: dark)');
  let reduce = opts.reduceMotion ?? mq.matches;

  const X = new Float64Array(N), V = new Float64Array(N), T = new Float64Array(N), K = new Float64Array(N), C = new Float64Array(N);
  let state = 'idle', ret = 'idle', errUntil = 0;
  let mic = 0, out = 0, micS = 0, outS = 0;
  let running = false, raf = 0, last = 0, cw = 0, ch = 0, dpr = 1, S = 1, ro = null;
  let nextBlink = 0, blinkRelease = 0, doubleBlink = false, nextSac = 0, sx = 0, sy = 0, side = 1;
  let lookMode = 0, lookEl = null, lookX = 0, lookY = 0, vx = 0, vy = 0, hasVec = false, lastMeasure = 0;
  let pUntil = 0, pOpen = 0, pTilt = 0, pMC = 0, pSQ = 0, pErr = 0;
  let ink = opts.ink || '#f5f5f7', errc = opts.err || '#ff6a61';

  function colors() {
    if (opts.ink) return;
    const cs = getComputedStyle(canvas);
    ink = cs.getPropertyValue('--ink').trim() || (dark.matches ? '#f5f5f7' : '#1d1d1f');
    errc = cs.getPropertyValue('--err').trim() || '#d70015';
  }

  function springs() {
    const slow = reduce ? 1.9 : 1;
    for (let i = 0; i < N; i++) {
      const r = RESP[i] * (i === BLINK || i === MO ? 1 : slow);
      K[i] = (2 * PI / r) ** 2;
      C[i] = 4 * PI * DAMP[i] / r;
    }
  }

  function resize() {
    const r = canvas.getBoundingClientRect();
    cw = Math.max(1, r.width); ch = Math.max(1, r.height);
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(cw * dpr); canvas.height = Math.round(ch * dpr);
    S = Math.min(cw / 0.52, ch / 0.8);
    if (!running) draw();
  }

  function measure() {
    const r = canvas.getBoundingClientRect();
    const fx = r.left + r.width / 2, fy = r.top + r.height * 0.45;
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

  function scheduleBlink(now) {
    const b = ST[state].blink;
    nextBlink = now + b[0] + Math.random() * (b[1] - b[0]);
  }

  function frameLogic(now, dt) {
    const s = ST[state];
    if (state === 'error' && errUntil && now > errUntil) { errUntil = 0; setState(ret); return; }
    if (pUntil && now > pUntil) { pUntil = 0; pOpen = pTilt = pMC = pSQ = pErr = 0; }

    if (!reduce || state !== 'idle') {
      if (blinkRelease) { if (now > blinkRelease) { blinkRelease = 0; T[BLINK] = 0; if (doubleBlink) { doubleBlink = false; nextBlink = now + 140; } else scheduleBlink(now); } }
      else if (now > nextBlink) { T[BLINK] = 1; blinkRelease = now + (state === 'idle' ? 170 : 110); doubleBlink = !reduce && Math.random() < 0.16; }
    }

    if (lookMode && now - lastMeasure > 140) { lastMeasure = now; measure(); }

    if (now >= nextSac) {
      const amp = reduce ? 0 : (lookMode ? s.amp * 0.3 : s.amp);
      sx = (Math.random() * 2 - 1) * amp; sy = (Math.random() * 2 - 1) * amp * 0.7;
      if (state === 'thinking') { side = -side; }
      nextSac = now + (state === 'thinking' ? 1500 + Math.random() * 1700 : state === 'working' ? 900 + Math.random() * 1200 : 700 + Math.random() * 1900);
    }

    let bx = s.gx, by = s.gy;
    if (state === 'thinking' && !lookMode) bx = s.gx * side;
    if (lookMode && hasVec) { bx = vx; by = vy; }
    const gs = reduce ? 0.35 : 1;
    T[GX] = Math.max(-1, Math.min(1, bx + sx)) * gs;
    T[GY] = Math.max(-1, Math.min(1, by + sy)) * gs;

    const k = Math.min(1, dt * 14);
    micS += (mic - micS) * k;
    outS += (out - outS) * Math.min(1, dt * (out > outS ? 30 : 12));

    const L = state === 'listening', P = state === 'speaking';
    T[OPEN] = s.open + (L ? 0.14 * micS : 0) + pOpen;
    T[TILT] = s.tilt + pTilt;
    T[MW] = s.mw + (L ? 0.05 * micS : P ? 0.05 * outS : 0);
    T[MC] = s.mc + pMC;
    T[MO] = P ? Math.min(1, outS * 1.15) * 0.085 : L ? micS * 0.02 : 0;
    T[SQ] = s.sq + pSQ;
    T[ERR] = (state === 'error' ? 1 : 0) + pErr;
    T[BR] = reduce ? 0 : 0.012 * Math.sin(now * 0.0012) + (P ? outS * 0.012 : 0);
    const f = reduce ? 0.3 : 0.5;
    T[HX] = T[GX] * f * 0.09;
    T[HY] = T[GY] * f * 0.07;
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

  function draw() {
    const c = ctx;
    c.setTransform(1, 0, 0, 1, 0, 0);
    c.clearRect(0, 0, canvas.width, canvas.height);
    const bs = 1 + X[BR], cx = cw / 2, cy = ch * 0.47;
    const blink = Math.max(0, Math.min(1, X[BLINK]));
    const open = Math.max(0.05, X[OPEN]), sq = Math.max(0, X[SQ]);
    const ew = EYE_W * (1 + sq * 0.15 + blink * 0.22);
    const eh = Math.max(0.016, EYE_H * open * (1 - 0.93 * blink) * (1 - sq * 0.5));
    const tilt = X[TILT], err = Math.max(0, Math.min(1, X[ERR]));
    const k = dpr * S * bs;
    for (let i = 0; i < 2; i++) {
      const sg = i ? 1 : -1, a = -sg * tilt, co = Math.cos(a), si = Math.sin(a);
      const ex = sg * EYE_X + X[HX] + X[GX] * 0.04, ey = EYE_Y + X[HY] + X[GY] * 0.03;
      c.setTransform(k * co, k * si, -k * si, k * co, dpr * (cx + ex * S * bs), dpr * (cy + ey * S * bs));
      c.globalAlpha = 0.03;
      c.fillStyle = ink;
      c.beginPath(); pill(c, ew * 1.4, eh * 1.14); c.fill();
      c.globalAlpha = 1;
      c.beginPath(); pill(c, ew, eh); c.fill();
      if (err > 0.02) { c.globalAlpha = err; c.fillStyle = errc; c.fill(); c.globalAlpha = 1; }
    }
    const mw = Math.max(0.04, X[MW]), mo = Math.max(0, X[MO]), mc = X[MC];
    const my = MOUTH_Y + X[HY] * 0.8, mx = X[HX] * 0.8;
    c.setTransform(k, 0, 0, k, dpr * (cx + mx * S * bs), dpr * (cy + my * S * bs));
    const th = 0.011 + mo;
    c.fillStyle = ink;
    c.beginPath();
    c.moveTo(-mw / 2, 0);
    c.quadraticCurveTo(0, mc * 2.2 - th, mw / 2, 0);
    c.quadraticCurveTo(0, mc * 2.2 + th, -mw / 2, 0);
    c.closePath();
    c.fill();
    if (err > 0.02) { c.globalAlpha = err; c.fillStyle = errc; c.fill(); c.globalAlpha = 1; }
  }

  function tick(now) {
    if (!running) return;
    raf = requestAnimationFrame(tick);
    const slowFrame = reduce || state === 'idle';
    if (now - last < (slowFrame ? 32 : 15)) return;
    const dt = Math.min((now - last) / 1000, 0.066);
    last = now;
    frameLogic(now, dt);
    integrate(dt);
    draw();
  }

  function onVisibility() {
    if (!running) return;
    if (document.hidden) { cancelAnimationFrame(raf); raf = 0; }
    else if (!raf) { last = performance.now(); raf = requestAnimationFrame(tick); }
  }

  function setState(name) {
    if (!ST[name] || name === state) return;
    const now = performance.now();
    if (name === 'error') { ret = state === 'error' ? ret : state; errUntil = now + 1500; }
    state = name;
    scheduleBlink(now);
    nextSac = 0;
    if (name === 'thinking') V[GY] -= 0.5;
  }

  function lookAt(target) {
    if (!target) { lookMode = 0; lookEl = null; hasVec = false; return; }
    if (target.nodeType === 1) { lookMode = 1; lookEl = target; }
    else { lookMode = 2; lookEl = null; lookX = target.x; lookY = target.y; }
    lastMeasure = performance.now(); measure();
  }

  function pulse(kind) {
    const now = performance.now();
    if (kind === 'blink') { T[BLINK] = 1; blinkRelease = now + 110; return; }
    if (kind === 'nod') { if (!reduce) V[HY] += 0.9; pOpen = -0.08; pUntil = now + 380; return; }
    if (kind === 'ok') { pOpen = -0.1; pMC = 0.032; pUntil = now + 1500; if (!reduce) V[HY] += 0.4; return; }
    if (kind === 'wince') { pTilt = 0.24; pOpen = -0.4; pSQ = 0.3; pMC = -0.12; pErr = 0; pUntil = now + 1000; return; }
    if (kind === 'error') { pTilt = 0.24; pOpen = -0.4; pSQ = 0.3; pMC = -0.12; pErr = 1; pUntil = now + 1100; return; }
    if (kind === 'startle') { pOpen = 0.3; pUntil = now + 320; if (!reduce) V[HY] -= 0.6; }
  }

  function start() {
    if (running) return;
    running = true;
    colors(); springs(); resize();
    const s = ST[state];
    if (!hasVec) { X[OPEN] = T[OPEN] = s.open; X[MW] = T[MW] = s.mw; X[MC] = T[MC] = s.mc; }
    last = performance.now(); scheduleBlink(last);
    raf = requestAnimationFrame(tick);
  }

  function stop() { running = false; cancelAnimationFrame(raf); raf = 0; }

  function destroy() {
    stop();
    ro?.disconnect();
    document.removeEventListener('visibilitychange', onVisibility);
    mq.removeEventListener('change', onMq);
    dark.removeEventListener('change', colors);
  }

  function onMq() { reduce = opts.reduceMotion ?? mq.matches; springs(); }

  document.addEventListener('visibilitychange', onVisibility);
  mq.addEventListener('change', onMq);
  dark.addEventListener('change', colors);
  if (typeof ResizeObserver === 'function') { ro = new ResizeObserver(resize); ro.observe(canvas); }
  colors(); springs();
  X[OPEN] = T[OPEN] = ST.idle.open; X[MW] = T[MW] = ST.idle.mw; X[MC] = T[MC] = ST.idle.mc;
  resize();

  return {
    setState,
    setLevel(m, o) { mic = Math.max(0, Math.min(1, m || 0)); out = Math.max(0, Math.min(1, o || 0)); },
    lookAt,
    pulse,
    start, stop, destroy, resize,
    get state() { return state; },
    get running() { return running; },
  };
}
