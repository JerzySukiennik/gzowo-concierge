// Gzowo Concierge - Firebase Realtime Database relay: the phone and the host both connect outbound.
// Layout under /c/<sid>: inbox (phone -> host commands), feed (host -> phone events), state (snapshot + heartbeat).
import { config } from './config.mjs';
import { bus, chat, approve, snapshot, applyPolicy, forgetFact, clearThread, newThread, renameThread, deleteThread, restoreThread, validThread } from './commands.mjs';
import { today } from './today.mjs';
import { callTool } from './agent.mjs';
import { store } from './db.mjs';
import { mintLiveToken } from './live.mjs';
import { live } from './live-state.mjs';
import { createAuth } from './fbauth.mjs';
import { connectorSummary } from './connectors/index.mjs';

const SV = { '.sv': 'timestamp' };
const TTL_MS = 10 * 60 * 1000;
const FEED_KEEP = 300;
const sleep = ms => new Promise(r => setTimeout(r, ms));

const authMode = () => !!(config.relay.hostEmail && config.relay.hostPassword && config.relay.apiKey);

export function pairingUrl() {
  return authMode() ? config.relay.hostingUrl : `${config.relay.hostingUrl}/#s=${config.relay.sid}`;
}

export function startRelay() {
  if (!config.relay.enabled || !config.relay.dbUrl || !config.relay.sid) return;
  const auth = authMode() ? createAuth({ apiKey: config.relay.apiKey, email: config.relay.hostEmail, password: config.relay.hostPassword }) : null;
  const base = auth ? `${config.relay.dbUrl}/u/main` : `${config.relay.dbUrl}/c/${config.relay.sid}`;
  const url = async (p, q = '') => {
    if (!auth) return `${base}/${p}.json${q}`;
    const tok = await auth.token();
    return `${base}/${p}.json${q}${q ? '&' : '?'}auth=${tok}`;
  };
  const seen = new Set();
  const log = (...a) => console.log('[relay]', ...a);

  async function call(method, p, body, q) {
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        const res = await fetch(await url(p, q), { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000) });
        if (res.ok) return res.json();
        if (res.status === 401 || res.status === 403) auth?.invalidate();
        if (res.status < 500 && res.status !== 429) { log(method, p, 'HTTP', res.status, (await res.text()).slice(0, 120)); return null; }
      } catch (err) { if (attempt === 3) log(method, p, 'failed:', String(err.message || err).slice(0, 100)); }
      await sleep(1000 * 2 ** attempt);
    }
    return null;
  }

  let feedChain = Promise.resolve();
  const pushFeed = e => { const t = validThread(e.thread); feedChain = feedChain.then(() => call('POST', `feed/${t}`, { ...e, thread: t, ts: SV })); };

  const stateBody = () => {
    const s = snapshot();
    const policies = {};
    for (const [k, v] of Object.entries(s.policies)) policies[k.replace(/\./g, '_')] = v;
    const facts = {}; for (const f of s.facts) facts[f.id] = f.text;
    const pending = {}; for (const p of s.pending) pending[p.id] = p.summary;
    const cs = connectorSummary();
    const labels = {}; for (const [k, v] of Object.entries(s.labels || {})) labels[k.replace(/\./g, '_')] = v;
    const threads = {}; for (const t of s.threads) threads[t.id] = { title: t.title, updated: t.updated, busy: !!t.busy };
    return { busy: s.busy, policies, facts, pending, labels, connectors: cs.states, connectorMeta: cs.meta, threads };
  };
  let statePending = false;
  const pushState = () => {
    if (statePending) return;
    statePending = true;
    setTimeout(() => { statePending = false; call('PATCH', 'state', { ...stateBody(), online: SV }); }, 150);
  };

  bus.on('event', e => pushFeed(e));
  bus.on('state', pushState);
  bus.on('cleared', t => { feedChain = feedChain.then(() => call('DELETE', `feed/${validThread(t)}`)); });

  const ID = /^[\w-]{8,64}$/;
  const remote = new Map();

  function endRemote(cid) {
    const r = remote.get(cid);
    if (!r) return;
    clearTimeout(r.timer);
    live.sessions.delete(r.session);
    remote.delete(cid);
    call('DELETE', `live/${cid}`);
  }

  async function liveToken(m) {
    try {
      const t = await mintLiveToken();
      if (!remote.has(m.cid)) {
        const session = { notify: note => call('POST', `live/${m.cid}/notify`, { text: note }) };
        live.sessions.add(session);
        remote.set(m.cid, { session, thread: validThread(m.thread), timer: setTimeout(() => endRemote(m.cid), 35 * 60e3) });
      }
      await call('PUT', `live/${m.cid}/token`, { ...t, ts: SV });
    } catch (err) {
      await call('PUT', `live/${m.cid}/token`, { error: String(err.message || err).slice(0, 160) });
    }
  }

  async function liveTool(m) {
    let args = {};
    try { args = JSON.parse(m.argsJson || '{}'); } catch {}
    const thread = remote.get(m.cid)?.thread || 'main';
    const emit = e => { const ev = { ...e, rid: m.cid, thread }; call('POST', `live/${m.cid}/ev`, ev); bus.emit('event', ev); };
    const response = await callTool(thread, { name: String(m.name), args }, emit);
    bus.emit('state');
    await call('POST', `live/${m.cid}/ev`, { type: 'pending', pending: Object.fromEntries(snapshot().pending.map(p => [p.id, p.summary])), rid: m.cid });
    await call('PUT', `live/${m.cid}/res/${m.callId}`, { json: JSON.stringify(response) });
  }

  function liveTurn(m) {
    const u = String(m.user || '').trim().slice(0, 4000), a = String(m.assistant || '').trim().slice(0, 4000);
    const rid = ID.test(m.rid || '') ? m.rid : m.cid;
    const thread = remote.get(m.cid)?.thread || validThread(m.thread);
    store.ensureThread(thread);
    if (u) { store.addContent(thread, { role: 'user', parts: [{ text: u }] }); bus.emit('event', { type: 'user', text: u, rid, cid: rid, thread }); }
    if (a) { store.addContent(thread, { role: 'model', parts: [{ text: a }] }); bus.emit('event', { type: 'text', text: a, rid, thread }); }
  }

  async function onInboxItem(id, m) {
    if (seen.has(id)) return;
    seen.add(id);
    if (seen.size > 2000) seen.clear();
    await call('DELETE', `inbox/${id}`);
    if (!m || typeof m !== 'object' || !m.type) return;
    if (Date.now() - (m.ts || 0) > TTL_MS) {
      bus.emit('event', { type: 'error', message: `Byłem offline i pominąłem starą wiadomość: "${String(m.text || m.type).slice(0, 80)}"` });
      return;
    }
    try {
      if (m.type === 'chat' && typeof m.text === 'string' && m.text.trim()) chat(m.text.trim(), undefined, { cid: typeof m.cid === 'string' ? m.cid.slice(0, 64) : undefined, thread: validThread(m.thread) });
      else if (m.type === 'approval' && typeof m.id === 'string') approve(m.id, !!m.approve);
      else if (m.type === 'policy') applyPolicy(String(m.action), String(m.policy));
      else if (m.type === 'forget') forgetFact(Number(m.id));
      else if (m.type === 'clear') clearThread(validThread(m.thread));
      else if (m.type === 'thread-new') newThread(typeof m.thread === 'string' ? m.thread : undefined);
      else if (m.type === 'thread-rename' && typeof m.title === 'string') renameThread(validThread(m.thread), m.title);
      else if (m.type === 'thread-delete') deleteThread(validThread(m.thread));
      else if (m.type === 'thread-restore') restoreThread(validThread(m.thread));
      else if (m.type === 'today-refresh') refreshToday();
      else if (m.type === 'live-token' && ID.test(m.cid || '')) liveToken(m);
      else if (m.type === 'live-tool' && ID.test(m.cid || '') && ID.test(m.callId || '')) liveTool(m);
      else if (m.type === 'live-turn' && ID.test(m.cid || '')) liveTurn(m);
      else if (m.type === 'live-end' && ID.test(m.cid || '')) endRemote(m.cid);
    } catch (err) {
      bus.emit('event', { type: 'error', message: String(err.message || err) });
    }
  }

  function onSse(ev, data) {
    if (ev === 'cancel' || ev === 'auth_revoked') throw new Error(`stream ${ev}`);
    if (ev !== 'put' && ev !== 'patch') return;
    const { path, data: d } = JSON.parse(data);
    if (!d || typeof d !== 'object') return;
    if (path === '/') {
      Object.entries(d).sort((a, b) => (a[1]?.ts || 0) - (b[1]?.ts || 0)).forEach(([id, m]) => onInboxItem(id, m));
    } else {
      const parts = path.split('/').filter(Boolean);
      if (parts.length === 1) onInboxItem(parts[0], d);
    }
  }

  async function listen() {
    let backoff = 1000;
    for (;;) {
      const ctrl = new AbortController();
      let last = Date.now();
      const dog = setInterval(() => { if (Date.now() - last > 90000) ctrl.abort(); }, 15000);
      try {
        const res = await fetch(await url('inbox'), { headers: { accept: 'text/event-stream' }, signal: ctrl.signal });
        if (!res.ok) { if (res.status === 401 || res.status === 403) auth?.invalidate(); throw new Error(`stream HTTP ${res.status}`); }
        log('connected');
        backoff = 1000;
        pushState();
        const dec = new TextDecoder();
        let buf = '', ev = '';
        for await (const chunk of res.body) {
          last = Date.now();
          buf += dec.decode(chunk, { stream: true });
          let i;
          while ((i = buf.indexOf('\n')) >= 0) {
            const line = buf.slice(0, i).replace(/\r$/, '');
            buf = buf.slice(i + 1);
            if (line.startsWith('event:')) ev = line.slice(6).trim();
            else if (line.startsWith('data:')) onSse(ev, line.slice(5).trim());
          }
        }
      } catch (err) {
        if (!ctrl.signal.aborted) log('stream error:', String(err.message || err).slice(0, 120));
      } finally {
        clearInterval(dog);
      }
      await sleep(backoff);
      backoff = Math.min(backoff * 2, 30000);
    }
  }

  async function trimFeed() {
    const threads = await call('GET', 'feed', undefined, '?shallow=true');
    if (!threads) return;
    for (const t of Object.keys(threads)) {
      const keys = await call('GET', `feed/${t}`, undefined, '?shallow=true');
      if (!keys) continue;
      const all = Object.keys(keys).sort();
      if (all.length <= FEED_KEEP) continue;
      const drop = {};
      all.slice(0, all.length - FEED_KEEP).forEach(k => { drop[k] = null; });
      await call('PATCH', `feed/${t}`, drop);
    }
  }

  async function refreshToday() {
    try { await call('PATCH', 'state', { todayJson: JSON.stringify(await today(true)) }); } catch (err) { log('today failed:', String(err.message || err).slice(0, 100)); }
  }

  setInterval(() => call('PUT', 'state/online', SV), 20000).unref?.();
  setInterval(trimFeed, 30 * 60 * 1000).unref?.();
  setInterval(refreshToday, 10 * 60 * 1000).unref?.();
  setTimeout(refreshToday, 5000);
  trimFeed();
  call('DELETE', 'live');
  listen();
  log('started,', auth ? 'signed-in mode (u/main)' : 'legacy key mode', '| open:', pairingUrl().replace(config.relay.sid, '<sid>'));
}
