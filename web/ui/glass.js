// Gzowo Concierge - glass helpers: fx switches (goo on/off), pointer and press sheen, spring easings, SVG goo shape layers for small isolated containers.
const root = document.documentElement;
const qs = new URLSearchParams(location.search);
export const reduceMq = matchMedia('(prefers-reduced-motion: reduce)');
const hoverMq = matchMedia('(hover: hover) and (pointer: fine)');
const hasLinear = typeof CSS !== 'undefined' && CSS.supports && CSS.supports('transition-timing-function', 'linear(0, 1)');

export const EASE = 'cubic-bezier(.22, 1, .36, 1)';
export const SPRING = hasLinear ? 'linear(0, 0.1, 0.287, 0.473, 0.627, 0.743, 0.827, 0.886, 0.925, 0.952, 0.969, 0.98, 0.987, 0.992, 0.995, 0.997, 0.998, 1)' : EASE;
export const SPRING_B = hasLinear ? 'linear(0, 0.097, 0.302, 0.523, 0.713, 0.856, 0.951, 1.006, 1.031, 1.038, 1.035, 1.027, 1.019, 1.012, 1.006, 1.002, 1, 0.999, 1)' : 'cubic-bezier(.34, 1.4, .5, 1)';

export const gooOn = () => root.dataset.goo === '1';

export function initFx() {
  const apply = () => {
    root.dataset.goo = !reduceMq.matches && root.dataset.fx !== 'lite' && qs.get('goo') !== '0' ? '1' : '0';
    dispatchEvent(new Event('gooapply'));
  };
  reduceMq.addEventListener('change', apply);
  addEventListener('fxchange', apply);
  apply();
}

export function initSheen() {
  let cur = null, rect = null, stale = true, px = 0, py = 0, raf = 0, hold = 0;
  const set = (el, x, y, on) => {
    el.style.setProperty('--mx', x.toFixed(1) + 'px');
    el.style.setProperty('--my', y.toFixed(1) + 'px');
    el.style.setProperty('--sheen', on ? '1' : '');
  };
  const frame = () => {
    raf = 0;
    if (!cur) return;
    if (stale) { rect = cur.getBoundingClientRect(); stale = false; }
    set(cur, px - rect.left, py - rect.top, true);
  };
  const release = el => { if (el) { el.style.removeProperty('--sheen'); el.style.removeProperty('--mx'); el.style.removeProperty('--my'); } };
  if (hoverMq.matches) {
    document.addEventListener('pointerover', e => {
      const g = e.target.closest && e.target.closest('.glass, .btn, .pill, .icon-btn, .ccard, .sug');
      if (g === cur) return;
      release(cur);
      cur = g; stale = true;
    }, { passive: true });
    document.addEventListener('pointermove', e => {
      if (!cur || e.pointerType === 'touch') return;
      px = e.clientX; py = e.clientY;
      if (!raf) raf = requestAnimationFrame(frame);
    }, { passive: true });
    document.addEventListener('scroll', () => { stale = true; }, { passive: true, capture: true });
    addEventListener('resize', () => { stale = true; });
  }
  document.addEventListener('pointerdown', e => {
    const g = e.target.closest && e.target.closest('.glass, .btn, .pill, .icon-btn, .ccard, .sug, #send');
    if (!g) return;
    const r = g.getBoundingClientRect();
    set(g, e.clientX - r.left, e.clientY - r.top, true);
    clearTimeout(hold);
    const end = () => { hold = setTimeout(() => { if (g !== cur) release(g); }, 380); removeEventListener('pointerup', end, true); removeEventListener('pointercancel', end, true); };
    addEventListener('pointerup', end, true); addEventListener('pointercancel', end, true);
  }, { passive: true });
}

export function createGoo(host, { pad = 28 } = {}) {
  const layer = document.createElement('div');
  layer.className = 'goo';
  layer.setAttribute('aria-hidden', 'true');
  layer.style.setProperty('--pad', pad + 'px');
  host.prepend(layer);
  const shapes = new Map();
  const ro = new ResizeObserver(() => sync());
  ro.observe(host);

  function rel(el) {
    let x = 0, y = 0, n = el;
    while (n && n !== host) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent; }
    return n === host ? { x, y } : null;
  }

  function sync() {
    const d = gooOn() ? 1.5 : 0;
    for (const [el, s] of shapes) {
      const p = rel(el);
      if (!p) continue;
      const st = s.i.style;
      st.left = (p.x + pad + d) + 'px';
      st.top = (p.y + pad + d) + 'px';
      st.width = Math.max(0, el.offsetWidth - d * 2) + 'px';
      st.height = Math.max(0, el.offsetHeight - d * 2) + 'px';
    }
  }

  function track(el, opts = {}) {
    if (shapes.has(el)) return shapes.get(el).i;
    const i = document.createElement('i');
    i.className = 'gs';
    i.style.borderRadius = getComputedStyle(el).borderRadius;
    layer.append(i);
    shapes.set(el, { i });
    ro.observe(el);
    sync();
    if (opts.enter && !reduceMq.matches && gooOn() && i.animate) {
      const from = opts.from && rel(opts.from) ? opts.from : null;
      let dy = -(el.offsetHeight * 0.55 + 4);
      if (from) { const a = rel(el), b = rel(from); dy = (b.y + from.offsetHeight / 2) - (a.y + el.offsetHeight / 2); }
      i.animate([{ transform: `translate3d(0, ${dy}px, 0) scale(.82, .45)`, opacity: .0 }, { opacity: 1, offset: .35 }, { transform: 'none', opacity: 1 }], { duration: 620, easing: SPRING_B, fill: 'backwards' });
    }
    return i;
  }

  function untrack(el, opts = {}) {
    const s = shapes.get(el);
    if (!s) return;
    shapes.delete(el);
    ro.unobserve(el);
    const done = () => s.i.remove();
    if (opts.leave && !reduceMq.matches && gooOn() && s.i.animate) {
      let dy = 16;
      if (opts.to) { const a = rel(opts.to); const cur = parseFloat(s.i.style.top) - pad; if (a) dy = (a.y + opts.to.offsetHeight / 2) - (cur + el.offsetHeight / 2); }
      const an = s.i.animate([{ transform: 'none', opacity: 1 }, { transform: `translate3d(0, ${dy}px, 0) scale(.82, .45)`, opacity: 0 }], { duration: 300, easing: EASE, fill: 'forwards' });
      an.onfinish = done;
      setTimeout(done, 420);
    } else done();
  }

  addEventListener('gooapply', sync);
  return { layer, track, untrack, sync, destroy() { ro.disconnect(); layer.remove(); shapes.clear(); removeEventListener('gooapply', sync); } };
}

export function relTime(ms, now = Date.now()) {
  const s = Math.max(0, (now - ms) / 1000);
  if (s < 45) return 'teraz';
  if (s < 3600) return Math.round(s / 60) + ' min';
  if (s < 86400) return Math.round(s / 3600) + ' godz.';
  const d = Math.round(s / 86400);
  return d === 1 ? 'wczoraj' : d < 7 ? d + ' dni' : Math.round(d / 7) + ' tyg.';
}

export function toMs(v) {
  if (typeof v === 'number') return v < 1e12 ? v * 1000 : v;
  const t = Date.parse(v);
  return Number.isFinite(t) ? t : 0;
}
