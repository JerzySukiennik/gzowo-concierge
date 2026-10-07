// Gzowo Concierge - Concierge bot data: eight flat shapes as star-shaped implicit outlines sampled into 64 radii, sixteen eye-only faces, black or white ink.
const N = 64, TAU = Math.PI * 2;
const DIR = Array.from({ length: N }, (_, i) => [Math.cos(i / N * TAU), Math.sin(i / N * TAU)]);

const len = (x, y) => Math.hypot(x, y);

function segDist(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay, t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy || 1)));
  return len(px - ax - dx * t, py - ay - dy * t);
}

function polySdf(pts) {
  const n = pts.length;
  return (x, y) => {
    let inside = true, best = 1e9, maxS = -1e9;
    for (let i = 0; i < n; i++) {
      const a = pts[i], b = pts[(i + 1) % n];
      const ex = b[0] - a[0], ey = b[1] - a[1], el = len(ex, ey);
      const s = ((x - a[0]) * ey - (y - a[1]) * ex) / el;
      if (s > 0) inside = false;
      if (s > maxS) maxS = s;
      const d = segDist(x, y, a[0], a[1], b[0], b[1]);
      if (d < best) best = d;
    }
    return inside ? maxS : best;
  };
}

function ngon(n, r, rot) {
  return Array.from({ length: n }, (_, i) => [Math.cos(rot + i / n * TAU) * r, Math.sin(rot + i / n * TAU) * r]);
}

function smoothUnion(a, b, k) {
  const h = Math.max(k - Math.abs(a - b), 0) / k;
  return Math.min(a, b) - h * h * k * 0.25;
}

function roundCone(x, y, r1, r2, h) {
  const px = Math.abs(x), py = -y;
  const b = (r1 - r2) / h, a = Math.sqrt(1 - b * b);
  const k = px * -b + py * a;
  if (k < 0) return len(px, py) - r1;
  if (k > a * h) return len(px, py - h) - r2;
  return px * a + py * b - r1;
}

const tri = polySdf(ngon(3, 0.6, -Math.PI / 2)), hex = polySdf(ngon(6, 0.7, 0));

const DEFS = [
  { id: 'circle', name: 'Okrąg', k: 1, f: (x, y) => len(x, y) - 1 },
  { id: 'pebble', name: 'Kamyk', k: 1.03, f: (x, y) => { const yy = y / 0.86, a = Math.atan2(yy, x); return len(x, yy) / (1 + 0.075 * Math.cos(2 * a - 0.35) + 0.045 * Math.cos(3 * a + 2.2)) - 1; } },
  { id: 'squircle', name: 'Kostka', k: 0.95, f: (x, y) => Math.pow(Math.pow(Math.abs(x), 4.4) + Math.pow(Math.abs(y), 4.4), 1 / 4.4) - 1 },
  { id: 'capsule', name: 'Kapsuła', k: 1.12, f: (x, y) => segDist(x, y, -0.5, 0, 0.5, 0) - 0.46 },
  { id: 'triangle', name: 'Trójkąt', k: 1.06, f: (x, y) => tri(x, y) - 0.3 },
  { id: 'hexagon', name: 'Sześciokąt', k: 0.98, f: (x, y) => hex(x, y) - 0.27 },
  { id: 'cloud', name: 'Chmurka', k: 1.08, smooth: 1, f: (x, y) => {
    let d = len(x + 0.5, y - 0.2) - 0.46;
    for (const c of [[0.5, 0.2, 0.44], [0.0, 0.34, 0.5], [-0.27, -0.26, 0.4], [0.28, -0.25, 0.38], [0, 0.0, 0.5]]) d = smoothUnion(d, len(x - c[0], y - c[1]) - c[2], 0.07);
    return d;
  } },
  { id: 'droplet', name: 'Kropla', k: 1.08, f: (x, y) => roundCone(x, y, 0.62, 0.07, 0.9) },
];

function solve(f) {
  const r = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    let lo = 0, hi = 3;
    for (let s = 0; s < 26; s++) { const m = (lo + hi) / 2; if (f(DIR[i][0] * m, DIR[i][1] * m) < 0) lo = m; else hi = m; }
    r[i] = (lo + hi) / 2;
  }
  return r;
}

function blur(r) {
  const o = new Float32Array(N);
  for (let i = 0; i < N; i++) o[i] = (r[(i + N - 1) % N] + 2 * r[i] + r[(i + 1) % N]) / 4;
  return o;
}

