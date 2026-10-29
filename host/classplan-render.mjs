// Gzowo Concierge - class plan PDF in the Minimal look, printed by headless Chrome, with the disclaimer on every page.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';

const BROWSERS = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser', '/Applications/Chromium.app/Contents/MacOS/Chromium'];
const MONTHS = ['stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca', 'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia'];
const DAYS = ['niedziela', 'poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota'];
const SHORT = ['nd', 'pn', 'wt', 'śr', 'czw', 'pt', 'sb'];
export const DISCLAIMER = 'Informacje od Jurka. Mogą być niepełne, jeśli nie było mnie w szkole, nie uważałem albo czegoś nie zapisałem.';
export const SIGNATURE = 'Made by Gzowo Concierge';
const TYPE_LABEL = { test: 'Sprawdzian', quiz: 'Kartkówka', exam: 'Egzamin', homework: 'Zadanie', event: 'Wydarzenie', holiday: 'Święto', day_off: 'Wolne', info: 'Info' };

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const day = s => new Date(`${s}T12:00:00`);
const addDays = (s, n) => { const d = day(s); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
const longDate = s => { const d = day(s); return `${DAYS[d.getDay()]}, ${d.getDate()} ${MONTHS[d.getMonth()]}`; };
const shortDate = s => { const d = day(s); return `${SHORT[d.getDay()]} ${d.getDate()}.${String(d.getMonth() + 1).padStart(2, '0')}`; };
const cap = s => String(s || '').charAt(0).toUpperCase() + String(s || '').slice(1);
const plural = (n, one, few, many) => (n === 1 ? one : [2, 3, 4].includes(n % 10) && ![12, 13, 14].includes(n % 100) ? few : many);

function period(from, to) {
  const a = day(from), b = day(to);
  return a.getMonth() === b.getMonth() ? `${a.getDate()}-${b.getDate()} ${MONTHS[b.getMonth()]} ${b.getFullYear()}` : `${a.getDate()} ${MONTHS[a.getMonth()]} - ${b.getDate()} ${MONTHS[b.getMonth()]} ${b.getFullYear()}`;
}

function weeks(from, to) {
  const start = addDays(from, 1 - (day(from).getDay() || 7));
  const rows = [];
  for (let w = start; w <= to; w = addDays(w, 7)) rows.push([0, 1, 2, 3, 4].map(i => addDays(w, i)));
  return rows;
}

const topicOf = t => {
  const s = String(t.subject || '').trim(), topic = String(t.topic || '').trim();
  return s && topic.toLowerCase().startsWith(s.toLowerCase()) ? topic.slice(s.length).replace(/^[\s,:.-]+/, '') : topic;
};

function body(plan, { from, to }) {
  const byDay = new Map(plan.days.map(d => [d.date, d.entries]));
  const rows = weeks(from, to);
  const grid = rows.map(row => `
    <div class="week">${row.map(d => {
      const entries = byDay.get(d) || [];
      const off = entries.some(e => e.type === 'holiday' || e.type === 'day_off');
      const outside = d < from || d > to;
      return `<div class="cell${off ? ' off' : ''}${outside ? ' outside' : ''}">
        <div class="cell-date"><span class="num">${day(d).getDate()}</span><span class="dow">${SHORT[day(d).getDay()]}</span></div>
        ${entries.map(e => `<div class="entry t-${e.type}"><span class="tag">${esc(TYPE_LABEL[e.type] || e.type)}</span>${e.subject && !e.text.toLowerCase().includes(e.subject.toLowerCase()) ? `<b>${esc(e.subject)}</b> ` : ''}${esc(e.text)}</div>`).join('')}
      </div>`;
    }).join('')}</div>`).join('');

  const tests = [...plan.tests].sort((a, b) => a.date.localeCompare(b.date));
  const testRows = tests.length ? tests.map(t => `
    <div class="test">
      <div class="test-date">${esc(longDate(t.date))}</div>
      <div class="test-main">
        <div class="test-title"><span class="subject">${esc(t.subject)}</span> <span class="kind">${esc(cap(t.kind))}</span> <span class="sure s-${esc(t.certainty)}">${esc(t.certainty)}</span></div>
        ${topicOf(t) ? `<div class="topic">${esc(topicOf(t))}</div>` : ''}
        ${t.scope.length ? `<ul class="scope">${t.scope.map(s => `<li>${esc(s)}</li>`).join('')}</ul>` : ''}
        <div class="source">Źródło: ${esc(t.source)}</div>
      </div>
    </div>`).join('') : '<p class="empty">Nie wiemy o żadnych sprawdzianach ani kartkówkach.</p>';

  const events = [...plan.events].sort((a, b) => a.date.localeCompare(b.date));
  const eventRows = events.length ? events.map(e => `
    <div class="row">
      <div class="row-date">${esc(shortDate(e.date))}${e.end_date && e.end_date !== e.date ? `<br>${esc(shortDate(e.end_date))}` : ''}</div>
      <div class="row-main"><div class="row-title">${esc(e.title)} <span class="ev-kind">${esc(e.kind)}</span></div>${e.detail ? `<div class="row-sub">${esc(e.detail)}</div>` : ''}</div>
    </div>`).join('') : '<p class="empty">Brak dni wolnych i wydarzeń.</p>';

  const homework = plan.homework.length ? `
    <section class="homework"><h2>Zadania domowe</h2>${plan.homework.map(h => `
      <div class="row"><div class="row-date">${esc(shortDate(h.due))}</div><div class="row-main"><div class="row-title">${esc(h.subject)}</div><div class="row-sub">${esc(h.task)}</div></div></div>`).join('')}
    </section>` : '';

  const gaps = plan.gaps.length ? `<section class="gaps"><h2>Do sprawdzenia</h2><ul>${plan.gaps.map(g => `<li>${esc(g)}</li>`).join('')}</ul></section>` : '';

  return { grid, testRows, eventRows, homework, gaps, testCount: tests.length, weekCount: rows.length };
}

const CSS = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  :root { --ink: #161618; --mute: #6b6b70; --line: #dcdce0; --soft: #f3f3f5; }
  @page { size: A4; margin: 14mm 13mm 17mm;
    @bottom-left { content: "${DISCLAIMER}"; font: 7.5pt Inter, -apple-system, sans-serif; color: #777; vertical-align: top; padding-top: 4mm; width: 72%; }
    @bottom-right { content: "${SIGNATURE}  ·  " counter(page) "/" counter(pages); font: 7.5pt Inter, -apple-system, sans-serif; color: #777; vertical-align: top; padding-top: 4mm; }
  }
  body { font-family: Inter, -apple-system, sans-serif; color: var(--ink); font-size: 9.6pt; line-height: 1.42; }
  h2 { font-size: 8pt; text-transform: uppercase; letter-spacing: .12em; color: var(--mute); font-weight: 700; margin: 6mm 0 2.5mm; break-after: avoid; }
  ul { padding-left: 4.5mm; }
  .mast { display: flex; justify-content: space-between; align-items: flex-end; border-bottom: 2.2pt solid var(--ink); padding-bottom: 4mm; margin-bottom: 5mm; }
  .mast h1 { font-size: 27pt; font-weight: 800; letter-spacing: -.025em; line-height: 1; }
  .mast .sub { color: var(--mute); font-size: 10pt; margin-top: 2mm; }
  .mast .badge { font: 600 8pt 'JetBrains Mono', monospace; text-transform: uppercase; letter-spacing: .08em; color: var(--mute); text-align: right; }
  .summary { font-size: 11pt; line-height: 1.5; margin-bottom: 2mm; max-width: 165mm; }
  .week { display: grid; grid-template-columns: repeat(5, 1fr); border-top: 1pt solid var(--ink); }
  .week + .week { border-top: 1pt solid var(--line); }
  .cell { padding: 2mm 2mm 3mm; min-height: 24mm; border-left: 1pt solid var(--line); break-inside: avoid; }
  .cell:first-child { border-left: 0; padding-left: 0; }
  .cell.outside { opacity: .3; }
  .cell.off { background: repeating-linear-gradient(135deg, transparent 0 2.2mm, var(--soft) 2.2mm 4.4mm); }
  .cell-date { display: flex; align-items: baseline; gap: 1.5mm; margin-bottom: 1.5mm; }
  .cell-date .num { font-size: 15pt; font-weight: 700; letter-spacing: -.02em; }
  .cell-date .dow { font-size: 7.5pt; text-transform: uppercase; color: var(--mute); letter-spacing: .08em; }
  .entry { font-size: 8pt; line-height: 1.3; margin-top: 1.2mm; break-inside: avoid; }
  .entry .tag { display: block; font: 600 6.5pt 'JetBrains Mono', monospace; text-transform: uppercase; letter-spacing: .06em; color: var(--mute); }
  .entry.t-test .tag, .entry.t-quiz .tag, .entry.t-exam .tag { color: #fff; background: var(--ink); display: inline-block; padding: .3mm 1.2mm; border-radius: 1mm; margin-bottom: .6mm; }
  .test { display: grid; grid-template-columns: 34mm 1fr; gap: 4mm; padding: 3mm 0; border-bottom: 1pt solid var(--line); break-inside: avoid; }
  .tests h2 + .test { border-top: 1pt solid var(--ink); }
  .test-date { font: 600 8.5pt 'JetBrains Mono', monospace; padding-top: .6mm; }
  .test-title { font-size: 11pt; font-weight: 700; display: flex; flex-wrap: wrap; gap: 2mm; align-items: baseline; }
  .test-title .kind { font-weight: 400; color: var(--mute); }
  .topic { font-size: 10pt; margin-top: .6mm; }
  .scope { columns: 2; column-gap: 8mm; margin-top: 1.6mm; }
  .scope li { break-inside: avoid; margin: .5mm 0; }
  .source { font-size: 7.5pt; color: var(--mute); margin-top: 1.4mm; }
  .sure { font: 600 7pt 'JetBrains Mono', monospace; text-transform: uppercase; padding: .5mm 1.6mm; border: 1pt solid var(--ink); border-radius: 1mm; }
  .sure.s-pewne { background: var(--ink); color: #fff; }
  .sure.s-niepewne { border-style: dashed; color: var(--mute); border-color: var(--mute); }
  .cols { display: grid; grid-template-columns: 1.15fr 1fr; gap: 9mm; }
  .row { display: grid; grid-template-columns: 16mm 1fr; gap: 3.5mm; align-items: baseline; padding: 2.4mm 0; border-bottom: 1pt solid var(--line); break-inside: avoid; }
  .row-date { font: 600 8.5pt 'JetBrains Mono', monospace; }
  .row-title { font-weight: 600; font-size: 10.5pt; }
  .row-sub { color: var(--mute); }
  .ev-kind { font-size: 7.5pt; color: var(--mute); font-weight: 400; margin-left: 1mm; }
  .gaps ul { list-style: none; padding: 0; }
  .gaps li { padding-left: 5mm; position: relative; margin: 1mm 0; break-inside: avoid; }
  .gaps li:before { content: "?"; position: absolute; left: 0; font-weight: 800; }
  .empty { opacity: .7; }
`;

export function planHtml(plan, { from, to }) {
  const p = body(plan, { from, to });
  const span = p.weekCount === 1 ? 'plan na tydzień' : `plan na ${p.weekCount} ${plural(p.weekCount, 'tydzień', 'tygodnie', 'tygodni')}`;
  return `<!doctype html><html lang="pl"><head><meta charset="utf-8"><title>${esc(plan.title)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;600&display=block" rel="stylesheet">
<style>${CSS}</style></head><body>
<header class="mast"><div><h1>Klasa 8K</h1><div class="sub">${esc(period(from, to))}  ·  sprawdziany, wolne, wydarzenia</div></div><div class="badge">${span}<br>${p.testCount} ${plural(p.testCount, 'test', 'testy', 'testów')}</div></header>
<p class="summary">${esc(plan.summary)}</p>
<section class="cal"><h2>${p.weekCount === 1 ? 'Tydzień' : 'Tygodnie'}</h2>${p.grid}</section>
<section class="tests"><h2>Sprawdziany i kartkówki: z czego są</h2>${p.testRows}</section>
<div class="cols">
  <section class="events"><h2>Wolne i wydarzenia</h2>${p.eventRows}</section>
  <div>${p.homework}${p.gaps}</div>
</div>
</body></html>`;
}

function browser() {
  const b = BROWSERS.find(p => fs.existsSync(p));
  if (!b) throw new Error('Do PDF potrzebny jest Google Chrome albo Brave.');
  return b;
}

export async function renderPlan(plan, { from, to, out, workDir }) {
  const html = path.join(workDir || os.tmpdir(), 'plan.html');
  fs.writeFileSync(html, planHtml(plan, { from, to }));
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'classplan-chrome-'));
  try {
    await new Promise((resolve, reject) => execFile(browser(), [
      '--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check', `--user-data-dir=${profile}`,
      '--no-pdf-header-footer', '--virtual-time-budget=15000', `--print-to-pdf=${out}`, `file://${html}`,
    ], { timeout: 90000 }, err => (err ? reject(err) : resolve())));
  } finally { fs.rmSync(profile, { recursive: true, force: true }); }
  if (!fs.existsSync(out) || fs.statSync(out).size < 2000) throw new Error('Chrome nie zrobił PDF-u.');
  return out;
}
