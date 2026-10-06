// Gzowo Concierge - SQLite store: conversation contents, facts, settings, approvals.
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import crypto from 'node:crypto';
import { config } from './config.mjs';

const db = new DatabaseSync(path.join(config.dataDir, 'concierge.db'));
db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS contents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread TEXT NOT NULL,
    role TEXT NOT NULL,
    parts TEXT NOT NULL,
    ts INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS contents_thread ON contents(thread, id);
  CREATE TABLE IF NOT EXISTS facts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    text TEXT NOT NULL,
    ts INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS approvals (
    id TEXT PRIMARY KEY,
    thread TEXT NOT NULL,
    action TEXT NOT NULL,
    tool TEXT NOT NULL,
    args TEXT NOT NULL,
    summary TEXT NOT NULL,
    status TEXT NOT NULL,
    result TEXT,
    ts INTEGER NOT NULL
  );
`);

const now = () => Date.now();

export const store = {
  addContent(thread, content) {
    db.prepare('INSERT INTO contents (thread, role, parts, ts) VALUES (?, ?, ?, ?)')
      .run(thread, content.role, JSON.stringify(content.parts), now());
  },
  loadContents(thread, limit = 60) {
    const rows = db.prepare('SELECT id, role, parts, ts FROM contents WHERE thread = ? ORDER BY id DESC LIMIT ?')
      .all(thread, limit).reverse();
    const list = rows.map(r => ({ id: r.id, ts: r.ts, role: r.role, parts: JSON.parse(r.parts) }));
    const startsClean = c => c.role === 'user' && c.parts.some(p => p.text) && !c.parts.some(p => p.functionResponse);
    while (list.length && !startsClean(list[0])) list.shift();
    return list;
  },
  clearThread(thread) {
    db.prepare('DELETE FROM contents WHERE thread = ?').run(thread);
  },
  facts() {
    return db.prepare('SELECT id, text FROM facts ORDER BY id').all();
  },
  addFact(text) {
    const dup = db.prepare('SELECT id FROM facts WHERE lower(text) = lower(?)').get(text);
    if (dup) return dup.id;
    return Number(db.prepare('INSERT INTO facts (text, ts) VALUES (?, ?)').run(text, now()).lastInsertRowid);
  },
  removeFact(id) {
    return db.prepare('DELETE FROM facts WHERE id = ?').run(id).changes > 0;
  },
  getSetting(key, fallback = null) {
    const r = db.prepare('SELECT value FROM settings WHERE key = ?').get(key);
    return r ? JSON.parse(r.value) : fallback;
  },
  setSetting(key, value) {
    db.prepare('INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value')
      .run(key, JSON.stringify(value));
  },
  createApproval({ thread, action, tool, args, summary }) {
    const id = crypto.randomUUID();
    db.prepare('INSERT INTO approvals (id, thread, action, tool, args, summary, status, ts) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
      .run(id, thread, action, tool, JSON.stringify(args), summary, 'pending', now());
    return id;
  },
  getApproval(id) {
    const r = db.prepare('SELECT * FROM approvals WHERE id = ?').get(id);
    return r ? { ...r, args: JSON.parse(r.args), result: r.result ? JSON.parse(r.result) : null } : null;
  },
  pendingApprovals() {
    return db.prepare("SELECT * FROM approvals WHERE status = 'pending' ORDER BY ts").all()
      .map(r => ({ ...r, args: JSON.parse(r.args) }));
  },
  resolveApproval(id, status, result) {
    db.prepare('UPDATE approvals SET status = ?, result = ? WHERE id = ?')
      .run(status, result === undefined ? null : JSON.stringify(result), id);
  },
};
