// Gzowo Concierge - Concierge bot painter: flat two-colour vector body (solid black with white eyes or solid white with a thin outline and black eyes), eyes projected on a sphere, sleep arcs; shared by the live face and static thumbnails.
import { SHAPE_N, DIR, SHAPE_BY_ID, FACES, inkOf } from './bot-data.js';

const TAU = Math.PI * 2, RAD = Math.PI / 180;
const PX = new Float32Array(SHAPE_N), PY = new Float32Array(SHAPE_N);

export function makeGfx(c, R, color, dark) {
  const ink = inkOf(color, dark);
  return { R, dark, color, body: ink.body, eye: ink.eye, line: ink.line };
}

export function newEyes() {
  return [{ x: 0, y: 0, a: 1, b: 0, c: 0, d: 1, w: 0, h: 0, o: 1, al: 0 }, { x: 0, y: 0, a: 1, b: 0, c: 0, d: 1, w: 0, h: 0, o: 1, al: 0 }];
}

function radiusAt(radii, ang) {
  const f = (((ang / TAU) % 1) + 1) % 1 * SHAPE_N, i = Math.floor(f), t = f - i;
  return radii[i % SHAPE_N] * (1 - t) + radii[(i + 1) % SHAPE_N] * t;
}

export function layoutEyes(eyes, v, radii, ew = 1, eh = 1, blink = 0) {
  const roll = v.roll * RAD, cr = Math.cos(roll), sr = Math.sin(roll), pit = v.pit * RAD;
  for (let i = 0; i < 2; i++) {
    const sg = i ? 1 : -1, yawE = (v.yaw + sg * v.split) * RAD;
    const x0 = Math.sin(yawE) * Math.cos(pit), y0 = Math.sin(pit), depth = Math.cos(yawE) * Math.cos(pit);
    let x = x0 * cr - y0 * sr, y = x0 * sr + y0 * cr;
    const dist = Math.hypot(x, y), phi = Math.atan2(y, x);
    const lim = radiusAt(radii, phi) * 0.72;
    if (dist > lim) { x *= lim / dist; y *= lim / dist; }
    const f = Math.max(0.16, Math.pow(Math.max(0, depth), 0.7));
    const al = Math.max(0, Math.min(1, (depth - 0.04) / 0.22));
    const th = (i ? v.t1 : v.t0) * RAD + roll, al2 = th - phi;
    const ca = Math.cos(al2), sa = Math.sin(al2), cp = Math.cos(phi), sp = Math.sin(phi);
    const e = eyes[i];
    e.x = x; e.y = y;
    e.a = cp * f * ca - sp * sa; e.b = sp * f * ca + cp * sa;
    e.c = -cp * f * sa - sp * ca; e.d = -sp * f * sa + cp * ca;
    e.w = (i ? v.w1 : v.w0) * ew;
    e.h = (i ? v.h1 : v.h0) * eh;
    e.o = (i ? v.o1 : v.o0) * (1 - 0.93 * blink);
    e.al = al;
  }
}

export function faceValues(out, name, gx = 0, gy = 0) {
  const f = FACES[name] || FACES.neutral;
  out.yaw = f.yaw + gx; out.pit = f.pit + gy; out.roll = f.roll; out.split = f.split;
  out.w0 = f.eyes[0][0]; out.h0 = f.eyes[0][1]; out.t0 = f.eyes[0][2]; out.o0 = f.eyes[0][3];
  out.w1 = f.eyes[1][0]; out.h1 = f.eyes[1][1]; out.t1 = f.eyes[1][2]; out.o1 = f.eyes[1][3];
  return out;
}

function pill(c, w, h, yc) {
  const r = Math.min(w, h) / 2, hw = w / 2, hh = h / 2;
  c.moveTo(-hw + r, yc - hh);
  c.lineTo(hw - r, yc - hh);
  c.arc(hw - r, yc - hh + r, r, -Math.PI / 2, 0);
  c.lineTo(hw, yc + hh - r);
  c.arc(hw - r, yc + hh - r, r, 0, Math.PI / 2);
  c.lineTo(-hw + r, yc + hh);
  c.arc(-hw + r, yc + hh - r, r, Math.PI / 2, Math.PI);
  c.lineTo(-hw, yc - hh + r);
  c.arc(-hw + r, yc - hh + r, r, Math.PI, Math.PI * 1.5);
  c.closePath();
}

function bodyPath(c, radii, R, yo) {
  const n = SHAPE_N;
  for (let i = 0; i < n; i++) { PX[i] = DIR[i][0] * radii[i] * R; PY[i] = DIR[i][1] * radii[i] * R + yo; }
  c.beginPath();
  c.moveTo((PX[n - 1] + PX[0]) / 2, (PY[n - 1] + PY[0]) / 2);
  for (let i = 0; i < n; i++) { const j = (i + 1) % n; c.quadraticCurveTo(PX[i], PY[i], (PX[i] + PX[j]) / 2, (PY[i] + PY[j]) / 2); }
  c.closePath();
}

