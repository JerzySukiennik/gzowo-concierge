// Gzowo Concierge - class plan PDF: one HTML layout in several looks, printed by headless Chrome, with the disclaimer on every page.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';

const BROWSERS = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser', '/Applications/Chromium.app/Contents/MacOS/Chromium'];
const MONTHS = ['stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca', 'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia'];
const DAYS = ['niedziela', 'poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota'];
const SHORT = ['nd', 'pn', 'wt', 'śr', 'czw', 'pt', 'sb'];
export const DISCLAIMER = 'Informacje od Jurka. Mogą być niepełne, jeśli nie było mnie w szkole, nie uważałem albo czegoś nie zapisałem.';
const SIGNATURE = 'Made by Gzowo Concierge';
const TYPE_LABEL = { test: 'Sprawdzian', quiz: 'Kartkówka', exam: 'Egzamin', homework: 'Zadanie', event: 'Wydarzenie', holiday: 'Święto', day_off: 'Wolne', info: 'Info' };
const SUBJECT_HUES = [212, 152, 268, 38, 186, 236, 96, 300, 26, 170, 250, 56];

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const day = s => new Date(`${s}T12:00:00`);
const addDays = (s, n) => { const d = day(s); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
const longDate = s => { const d = day(s); return `${DAYS[d.getDay()]}, ${d.getDate()} ${MONTHS[d.getMonth()]}`; };
const shortDate = s => { const d = day(s); return `${SHORT[d.getDay()]} ${d.getDate()}.${String(d.getMonth() + 1).padStart(2, '0')}`; };
const dayMonth = s => { const d = day(s); return `${d.getDate()} ${MONTHS[d.getMonth()]}`; };

function period(from, to) {
  const a = day(from), b = day(to);
  return a.getMonth() === b.getMonth() ? `${a.getDate()}-${b.getDate()} ${MONTHS[b.getMonth()]} ${b.getFullYear()}` : `${a.getDate()} ${MONTHS[a.getMonth()]} - ${b.getDate()} ${MONTHS[b.getMonth()]} ${b.getFullYear()}`;
}

function subjectHue(name, map) {
  const k = String(name || '').toLowerCase().trim();
  if (!map.has(k)) map.set(k, SUBJECT_HUES[map.size % SUBJECT_HUES.length]);
  return map.get(k);
}

function weeks(from, to) {
  const start = addDays(from, 1 - (day(from).getDay() || 7));
  const rows = [];
  for (let w = start; w <= to; w = addDays(w, 7)) rows.push([0, 1, 2, 3, 4].map(i => addDays(w, i)));
  return rows;
}

const kindClass = k => ({ sprawdzian: 'test', 'kartkówka': 'quiz', 'egzamin próbny': 'exam', test: 'test', 'odpowiedź ustna': 'quiz', inne: 'info' })[k] || 'info';
const topicOf = t => {
  const s = String(t.subject || '').trim(), topic = String(t.topic || '').trim();
  return s && topic.toLowerCase().startsWith(s.toLowerCase()) ? topic.slice(s.length).replace(/^[\s,:.-]+/, '') : topic;
};
const titleOf = t => {
  const s = String(t.subject || '').trim(), topic = topicOf(t);
  const lead = s.toLowerCase().split(/[\s(,:]/)[0];
  if (!topic) return `<span class="subject">${esc(s)}</span>`;
  if (lead.length >= 4 && topic.toLowerCase().startsWith(lead)) return esc(topic);
  return `<span class="subject">${esc(s)}</span>: ${esc(topic)}`;
};
const cap = s => String(s || '').charAt(0).toUpperCase() + String(s || '').slice(1);

function body(plan, { from, to }) {
  const hues = new Map();
  const byDay = new Map(plan.days.map(d => [d.date, d.entries]));
  const hueStyle = s => (s ? ` style="--h:${subjectHue(s, hues)}"` : '');
  const grid = weeks(from, to).map(row => `
    <div class="week">${row.map(d => {
      const entries = byDay.get(d) || [];
      const off = entries.some(e => e.type === 'holiday' || e.type === 'day_off');
      const outside = d < from || d > to;
      return `<div class="cell${off ? ' off' : ''}${outside ? ' outside' : ''}">
        <div class="cell-date"><span class="dow">${SHORT[day(d).getDay()]}</span><span class="num">${day(d).getDate()}</span></div>
        ${entries.map(e => `<div class="entry t-${e.type}"${hueStyle(e.subject)}><span class="tag">${esc(TYPE_LABEL[e.type] || e.type)}</span>${e.subject && !e.text.toLowerCase().includes(e.subject.toLowerCase()) ? `<b>${esc(e.subject)}</b> ` : ''}${esc(e.text)}</div>`).join('')}
      </div>`;
    }).join('')}</div>`).join('');

  const tests = [...plan.tests].sort((a, b) => a.date.localeCompare(b.date));
  const testRows = tests.length ? tests.map((t, i) => `
    <div class="row k-${kindClass(t.kind)}"${hueStyle(t.subject)}>
      <div class="row-date">${esc(shortDate(t.date))}</div>
      <div class="row-main"><div class="row-title"><span class="subject">${esc(t.subject)}</span> <span class="kind">${esc(cap(t.kind))}</span></div><div class="row-sub">${esc(topicOf(t))}</div>
        <div class="row-side"><span class="sure s-${esc(t.certainty)}">${esc(t.certainty)}</span><span class="page-ref">notatki ${i + 1}</span></div></div>
    </div>`).join('') : '<p class="empty">W tych dwóch tygodniach nie wiemy o żadnych sprawdzianach ani kartkówkach.</p>';

  const events = [...plan.events].sort((a, b) => a.date.localeCompare(b.date));
  const eventRows = events.length ? events.map(e => `
    <div class="row ev ev-${esc(e.kind.replace(/\s+/g, '-'))}">
      <div class="row-date">${esc(shortDate(e.date))}${e.end_date && e.end_date !== e.date ? `<br>${esc(shortDate(e.end_date))}` : ''}</div>
      <div class="row-main"><div class="row-title">${esc(e.title)} <span class="ev-kind">${esc(e.kind)}</span></div>${e.detail ? `<div class="row-sub">${esc(e.detail)}</div>` : ''}</div>
    </div>`).join('') : '<p class="empty">Brak dni wolnych i wydarzeń.</p>';

  const homework = plan.homework.length ? `
    <section class="block homework"><h2>Zadania domowe</h2>${plan.homework.map(h => `
      <div class="row"${hueStyle(h.subject)}><div class="row-date">${esc(shortDate(h.due))}</div><div class="row-main"><div class="row-title"><span class="subject">${esc(h.subject)}</span></div><div class="row-sub">${esc(h.task)}</div></div></div>`).join('')}
    </section>` : '';

  const gaps = plan.gaps.length ? `<section class="block gaps"><h2>Do sprawdzenia</h2><ul>${plan.gaps.map(g => `<li>${esc(g)}</li>`).join('')}</ul></section>` : '';

  const notes = tests.map((t, i) => `
    <article class="notes"${hueStyle(t.subject)}>
      <header class="notes-head">
        <div class="notes-num">${i + 1}</div>
        <div>
          <div class="notes-kicker">${esc(cap(t.kind))} · ${esc(longDate(t.date))} · ${esc(t.certainty)}</div>
          <h2 class="notes-title">${titleOf(t)}</h2>
          <div class="notes-source">Źródło: ${esc(t.source)}</div>
        </div>
      </header>
      ${t.scope.length ? `<div class="scope"><h3>Zakres</h3><ul>${t.scope.map(s => `<li>${esc(s)}</li>`).join('')}</ul></div>` : ''}
      ${t.notes.map(n => `<section class="note-sec${n.basis === 'uzupełnione' ? ' filled' : ''}"><h3>${esc(n.heading)}${n.basis === 'uzupełnione' ? '<span class="basis">uzupełnione</span>' : ''}</h3><ul>${n.points.map(p => `<li>${esc(p)}</li>`).join('')}</ul></section>`).join('')}
      ${t.key_terms.length ? `<section class="terms"><h3>Pojęcia</h3><dl>${t.key_terms.map(k => `<div><dt>${esc(k.term)}</dt><dd>${esc(k.meaning)}</dd></div>`).join('')}</dl></section>` : ''}
      ${t.examples.length ? `<section class="examples"><h3>Przykłady</h3>${t.examples.map(x => `<div class="example"><div class="ex-q">${esc(x.problem)}</div><div class="ex-a">${esc(x.solution)}</div></div>`).join('')}</section>` : ''}
      ${t.practice.length ? `<section class="practice"><h3>Sprawdź się</h3><ol>${t.practice.map(p => `<li>${esc(p)}</li>`).join('')}</ol></section>` : ''}
    </article>`).join('');

  return { grid, testRows, eventRows, homework, gaps, notes, testCount: tests.length };
}

const BASE_CSS = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  @page { size: A4; margin: 14mm 13mm 17mm;
    @bottom-left { content: "${DISCLAIMER}"; font: 7.5pt var(--foot-font, -apple-system, sans-serif); color: #777; vertical-align: top; padding-top: 4mm; width: 72%; }
    @bottom-right { content: "${SIGNATURE}  ·  " counter(page) "/" counter(pages); font: 7.5pt var(--foot-font, -apple-system, sans-serif); color: #777; vertical-align: top; padding-top: 4mm; }
  }
  body { font-size: 9.6pt; line-height: 1.42; }
  .week { display: grid; grid-template-columns: repeat(5, 1fr); }
  .cell { break-inside: avoid; }
  .entry { break-inside: avoid; }
  .row { display: grid; grid-template-columns: 16mm 1fr; gap: 3.5mm; align-items: baseline; break-inside: avoid; }
  .row-side { display: flex; gap: 2.5mm; align-items: baseline; margin-top: 1mm; }
  .ev-kind { margin-left: 1mm; }
  .cols .homework { margin-top: 2mm; }
  .gaps ul { columns: 2; column-gap: 8mm; }
  .gaps li { break-inside: avoid; }
  .notes { break-before: page; }
  .notes + .notes { break-before: auto; margin-top: 9mm; }
  .notes-head { display: grid; grid-template-columns: auto 1fr; gap: 4mm; align-items: start; break-after: avoid; }
  h2, h3 { break-after: avoid; }
  .note-sec, .terms > dl > div, .example, .practice li, .scope { break-inside: avoid; }
  ul, ol { padding-left: 4.5mm; }
  li { margin: .8mm 0; }
  .terms dl > div { display: grid; grid-template-columns: 38mm 1fr; gap: 3mm; padding: 1.2mm 0; }
  .empty { opacity: .7; }
`;

const THEME_DEFS = {
  minimal: {
    name: 'Minimal',
    fonts: 'Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500',
    css: `
      :root { --ink: #161618; --mute: #6b6b70; --line: #dcdce0; --soft: #f3f3f5; --foot-font: Inter; }
      body { font-family: Inter, -apple-system, sans-serif; color: var(--ink); }
      .mast { display: flex; justify-content: space-between; align-items: flex-end; border-bottom: 2.2pt solid var(--ink); padding-bottom: 4mm; margin-bottom: 5mm; }
      .mast h1 { font-size: 27pt; font-weight: 800; letter-spacing: -.025em; line-height: 1; }
      .mast .sub { color: var(--mute); font-size: 10pt; margin-top: 2mm; }
      .mast .badge { font: 600 8pt 'JetBrains Mono', monospace; text-transform: uppercase; letter-spacing: .08em; color: var(--mute); text-align: right; }
      .summary { font-size: 11pt; line-height: 1.5; margin-bottom: 6mm; max-width: 165mm; }
      h2 { font-size: 8pt; text-transform: uppercase; letter-spacing: .12em; color: var(--mute); font-weight: 700; margin: 6mm 0 2.5mm; }
      .week { border-top: 1pt solid var(--ink); }
      .week + .week { border-top: 1pt solid var(--line); }
      .cell { padding: 2mm 2mm 3mm; min-height: 24mm; border-left: 1pt solid var(--line); }
      .cell:first-child { border-left: 0; padding-left: 0; }
      .cell.outside { opacity: .3; }
      .cell.off { background: repeating-linear-gradient(135deg, transparent 0 2.2mm, var(--soft) 2.2mm 4.4mm); }
      .cell-date { display: flex; align-items: baseline; gap: 1.5mm; margin-bottom: 1.5mm; }
      .cell-date .num { font-size: 15pt; font-weight: 700; letter-spacing: -.02em; }
      .cell-date .dow { font-size: 7.5pt; text-transform: uppercase; color: var(--mute); letter-spacing: .08em; order: 2; }
      .entry { font-size: 8pt; line-height: 1.3; margin-top: 1.2mm; }
      .entry .tag { display: block; font: 600 6.5pt 'JetBrains Mono', monospace; text-transform: uppercase; letter-spacing: .06em; color: var(--mute); }
      .entry.t-test .tag, .entry.t-quiz .tag, .entry.t-exam .tag { color: #fff; background: var(--ink); display: inline-block; padding: .3mm 1.2mm; border-radius: 1mm; margin-bottom: .6mm; }
      .row { padding: 2.4mm 0; border-bottom: 1pt solid var(--line); }
      .row-date { font: 600 8.5pt 'JetBrains Mono', monospace; }
      .row-title { font-weight: 600; font-size: 10.5pt; }
      .row-title .kind { font-weight: 400; color: var(--mute); }
      .row-sub { color: var(--mute); }
      .sure { font: 600 7pt 'JetBrains Mono', monospace; text-transform: uppercase; padding: .5mm 1.6mm; border: 1pt solid var(--ink); border-radius: 1mm; }
      .sure.s-pewne { background: var(--ink); color: #fff; }
      .sure.s-niepewne { border-style: dashed; color: var(--mute); border-color: var(--mute); }
      .page-ref, .ev-kind { font-size: 7.5pt; color: var(--mute); }
      .cols { display: grid; grid-template-columns: 1.15fr 1fr; gap: 9mm; }
      .gaps ul { list-style: none; padding: 0; } .gaps li { padding-left: 5mm; position: relative; } .gaps li:before { content: "?"; position: absolute; left: 0; font-weight: 800; }
      .notes-num { font-size: 30pt; font-weight: 800; line-height: .9; letter-spacing: -.04em; }
      .notes-kicker { font: 600 7.5pt 'JetBrains Mono', monospace; text-transform: uppercase; letter-spacing: .07em; color: var(--mute); }
      .notes-title { font-size: 17pt; text-transform: none; letter-spacing: -.015em; color: var(--ink); margin: 1mm 0; font-weight: 800; }
      .notes-source { font-size: 8pt; color: var(--mute); }
      .notes h3 { font-size: 10.5pt; font-weight: 700; margin: 5mm 0 1.5mm; display: flex; gap: 2mm; align-items: baseline; }
      .basis { font: 600 6.5pt 'JetBrains Mono', monospace; text-transform: uppercase; border: 1pt dashed var(--mute); color: var(--mute); padding: .2mm 1.2mm; border-radius: 1mm; }
      .scope { background: var(--soft); padding: 3mm 4mm; margin-top: 4mm; border-radius: 1.5mm; } .scope h3 { margin-top: 0; }
      .terms dl > div { border-bottom: 1pt solid var(--line); } .terms dt { font-weight: 600; }
      .example { border-left: 2pt solid var(--ink); padding: 1mm 0 1mm 3.5mm; margin: 2.5mm 0; }
      .ex-q { font-weight: 600; } .ex-a { color: #333; white-space: pre-wrap; }
      .practice ol { padding-left: 5mm; }
    `,
    head: (p, info) => `<header class="mast"><div><h1>Klasa 8K</h1><div class="sub">${esc(info.period)}  ·  sprawdziany, wolne, notatki</div></div><div class="badge">plan na 2 tygodnie<br>${info.testCount} ${info.testCount === 1 ? 'test' : 'testy'}</div></header>`,
  },
  zeszyt: {
    name: 'Zeszyt',
    fonts: 'Nunito:wght@400;600;700;800&family=Caveat:wght@600;700',
    css: `
      :root { --ink: #1f2a3a; --mute: #5d6b80; --grid: #dbe6f3; --blue: #2c5fa8; --mark: #ffe46b; --foot-font: Nunito; }
      @page { background: #fbfcfe; }
      body { font-family: Nunito, sans-serif; color: var(--ink); background-image: linear-gradient(var(--grid) .6pt, transparent .6pt), linear-gradient(90deg, var(--grid) .6pt, transparent .6pt); background-size: 5mm 5mm; }
      .mast { border-left: 1.4pt solid var(--blue); padding: 1mm 0 3mm 5mm; margin-bottom: 5mm; }
      .mast h1 { font-family: Caveat, cursive; font-size: 40pt; line-height: .95; color: var(--blue); }
      .mast .sub { font-weight: 700; font-size: 11pt; }
      .summary { font-size: 11pt; background: #fff; border: 1pt solid var(--grid); border-radius: 3mm; padding: 3.5mm 4.5mm; margin-bottom: 4mm; box-shadow: 1mm 1mm 0 var(--grid); }
      h2 { font-family: Caveat, cursive; font-size: 22pt; color: var(--blue); margin: 5mm 0 1.5mm; font-weight: 700; }
      .week { gap: 2mm; margin-bottom: 2mm; }
      .cell { background: #fff; border: 1pt solid var(--grid); border-radius: 2.5mm; padding: 2mm; min-height: 25mm; }
      .cell.outside { opacity: .35; }
      .cell.off { background: #eef3fa; border-style: dashed; }
      .cell-date { display: flex; gap: 1.5mm; align-items: baseline; }
      .cell-date .num { font-family: Caveat, cursive; font-size: 20pt; line-height: .9; color: var(--blue); }
      .cell-date .dow { font-weight: 800; font-size: 7.5pt; text-transform: uppercase; color: var(--mute); }
      .entry { font-size: 8pt; margin-top: 1.4mm; line-height: 1.28; }
      .entry .tag { display: block; font-weight: 800; font-size: 6.8pt; text-transform: uppercase; color: var(--mute); }
      .entry.t-test, .entry.t-quiz, .entry.t-exam { background: linear-gradient(transparent 8%, var(--mark) 8% 92%, transparent 92%); padding: .5mm 1mm; margin-left: -1mm; }
      .entry.t-test .tag, .entry.t-quiz .tag, .entry.t-exam .tag { color: var(--ink); }
      .row { background: #fff; border: 1pt solid var(--grid); border-radius: 2.5mm; padding: 2.2mm 3mm; margin-bottom: 1.6mm; }
      .row-date { font-family: Caveat, cursive; font-size: 15pt; line-height: 1; color: var(--blue); }
      .row-title { font-weight: 800; } .row-title .kind { font-weight: 600; color: var(--mute); }
      .row-sub { color: var(--mute); }
      .k-test .row-title .subject, .k-quiz .row-title .subject, .k-exam .row-title .subject { background: linear-gradient(transparent 45%, var(--mark) 45%); }
      .sure { font-family: Caveat, cursive; font-size: 13pt; color: var(--blue); }
      .sure.s-niepewne { color: var(--mute); }
      .page-ref, .ev-kind { font-size: 7.5pt; color: var(--mute); }
      .cols { display: grid; grid-template-columns: 1.1fr 1fr; gap: 6mm; }
      .gaps ul { background: #fff; border: 1pt dashed var(--blue); border-radius: 2.5mm; padding: 2.5mm 4mm 2.5mm 8mm; }
      .notes-num { font-family: Caveat, cursive; font-size: 46pt; line-height: .8; color: var(--blue); }
      .notes-kicker { font-weight: 800; font-size: 7.5pt; text-transform: uppercase; color: var(--mute); }
      .notes-title { font-family: Nunito, sans-serif; font-size: 17pt; font-weight: 800; color: var(--ink); margin: .5mm 0; }
      .notes-title .subject { background: linear-gradient(transparent 50%, var(--mark) 50%); }
      .notes-source { font-size: 8pt; color: var(--mute); }
      .notes h3 { font-family: Caveat, cursive; font-size: 17pt; color: var(--blue); margin: 4mm 0 .5mm; display: flex; gap: 2mm; align-items: baseline; }
      .basis { font-family: Nunito; font-size: 6.8pt; font-weight: 800; text-transform: uppercase; color: var(--mute); border: 1pt dashed var(--mute); padding: 0 1.2mm; border-radius: 2mm; }
      .note-sec, .scope, .terms, .examples, .practice { background: #fff; border: 1pt solid var(--grid); border-radius: 2.5mm; padding: 1mm 4mm 2.5mm; margin-top: 3mm; }
      .terms dl > div { border-bottom: 1pt dotted var(--grid); } .terms dt { font-weight: 800; }
      .example { padding: 1.5mm 0; border-bottom: 1pt dotted var(--grid); } .ex-q { font-weight: 800; } .ex-a { white-space: pre-wrap; }
    `,
    head: (p, info) => `<header class="mast"><h1>Plan klasy 8K</h1><div class="sub">${esc(info.period)}</div></header>`,
  },
  gazetka: {
    name: 'Gazetka',
    fonts: 'Fraunces:opsz,wght@9..144,400;9..144,600;9..144,800&family=Source+Sans+3:wght@400;600;700',
    css: `
      :root { --ink: #141414; --mute: #5f5f5f; --rule: #141414; --navy: #1f3a5f; --paper: #fbf9f4; --foot-font: 'Source Sans 3'; }
      @page { background: var(--paper); }
      body { font-family: 'Source Sans 3', sans-serif; color: var(--ink); background: var(--paper); font-size: 9.8pt; }
      .mast { text-align: center; border-top: 3pt double var(--rule); border-bottom: 1pt solid var(--rule); padding: 3mm 0 2mm; margin-bottom: 1mm; }
      .mast h1 { font-family: Fraunces, serif; font-weight: 800; font-size: 44pt; letter-spacing: -.02em; line-height: .95; }
      .mast .sub { display: flex; justify-content: space-between; font-size: 8pt; text-transform: uppercase; letter-spacing: .12em; border-top: 1pt solid var(--rule); margin-top: 2.5mm; padding-top: 1.5mm; }
      .summary { font-family: Fraunces, serif; font-size: 12.5pt; line-height: 1.45; padding: 4mm 0; border-bottom: 1pt solid var(--rule); margin-bottom: 3mm; }
      .summary:first-letter { font-size: 30pt; float: left; line-height: .9; padding: 1mm 1.5mm 0 0; font-weight: 800; color: var(--navy); }
      h2 { font-family: Fraunces, serif; font-size: 15pt; font-weight: 800; margin: 5mm 0 2mm; padding-bottom: 1mm; border-bottom: 2pt solid var(--rule); }
      .week { border-bottom: 1pt solid var(--rule); }
      .cell { padding: 2mm 2.2mm 3mm; min-height: 23mm; border-left: .6pt solid #bdb8ad; }
      .cell:first-child { border-left: 0; }
      .cell.outside { opacity: .3; }
      .cell.off { background: #efebe1; }
      .cell-date { display: flex; align-items: baseline; gap: 1.5mm; border-bottom: .6pt solid #bdb8ad; margin-bottom: 1mm; }
      .cell-date .num { font-family: Fraunces, serif; font-size: 17pt; font-weight: 800; }
      .cell-date .dow { font-size: 7pt; text-transform: uppercase; letter-spacing: .1em; color: var(--mute); }
      .entry { font-size: 8pt; line-height: 1.3; margin-top: 1.2mm; }
      .entry .tag { display: block; font-size: 6.5pt; font-weight: 700; text-transform: uppercase; letter-spacing: .1em; color: var(--navy); }
      .entry.t-test, .entry.t-quiz, .entry.t-exam { font-weight: 600; }
      .row { padding: 2.2mm 0; border-bottom: .6pt solid #bdb8ad; }
      .row-date { font-family: Fraunces, serif; font-weight: 600; font-size: 10pt; }
      .row-title { font-family: Fraunces, serif; font-weight: 600; font-size: 11pt; } .row-title .kind { font-family: 'Source Sans 3'; font-size: 8pt; text-transform: uppercase; letter-spacing: .08em; color: var(--navy); font-weight: 700; }
      .row-sub { color: var(--mute); }
      .sure { font-size: 7pt; text-transform: uppercase; letter-spacing: .1em; font-weight: 700; }
      .sure.s-pewne { color: var(--navy); } .sure.s-niepewne { color: var(--mute); font-style: italic; }
      .page-ref, .ev-kind { font-size: 7.5pt; color: var(--mute); font-style: italic; }
      .cols { display: grid; grid-template-columns: 1fr 1fr; gap: 7mm; }
      .cols > div + div { border-left: .6pt solid var(--rule); padding-left: 7mm; }
      .gaps { border: 1pt solid var(--rule); padding: 0 4mm 3mm; margin-top: 5mm; } .gaps h2 { border-bottom-width: 1pt; }
      .notes-head { border-bottom: 2pt solid var(--rule); padding-bottom: 2mm; }
      .notes-num { font-family: Fraunces, serif; font-size: 38pt; font-weight: 800; line-height: .85; color: var(--navy); }
      .notes-kicker { font-size: 7.5pt; text-transform: uppercase; letter-spacing: .12em; color: var(--navy); font-weight: 700; }
      .notes-title { font-family: Fraunces, serif; font-size: 19pt; border: 0; margin: .5mm 0; padding: 0; }
      .notes-source { font-size: 8pt; color: var(--mute); font-style: italic; }
      .notes-body { columns: 2; column-gap: 7mm; column-rule: .6pt solid #bdb8ad; margin-top: 3mm; }
      .notes h3 { font-family: Fraunces, serif; font-size: 11.5pt; margin: 3mm 0 1mm; display: flex; gap: 2mm; align-items: baseline; }
      .basis { font-family: 'Source Sans 3'; font-size: 6.5pt; text-transform: uppercase; letter-spacing: .1em; color: var(--mute); font-style: italic; }
      .scope { border-top: 1pt solid var(--rule); border-bottom: 1pt solid var(--rule); padding: 1mm 0 2mm; margin-top: 3mm; }
      .terms dl > div { display: block; padding: .8mm 0; } .terms dt { font-weight: 700; display: inline; } .terms dt:after { content: ": "; } .terms dd { display: inline; }
      .example { margin: 2mm 0; padding: 2mm 3mm; background: #efebe1; } .ex-q { font-weight: 700; } .ex-a { white-space: pre-wrap; }
    `,
    head: (p, info) => `<header class="mast"><h1>Gazetka 8K</h1><div class="sub"><span>Wydanie na ${esc(info.period)}</span><span>Sprawdziany · Wolne · Notatki</span></div></header>`,
    wrapNotes: true,
  },
  kolory: {
    name: 'Kolory',
    fonts: 'Plus+Jakarta+Sans:wght@400;500;600;700;800',
    css: `
      :root { --ink: #17181c; --mute: #676a73; --line: #e6e7eb; --bg: #f5f6f8; --foot-font: 'Plus Jakarta Sans'; }
      body { font-family: 'Plus Jakarta Sans', sans-serif; color: var(--ink); }
      .mast { background: var(--ink); color: #fff; border-radius: 5mm; padding: 6mm 7mm; margin-bottom: 5mm; display: flex; justify-content: space-between; align-items: flex-end; }
      .mast h1 { font-size: 26pt; font-weight: 800; letter-spacing: -.02em; line-height: 1; }
      .mast .sub { opacity: .75; margin-top: 1.5mm; font-size: 10pt; }
      .mast .dots { display: flex; gap: 1.6mm; } .mast .dots i { width: 4mm; height: 4mm; border-radius: 50%; display: block; }
      .summary { font-size: 11pt; background: var(--bg); border-radius: 4mm; padding: 4mm 5mm; margin-bottom: 5mm; }
      h2 { font-size: 13pt; font-weight: 800; margin: 5mm 0 2.5mm; letter-spacing: -.01em; }
      .week { gap: 2mm; margin-bottom: 2mm; }
      .cell { background: var(--bg); border-radius: 3.5mm; padding: 2.2mm; min-height: 25mm; }
      .cell.outside { opacity: .35; }
      .cell.off { background: repeating-linear-gradient(135deg, var(--bg) 0 2mm, #eceef2 2mm 4mm); }
      .cell-date { display: flex; align-items: baseline; gap: 1.4mm; margin-bottom: 1mm; }
      .cell-date .num { font-size: 15pt; font-weight: 800; }
      .cell-date .dow { font-size: 7.5pt; font-weight: 700; color: var(--mute); text-transform: uppercase; }
      .entry { font-size: 7.8pt; line-height: 1.3; margin-top: 1.3mm; background: #fff; border-radius: 2mm; padding: 1.2mm 1.6mm; border-left: 1.4mm solid hsl(var(--h, 220) 10% 70%); }
      .entry[style] { border-left-color: hsl(var(--h) 65% 55%); }
      .entry .tag { display: block; font-size: 6.5pt; font-weight: 800; text-transform: uppercase; color: var(--mute); letter-spacing: .04em; }
      .entry.t-test, .entry.t-quiz, .entry.t-exam { background: hsl(var(--h, 220) 80% 95%); }
      .row { background: var(--bg); border-radius: 3mm; padding: 2.4mm 3.5mm; margin-bottom: 1.8mm; border-left: 1.6mm solid hsl(var(--h, 220) 10% 75%); }
      .row[style] { border-left-color: hsl(var(--h) 65% 55%); }
      .row-date { font-weight: 800; font-size: 9pt; }
      .row-title { font-weight: 700; font-size: 10.5pt; } .row-title .kind { font-weight: 500; color: var(--mute); }
      .row-sub { color: var(--mute); }
      .sure { font-size: 7pt; font-weight: 800; text-transform: uppercase; padding: .6mm 2mm; border-radius: 10mm; background: #fff; }
      .sure.s-pewne { background: var(--ink); color: #fff; } .sure.s-niepewne { color: var(--mute); }
      .page-ref, .ev-kind { font-size: 7.5pt; color: var(--mute); font-weight: 600; }
      .cols { display: grid; grid-template-columns: 1.1fr 1fr; gap: 6mm; }
      .gaps ul { background: #fff7e0; border-radius: 3mm; padding: 3mm 4mm 3mm 8mm; }
      .notes-head { background: hsl(var(--h, 220) 80% 95%); border-radius: 4mm; padding: 4mm 5mm; }
      .notes-num { width: 11mm; height: 11mm; border-radius: 50%; background: hsl(var(--h, 220) 65% 50%); color: #fff; display: grid; place-items: center; font-weight: 800; font-size: 14pt; }
      .notes-kicker { font-size: 7.5pt; font-weight: 800; text-transform: uppercase; color: hsl(var(--h, 220) 55% 35%); letter-spacing: .04em; }
      .notes-title { font-size: 16pt; font-weight: 800; margin: .5mm 0; letter-spacing: -.01em; }
      .notes-source { font-size: 8pt; color: var(--mute); }
      .notes h3 { font-size: 10.5pt; font-weight: 800; margin: 4.5mm 0 1.2mm; display: flex; gap: 2mm; align-items: center; }
      .basis { font-size: 6.5pt; font-weight: 800; text-transform: uppercase; background: #fff7e0; color: #8a6400; padding: .4mm 1.8mm; border-radius: 10mm; }
      .scope { background: var(--bg); border-radius: 3mm; padding: 1mm 4mm 2.5mm; margin-top: 3mm; }
      .terms dl > div { border-bottom: 1pt solid var(--line); } .terms dt { font-weight: 700; }
      .example { background: var(--bg); border-radius: 3mm; padding: 2.5mm 3.5mm; margin: 2mm 0; } .ex-q { font-weight: 700; } .ex-a { white-space: pre-wrap; color: #333; }
    `,
    head: (p, info) => `<header class="mast"><div><h1>Klasa 8K · plan</h1><div class="sub">${esc(info.period)}</div></div><div class="dots">${info.hues.map(h => `<i style="background:hsl(${h} 65% 55%)"></i>`).join('')}</div></header>`,
  },
};

export const THEMES = Object.fromEntries(Object.entries(THEME_DEFS).map(([k, v]) => [k, v.name]));

export function planHtml(plan, { from, to, theme = 'minimal' }) {
  const t = THEME_DEFS[theme] || THEME_DEFS.minimal;
  const parts = body(plan, { from, to });
  const hues = [...new Set(plan.tests.map(x => x.subject.toLowerCase().trim()))].map((_, i) => SUBJECT_HUES[i % SUBJECT_HUES.length]);
  const info = { period: period(from, to), testCount: parts.testCount, hues };
  const notes = t.wrapNotes ? parts.notes.replace(/(<\/header>)([\s\S]*?)(<\/article>)/g, '$1<div class="notes-body">$2</div>$3') : parts.notes;
  return `<!doctype html><html lang="pl"><head><meta charset="utf-8"><title>${esc(plan.title)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=${t.fonts}&display=block" rel="stylesheet">
<style>${BASE_CSS}${t.css}</style></head><body>
${t.head(plan, info)}
<p class="summary">${esc(plan.summary)}</p>
<section class="block cal"><h2>Dwa tygodnie</h2>${parts.grid}</section>
<div class="cols">
  <div><section class="block tests"><h2>Sprawdziany i kartkówki</h2>${parts.testRows}</section>${parts.homework}</div>
  <div><section class="block events"><h2>Wolne i wydarzenia</h2>${parts.eventRows}</section></div>
</div>
${parts.gaps}
${notes}
</body></html>`;
}

function browser() {
  const b = BROWSERS.find(p => fs.existsSync(p));
  if (!b) throw new Error('Do PDF potrzebny jest Google Chrome albo Brave.');
  return b;
}

export async function renderPlan(plan, { from, to, theme, out, workDir }) {
  const dir = workDir || os.tmpdir();
  const html = path.join(dir, `plan-${theme}.html`);
  fs.writeFileSync(html, planHtml(plan, { from, to, theme }));
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
