// Gzowo Concierge - WhatsApp Desktop, read only: class groups, their messages and attachments straight from the app's local database.
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { config } from './config.mjs';
import { store } from './db.mjs';

const BASE = process.env.WHATSAPP_DIR || path.join(os.homedir(), 'Library/Group Containers/group.net.whatsapp.WhatsApp.shared');
const EPOCH = 978307200;
const DEFAULT_GROUPS = ['Ogłoszenia klasowe 8K', 'Klasa 8K'];
const KINDS = { 0: 'text', 1: 'photo', 2: 'video', 3: 'voice', 8: 'document', 15: 'sticker', 66: 'album' };
const MIME = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.pdf': 'application/pdf' };

export const classGroups = () => store.getSetting('whatsappGroups', DEFAULT_GROUPS);

function open() {
  const file = path.join(BASE, 'ChatStorage.sqlite');
  if (!fs.existsSync(file)) throw new Error('Nie widzę bazy WhatsAppa na tym Macu.');
  return new DatabaseSync(file, { readOnly: true });
}

const toTs = d => (d + EPOCH) * 1000;
const fromTs = ms => ms / 1000 - EPOCH;
const local = ms => new Intl.DateTimeFormat('sv-SE', { timeZone: config.timezone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }).format(new Date(ms));

export function waGroups() {
  const db = open();
  try {
    const names = classGroups();
    return db.prepare('SELECT Z_PK pk, ZPARTNERNAME name, ZLASTMESSAGEDATE last FROM ZWACHATSESSION WHERE ZSESSIONTYPE = 1').all()
      .filter(g => names.some(n => (g.name || '').startsWith(n)))
      .map(g => ({ group: g.name, last_message: g.last ? local(toTs(g.last)) : null }));
  } finally { db.close(); }
}

export function waMessages({ group, from, to, limit = 400 }) {
  const db = open();
  try {
    const names = classGroups();
    const g = db.prepare('SELECT Z_PK pk, ZPARTNERNAME name FROM ZWACHATSESSION WHERE ZSESSIONTYPE = 1').all()
      .find(s => names.some(n => (s.name || '').startsWith(n)) && (s.name || '').toLowerCase().startsWith(String(group || '').toLowerCase().trim()));
    if (!g) throw new Error(`Czytam tylko grupy klasowe: ${names.join(', ')}.`);
    const start = from ? Date.parse(`${from}T00:00:00`) : Date.now() - 28 * 864e5;
    const end = to ? Date.parse(`${to}T23:59:59`) : Date.now();
    const rows = db.prepare(`SELECT m.Z_PK id, m.ZMESSAGEDATE d, m.ZMESSAGETYPE ty, m.ZTEXT t, m.ZISFROMME me, m.ZGROUPMEMBER gm, gmb.ZISADMIN admin,
        mi.ZMEDIALOCALPATH p, mi.ZTITLE caption, mi.ZFILESIZE size
      FROM ZWAMESSAGE m LEFT JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM LEFT JOIN ZWAGROUPMEMBER gmb ON gmb.Z_PK = m.ZGROUPMEMBER
      WHERE m.ZCHATSESSION = ? AND m.ZMESSAGEDATE BETWEEN ? AND ? ORDER BY m.ZMESSAGEDATE LIMIT ?`).all(g.pk, fromTs(start), fromTs(end), Math.min(Number(limit) || 400, 800));
    const people = new Map();
    const who = r => {
      if (r.me) return 'Jurek';
      if (!r.gm) return 'ktoś';
      if (!people.has(r.gm)) people.set(r.gm, `osoba ${people.size + 1}`);
      return people.get(r.gm) + (r.admin ? ' (admin grupy)' : '');
    };
    const messages = [];
    for (const r of rows) {
      const kind = KINDS[r.ty] || 'other';
      if (kind === 'other' || kind === 'sticker') continue;
      const text = String(r.t || '').trim(), caption = String(r.caption || '').trim();
      const file = r.p && fs.existsSync(path.join(BASE, 'Message', r.p)) ? r.p : null;
      if (kind === 'text' && !text) continue;
      const m = { id: r.id, time: local(toTs(r.d)), from: who(r), kind };
      if (text) m.text = text.slice(0, 1500);
      if (caption && !/^(@\d+\s*)+$/.test(caption)) m.caption = caption.slice(0, 300);
      if (['photo', 'document'].includes(kind)) m.can_open = !!file && MIME[path.extname(file).toLowerCase()] !== undefined;
      messages.push(m);
    }
    return { group: g.name, from: local(start).slice(0, 10), to: local(end).slice(0, 10), count: messages.length, messages };
  } finally { db.close(); }
}

export function waAttachment(id) {
  const db = open();
  try {
    const r = db.prepare(`SELECT m.ZCHATSESSION s, mi.ZMEDIALOCALPATH p, mi.ZTITLE caption FROM ZWAMESSAGE m JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM WHERE m.Z_PK = ?`).get(Number(id));
    if (!r?.p) throw new Error('Ta wiadomość nie ma załącznika.');
    const names = classGroups();
    const s = db.prepare('SELECT ZPARTNERNAME name FROM ZWACHATSESSION WHERE Z_PK = ?').get(r.s);
    if (!names.some(n => (s?.name || '').startsWith(n))) throw new Error('Czytam tylko grupy klasowe.');
    const file = path.join(BASE, 'Message', r.p);
    const mime = MIME[path.extname(file).toLowerCase()];
    if (!mime || !fs.existsSync(file)) throw new Error('Tego załącznika nie ma na dysku albo nie umiem go otworzyć.');
    return { file, mime, caption: r.caption || '' };
  } finally { db.close(); }
}
