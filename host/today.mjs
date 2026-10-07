// Gzowo Concierge - the "Dzisiaj" widgets: next events, weather and reminders, cached for a few minutes.
import { cal } from './tools/calendar.mjs';
import { weather } from './connectors/defs.mjs';
import { isActive } from './connectors/index.mjs';
import { store } from './db.mjs';
import { config } from './config.mjs';

let cache = { t: 0, data: null };

function localDate(offsetDays) {
  const d = new Date(Date.now() + offsetDays * 86400000);
  return new Intl.DateTimeFormat('sv-SE', { timeZone: config.timezone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
}

export async function today(force = false) {
  if (!force && cache.data && Date.now() - cache.t < 5 * 60 * 1000) return cache.data;
  const [events, wx, rem] = await Promise.allSettled([
    cal('list', { from: localDate(0), to: localDate(2) }),
    weather({ city: store.getSetting('weatherCity', 'Warszawa'), days: 3 }),
    isActive('reminders') ? cal('rem-list', { limit: 8 }) : Promise.resolve(null),
  ]);
  const data = {
    generatedAt: Date.now(),
    calendar: events.status === 'fulfilled' ? (events.value.events || []).map(e => ({ title: e.title, start: e.start, end: e.end, allDay: e.allDay, calendar: e.calendar })) : [],
    weather: wx.status === 'fulfilled' ? wx.value : null,
    reminders: rem.status === 'fulfilled' && rem.value ? (rem.value.reminders || []).map(r => ({ title: r.title, due: r.due, list: r.list })) : null,
  };
  cache = { t: Date.now(), data };
  return data;
}
