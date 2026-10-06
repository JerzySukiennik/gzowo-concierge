// Gzowo Concierge - iCloud calendar tools via the ConciergeCal EventKit helper app.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { config } from '../config.mjs';

async function cal(command, opts = {}) {
  const out = path.join(config.dataDir, `cal-${crypto.randomUUID()}.json`);
  const args = ['-n', config.calApp, '--args', command, '--out', out];
  for (const [k, v] of Object.entries(opts)) {
    if (v !== undefined && v !== null && v !== '') args.push(`--${k}`, String(v));
  }
  spawn('open', args, { stdio: 'ignore' }).on('error', () => {});
  const deadline = Date.now() + 130000;
  while (!fs.existsSync(out)) {
    if (Date.now() > deadline) throw new Error('Calendar helper timed out (permission dialog pending?)');
    await new Promise(r => setTimeout(r, 60));
  }
  const data = JSON.parse(fs.readFileSync(out, 'utf8'));
  fs.rmSync(out, { force: true });
  if (!data.ok) throw new Error(data.error || 'calendar error');
  return data;
}

const DT = 'Local time ISO 8601 without timezone, e.g. 2026-10-08T15:15:00';

export const calendarTools = [
  {
    name: 'calendar_list',
    action: 'calendar.read',
    policy: 'auto',
    description: "List events from the user's iCloud calendar in a time range. Use for any question about schedule, tests, plans, free time.",
    parameters: {
      type: 'object',
      properties: {
        from: { type: 'string', description: `Range start. ${DT} or YYYY-MM-DD` },
        to: { type: 'string', description: `Range end (exclusive). ${DT} or YYYY-MM-DD` },
        query: { type: 'string', description: 'Optional text filter on title, notes, location' },
      },
      required: ['from', 'to'],
    },
    summarize: a => `Check calendar ${a.from} to ${a.to}`,
    run: a => cal('list', { from: a.from, to: a.to, query: a.query }),
  },
  {
    name: 'calendar_add',
    action: 'calendar.write',
    policy: 'auto',
    description: "Create an event in the user's iCloud calendar.",
    parameters: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        start: { type: 'string', description: DT },
        end: { type: 'string', description: `${DT}. Defaults to 1 hour after start.` },
        allDay: { type: 'boolean' },
        location: { type: 'string' },
        notes: { type: 'string' },
        alarmMinutes: { type: 'number', description: 'Reminder this many minutes before start' },
      },
      required: ['title', 'start'],
    },
    summarize: a => `Add to calendar: ${a.title} (${a.start})`,
    run: a => cal('add', a),
  },
  {
    name: 'calendar_update',
    action: 'calendar.write',
    policy: 'auto',
    description: 'Change an existing calendar event. Get the id from calendar_list first.',
    parameters: {
      type: 'object',
      properties: {
        id: { type: 'string' },
        title: { type: 'string' },
        start: { type: 'string', description: `${DT}. Event keeps its duration unless end is given.` },
        end: { type: 'string', description: DT },
        allDay: { type: 'boolean' },
        location: { type: 'string' },
        notes: { type: 'string' },
      },
      required: ['id'],
    },
    summarize: a => `Edit calendar event ${a.title || a.id}`,
    run: a => cal('update', a),
  },
  {
    name: 'calendar_delete',
    action: 'calendar.delete',
    policy: 'ask',
    description: 'Delete a calendar event. Get the id from calendar_list first.',
    parameters: { type: 'object', properties: { id: { type: 'string' }, title: { type: 'string', description: 'Event title, for the confirmation text' } }, required: ['id'] },
    summarize: a => `Delete calendar event ${a.title || a.id}`,
    run: a => cal('delete', { id: a.id }),
  },
];
