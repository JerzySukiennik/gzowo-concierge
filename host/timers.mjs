// Gzowo Concierge - timers set by voice or chat: kept in settings, shown live on the Mac island, rung in the room and on the phone when they end.
import crypto from 'node:crypto';
import { store } from './db.mjs';
import { announce } from './room.mjs';
import { pushAll } from './push.mjs';

const KEY = 'timers';
const KEEP_DONE = 90e3;
const MAX = 8;
let wake = null;
let onChange = () => {};

export const onTimersChange = fn => { onChange = fn; };

const all = () => store.getSetting(KEY, []);
const save = list => { store.setSetting(KEY, list); schedule(); onChange(); };

export function timerState() {
  const now = Date.now();
  return all().filter(t => !t.done || now - t.done < KEEP_DONE).map(({ id, label, ends, total, done }) => ({ id, label, ends, total, done: done || null }));
}

const spoken = sec => {
  const m = Math.floor(sec / 60), s = Math.round(sec % 60);
  if (!m) return `${s} s`;
  if (m < 60) return s ? `${m} min ${s} s` : `${m} min`;
  const h = Math.floor(m / 60), r = m % 60;
  return r ? `${h} h ${r} min` : `${h} h`;
};

export function startTimer({ seconds, label = '', origin = 'chat' }) {
  const total = Math.round(Number(seconds));
  if (!Number.isFinite(total) || total < 5) throw new Error('Timer musi trwać co najmniej 5 sekund.');
  if (total > 24 * 3600) throw new Error('Timer może trwać najwyżej 24 godziny.');
  const list = all().filter(t => !t.done);
  if (list.length >= MAX) throw new Error(`Mogę trzymać najwyżej ${MAX} timerów naraz.`);
  const t = { id: crypto.randomUUID().slice(0, 8), label: String(label || '').trim().slice(0, 40), ends: Date.now() + total * 1000, total, origin };
  save([...all().filter(x => !x.done || Date.now() - x.done < KEEP_DONE), t]);
  return { id: t.id, label: t.label, ends: new Date(t.ends).toISOString(), length: spoken(total) };
}

function pick(list, { id, label }) {
  if (id) return list.filter(t => t.id === id);
  const q = String(label || '').trim().toLowerCase();
  if (q) return list.filter(t => t.label.toLowerCase().includes(q));
  return list;
}

export function cancelTimer({ id, label, all: everything } = {}) {
  const running = all().filter(t => !t.done);
  const hit = pick(running, { id, label });
  if (!hit.length) throw new Error(running.length ? 'Nie ma takiego timera.' : 'Nie ma żadnego włączonego timera.');
  if (hit.length > 1 && !everything && !id) return { cancelled: 0, ambiguous: hit.map(t => t.label || spoken((t.ends - Date.now()) / 1000) + ' do końca') };
  const ids = new Set(hit.map(t => t.id));
  save(all().filter(t => !ids.has(t.id)));
  return { cancelled: ids.size };
}

export function extendTimer({ id, seconds }) {
  const list = all();
  const t = list.find(x => x.id === id && !x.done);
  if (!t) throw new Error('Nie ma takiego timera.');
  const add = Math.round(Number(seconds) || 60);
  t.ends += add * 1000;
  t.total += add;
  save(list);
  return { id, ends: new Date(t.ends).toISOString() };
}

export function dismissTimer(id) {
  save(all().filter(t => t.id !== id));
  return { ok: true };
}

export function listTimers() {
  const now = Date.now();
  return all().filter(t => !t.done).map(t => ({ label: t.label || null, left: spoken(Math.max(0, (t.ends - now) / 1000)), ends: new Date(t.ends).toISOString() }));
}

function ring(t) {
  const what = t.label ? `Timer „${t.label}” się skończył.` : `Minęło ${spoken(t.total)}.`;
  if (t.origin === 'room') announce(what);
  pushAll({ title: 'Timer', body: what, url: '/', tag: `timer-${t.id}` }).catch(() => {});
}

function fire() {
  const now = Date.now();
  const list = all();
  let dirty = false;
  for (const t of list) if (!t.done && t.ends <= now) { t.done = now; dirty = true; ring(t); }
  const kept = list.filter(t => !t.done || now - t.done < KEEP_DONE);
  if (dirty || kept.length !== list.length) save(kept); else schedule();
}

function schedule() {
  clearTimeout(wake);
  const now = Date.now();
  const next = all().reduce((m, t) => Math.min(m, t.done ? t.done + KEEP_DONE : t.ends), Infinity);
  if (next === Infinity) return;
  wake = setTimeout(fire, Math.max(50, Math.min(next - now, 2 ** 31 - 1)));
}

export function startTimers() { fire(); }
