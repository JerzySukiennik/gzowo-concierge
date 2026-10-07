// Gzowo Concierge - HTTP host: static web UI, NDJSON chat stream, approvals, settings.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { config } from './config.mjs';
import { store } from './db.mjs';
import { chat, approve, snapshot, applyPolicy, forgetFact, clearThread, history, newThread, renameThread, deleteThread, restoreThread, threadList, validThread } from './commands.mjs';
import { today } from './today.mjs';
import { getAvatar, setAvatar } from './commands.mjs';
import { startRelay, pairingUrl } from './relay.mjs';
import { handleLiveUpgrade } from './live.mjs';
import { getPersona, isDefaultPersona, setPersona } from './prompt.mjs';
import { listSkills, deleteSkill } from './skills.mjs';
import { listCards, addCard, removeCard } from './vault.mjs';
import { listConnectors, connect as connectConnector, setup as setupConnector, disconnect as disconnectConnector, policyLabels, googleCallback } from './connectors/index.mjs';

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const isLoopback = req => ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
function authorized(req) {
  if (isLoopback(req)) return true;
  const h = req.headers.authorization || '';
  const given = h.startsWith('Bearer ') ? h.slice(7) : new URL(req.url, 'http://x').searchParams.get('t') || '';
  const a = Buffer.from(given), b = Buffer.from(config.token);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

const json = (res, code, obj) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj)); };
const readBody = req => new Promise((resolve, reject) => {
  let s = '';
  req.on('data', d => { s += d; if (s.length > 1e6) reject(new Error('body too large')); });
  req.on('end', () => { try { resolve(s ? JSON.parse(s) : {}); } catch (e) { reject(e); } });
});

function ndjson(res, job) {
  res.writeHead(200, { 'content-type': 'application/x-ndjson', 'cache-control': 'no-store', 'x-accel-buffering': 'no' });
  const send = e => res.write(JSON.stringify(e) + '\n');
  const beat = setInterval(() => send({ type: 'ping' }), 15000);
  job(send).catch(err => send({ type: 'error', message: String(err.message || err) })).finally(() => { clearInterval(beat); send({ type: 'done' }); res.end(); });
}

