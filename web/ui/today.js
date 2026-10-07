// Gzowo Concierge - "Dzisiaj" panel: glass widgets for upcoming events, weather and reminders, rendered from GET /api/today (or relay state).
import { icon, skyIcon } from './icons.js';

const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const hm = d => d.toLocaleTimeString('pl-PL', { hour: '2-digit', minute: '2-digit' });
const sameDay = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
const dayName = d => { const t = d.toLocaleDateString('pl-PL', { weekday: 'long', day: 'numeric', month: 'long' }); return t.charAt(0).toUpperCase() + t.slice(1); };
const skyKind = s => { const i = skyIcon(s); return i === 'sun' ? 'sun' : i === 'rain' ? 'rain' : i === 'snow' ? 'snow' : 'cloud'; };

function widget(cls, ic, title) {
  const w = el('section', 'wd glass ' + cls);
  w.innerHTML = `<header class="wd-h"><span class="wd-ic">${icon(ic, 16)}</span><h3></h3></header>`;
  w.querySelector('h3').textContent = title;
  return w;
}

function note(text, action, onClick) {
  const n = el('div', 'wd-note');
  n.append(el('p', null, text));
  if (action) { const b = el('button', 'pill', icon('link', 16) + '<span></span>'); b.type = 'button'; b.querySelector('span').textContent = action; b.onclick = onClick; n.append(b); }
  return n;
}

function eventsWidget(list, now) {
  const w = widget('wd-cal', 'calendar', 'Najbliższe wydarzenia');
  const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  const items = (list || []).map(e => ({ ...e, s: new Date(e.start), e: new Date(e.end) })).filter(e => !isNaN(e.s)).sort((a, b) => (b.allDay - a.allDay) * 0 + a.s - b.s);
  const today = items.filter(e => sameDay(e.s, now) && (e.allDay || e.e > now));
  const next = items.filter(e => sameDay(e.s, tomorrow));
  const group = (title, sub, arr, isToday) => {
    const g = el('div', 'ev-day');
    const h = el('h4', null, '<span></span><small></small>');
    h.firstChild.textContent = title; h.lastChild.textContent = sub;
    g.append(h);
    if (!arr.length) { g.append(el('p', 'ev-none', isToday ? 'Na dziś nic więcej.' : 'Nic zaplanowane.')); return g; }
    const wrap = el('div', 'ev-list');
    arr.forEach(e => {
      const ongoing = !e.allDay && e.s <= now && e.e > now;
      const r = el('div', 'ev' + (ongoing ? ' now' : '') + (e.allDay ? ' all' : ''));
      const t = el('div', 'ev-time');
      if (e.allDay) t.innerHTML = '<b>Cały</b><small>dzień</small>';
      else { t.innerHTML = '<b></b><small></small>'; t.firstChild.textContent = hm(e.s); t.lastChild.textContent = 'do ' + hm(e.e); }
      const b = el('div', 'ev-t', '<span class="ev-name"></span><span class="ev-cal"></span>');
      b.querySelector('.ev-name').textContent = e.title;
      b.querySelector('.ev-cal').textContent = e.calendar || '';
      r.append(t, b);
      if (ongoing) {
        const p = Math.min(1, Math.max(0, (now - e.s) / Math.max(1, e.e - e.s)));
        const bar = el('i', 'ev-bar'); bar.style.setProperty('--p', p.toFixed(3));
        r.append(bar);
        r.setAttribute('aria-label', 'Teraz: ' + e.title);
      }
      wrap.append(r);
    });
    g.append(wrap);
    return g;
  };
  w.append(group('Dzisiaj', dayName(now), today, true), group('Jutro', dayName(tomorrow), next, false));
  return w;
}

