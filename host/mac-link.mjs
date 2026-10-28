// Gzowo Concierge - control channel to the native Mac app (/mac, loopback only): whole-screen screenshots, showing a thread or a link, activity samples.
import crypto from 'node:crypto';
import { acceptUpgrade } from './ws.mjs';
import { store } from './db.mjs';

let link = null;
const waiting = new Map();

export const macConnected = () => !!link?.open;

export function handleMacUpgrade(req, socket) {
  const conn = acceptUpgrade(req, socket, {
    maxFrame: 16 << 20,
    onMessage: (data, binary) => {
      if (binary) return;
      let m; try { m = JSON.parse(data); } catch { return; }
      if (m.type === 'activity' && typeof m.app === 'string' && m.app) {
        store.addActivity(m.app.slice(0, 80), String(m.title || '').slice(0, 200));
        return;
      }
      if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); }
    },
    onClose: () => { if (link === conn) link = null; },
  });
  if (conn) link = conn;
}

export function macRequest(type, payload = {}, timeout = 15000) {
  if (!link?.open) return Promise.reject(new Error('Apka Concierge na Macu nie jest uruchomiona.'));
  const id = crypto.randomUUID();
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => { waiting.delete(id); reject(new Error('Mac nie odpowiedział.')); }, timeout);
    waiting.set(id, m => { clearTimeout(t); m.error ? reject(new Error(m.error)) : resolve(m); });
    link.sendText(JSON.stringify({ ...payload, type, id }));
  });
}
