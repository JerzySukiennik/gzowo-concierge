// Gzowo Concierge - shared command layer used by the local HTTP API and the Firebase relay: threads, chat, approvals, settings.
import { EventEmitter } from 'node:events';
import crypto from 'node:crypto';
import { run, resolveApproval } from './agent.mjs';
import { generate, textOf } from './gemini.mjs';
import { store } from './db.mjs';
import { listPolicies, setPolicy } from './tools/index.mjs';
import { policyLabels } from './connectors/index.mjs';
import { live } from './live-state.mjs';

export const THREAD = 'main';

const SHAPES = ['circle', 'pebble', 'squircle', 'capsule', 'triangle', 'hexagon', 'cloud', 'droplet'];
const COLORS = ['auto', 'black', 'white'];
export function getAvatar() {
  const a = store.getSetting('avatar', null) || {};
  return { shape: SHAPES.includes(a.shape) ? a.shape : 'circle', color: COLORS.includes(a.color) ? a.color : 'auto' };
}
export function setAvatar(shape, color) {
  const next = { shape: SHAPES.includes(shape) ? shape : getAvatar().shape, color: COLORS.includes(color) ? color : getAvatar().color };
  store.setSetting('avatar', next);
  bus.emit('state');
  return next;
}
export const bus = new EventEmitter();
const locks = new Map();
const active = new Map();
const ID = /^[\w-]{4,64}$/;

export const validThread = t => (t === 'main' || ID.test(t || '') ? t : 'main');

function queue(thread, job) {
  const prev = locks.get(thread) || Promise.resolve();
  const next = prev.catch(() => {}).then(job);
  locks.set(thread, next);
  return next;
}

const busyAny = () => [...active.values()].some(n => n > 0);

export function threadList() {
  return store.listThreads().map(t => ({ id: t.id, title: t.title, updated: t.updated, busy: (active.get(t.id) || 0) > 0 }));
}

export function snapshot() {
  return {
    busy: busyAny(),
    policies: listPolicies(),
    labels: policyLabels(),
    facts: store.facts(),
    pending: store.pendingApprovals().map(a => ({ id: a.id, summary: a.summary, thread: a.thread })),
    threads: threadList(),
    avatar: getAvatar(),
  };
}

const changed = () => bus.emit('state');

function track(rid, send, thread) {
  return e => { const ev = { ...e, rid, thread }; send(ev); bus.emit('event', ev); };
}

async function tracked(thread, fn) {
  active.set(thread, (active.get(thread) || 0) + 1); changed();
  try { await fn(); } finally { active.set(thread, active.get(thread) - 1); changed(); }
}

async function autoTitle(thread) {
  const t = store.getThread(thread);
  if (!t || t.titled) return;
  const msgs = history(thread);
  const first = msgs.find(m => m.role === 'user')?.text;
  if (!first) return;
  const reply = msgs.find(m => m.role === 'assistant')?.text || '';
  let title = first.replace(/\s+/g, ' ').slice(0, 40);
  try {
    const res = await generate({
      system: 'Wymyślasz krótkie tytuły rozmów. Odpowiadasz samym tytułem po polsku: maksymalnie 4 słowa, bez cudzysłowów, bez kropki na końcu, bez emoji.',
      contents: [{ role: 'user', parts: [{ text: `Początek rozmowy.\nUżytkownik: ${first.slice(0, 300)}\nAsystent: ${reply.slice(0, 300)}` }] }],
      thinking: 'minimal',
    });
    const got = textOf(res.candidates?.[0]?.content?.parts).replace(/["„”.\n]/g, ' ').replace(/\s+/g, ' ').trim();
    if (got && got.length <= 60) title = got;
  } catch {}
  store.autoTitleThread(thread, title);
  changed();
}

export function chat(text, send = () => {}, { cid, thread = THREAD } = {}) {
  thread = validThread(thread);
  store.ensureThread(thread);
  const rid = cid || crypto.randomUUID();
  bus.emit('event', { type: 'user', text, rid, cid: rid, thread });
  const emit = track(rid, send, thread);
  return queue(thread, () => tracked(thread, () => run(thread, text, emit)))
    .catch(err => emit({ type: 'error', message: String(err.message || err) }))
    .then(() => autoTitle(thread));
}

export function approve(id, yes, send = () => {}) {
  const a = store.getApproval(id);
  const thread = validThread(a?.thread);
  const rid = crypto.randomUUID();
  const emit = track(rid, send, thread);
  const quiet = live.sessions.size > 0;
  return queue(thread, () => tracked(thread, async () => {
    const r = await resolveApproval(id, yes, emit, { quiet });
    if (quiet && r) bus.emit('approval-result', { ...r, thread });
  }))
    .catch(err => emit({ type: 'error', message: String(err.message || err) }));
}

export function newThread(id) {
  const tid = id && ID.test(id) ? id : crypto.randomUUID();
  store.ensureThread(tid);
  changed();
  return tid;
}
export function renameThread(id, title) { if (!store.getThread(id)) throw new Error('Nie ma takiej rozmowy.'); store.renameThread(id, title); changed(); }
export function deleteThread(id) {
  if (id === THREAD) { clearThread(id); return; }
  store.setThreadDeleted(id, true); changed();
}
export function restoreThread(id) { store.setThreadDeleted(id, false); changed(); }

export function applyPolicy(action, policy) { const r = setPolicy(action, policy); changed(); return r; }
export function forgetFact(id) { const ok = store.removeFact(id); changed(); return ok; }
export function clearThread(thread = THREAD) { thread = validThread(thread); store.clearThread(thread); bus.emit('cleared', thread); changed(); }

export function history(thread = THREAD) {
  const out = [];
  for (const c of store.loadContents(validThread(thread), 200)) {
    const text = c.parts.filter(p => p.text && !p.thought).map(p => p.text).join('');
    if (!text || text.startsWith('[System:')) continue;
    out.push({ role: c.role === 'model' ? 'assistant' : 'user', text, ts: c.ts });
  }
  return out;
}
