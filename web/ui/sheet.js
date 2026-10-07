// Gzowo Concierge - generic spring panel: bottom sheet or left drawer on phones, nonmodal right panel on desktop; draggable, interruptible, velocity handoff.
import { spring, project, rubber } from './spring.js';

const reg = new Set();

export function createSheet({ el, body, scrim, shifts = [], edge, shiftPx, onOpen, onClose }) {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  let p = 0, open = false, anim = null, size = 0, drag = null, mode = null;

  const cur = () => edge();
  const horizontal = e => e === 'left' || e === 'right';

  function measure() { mode = cur(); size = !mode ? 0 : horizontal(mode) ? el.offsetWidth + 24 : el.offsetHeight; }

  function apply(v) {
    p = v;
    if (!mode) { el.style.transform = ''; return; }
    if (mode === 'right') {
      el.style.transform = `translate3d(${(1 - v) * size}px,0,0)`;
      let best = null;
      reg.forEach(r => { if (r.mode() === 'right' && (!best || r.p() > best.p())) best = r; });
      const s = best && best.shiftPx ? -best.shiftPx() * Math.min(Math.max(best.p(), 0), 1) : 0;
      shifts.forEach(n => { n.style.transform = s ? `translate3d(${s}px,0,0)` : ''; });
      if (scrim) scrim.style.opacity = '0';
    } else if (mode === 'left') {
      el.style.transform = `translate3d(${-(1 - v) * size}px,0,0)`;
      if (scrim) scrim.style.opacity = String(Math.min(Math.max(v, 0), 1));
    } else {
      el.style.transform = `translate3d(0,${(1 - v) * size}px,0)`;
      shifts.forEach(n => { n.style.transform = ''; });
      if (scrim) scrim.style.opacity = String(Math.min(Math.max(v, 0), 1));
    }
  }

  function settle(target) {
    if (!target && mode) { el.style.visibility = 'hidden'; scrim?.classList.remove('on'); }
  }

  function run(target, velocity = 0) {
    anim?.stop();
    if (reduce.matches) { apply(target); settle(target); return; }
    anim = spring({ from: p, to: target, velocity, response: target ? 0.42 : 0.36, damping: target ? 0.88 : 1, onUpdate: apply, onDone: () => settle(target) });
  }

  function show() {
    if (open) return;
    measure();
    if (!mode) return;
    open = true;
    el.style.visibility = 'visible';
    scrim?.classList.add('on');
    if (p === 0) apply(0);
    onOpen?.(mode);
    run(1);
  }

  function hide(velocity = 0) {
    if (!open) return;
    open = false;
    measure();
    onClose?.(mode);
    run(0, velocity);
  }

  scrim?.addEventListener('click', () => hide());

  el.addEventListener('touchstart', e => {
    const m = cur();
    if ((m !== 'bottom' && m !== 'left') || !open || e.touches.length !== 1) return;
    anim?.stop();
    const t = e.touches[0];
    drag = { m, x0: t.clientX, y0: t.clientY, x: t.clientX, y: t.clientY, t: performance.now(), v: 0, active: false, fromBody: body.contains(e.target), top: body.scrollTop <= 0 };
  }, { passive: true });

  el.addEventListener('touchmove', e => {
    if (!drag) return;
    const t = e.touches[0], now = performance.now();
    if (drag.m === 'bottom') {
      const dy = t.clientY - drag.y0;
      if (!drag.active) {
        if (Math.abs(dy) < 8) return;
        if (dy > 0 && (!drag.fromBody || (drag.top && body.scrollTop <= 0))) { drag.active = true; drag.y0 = t.clientY; measure(); }
        else { drag = null; return; }
      }
      e.preventDefault();
      const d = t.clientY - drag.y0;
      drag.v = 0.6 * ((t.clientY - drag.y) / Math.max(now - drag.t, 1) * 1000) + 0.4 * drag.v;
      drag.y = t.clientY; drag.t = now;
      apply(d >= 0 ? 1 - d / size : 1 + rubber(-d, size) / size);
    } else {
      const dx = t.clientX - drag.x0, dy = t.clientY - drag.y0;
      if (!drag.active) {
        if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
        if (dx < 0 && Math.abs(dx) > Math.abs(dy) * 1.2) { drag.active = true; drag.x0 = t.clientX; measure(); }
        else { drag = null; return; }
      }
      e.preventDefault();
      const d = drag.x0 - t.clientX;
      drag.v = 0.6 * ((drag.x - t.clientX) / Math.max(now - drag.t, 1) * 1000) + 0.4 * drag.v;
      drag.x = t.clientX; drag.t = now;
      apply(d >= 0 ? 1 - d / size : 1 + rubber(-d, size) / size);
    }
  }, { passive: false });

  function release() {
    if (!drag) return;
    const d = drag, was = d.active;
    drag = null;
    if (!was) return;
    const travelled = (1 - p) * size;
    const landing = travelled + project(d.v);
    if (landing > size * 0.45) hide(-d.v / size);
    else run(1, -d.v / size);
  }
  el.addEventListener('touchend', release);
  el.addEventListener('touchcancel', release);

  function remode() {
    const next = cur();
    if (next === mode) { measure(); if (mode) apply(open ? 1 : 0); return; }
    anim?.stop();
    const was = open;
    mode = next;
    if (!mode) { open = false; p = 0; el.style.transform = ''; el.style.visibility = ''; scrim?.classList.remove('on'); shifts.forEach(n => { n.style.transform = ''; }); if (scrim) scrim.style.opacity = ''; if (was) onClose?.(null); return; }
    measure();
    if (was) { el.style.visibility = 'visible'; scrim?.classList.toggle('on', mode !== 'right'); apply(1); }
    else { el.style.visibility = 'hidden'; el.style.transform = ''; p = 0; apply(0); }
  }
  addEventListener('resize', () => { if (open || mode !== cur()) remode(); });
  reg.add({ mode: () => mode, p: () => p, shiftPx });
  mode = cur();
  if (mode) { measure(); el.style.visibility = 'hidden'; apply(0); }

  return {
    show, hide, remode,
    toggle() { open ? hide() : show(); },
    get isOpen() { return open; },
    get mode() { return cur(); },
    get modal() { const m = cur(); return m === 'bottom' || m === 'left'; },
  };
}
