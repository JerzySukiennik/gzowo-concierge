// Gzowo Concierge - settings sheet: draggable spring bottom sheet on phones, nonmodal side inspector on desktop.
import { spring, project, rubber } from './spring.js';

export function createSheet({ el, body, scrim, shifts, onOpen, onClose }) {
  const wide = matchMedia('(min-width: 900px)');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  let p = 0, open = false, anim = null, size = 0, drag = null;

  const shiftPx = () => Math.max(0, Math.min(744 - innerWidth / 2, innerWidth / 2 - 376));

  function measure() { size = wide.matches ? el.offsetWidth + 24 : el.offsetHeight; }

  function apply(v) {
    p = v;
    if (wide.matches) {
      el.style.transform = `translate3d(${(1 - v) * size}px,0,0)`;
      const s = -shiftPx() * Math.min(Math.max(v, 0), 1);
      shifts.forEach(n => { n.style.transform = s ? `translate3d(${s}px,0,0)` : ''; });
      scrim.style.opacity = '0';
    } else {
      el.style.transform = `translate3d(0,${(1 - v) * size}px,0)`;
      shifts.forEach(n => { n.style.transform = ''; });
      scrim.style.opacity = String(Math.min(Math.max(v, 0), 1));
    }
  }

  function run(target, velocity = 0) {
    anim?.stop();
    if (reduce.matches) { apply(target); settle(target); return; }
    anim = spring({ from: p, to: target, velocity, response: target ? 0.42 : 0.36, damping: target ? 0.88 : 1, onUpdate: apply, onDone: () => settle(target) });
  }

  function settle(target) {
    if (!target) { el.style.visibility = 'hidden'; scrim.classList.remove('on'); }
  }

  function show() {
    if (open) return;
    open = true;
    el.style.visibility = 'visible';
    scrim.classList.add('on');
    measure();
    if (p === 0) apply(0);
    onOpen?.();
    run(1);
  }

  function hide(velocity = 0) {
    if (!open) return;
    open = false;
    measure();
    onClose?.();
    run(0, velocity);
  }

  scrim.addEventListener('click', () => hide());

  el.addEventListener('touchstart', e => {
    if (wide.matches || !open || e.touches.length !== 1) return;
    anim?.stop();
    const y = e.touches[0].clientY;
    drag = { y0: y, y, t: performance.now(), v: 0, active: false, fromBody: body.contains(e.target), top: body.scrollTop <= 0 };
  }, { passive: true });

  el.addEventListener('touchmove', e => {
    if (!drag) return;
    const y = e.touches[0].clientY, now = performance.now(), dy = y - drag.y0;
    if (!drag.active) {
      if (Math.abs(dy) < 8) return;
      if (dy > 0 && (!drag.fromBody || (drag.top && body.scrollTop <= 0))) { drag.active = true; drag.y0 = y; measure(); }
      else { drag = null; return; }
    }
    e.preventDefault();
    const d = y - drag.y0;
    drag.v = 0.6 * ((y - drag.y) / Math.max(now - drag.t, 1) * 1000) + 0.4 * drag.v;
    drag.y = y; drag.t = now;
    apply(d >= 0 ? 1 - d / size : 1 + rubber(-d, size) / size);
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

  wide.addEventListener('change', () => { measure(); apply(open ? 1 : 0); });
  addEventListener('resize', () => { if (open) { measure(); apply(1); } });

  return {
    show, hide,
    toggle() { open ? hide() : show(); },
    get isOpen() { return open; },
    get isWide() { return wide.matches; },
  };
}
