// Gzowo Concierge - Face: the flat black and white Concierge bot, eight shapes and sixteen eye-only faces on a shared ticker; spring body, cursor gaze, blinks, poke wobble, state to face mapping, sleep.
import { subscribe, onIdle, poke as wakeTicker } from './ui/ticker.js';
import { SHAPE_BY_ID, SHAPE_N, FACES } from './bot-data.js';
import { makeGfx, newEyes, layoutEyes, faceValues, paintBot } from './bot-paint.js';
import { getAvatar, onAvatar } from './ui/avatar.js';

const PI = Math.PI;
const SQ = 0, BX = 1, BY = 2, ROT = 3, YAW = 4, PIT = 5, ROLL = 6, SPL = 7, W0 = 8, H0 = 9, T0 = 10, O0 = 11, W1 = 12, H1 = 13, T1 = 14, O1 = 15, BL = 16, SL = 17, ZZ = 18, N = 19;
const RESP = [0.34, 0.3, 0.38, 0.34, 0.14, 0.14, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.06, 0.5, 0.5];
const DAMP = [0.34, 0.8, 0.5, 0.55, 0.9, 0.9, 0.85, 0.85, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.9, 1, 1];
const WT = [1, 1, 1, 1, 0.02, 0.02, 0.02, 0.02, 1, 1, 0.02, 1, 1, 1, 0.02, 1, 1, 1, 1];
const BLINKS = { idle: [3200, 6800], listening: [2600, 5200], thinking: [3800, 7000], speaking: [2800, 5600], working: [3000, 6000], alert: [4200, 8000], error: [5000, 9000] };
const AMP = { idle: 5, listening: 3, thinking: 12, speaking: 4, working: 8, alert: 1, error: 1, sleep: 0 };
const SLEEP_MS = 20000;
const STATES = ['idle', 'listening', 'thinking', 'speaking', 'working', 'alert', 'error', 'sleep'];
let greeted = false;
const debugHook = new URLSearchParams(location.search).get('debug') === '1';

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

