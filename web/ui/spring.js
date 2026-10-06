// Gzowo Concierge - interruptible critically-damped spring (response + damping ratio) with velocity handoff.
export function spring({ from, to, velocity = 0, response = 0.4, damping = 1, onUpdate, onDone }) {
  const k = (2 * Math.PI / response) ** 2;
  const c = 4 * Math.PI * damping / response;
  let x = from, v = velocity, last = performance.now(), raf = 0, alive = true;
  const eps = Math.max(Math.abs(to - from), 1) * 0.0008;
  function frame(now) {
    if (!alive) return;
    let dt = Math.min((now - last) / 1000, 0.05);
    last = now;
    const steps = Math.max(1, Math.ceil(dt / 0.004));
    const h = dt / steps;
    for (let i = 0; i < steps; i++) {
      const a = -k * (x - to) - c * v;
      v += a * h;
      x += v * h;
    }
    if (Math.abs(x - to) < eps && Math.abs(v) < eps * 8) {
      x = to; v = 0; alive = false;
      onUpdate(x, v);
      onDone?.();
      return;
    }
    onUpdate(x, v);
    raf = requestAnimationFrame(frame);
  }
  raf = requestAnimationFrame(frame);
  return {
    stop() { alive = false; cancelAnimationFrame(raf); },
    get value() { return x; },
    get velocity() { return v; },
  };
}

export function project(velocity, rate = 0.998) {
  return (velocity / 1000) * rate / (1 - rate);
}

export function rubber(over, dim, c = 0.55) {
  return (over * dim * c) / (dim + c * Math.abs(over));
}
