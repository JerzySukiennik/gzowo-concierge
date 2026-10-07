// Gzowo Concierge - voice glow: a light that rises from the bottom with mic and voice level and sweeps side to side while thinking; transform and opacity only.
import { subscribe } from './ticker.js';

const TARGET = {
  idle: [0.16, 0.4, 0], connecting: [0.22, 0.55, 0], listening: [0.3, 0.62, 0], thinking: [0.5, 0.9, 0.36],
  working: [0.4, 0.7, 0.22], speaking: [0.34, 0.7, 0], alert: [0.34, 0.7, 0], error: [0.12, 0.28, 0],
};

export function createGlow(root) {
  const [base, core, a, b] = root.querySelectorAll('.gl');
  const mq = matchMedia('(prefers-reduced-motion: reduce)');
  let state = 'idle', mic = 0, out = 0, unsub = null, last = 0, W = 400;
  const cur = { h: 0.14, o: 0.3, sw: 0, lv: 0 };
  const w = { bh: -1, bo: -1, ch: -1, co: -1, ax: -9999, ah: -1, ao: -1, bx: -9999 };

  function paint(t, dt) {
    const [h0, o0, sw0] = TARGET[state] || TARGET.idle;
    const lv = state === 'listening' ? mic : state === 'speaking' ? out : 0;
    const k = Math.min(1, dt * 7);
    cur.lv += (lv - cur.lv) * Math.min(1, dt * (lv > cur.lv ? 22 : 7));
    cur.h += (h0 + cur.lv * (state === 'speaking' ? 0.6 : 0.55) - cur.h) * k;
    cur.o += (Math.min(1, o0 + cur.lv * 0.42) - cur.o) * k;
    cur.sw += (sw0 - cur.sw) * Math.min(1, dt * 3);
    const pulse = state === 'alert' ? 0.05 * Math.sin(t * 0.0022) : state === 'connecting' ? 0.04 * Math.sin(t * 0.004) : 0;
    const bh = Math.max(0.02, cur.h + pulse);
    const ax = Math.sin(t * 0.00115) * cur.sw * W, bx = -Math.sin(t * 0.00115 + 0.9) * cur.sw * W;
    const set = (el, key, v, eps, fn) => { if (Math.abs(v - w[key]) > eps) { w[key] = v; fn(); } };
    set(base, 'bh', bh, 0.004, () => { base.style.transform = 'scale3d(1,' + bh.toFixed(3) + ',1)'; });
    set(base, 'bo', cur.o, 0.004, () => { base.style.opacity = cur.o.toFixed(3); });
    const chh = bh * 1.15;
    set(core, 'ch', chh, 0.004, () => { core.style.transform = 'scale3d(' + (0.7 + cur.lv * 0.5).toFixed(3) + ',' + chh.toFixed(3) + ',1)'; });
    set(core, 'co', cur.o, 0.004, () => { core.style.opacity = Math.min(1, cur.o * 0.9).toFixed(3); });
    set(a, 'ax', ax, 0.5, () => { a.style.transform = 'translate3d(' + ax.toFixed(1) + 'px,0,0) scale3d(1,' + (bh * 0.9).toFixed(3) + ',1)'; });
    set(a, 'ao', cur.sw, 0.004, () => { a.style.opacity = Math.min(1, 0.15 + cur.sw * 2).toFixed(3); b.style.opacity = a.style.opacity; });
    set(b, 'bx', bx, 0.5, () => { b.style.transform = 'translate3d(' + bx.toFixed(1) + 'px,0,0) scale3d(1,' + (bh * 0.9).toFixed(3) + ',1)'; });
  }

  function tick(now) {
    const dt = Math.min((now - last) / 1000, 0.066);
    last = now;
    paint(now, dt);
  }

  function clearInline() { [base, core, a, b].forEach(e => { e.style.transform = ''; e.style.opacity = ''; }); for (const k in w) w[k] = k === 'ax' || k === 'bx' ? -9999 : -1; }

  function start() {
    if (unsub) return;
    root.dataset.s = state;
    W = root.clientWidth || 400;
    if (mq.matches) { clearInline(); return; }
    last = performance.now();
    unsub = subscribe(tick);
  }

  function stop() { if (unsub) { unsub(); unsub = null; } }

  mq.addEventListener('change', () => { if (unsub || root.dataset.s) { stop(); start(); } });
  addEventListener('resize', () => { W = root.clientWidth || W; });

  return {
    start, stop,
    setState(s) { if (s === state) return; state = TARGET[s] ? s : 'idle'; root.dataset.s = state; },
    setLevel(m, o) { mic = Math.max(0, Math.min(1, m || 0)); out = Math.max(0, Math.min(1, o || 0)); },
  };
}
