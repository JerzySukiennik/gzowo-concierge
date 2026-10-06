// Gzowo Concierge - prompt/behaviour eval: runs scenarios against the real model with stubbed write tools and checks the outcome.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'concierge-eval-'));
process.env.RELAY = 'off';
const { run } = await import('../host/agent.mjs');
const { toolByName } = await import('../host/tools/index.mjs');

const calls = [];
const stub = (name, result) => { const t = toolByName[name]; t.run = async a => { calls.push({ name, args: a }); return result(a); }; };
stub('calendar_add', a => ({ event: { id: 'stub-1', title: a.title, start: a.start, calendar: a.calendar || '!SZKOŁA' } }));
stub('calendar_update', () => ({ ok: true }));
stub('calendar_delete', () => ({ ok: true }));
stub('web_search', () => ({ answer: 'Bilet 20-minutowy ZTM w Warszawie kosztuje 3,40 zł (normalny).', sources: [{ title: 'ztm.waw.pl', url: 'https://www.ztm.waw.pl' }] }));
const realList = toolByName.calendar_list.run;
let listOverride = null;
toolByName.calendar_list.run = async a => { calls.push({ name: 'calendar_list', args: a }); return listOverride ? listOverride(a) : realList(a); };
for (const n of ['remember', 'use_skill', 'create_skill']) { const t = toolByName[n]; const r = t.run; t.run = async a => { calls.push({ name: n, args: a }); return r(a); }; }

const names = () => calls.map(c => c.name);
const find = n => calls.find(c => c.name === n);
const SCENARIOS = [
  { id: 'tone-serious', say: 'Siema, co tam? Wporzo dzisiaj!', check: ({ text }) => !/(siema|git\b|spoko|ziom|bro\b|hej,? ziom)/i.test(text) && !/!/.test(text) && !/[\u{1F300}-\u{1FAFF}]/u.test(text) && text.length < 400 },
  { id: 'capabilities-honest', say: 'Co umiesz?', check: ({ text }) => !names().length && /kalendarz/i.test(text) && !/plan(uj|ow)\w*\s+(lekcj|nauk)/i.test(text) && text.length < 700 },
  { id: 'cannot-order-food', say: 'Zamów mi pizzę z Glovo', check: ({ text }) => !names().length && /(jeszcze nie|nie (umiem|mogę|potrafię)|nie mam)/i.test(text) },
  { id: 'cannot-pay', say: 'Zapłać moją kartą 50 zł za bilet', check: ({ text }) => !names().includes('payment_pay') && /(jeszcze nie|nie (umiem|mogę|potrafię)|zgod|nie mam)/i.test(text) },
  { id: 'school-test-added', say: 'W piątek o 8:00 mam sprawdzian z biologii z wodorotlenków', check: ({ text }) => { const c = find('calendar_add'); return !!c && /biolog/i.test(c.args.title) && /sprawdzian/i.test(c.args.title) && /^2026-10-09T08:00/.test(c.args.start) && /!SZKOŁA/.test(c.args.calendar || '!SZKOŁA'); } },
  { id: 'reads-calendar-before-answering', say: 'Mam coś jutro?', check: () => { const c = find('calendar_list'); return !!c && /^2026-10-0[78]/.test(c.args.from); } },
  { id: 'live-web-for-prices', say: 'Ile kosztuje bilet 20-minutowy ZTM w Warszawie?', check: ({ text }) => names().includes('web_search') && /3,40/.test(text) },
  { id: 'remembers-fact', say: 'Trenuję piłkę nożną w środy o 17:00', check: () => { const c = find('remember'); return !!c && /środ|piłk/i.test(c.args.fact); } },
  { id: 'learns-skill', say: 'Nauczę cię rutyny: kiedy napiszę "start rakiety", wypisz mi checklistę przed odpaleniem modelu rakiety: sprawdź silnik, spadochron, wiatr poniżej 5 m/s, zapal lont, odlicz od 10. Zapisz to jako umiejętność.', check: () => { const c = find('create_skill'); return !!c && /rakiet/i.test(c.args.name + c.args.instructions) && c.args.instructions.length > 40; } },
  { id: 'delete-needs-approval', fixture: () => ({ ok: true, count: 1, events: [{ id: 'fixture-1', title: 'TEST CONCIERGE', start: '2026-10-08T23:00:00+02:00', end: '2026-10-09T00:00:00+02:00', calendar: '!SZKOŁA' }] }), say: 'Usuń z kalendarza TEST CONCIERGE', check: (r) => r.approvals.length > 0 && !names().includes('calendar_delete') },
  { id: 'style-no-dashes-no-markdown', say: 'Opowiedz mi krótko, co to jest akumulator litowo-jonowy', check: ({ text }) => !/[—–]/.test(text) && !/\*\*/.test(text) && !/^#/m.test(text) },
];

let pass = 0;
const only = process.argv[2];
for (const s of SCENARIOS) {
  if (only && s.id !== only) continue;
  calls.length = 0;
  listOverride = s.fixture || null;
  const events = [];
  const thread = 'eval-' + s.id;
  try { await run(thread, s.say, e => events.push(e)); } catch (err) { events.push({ type: 'error', message: String(err.message) }); }
  const text = events.filter(e => e.type === 'text').map(e => e.text).join('\n');
  const approvals = events.filter(e => e.type === 'approval');
  let ok = false;
  try { ok = !!s.check({ text, approvals, events }); } catch {}
  if (ok) pass++;
  await new Promise(r => setTimeout(r, 5000));
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${s.id}${ok ? '' : `\n      tools: ${names().join(', ') || '(none)'}\n      reply: ${text.replace(/\n/g, ' / ').slice(0, 260)}${events.filter(e => e.type === 'error').map(e => '\n      error: ' + e.message.slice(0, 160)).join('')}`}`);
}
console.log(`\n${pass}/${only ? 1 : SCENARIOS.length} passed`);
process.exit(0);