function zeds(c, R, t, a) {
  c.lineCap = 'round'; c.lineJoin = 'round';
  for (let i = 0; i < 3; i++) {
    const ph = ((t * 0.00045 + i / 3) % 1), s = R * (0.07 + 0.055 * ph + i * 0.01);
    const x = R * (0.62 + ph * 0.34) + Math.sin(ph * 6 + i) * R * 0.03, y = -R * (0.46 + ph * 0.78);
    c.globalAlpha = a * Math.min(1, ph * 5) * Math.min(1, (1 - ph) * 2.2);
    c.lineWidth = Math.max(1.4, s * 0.34);
    c.beginPath(); c.moveTo(x - s, y - s); c.lineTo(x + s, y - s); c.lineTo(x - s, y + s); c.lineTo(x + s, y + s); c.stroke();
  }
  c.globalAlpha = 1;
}

export function paintBot(c, gfx, S) {
  const R = gfx.R, shape = S.shape;
  const yo = -shape.mid * R;
  c.save();
  c.translate(S.cx, S.groundY - (shape.bottom - shape.mid) * R * S.sy - Math.max(0, S.hop) * R * 0.55 + S.dy);
  c.rotate(S.rot);
  c.scale(S.sx, S.sy);
  bodyPath(c, S.radii, R, yo);
  c.fillStyle = gfx.body; c.fill();
  if (gfx.line) { c.lineJoin = 'round'; c.lineWidth = Math.max(1.5, R * 0.032); c.strokeStyle = gfx.line; c.stroke(); }

  const blink = S.blink, arcT = Math.max(0, Math.min(1, (blink - 0.78) / 0.22));
  for (let i = 0; i < 2; i++) {
    const e = S.eyes[i];
    if (e.al <= 0.01) continue;
    c.save();
    c.transform(e.a, e.b, e.c, e.d, e.x * R, e.y * R + yo);
    const w = Math.max(0.001, e.w * R), hh = Math.max(0.001, e.h * R);
    if (arcT < 1) {
      const o = Math.max(0.05, e.o), h = hh * o, yc = (1 - o) * hh / 2;
      c.globalAlpha = e.al * (1 - arcT);
      c.fillStyle = gfx.eye; c.beginPath(); pill(c, w, h, yc); c.fill();
    }
    if (arcT > 0) {
      c.globalAlpha = e.al * arcT; c.strokeStyle = gfx.eye; c.lineCap = 'round'; c.lineWidth = w * 0.5;
      c.beginPath(); c.moveTo(-w * 1.05, 0); c.quadraticCurveTo(0, w * 1.5 * S.sleep, w * 1.05, 0); c.stroke();
    }
    c.restore();
  }
  c.globalAlpha = 1;
  if (S.zz > 0.02) { c.strokeStyle = gfx.dark ? '#f2f2f2' : '#111111'; zeds(c, R, S.t, S.zz); }
  c.restore();
}

const statics = new Map();

export function drawStatic(canvas, opts = {}) {
  const cs = canvas.getBoundingClientRect();
  const css = Math.max(8, canvas.clientWidth || cs.width || parseFloat(canvas.dataset.size) || 48);
  const dpr = Math.min(window.devicePixelRatio || 1, 3);
  const px = Math.round(css * dpr);
  if (canvas.width !== px) { canvas.width = px; canvas.height = px; }
  const c = canvas.getContext('2d');
  c.setTransform(1, 0, 0, 1, 0, 0);
  c.clearRect(0, 0, px, px);
  c.setTransform(dpr, 0, 0, dpr, 0, 0);
  const shape = SHAPE_BY_ID.get(opts.shape) || SHAPE_BY_ID.get('circle');
  const dark = opts.dark ?? matchMedia('(prefers-color-scheme: dark)').matches;
  const R = css * (opts.fill || 0.4);
  const v = faceValues(statics.get('v') || statics.set('v', {}).get('v'), opts.face || 'neutral');
  const eyes = statics.get('e') || statics.set('e', newEyes()).get('e');
  layoutEyes(eyes, v, shape.radii, 1, 1, 0);
  const gfx = makeGfx(c, R, opts.color, dark);
  paintBot(c, gfx, { shape, radii: shape.radii, cx: css / 2, groundY: css / 2 + (shape.bottom - shape.mid) * R, dy: 0, rot: 0, sx: 1, sy: 1, hop: 0, eyes, blink: 0, sleep: 0, zz: 0, t: 0 });
}
