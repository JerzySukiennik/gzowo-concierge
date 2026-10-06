// Gzowo Concierge - HTTP host: static web UI, NDJSON chat stream, approvals, settings.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { config } from './config.mjs';
import { store } from './db.mjs';
import { chat, approve, snapshot, applyPolicy, forgetFact, clearThread, history } from './commands.mjs';
import { startRelay, pairingUrl } from './relay.mjs';
import { getPersona, isDefaultPersona, setPersona } from './prompt.mjs';
import { listSkills, deleteSkill } from './skills.mjs';
import { listCards, addCard, removeCard } from './vault.mjs';

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
  if (p === '/api/history') return json(res, 200, { messages: history(), ...snapshot() });
  if (p === '/api/pair') return isLoopback(req) ? json(res, 200, { url: pairingUrl() }) : json(res, 403, { error: 'local only' });
  if (p === '/api/chat' && req.method === 'POST') {
    const { text } = await readBody(req);
    if (!text?.trim()) return json(res, 400, { error: 'text required' });
    return ndjson(res, send => chat(text.trim(), send));
  }
  const ap = p.match(/^\/api\/approvals\/([\w-]+)$/);
  if (ap && req.method === 'POST') {
    const { approve: yes } = await readBody(req);
    return ndjson(res, send => approve(ap[1], !!yes, send));
  }
  if (p === '/api/policies' && req.method === 'POST') { const { action, policy } = await readBody(req); return json(res, 200, applyPolicy(action, policy)); }
  const f = p.match(/^\/api\/facts\/(\d+)$/);
  if (f && req.method === 'DELETE') return json(res, 200, { ok: forgetFact(Number(f[1])) });
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
  if (p === '/api/clear' && req.method === 'POST') { clearThread(); return json(res, 200, { ok: true }); }
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
    if (url.pathname.startsWith('/api/')) {
      if (!authorized(req)) return json(res, 401, { error: 'unauthorized' });
      return await api(req, res, url);
    }
    return serveStatic(res, url.pathname);
  } catch (err) {
    if (!res.headersSent) json(res, 500, { error: String(err.message || err) }); else res.end();
  }
});

server.listen(config.port, config.host, () => { console.log(`Gzowo Concierge on http://localhost:${config.port}`); startRelay(); });