async function api(req, res, url) {
  const p = url.pathname;
  if (p === '/api/health') return json(res, 200, { ok: true, model: config.chatModel, time: new Date().toISOString() });
  if (p === '/api/state') return json(res, 200, snapshot());
  if (p === '/api/history') return json(res, 200, { messages: history(url.searchParams.get('thread') || 'main'), ...snapshot() });
  if (p === '/api/avatar') {
    if (req.method === 'POST') { const { shape, color } = await readBody(req); return json(res, 200, setAvatar(shape, color)); }
    return json(res, 200, getAvatar());
  }
  if (p === '/api/today') return json(res, 200, await today(url.searchParams.get('refresh') === '1'));
  if (p === '/api/threads' && req.method === 'GET') return json(res, 200, { threads: threadList() });
  if (p === '/api/threads' && req.method === 'POST') return json(res, 200, { id: newThread() });
  const th = p.match(/^\/api\/threads\/([\w-]+)(?:\/(rename|restore))?$/);
  if (th) {
    const id = validThread(th[1]);
    if (th[2] === 'rename' && req.method === 'POST') { renameThread(id, (await readBody(req)).title || ''); return json(res, 200, { ok: true }); }
    if (th[2] === 'restore' && req.method === 'POST') { restoreThread(id); return json(res, 200, { ok: true }); }
    if (!th[2] && req.method === 'DELETE') { deleteThread(id); return json(res, 200, { ok: true }); }
  }
  if (p === '/api/pair') return isLoopback(req) ? json(res, 200, { url: pairingUrl() }) : json(res, 403, { error: 'local only' });
  if (p === '/api/chat' && req.method === 'POST') {
    const { text, thread } = await readBody(req);
    if (!text?.trim()) return json(res, 400, { error: 'text required' });
    return ndjson(res, send => chat(text.trim(), send, { thread: validThread(thread) }));
  }
  const ap = p.match(/^\/api\/approvals\/([\w-]+)$/);
  if (ap && req.method === 'POST') {
    const { approve: yes } = await readBody(req);
    return ndjson(res, send => approve(ap[1], !!yes, send));
  }
  if (p === '/api/policies' && req.method === 'POST') { const { action, policy } = await readBody(req); return json(res, 200, applyPolicy(action, policy)); }
  const f = p.match(/^\/api\/facts\/(\d+)$/);
  if (f && req.method === 'DELETE') return json(res, 200, { ok: forgetFact(Number(f[1])) });
  if (p === '/api/connectors' && req.method === 'GET') return json(res, 200, { connectors: listConnectors(), labels: policyLabels() });
  const cn = p.match(/^\/api\/connectors\/([a-z0-9-]+)\/(connect|setup|token|disconnect)$/);
  if (cn && req.method === 'POST') {
    if (!isLoopback(req)) return json(res, 403, { error: 'Konektory można zmieniać tylko na Macu.' });
    const [, id, action] = cn;
    try {
      if (action === 'connect') return json(res, 200, await connectConnector(id));
      if (action === 'setup') return json(res, 200, await setupConnector(id, (await readBody(req)).values));
      if (action === 'disconnect') return json(res, 200, await disconnectConnector(id));
      return json(res, 501, { error: 'Ten konektor nie używa tokenu.' });
    } catch (err) { return json(res, 400, { error: String(err.message || err) }); }
  }
  if (p === '/api/persona') {
    if (req.method === 'POST') { const { persona } = await readBody(req); setPersona(persona); }
    return json(res, 200, { persona: getPersona(), isDefault: isDefaultPersona() });
  }
  if (p === '/api/skills') return json(res, 200, listSkills().map(({ name, description, source }) => ({ name, description, source })));
  const sk = p.match(/^\/api\/skills\/([a-z0-9-]+)$/);
  if (sk && req.method === 'DELETE') return json(res, 200, { ok: deleteSkill(sk[1]) });
  if (p === '/api/cards' || p.startsWith('/api/cards/')) {
    if (!isLoopback(req)) return json(res, 403, { error: 'Cards can only be managed from the Mac itself.' });
    if (p === '/api/cards' && req.method === 'GET') return json(res, 200, listCards());
    if (p === '/api/cards' && req.method === 'POST') return json(res, 200, addCard(await readBody(req)));
    const cd = p.match(/^\/api\/cards\/([\w-]+)$/);
    if (cd && req.method === 'DELETE') return json(res, 200, { ok: removeCard(cd[1]) });
  }
  if (p === '/api/clear' && req.method === 'POST') { clearThread(validThread((await readBody(req)).thread)); return json(res, 200, { ok: true }); }
  return json(res, 404, { error: 'not found' });
}

function serveStatic(res, pathname) {
  let rel = decodeURIComponent(pathname === '/' ? '/index.html' : pathname);
  const file = path.join(config.webDir, path.normalize(rel).replace(/^(\.\.[/\\])+/, ''));
  if (!file.startsWith(config.webDir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end('not found'); }
  res.writeHead(200, { 'content-type': MIME[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-cache' });
  fs.createReadStream(file).pipe(res);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  try {
    if (url.pathname === '/oauth/google/callback') {
      if (!isLoopback(req)) return json(res, 403, { error: 'local only' });
      let ok = true, msg = '';
      try { await googleCallback(url.searchParams); } catch (err) { ok = false; msg = String(err.message || err); }
      res.writeHead(ok ? 200 : 400, { 'content-type': 'text/html; charset=utf-8' });
      const esc = t => t.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
      return res.end(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Concierge</title><body style="font:17px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:100vh;margin:0;background:#f5f5f7;color:#1d1d1f"><div style="text-align:center;max-width:420px;padding:24px"><h1 style="font-size:26px;margin:0 0 10px">${ok ? 'Połączono z Google' : 'Nie udało się połączyć'}</h1><p style="color:#6e6e73;line-height:1.5">${ok ? 'Możesz zamknąć tę kartę i wrócić do Concierge.' : esc(msg)}</p></div>`);
    }
    if (url.pathname.startsWith('/api/')) {
      if (!authorized(req)) return json(res, 401, { error: 'unauthorized' });
      return await api(req, res, url);
    }
    return serveStatic(res, url.pathname);
  } catch (err) {
    if (!res.headersSent) json(res, 500, { error: String(err.message || err) }); else res.end();
  }
});

server.on('upgrade', (req, socket) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname !== '/live' || !authorized(req)) { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n'); socket.destroy(); return; }
  handleLiveUpgrade(req, socket);
});

server.listen(config.port, config.host, () => { console.log(`Gzowo Concierge on http://localhost:${config.port}`); startRelay(); });
