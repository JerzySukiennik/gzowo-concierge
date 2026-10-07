// Gzowo Concierge - avatar choice (shape and ink: black, white or auto): localStorage cache for a flash-free first paint, change subscribers, mini logo canvases, favicon and touch icon.
import { SHAPE_BY_ID, COLOR_BY_ID, SHAPES, DEFAULTS } from '../bot-data.js';
import { drawStatic } from '../bot-paint.js';

const KEY = 'cavatar';
const validColor = c => COLOR_BY_ID.has(c);

function read() {
  try {
    const o = JSON.parse(localStorage.getItem(KEY));
    if (o && SHAPE_BY_ID.has(o.shape) && validColor(o.color)) return { shape: o.shape, color: o.color };
  } catch {}
  return null;
}

let cur = read() || { ...DEFAULTS };
const subs = new Set();
let remote = null, timer = 0, iconTimer = 0;

export const getAvatar = () => ({ ...cur });
export const onAvatar = fn => { subs.add(fn); return () => { subs.delete(fn); }; };
export const setRemote = fn => { remote = fn; };

export function setAvatar(a, { persist = true } = {}) {
  const n = { shape: a && SHAPE_BY_ID.has(a.shape) ? a.shape : cur.shape, color: a && validColor(a.color) ? a.color : cur.color };
  if (n.shape === cur.shape && n.color === cur.color) return false;
  cur = n;
  try { localStorage.setItem(KEY, JSON.stringify(n)); } catch {}
  subs.forEach(f => f(cur));
  paintOrbs();
  clearTimeout(iconTimer);
  iconTimer = setTimeout(updateIcons, 250);
  if (persist && remote) { clearTimeout(timer); timer = setTimeout(() => remote({ ...cur }), 450); }
  return true;
}

export function randomAvatar() {
  const pick = a => a[Math.floor(Math.random() * a.length)];
  let n;
  do { n = { shape: pick(SHAPES).id, color: cur.color }; } while (n.shape === cur.shape);
  return n;
}

export function paintOrbs(root = document) {
  root.querySelectorAll('canvas.orb-c').forEach(c => drawStatic(c, { shape: cur.shape, color: cur.color, face: c.dataset.face || 'neutral', fill: 0.44, ground: false }));
}

function tile(size) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const x = c.getContext('2d');
  x.fillStyle = '#e7e9ec'; x.fillRect(0, 0, size, size);
  const o = document.createElement('canvas');
  o.dataset.size = String(size); o.width = o.height = size;
  drawStatic(o, { shape: cur.shape, color: cur.color === 'white' ? 'white' : 'black', dark: false, face: 'neutral', fill: 0.34 });
  x.drawImage(o, 0, 0, size, size);
  return c;
}

export function updateIcons() {
  try {
    const small = tile(96).toDataURL('image/png'), touch = tile(180).toDataURL('image/png');
    document.querySelectorAll('link[rel="icon"]').forEach(l => { l.href = small; });
    document.querySelectorAll('link[rel="apple-touch-icon"]').forEach(l => { l.href = touch; });
  } catch {}
}

let rs = 0;
addEventListener('resize', () => { clearTimeout(rs); rs = setTimeout(() => paintOrbs(), 220); });