export const SHAPES = DEFS.map(d => {
  let r = solve(d.f);
  for (let p = 0; p < (d.smooth || 0); p++) r = blur(r);
  let x0 = 9, x1 = -9, y0 = 9, y1 = -9;
  for (let i = 0; i < N; i++) { const x = DIR[i][0] * r[i], y = DIR[i][1] * r[i]; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
  const ext = Math.max(x1 - x0, y1 - y0) / 2, s = d.k / ext;
  const radii = Float32Array.from(r, v => v * s);
  return { id: d.id, name: d.name, radii, top: y0 * s, bottom: y1 * s, mid: (y0 + y1) * s / 2, left: x0 * s, right: x1 * s };
});

export const SHAPE_BY_ID = new Map(SHAPES.map(s => [s.id, s]));
export { N as SHAPE_N, DIR };

const E = (w, h, t = 0, o = 1) => [w, h, t, o];
const pair = (w, h, t = 0, o = 1) => [E(w, h, t, o), E(w, h, -t, o)];

export const FACES = {
  neutral: { name: 'Spokojna', yaw: 7, pit: 3, roll: -6, split: 15.5, eyes: pair(0.18, 0.4) },
  attentive: { name: 'Uważna', yaw: 3, pit: -2, roll: -1, split: 16, eyes: pair(0.205, 0.45) },
  surprised: { name: 'Zdziwiona', yaw: 2, pit: -5, roll: 0, split: 19, eyes: pair(0.42, 0.45) },
  excited: { name: 'Podekscytowana', yaw: 5, pit: -9, roll: -3, split: 19.5, eyes: pair(0.37, 0.55, -10) },
  happy: { name: 'Zadowolona', yaw: 4, pit: 6, roll: 0, split: 17, eyes: pair(0.27, 0.16, 15) },
  laughing: { name: 'Roześmiana', yaw: 3, pit: 9, roll: 0, split: 18, eyes: pair(0.34, 0.125, 21) },
  angry: { name: 'Zła', yaw: 2, pit: 4, roll: 0, split: 17, eyes: pair(0.34, 0.15, 31) },
  sad: { name: 'Smutna', yaw: 2, pit: 6, roll: 0, split: 16, eyes: pair(0.22, 0.41, -27) },
  scared: { name: 'Przestraszona', yaw: 0, pit: -10, roll: 0, split: 20.5, eyes: pair(0.4, 0.62) },
  suspicious: { name: 'Podejrzliwa', yaw: 13, pit: 3, roll: -6, split: 16, eyes: [E(0.21, 0.4), E(0.225, 0.14)] },
  confused: { name: 'Zmieszana', yaw: -11, pit: 2, roll: 9, split: 16.5, eyes: [E(0.2, 0.44, -18), E(0.285, 0.17, 14)] },
  curious: { name: 'Ciekawa', yaw: 15, pit: -6, roll: -14, split: 16.5, eyes: [E(0.24, 0.47, -8), E(0.195, 0.37, -8)] },
  proud: { name: 'Dumna', yaw: 4, pit: 10, roll: 0, split: 17, eyes: pair(0.3, 0.15, 18) },
  shy: { name: 'Wstydliwa', yaw: -17, pit: 8, roll: -6, split: 14, eyes: pair(0.17, 0.3) },
  unimpressed: { name: 'Znudzona', yaw: -19, pit: 1, roll: 0, split: 16, eyes: pair(0.3, 0.115) },
  sleepy: { name: 'Śpiąca', yaw: 5, pit: 4, roll: -3, split: 16, eyes: pair(0.2, 0.42, 0, 0.4) },
};

export const FACE_ORDER = Object.keys(FACES);

export const COLORS = [
  { id: 'black', name: 'Czarny' },
  { id: 'white', name: 'Biały' },
  { id: 'auto', name: 'Auto' },
];

export const COLOR_BY_ID = new Map(COLORS.map(c => [c.id, c]));
export const DEFAULTS = { shape: 'circle', color: 'auto' };

export function inkOf(color, dark) {
  const c = color === 'black' || color === 'white' ? color : dark ? 'white' : 'black';
  return c === 'black' ? { body: '#111111', eye: '#ffffff', line: null } : { body: '#ffffff', eye: '#111111', line: '#111111' };
}