function weatherWidget(wx, onConn) {
  const w = widget('wd-wx', 'cloudSun', 'Pogoda');
  if (!wx) { w.append(note('Pogoda pojawi się tutaj po połączeniu w Konektorach.', 'Konektory', () => onConn('weather'))); return w; }
  const kind = skyKind(wx.now && wx.now.sky);
  w.dataset.sky = kind;
  const n = wx.now || {};
  const top = el('div', 'wx-top');
  top.innerHTML = `<div class="wx-main"><span class="wx-place"></span><span class="wx-temp"></span><span class="wx-sky"></span></div><span class="wx-ic">${icon(skyIcon(n.sky), 40)}</span>`;
  top.querySelector('.wx-place').textContent = wx.place || '';
  top.querySelector('.wx-temp').textContent = Math.round(n.temp) + '°';
  top.querySelector('.wx-sky').textContent = n.sky || '';
  const stats = el('div', 'wx-stats');
  const stat = (ic, text, label) => { const s = el('span', 'wx-stat', icon(ic, 15) + '<span></span>'); s.lastChild.textContent = text; s.setAttribute('aria-label', label + ' ' + text); return s; };
  stats.append(stat('sun', 'odczuwalna ' + Math.round(n.feelsLike) + '°', 'Temperatura'), stat('wind', Math.round(n.wind_kmh) + ' km/h', 'Wiatr'), stat('drop', (n.rain_mm || 0) + ' mm', 'Opady'));
  const days = el('div', 'wx-days');
  (wx.days || []).slice(0, 4).forEach((d, i) => {
    const dt = new Date(d.date + 'T12:00:00');
    const c = el('div', 'wx-day', '<span class="wd-n"></span>' + icon(skyIcon(d.sky), 18) + '<span class="wd-t"></span>');
    c.querySelector('.wd-n').textContent = i === 0 ? 'Dziś' : dt.toLocaleDateString('pl-PL', { weekday: 'short' });
    c.querySelector('.wd-t').innerHTML = '<b>' + Math.round(d.max) + '°</b> <small>' + Math.round(d.min) + '°</small>';
    c.setAttribute('aria-label', (i === 0 ? 'Dziś' : dt.toLocaleDateString('pl-PL', { weekday: 'long' })) + ', ' + (d.sky || '') + ', od ' + Math.round(d.min) + ' do ' + Math.round(d.max) + ' stopni');
    days.append(c);
  });
  w.append(top, stats, days);
  return w;
}

function remindersWidget(list, now, onConn) {
  const w = widget('wd-rem', 'bell', 'Przypomnienia');
  if (!list) { w.append(note('Przypomnienia pojawią się tutaj po połączeniu w Konektorach.', 'Konektory', () => onConn('reminders'))); return w; }
  if (!list.length) { w.append(el('p', 'ev-none', 'Nic do zrobienia.')); return w; }
  const wrap = el('div', 'rem-list');
  const due = v => {
    if (!v) return '';
    const d = new Date(v);
    if (isNaN(d)) return '';
    const tm = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    return sameDay(d, now) ? 'dziś ' + hm(d) : sameDay(d, tm) ? 'jutro ' + hm(d) : d.toLocaleDateString('pl-PL', { weekday: 'short', day: 'numeric', month: 'short' });
  };
  list.slice(0, 6).forEach(r => {
    const late = r.due && new Date(r.due) < now;
    const row = el('div', 'rem' + (late ? ' late' : ''), '<span class="rem-c" aria-hidden="true"></span><span class="rem-b"><span class="rem-t"></span><span class="rem-s"></span></span>');
    row.querySelector('.rem-t').textContent = r.title;
    row.querySelector('.rem-s').textContent = [due(r.due), r.list].filter(Boolean).join(' · ');
    wrap.append(row);
  });
  w.append(wrap);
  return w;
}

export function createToday({ body, onConnectors }) {
  let loaded = false;

  function skeleton() {
    body.textContent = '';
    for (let i = 0; i < 3; i++) body.append(el('div', 'wd glass skel'));
  }

  function render(data) {
    loaded = true;
    const now = new Date();
    body.textContent = '';
    body.append(eventsWidget(data ? data.calendar : [], now), weatherWidget(data ? data.weather : null, onConnectors), remindersWidget(data ? data.reminders : null, now, onConnectors));
  }

  function error() {
    body.textContent = '';
    body.append(note('Nie udało się wczytać planu dnia. Spróbuję ponownie za chwilę.'));
  }

  skeleton();
  return { render, skeleton, error, get loaded() { return loaded; } };
}
