// Gzowo Concierge - tools around the main Mac and the room: look at the screen, show something on the Mac, announce in the room, summarize a day.
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { generate, textOf } from '../gemini.mjs';
import { config } from '../config.mjs';
import { store } from '../db.mjs';
import { bus } from '../commands.mjs';
import { macRequest } from '../mac-link.mjs';
import { announce } from '../room.mjs';
import { cal } from './calendar.mjs';

const VISION_MODELS = (process.env.VISION_MODELS || `gemini-3.5-flash,${config.chatModel},gemini-2.5-flash`).split(',');
const PROJECTS = process.env.PROJECTS_DIR || path.join(os.homedir(), 'Downloads/Claude/Projects');

const dayKey = d => new Intl.DateTimeFormat('sv-SE', { timeZone: config.timezone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);

function dayBounds(date) {
  const key = /^\d{4}-\d{2}-\d{2}$/.test(date || '') ? date : dayKey(new Date());
  const s = new Date(`${key}T00:00:00`), e = new Date(s);
  e.setDate(e.getDate() + 1);
  return { key, start: s.getTime(), end: e.getTime() };
}

function git(dir, args) {
  return new Promise(resolve => execFile('git', ['-C', dir, ...args], { timeout: 4000 }, (err, out) => resolve(err ? '' : out)));
}

async function projectsTouched(start, end) {
  let dirs = [];
  try { dirs = fs.readdirSync(PROJECTS, { withFileTypes: true }).filter(d => d.isDirectory() && fs.existsSync(path.join(PROJECTS, d.name, '.git'))).map(d => d.name); } catch {}
  const since = new Date(start).toISOString(), until = new Date(end).toISOString();
  const found = await Promise.all(dirs.map(async name => {
    const out = await git(path.join(PROJECTS, name), ['log', `--since=${since}`, `--until=${until}`, '--pretty=%s']);
    const commits = out.split('\n').map(s => s.trim()).filter(Boolean);
    return commits.length ? { project: name, commits: commits.length, messages: commits.slice(0, 6) } : null;
  }));
  return found.filter(Boolean).sort((a, b) => b.commits - a.commits);
}

function activitySummary(start, end) {
  const rows = store.activityBetween(start, end);
  const apps = new Map();
  for (const r of rows) {
    const a = apps.get(r.app) || { app: r.app, minutes: 0, titles: new Map() };
    a.minutes++;
    if (r.title) a.titles.set(r.title, (a.titles.get(r.title) || 0) + 1);
    apps.set(r.app, a);
  }
  return {
    active_minutes: rows.length,
    first: rows.length ? new Date(rows[0].ts).toLocaleTimeString('pl-PL', { timeZone: config.timezone, hour: '2-digit', minute: '2-digit' }) : null,
    last: rows.length ? new Date(rows[rows.length - 1].ts).toLocaleTimeString('pl-PL', { timeZone: config.timezone, hour: '2-digit', minute: '2-digit' }) : null,
    apps: [...apps.values()].sort((a, b) => b.minutes - a.minutes).slice(0, 10).map(a => ({
      app: a.app, minutes: a.minutes,
      top_windows: [...a.titles.entries()].sort((x, y) => y[1] - x[1]).slice(0, 5).map(([title, m]) => `${title} (${m} min)`),
    })),
  };
}

export const macTools = [
  {
    name: 'screen_look',
    action: 'mac.screen',
    policy: 'auto',
    description: "Look at the whole screen of Jurek's main Mac right now and answer a question about it: what is on it, what an error means, summarize or translate what he is reading, what to click next.",
    parameters: { type: 'object', properties: { question: { type: 'string', description: 'His question about the screen, in Polish' } }, required: ['question'] },
    summarize: a => `Patrzę na ekran Maca: ${a.question}`,
    async run({ question }) {
      const shot = await macRequest('screenshot', {}, 20000);
      let res, lastErr;
      for (const model of VISION_MODELS) {
        try {
          res = await generate({
            model,
            system: "You see a screenshot of Jurek's whole Mac screen. Answer his question in Polish, briefly and concretely (two to four sentences, it will be read aloud). Quote exact text, names and numbers from the screen when they matter. If something is too small or not visible, say so.",
            contents: [{ role: 'user', parts: [{ inlineData: { mimeType: 'image/jpeg', data: shot.data } }, { text: `Aktywna aplikacja: ${shot.app || '?'}${shot.title ? `, okno: ${shot.title}` : ''}.\nPytanie: ${question}` }] }],
            thinking: 'low',
          });
          break;
        } catch (err) {
          lastErr = err;
          if (![400, 404, 429, 500, 503].includes(err.status)) throw err;
        }
      }
      if (!res) throw lastErr;
      return { answer: textOf(res.candidates?.[0]?.content?.parts).trim(), app: shot.app || '', window: shot.title || '' };
    },
  },
  {
    name: 'mac_show',
    action: 'mac.show',
    policy: 'auto',
    description: "Show something on Jurek's main Mac: opens the Concierge window on this conversation, optionally after adding the full details as a written message (lists, recipes, steps, longer text that is awkward to hear), and optionally opens a web link in the browser. Use when he says 'pokaż to na Macu' or wants to read something.",
    parameters: { type: 'object', properties: {
      details: { type: 'string', description: 'Optional full content to show, in Polish, markdown allowed' },
      url: { type: 'string', description: 'Optional https link to open in the browser' },
    } },
    summarize: () => 'Pokazuję na Macu',
    async run({ details, url }, ctx = {}) {
      const thread = ctx.thread || 'main';
      const text = String(details || '').trim();
      if (text) {
        store.addContent(thread, { role: 'model', parts: [{ text }] });
        store.touchThread(thread);
        bus.emit('event', { type: 'text', text, rid: `show-${Date.now()}`, thread });
      }
      const link = /^https?:\/\//.test(url || '') ? url : '';
      await macRequest('show', { thread, url: link }, 8000);
      return { shown: true, thread, opened_url: link || null };
    },
  },
  {
    name: 'announce_in_room',
    action: 'room.announce',
    policy: 'auto',
    description: "Say a short announcement out loud on the speaker in Jurek's room (MacPetite). Use ONLY when he explicitly asked to be told in his room, for example 'powiedz mi w pokoju, jak skończysz'. One or two short Polish sentences.",
    parameters: { type: 'object', properties: { text: { type: 'string', description: 'What to say, in Polish' } }, required: ['text'] },
    summarize: a => `Ogłaszam w pokoju: ${a.text}`,
    async run({ text }) {
      const item = announce(text);
      if (!item) throw new Error('Pusty komunikat');
      return { queued: true };
    },
  },
  {
    name: 'day_summary',
    action: 'mac.day',
    policy: 'auto',
    description: "Facts for a summary of Jurek's day: what he worked on at the Mac (apps and windows, minutes), which projects got commits, Concierge conversations, and his calendar for that day and the next. Use when he asks how his day went or what he did; then summarize it in a few sentences and say what is ahead tomorrow.",
    parameters: { type: 'object', properties: { date: { type: 'string', description: 'YYYY-MM-DD, default today' } } },
    summarize: () => 'Zbieram podsumowanie dnia',
    async run({ date }) {
      const { key, start, end } = dayBounds(date);
      const next = dayKey(new Date(end + 3600e3));
      const [projects, events] = await Promise.all([
        projectsTouched(start, end),
        cal('list', { from: key, to: dayKey(new Date(end + 25 * 3600e3)) }).then(r => r.events || []).catch(() => null),
      ]);
      const conversations = store.listThreads().filter(t => t.updated >= start && t.updated < end).map(t => t.title).slice(0, 12);
      return {
        day: key,
        mac: activitySummary(start, end),
        projects,
        conversations,
        calendar: events && events.map(e => ({ title: e.title, start: e.start, allDay: e.allDay, day: (e.start || '').slice(0, 10) === next ? 'next day' : 'this day' })),
      };
    },
  },
];
