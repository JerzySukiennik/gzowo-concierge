// Gzowo Concierge - shared command layer used by the local HTTP API and the Firebase relay.
import { EventEmitter } from 'node:events';
import crypto from 'node:crypto';
import { run, resolveApproval } from './agent.mjs';
import { live } from './live-state.mjs';
import { store } from './db.mjs';
import { listPolicies, setPolicy } from './tools/index.mjs';

export const THREAD = 'main';
export const bus = new EventEmitter();
const locks = new Map();
let active = 0;

function queue(thread, job) {
  const prev = locks.get(thread) || Promise.resolve();
  const next = prev.catch(() => {}).then(job);
  locks.set(thread, next);
  return next;
}

export function snapshot() {
  return {
    busy: active > 0,
    policies: listPolicies(),
    facts: store.facts(),
    pending: store.pendingApprovals().map(a => ({ id: a.id, summary: a.summary })),
  };
}

const changed = () => bus.emit('state');

function track(rid, send) {
  return e => { const ev = { ...e, rid }; send(ev); bus.emit('event', ev); };
}

async function tracked(fn) {
  active++; changed();
  try { await fn(); } finally { active--; changed(); }
}

export function chat(text, send = () => {}, { cid } = {}) {
  const rid = cid || crypto.randomUUID();
  bus.emit('event', { type: 'user', text, rid, cid: rid });
  const emit = track(rid, send);
  return queue(THREAD, () => tracked(() => run(THREAD, text, emit)))
    .catch(err => emit({ type: 'error', message: String(err.message || err) }));
}

export function approve(id, yes, send = () => {}) {
  const rid = crypto.randomUUID();
  const emit = track(rid, send);
  const quiet = live.sessions.size > 0;
  return queue(THREAD, () => tracked(async () => {
    const r = await resolveApproval(id, yes, emit, { quiet });
    if (quiet && r) bus.emit('approval-result', r);
  }))
    .catch(err => emit({ type: 'error', message: String(err.message || err) }));
}

export function applyPolicy(action, policy) { const r = setPolicy(action, policy); changed(); return r; }
export function forgetFact(id) { const ok = store.removeFact(id); changed(); return ok; }
export function clearThread() { store.clearThread(THREAD); bus.emit('cleared'); changed(); }

export function history() {
  const out = [];
  for (const c of store.loadContents(THREAD, 200)) {
    const text = c.parts.filter(p => p.text && !p.thought).map(p => p.text).join('');
    if (!text || text.startsWith('[System:')) continue;
    out.push({ role: c.role === 'model' ? 'assistant' : 'user', text, ts: c.ts });
  }
  return out;
}
