// Gzowo Concierge - morning brief: scheduled agent run in its own thread, delivered as a Mac notification and Web Push.
import { EventEmitter } from 'node:events';
import { store } from './db.mjs';
import { config } from './config.mjs';
import { pushAll, subscriptions } from './push.mjs';

export const BRIEF_THREAD = 'poranny-brief';
export const briefBus = new EventEmitter();

const DEFAULTS = { enabled: true, time: '07:00', weekends: false };
const DAYS = ['niedziela', 'poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota'];
let running = false;

export function getBrief() {
  const s = { ...DEFAULTS, ...(store.getSetting('brief', null) || {}) };
  const last = store.getSetting('briefLast', null);
  return { enabled: !!s.enabled, time: /^\d{2}:\d{2}$/.test(s.time) ? s.time : DEFAULTS.time, weekends: !!s.weekends, thread: BRIEF_THREAD, devices: subscriptions().length, last: last ? { ts: last.ts, date: last.date, text: last.text } : null };
}

export function setBrief(patch = {}) {
  const cur = getBrief();
  const next = {
    enabled: patch.enabled === undefined ? cur.enabled : !!patch.enabled,
    time: /^([01]\d|2[0-3]):[0-5]\d$/.test(patch.time || '') ? patch.time : cur.time,
    weekends: patch.weekends === undefined ? cur.weekends : !!patch.weekends,
  };
  store.setSetting('brief', next);
  briefBus.emit('change');
  return getBrief();
}

function localNow() {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', { timeZone: config.timezone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', weekday: 'short', hourCycle: 'h23' }).formatToParts(new Date()).map(p => [p.type, p.value]));
  const dow = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(parts.weekday);
  return { date: `${parts.year}-${parts.month}-${parts.day}`, hm: `${parts.hour}:${parts.minute}`, dow };
}

const toMin = hm => Number(hm.slice(0, 2)) * 60 + Number(hm.slice(3));

function strip(text) {
  return text.replace(/\*\*/g, '').replace(/^#+\s*/gm, '').replace(/^[-*•]\s+/gm, '').replace(/\s+/g, ' ').trim();
}

export function summarize(text) {
  const plain = strip(text);
  return plain.length <= 170 ? plain : plain.slice(0, 167).replace(/\s+\S*$/, '') + '…';
}

export async function runBrief({ manual = false } = {}) {
  if (running) return { ok: false, error: 'Brief już się przygotowuje.' };
  running = true;
  try {
    const { chat } = await import('./commands.mjs');
    const now = localNow();
    store.ensureThread(BRIEF_THREAD);
    store.renameThread(BRIEF_THREAD, 'Poranny brief');
    const prompt = `[System: poranny brief. Dziś jest ${DAYS[now.dow]}, ${now.date}. Przygotuj dla Jurka krótki poranny brief. Zignoruj poprzednie briefe w tej rozmowie i pobierz świeże dane narzędziami: kalendarz na dziś i jutro, pogoda, przypomnienia (jeśli konektor jest włączony). Format: jedno zdanie powitania, potem 3 do 6 zwięzłych punktów (plan dnia z godzinami, pogoda i co ubrać, terminy i rzeczy do zapamiętania), na końcu jedno zdanie praktycznej rady. Maksymalnie 120 słów, po polsku, bez emoji, zwracaj się do niego po imieniu. Nie pytaj o nic, nie proponuj dodatkowych akcji.]`;
    let text = '';
    let failed = '';
    await chat(prompt, ev => { if (ev.type === 'text') text += (text ? '\n' : '') + ev.text; else if (ev.type === 'error') failed = ev.message; }, { thread: BRIEF_THREAD });
    if (!text.trim()) throw new Error(failed || 'Pusta odpowiedź modelu.');
    const last = { ts: Date.now(), date: now.date, text: text.trim() };
    store.setSetting('briefLast', last);
    const message = { title: 'Poranny brief', body: summarize(text), url: `/?thread=${BRIEF_THREAD}`, tag: 'brief' };
    const pushed = await pushAll(message).catch(() => ({ sent: 0 }));
    briefBus.emit('ready', { ...message, thread: BRIEF_THREAD, ts: last.ts, manual });
    briefBus.emit('change');
    return { ok: true, pushed: pushed.sent, devices: pushed.total ?? subscriptions().length };
  } catch (err) {
    return { ok: false, error: String(err.message || err) };
  } finally {
    running = false;
  }
}

let attempts = { date: '', n: 0, ts: 0 };

async function tick() {
  const b = getBrief();
  if (!b.enabled || running) return;
  const now = localNow();
  if (b.last?.date === now.date) return;
  if (!b.weekends && (now.dow === 0 || now.dow === 6)) return;
  const mins = toMin(now.hm), at = toMin(b.time);
  if (mins < at || mins > at + 240) return;
  if (attempts.date !== now.date) attempts = { date: now.date, n: 0, ts: 0 };
  if (attempts.n >= 3 || Date.now() - attempts.ts < 10 * 60 * 1000) return;
  attempts.n++; attempts.ts = Date.now();
  await runBrief();
}

export function startBrief() {
  setInterval(() => tick().catch(() => {}), 30000).unref?.();
  setTimeout(() => tick().catch(() => {}), 8000).unref?.();
}