export function followPointer(face) {
  if (!matchMedia('(hover: hover) and (pointer: fine)').matches) return () => {};
  let t = 0, idle = 0;
  const on = e => {
    const n = performance.now();
    if (n - t < 60) return;
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
  let reduce = opts.reduceMotion ?? mq.matches;

  const X = new Float64Array(N), V = new Float64Array(N), T = new Float64Array(N), K = new Float64Array(N), C = new Float64Array(N);
  const FV = {}, eyes = newEyes();
  const S = { shape: null, radii: null, cx: 0, groundY: 0, dy: 0, rot: 0, sx: 1, sy: 1, hop: 0, eyes, blink: 0, sleep: 0, zz: 0, t: 0 };
  let state = 'idle', ret = 'idle', errUntil = 0, asleep = false, lastActive = performance.now();
  let mic = 0, out = 0, micS = 0, outS = 0;
  let running = false, unsub = null, unIdle = null, unAv = null, last = 0, cw = 1, ch = 1, dpr = 1, R = 50, ro = null, gfx = null, energy = 1;
  let nextBlink = 0, blinkRelease = 0, doubleBlink = false, nextSac = 0, sx = 0, sy = 0, flip = false, nextFlip = 0;
  let lookMode = 0, lookEl = null, lookX = 0, lookY = 0, vx = 0, vy = 0, hasVec = false, lastMeasure = 0;
  let forceFace = null, forceUntil = 0, seq = null, own = false;
  let shapeId = opts.shape || getAvatar().shape, colorVal = opts.color || getAvatar().color;
  const curR = new Float32Array(SHAPE_N);
  let tgtR = SHAPE_BY_ID.get(shapeId).radii, morph = false;
  curR.set(tgtR);
  S.shape = SHAPE_BY_ID.get(shapeId);
  S.radii = curR;

  function buildGfx() { gfx = makeGfx(ctx, R, colorVal, dark.matches); }

  function springs() {
    const slow = reduce ? 1.9 : 1;
    for (let i = 0; i < N; i++) {
      const r = RESP[i] * (i === BL ? 1 : slow);
      K[i] = (2 * PI / r) ** 2;
      C[i] = 4 * PI * DAMP[i] / r;
    }
  }

  function resize() {
    const r = canvas.getBoundingClientRect();
    cw = Math.max(1, r.width); ch = Math.max(1, r.height);
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(cw * dpr); canvas.height = Math.round(ch * dpr);
    R = Math.min(cw, ch) * 0.34;
    buildGfx();
    if (!running) draw(performance.now());
  }

  function init() {
    const f = FACES.neutral;
    const set = [[YAW, f.yaw], [PIT, f.pit], [ROLL, f.roll], [SPL, f.split], [W0, f.eyes[0][0]], [H0, f.eyes[0][1]], [T0, f.eyes[0][2]], [O0, f.eyes[0][3]], [W1, f.eyes[1][0]], [H1, f.eyes[1][1]], [T1, f.eyes[1][2]], [O1, f.eyes[1][3]]];
    for (const [i, v] of set) X[i] = T[i] = v;
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
    const m = Math.min(1, d / Math.max(140, r.width * 0.55));
    vx = dx / d * m; vy = clamp(dy / d * m, -0.9, 0.9);
    hasVec = true;
  }

  const eff = () => (state === 'idle' && asleep ? 'sleep' : state);

  function scheduleBlink(now) {
    const b = BLINKS[eff()] || BLINKS.idle;
    nextBlink = now + b[0] + Math.random() * (b[1] - b[0]);
  }

  function startSeq(steps, now) { seq = { t0: now, steps }; }

  function seqFace(now) {
    if (!seq) return null;
    let t = now - seq.t0;
    for (const [ms, name] of seq.steps) { if (t < ms) return name; t -= ms; }
    seq = null;
    return null;
  }

  function wake(now) {
    lastActive = now;
    if (asleep) { asleep = false; scheduleBlink(now); nextSac = 0; startSeq([[420, 'surprised']], now); if (!reduce) { V[BY] += 2.2; V[SQ] -= 1.4; } }
  }

  function frameLogic(now, dt) {
    const e = eff();
    if (state === 'error' && errUntil && now > errUntil) { errUntil = 0; setState(ret); return; }
    if (state === 'idle' && !asleep && opts.autoSleep !== false && now - lastActive > SLEEP_MS) { asleep = true; blinkRelease = 0; }
    if (forceFace && forceUntil && now > forceUntil) { forceFace = null; forceUntil = 0; }

    if (e === 'sleep') T[BL] = 1;
    else if (!reduce || state !== 'idle') {
      if (blinkRelease) { if (now > blinkRelease) { blinkRelease = 0; T[BL] = 0; if (doubleBlink) { doubleBlink = false; nextBlink = now + 140; } else scheduleBlink(now); } }
      else if (now > nextBlink) { T[BL] = 1; blinkRelease = now + 120; doubleBlink = !reduce && Math.random() < 0.16; }
    } else T[BL] = 0;

    if (lookMode && now - lastMeasure > 120) { lastMeasure = now; measure(); }

    if (now >= nextSac) {
      const amp = reduce ? 0 : (lookMode ? AMP[e] * 0.3 : AMP[e]);
      sx = (Math.random() * 2 - 1) * amp; sy = (Math.random() * 2 - 1) * amp * 0.6;
      nextSac = now + (e === 'thinking' ? 700 + Math.random() * 900 : 700 + Math.random() * 1900);
    }
    if (e === 'thinking' && now > nextFlip) { flip = !flip; nextFlip = now + 1300 + Math.random() * 1200; }

    const k = Math.min(1, dt * 14);
    micS += (mic - micS) * k;
    outS += (out - outS) * Math.min(1, dt * (out > outS ? 30 : 12));
    if (mic > 0.08 || out > 0.04) lastActive = now;

    let name;
    if (forceFace) name = forceFace;
    else if ((name = seqFace(now))) name = name;
    else name = e === 'listening' || e === 'speaking' || e === 'working' ? 'attentive' : e === 'thinking' ? (flip ? 'curious' : 'suspicious') : e === 'alert' ? 'curious' : e === 'error' ? 'scared' : e === 'sleep' ? 'sleepy' : 'neutral';

    const gs = reduce ? 0.35 : 1, tracking = lookMode && hasVec && e !== 'sleep';
    let lx = tracking ? vx : 0, ly = tracking ? vy : 0;
    const gdx = (lx * 22 + sx * 0.7 + (e === 'thinking' ? (flip ? 10 : -10) : 0)) * gs;
    const gdy = (ly * 16 + sy * 0.7 + (e === 'thinking' ? -8 : 0) - (e === 'speaking' ? outS * 4 : 0)) * gs;
    faceValues(FV, name, gdx, gdy);
    T[YAW] = FV.yaw; T[PIT] = FV.pit; T[ROLL] = FV.roll + (e === 'thinking' ? (flip ? 5 : -5) : 0) * gs; T[SPL] = FV.split;
    let ew = 1, eh = 1;
    if (e === 'listening') { eh = 1 + 0.32 * micS; ew = 1 + 0.14 * micS; }
    else if (e === 'speaking') { eh = 1 + 0.16 * outS; }
    T[W0] = FV.w0 * ew; T[H0] = FV.h0 * eh; T[T0] = FV.t0; T[O0] = FV.o0;
    T[W1] = FV.w1 * ew; T[H1] = FV.h1 * eh; T[T1] = FV.t1; T[O1] = FV.o1;

    const body = reduce ? 0.3 : 1;
    T[ROT] = (lx * 0.075 + (e === 'thinking' ? (flip ? 0.05 : -0.05) : 0) + (e === 'alert' ? (tracking ? lx * 0.16 : 0.09) : 0) + (e === 'sleep' ? 0.06 : 0)) * body;
    T[BX] = lx * 0.05 * body;
    T[BY] = e === 'working' && !reduce ? Math.sin(now * 0.0062) * 0.018 : e === 'speaking' ? outS * 0.035 * body : 0;
    T[SQ] = (e === 'speaking' ? -outS * 0.13 : e === 'listening' ? -micS * 0.07 : e === 'sleep' ? 0.05 : 0) * body;
    T[SL] = e === 'sleep' ? 1 : 0;
    T[ZZ] = e === 'sleep' && !reduce ? 1 : 0;
  }

  function integrate(dt) {
    const n = Math.max(1, Math.ceil(dt / 0.008)), h = dt / n;
    for (let s = 0; s < n; s++) {
      for (let i = 0; i < N; i++) {
        V[i] += (-K[i] * (X[i] - T[i]) - C[i] * V[i]) * h;
        X[i] += V[i] * h;
      }
    }
    let en = 0;
    for (let i = 0; i < N; i++) en += Math.abs(V[i]) * WT[i] + Math.abs(X[i] - T[i]) * WT[i] * 4;
    energy = en;
  }

  function stepMorph(dt) {
    if (!morph) return;
    const k = 1 - Math.exp(-dt * 13);
    let d = 0;
    for (let i = 0; i < SHAPE_N; i++) { const df = tgtR[i] - curR[i]; curR[i] += df * k; d += Math.abs(df); }
    if (d < 0.004) { curR.set(tgtR); morph = false; }
  }

  function draw(now) {
    if (!gfx) return;
    const shape = S.shape;
    const br = reduce ? 0 : (asleep ? 0.024 : 0.011) * Math.sin(now * (asleep ? 0.0007 : 0.0013));
    const q = clamp(X[SQ], -0.3, 0.45);
    S.cx = cw / 2 + X[BX] * R;
    S.groundY = ch * 0.47 + (shape.bottom - shape.mid) * R;
    S.sx = (1 + q * 0.6) * (1 - br * 0.5);
    S.sy = (1 - q * 0.5) * (1 + br);
    S.rot = X[ROT];
    S.hop = X[BY];
    S.dy = 0;
    S.blink = clamp(X[BL], 0, 1);
    S.sleep = clamp(X[SL], 0, 1);
    S.zz = clamp(X[ZZ], 0, 1);
    S.t = now;
    FV.yaw = X[YAW]; FV.pit = X[PIT]; FV.roll = X[ROLL]; FV.split = X[SPL];
    FV.w0 = Math.max(0.02, X[W0]); FV.h0 = Math.max(0.02, X[H0]); FV.t0 = X[T0]; FV.o0 = clamp(X[O0], 0.05, 1.1);
    FV.w1 = Math.max(0.02, X[W1]); FV.h1 = Math.max(0.02, X[H1]); FV.t1 = X[T1]; FV.o1 = clamp(X[O1], 0.05, 1.1);
    layoutEyes(eyes, FV, curR, 1, 1, S.blink);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cw, ch);
    paintBot(ctx, gfx, S);
  }

  function tick(now) {
    if (!running) return;
    const e = eff();
    const calm = reduce || ((e === 'idle' || e === 'sleep') && energy < 0.04 && !morph && !seq && !forceFace);
    if (now - last < (calm ? 66 : 15)) return;
    const dt = Math.min((now - last) / 1000, 0.066);
    last = now;
    frameLogic(now, dt);
    integrate(dt);
    stepMorph(dt);
    draw(now);
  }

  function setState(name) {
    if (!STATES.includes(name) || name === state) return;
    const now = performance.now();
    if (name === 'error') { ret = state === 'error' ? ret : state; errUntil = now + 1500; startSeq([[1300, 'scared']], now); if (!reduce) { V[SQ] -= 2.2; V[BY] += 2; } }
    state = name;
    if (name !== 'idle') wake(now);
    scheduleBlink(now);
    nextSac = 0; nextFlip = 0;
    if (name === 'listening' && !reduce) V[BY] += 1.3;
    if (name === 'alert' && !reduce) { V[SQ] -= 1.4; V[BY] += 1.4; }
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
    const m = reduce ? 0 : 1;
    if (kind === 'blink') { T[BL] = 1; blinkRelease = now + 120; return; }
    if (kind === 'nod') { V[PIT] += 300 * m; V[SQ] += 1.1 * m; return; }
    if (kind === 'ok') { startSeq([[900, 'happy'], [900, 'proud']], now); V[BY] += 2.6 * m; V[SQ] += 1.4 * m; return; }
    if (kind === 'wince') { startSeq([[1100, 'sad']], now); V[SQ] += 1.8 * m; return; }
    if (kind === 'error') { startSeq([[1200, 'scared']], now); V[SQ] -= 2.4 * m; V[BY] += 2 * m; return; }
    if (kind === 'confused') { startSeq([[1100, 'confused']], now); V[ROT] += 2.4 * m; return; }
    if (kind === 'startle') { startSeq([[650, 'surprised']], now); V[BY] += 3.2 * m; V[SQ] -= 2 * m; return; }
    if (kind === 'hop') { startSeq([[900, 'happy']], now); V[BY] += 4 * m; V[SQ] += 1.2 * m; return; }
    if (kind === 'wiggle') { startSeq([[800, 'excited']], now); V[ROT] += 2.8 * m; V[SQ] += 1.6 * m; return; }
    if (kind === 'greet') { startSeq([[1500, 'excited']], now); V[BY] += 4.2 * m; V[SQ] += 1.5 * m; }
  }

  function poke() {
    const now = performance.now();
    wakeTicker(true);
    const was = asleep;
    wake(now);
    if (was) return;
    startSeq([[520, 'surprised']], now);
    if (!reduce) { V[SQ] += 3.4; V[ROT] += (Math.random() < 0.5 ? -1 : 1) * 1.3; V[BY] += 1.2; }
  }

  function setShape(id) {
    own = true;
    const s = SHAPE_BY_ID.get(id);
    if (!s || id === shapeId) return;
    shapeId = id;
    S.shape = s; tgtR = s.radii; morph = !reduce;
    if (reduce) curR.set(tgtR);
    else V[SQ] += 2.4;
    energy = 1;
    if (!running) draw(performance.now());
  }

  function setColor(c) {
    own = true;
    colorVal = c;
    buildGfx();
    energy = 1;
    if (!running) draw(performance.now());
  }

  function setFace(name, hold = 0) {
    if (!name || !FACES[name]) { forceFace = null; forceUntil = 0; return; }
    wake(performance.now());
    forceFace = name; forceUntil = hold ? performance.now() + hold : 0;
    energy = 1;
    if (!reduce) V[SQ] += 0.8;
    if (!running) { frameLogic(performance.now(), 0.016); for (let i = 0; i < N; i++) X[i] = T[i]; draw(performance.now()); }
  }

  function start() {
    if (running) return;
    running = true;
    springs(); resize();
    last = performance.now(); lastActive = last; scheduleBlink(last);
    unsub = subscribe(tick);
    if (opts.autoSleep !== false) unIdle = onIdle(() => { asleep = true; blinkRelease = 0; }, () => wake(performance.now()));
    if (!greeted && opts.greet !== false) { greeted = true; setTimeout(() => { if (running) pulse('greet'); }, 380); }
  }

  function stop() {
    running = false;
    if (unsub) { unsub(); unsub = null; }
    if (unIdle) { unIdle(); unIdle = null; }
  }

  function destroy() {
    stop();
    ro?.disconnect();
    unAv?.();
    canvas.removeEventListener('pointerdown', poke);
    mq.removeEventListener('change', onMq);
    dark.removeEventListener('change', onDark);
  }

  function onMq() { reduce = opts.reduceMotion ?? mq.matches; springs(); }
  function onDark() { buildGfx(); if (!running) draw(performance.now()); }

  mq.addEventListener('change', onMq);
  dark.addEventListener('change', onDark);
  if (opts.poke !== false) canvas.addEventListener('pointerdown', poke);
  if (opts.avatar !== false && !opts.shape && !opts.color) {
    unAv = onAvatar(a => { if (!own) { setShape(a.shape); setColor(a.color); own = false; } });
  }
  if (typeof ResizeObserver === 'function') { ro = new ResizeObserver(resize); ro.observe(canvas); }
  init();
  springs();
  resize();

  const api = {
    setState, lookAt, pulse, poke, setShape, setColor, setFace,
    setLevel(m, o) { mic = clamp(m || 0, 0, 1); out = clamp(o || 0, 0, 1); },
    start, stop, destroy, resize,
    sleep() { asleep = true; },
    get state() { return state; },
    get running() { return running; },
    get shape() { return shapeId; },
    get color() { return colorVal; },
  };
  if (debugHook) { (window.__faces ||= []).push({ canvas, api }); }
  return api;
}
