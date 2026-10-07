// Gzowo Concierge - shared rAF ticker: one loop for faces and glow; pauses when hidden or blurred, parks after 20 s without interaction, wakes on input or transport events, probes cadence to fall back to a lite look.
const root = document.documentElement;
const qs = new URLSearchParams(location.search);
const forced = qs.get('fx');
const subs = new Set(), sleepers = new Set(), wakers = new Set();
const ring = new Float32Array(120);
const perf = qs.get('perf') === '1' ? new Float32Array(40000) : null;
const IDLE_MS = qs.get('idle') ? Number(qs.get('idle')) : 20000;
let raf = 0, last = 0, ri = 0, seen = 0, bad = 0, probing = 0, held = 0, lastAct = performance.now(), slept = false, parked = false, away = false, lastPoke = 0;

if (perf) { window.__perf = { buf: perf, n: 0 }; }
if (forced === 'lite') root.dataset.fx = 'lite';

function goLite() {
  if (forced === 'full' || root.dataset.fx === 'lite') return;
  root.dataset.fx = 'lite';
  dispatchEvent(new Event('fxchange'));
}

function judge() {
  const a = Array.from(ring).sort((x, y) => x - y);
  const med = a[60];
  if (med > 29) { if (++bad >= 2) goLite(); } else bad = 0;
}

function park() {
  parked = true;
  cancelAnimationFrame(raf); raf = 0;
  root.dataset.idle = '1';
}

function loop(now) {
  raf = requestAnimationFrame(loop);
  const dt = now - last;
  last = now;
  if (dt > 0 && dt < 250) {
    if (perf && window.__perf.n < perf.length) perf[window.__perf.n++] = dt;
    if (++seen > 60) { ring[ri] = dt; ri = (ri + 1) % 120; if (ri === 0) judge(); }
  }
  const s = Math.min(dt / 1000, 0.066);
  for (const fn of subs) fn(now, s);
  if (!held && subs.size) {
    const idle = now - lastAct;
    if (!slept && idle > IDLE_MS) { slept = true; sleepers.forEach(f => f()); }
    else if (slept && idle > IDLE_MS + 1800) { park(); return; }
  }
  if (!subs.size && now > probing) { cancelAnimationFrame(raf); raf = 0; }
}

function kick() {
  if (raf || document.hidden || away || parked) return;
  last = performance.now();
  raf = requestAnimationFrame(loop);
}

function pause(on) {
  away = on;
  if (on) { cancelAnimationFrame(raf); raf = 0; root.dataset.hidden = '1'; }
  else { delete root.dataset.hidden; seen = 0; lastAct = performance.now(); poke(true); if (subs.size || performance.now() < probing) kick(); }
}

export function poke(force) {
  const now = performance.now();
  if (!force && now - lastPoke < 150) return;
  lastPoke = now; lastAct = now;
  if (slept || parked) {
    slept = false;
    wakers.forEach(f => f());
    if (parked) { parked = false; delete root.dataset.idle; kick(); }
  }
}

document.addEventListener('visibilitychange', () => pause(document.hidden));
addEventListener('blur', () => pause(true));
addEventListener('focus', () => { if (!document.hidden) pause(false); });
['pointermove', 'pointerdown', 'keydown', 'touchstart', 'wheel'].forEach(t => addEventListener(t, () => poke(), { passive: true, capture: true }));

export function subscribe(fn) {
  subs.add(fn);
  kick();
  return () => { subs.delete(fn); };
}

export function onIdle(sleepFn, wakeFn) {
  sleepers.add(sleepFn); wakers.add(wakeFn);
  return () => { sleepers.delete(sleepFn); wakers.delete(wakeFn); };
}

export function hold(on) {
  held = Math.max(0, held + (on ? 1 : -1));
  if (on) poke(true);
}

export function probe(ms = 5000) {
  probing = performance.now() + ms;
  kick();
}

export const isLite = () => root.dataset.fx === 'lite';
