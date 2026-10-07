// Gzowo Concierge - local transport: talks to the host that serves this page (Mac, loopback or LAN with token); threads, today, connectors.
import { getThreadId, setThreadId } from './thread-store.js';

export function createHttp(on) {
  const qs = new URLSearchParams(location.search);
  if (qs.get('t')) { try { localStorage.setItem('ct', qs.get('t')); } catch {} history.replaceState(null, '', location.pathname + location.hash); }
  const token = (() => { try { return localStorage.getItem('ct') || ''; } catch { return ''; } })();
  const H = { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) };
  let busyStreams = 0, threadId = getThreadId();

  async function stream(url, body) {
    busyStreams++; on.state({ busy: true });
    try {
      const res = await fetch(url, { method: 'POST', headers: H, body: JSON.stringify(body) });
      if (!res.ok) { on.event({ type: 'error', message: res.status === 401 ? 'Brak autoryzacji. Otwórz link z tokenem.' : 'Błąd hosta (' + res.status + ')' }); return; }
      const rd = res.body.getReader(), dec = new TextDecoder();
      let buf = '';
      for (;;) {
        const { done, value } = await rd.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        let i;
        while ((i = buf.indexOf('\n')) >= 0) {
          const line = buf.slice(0, i); buf = buf.slice(i + 1);
          if (!line) continue;
          const e = JSON.parse(line);
          if (e.type !== 'ping' && e.type !== 'done') on.event(e);
        }
      }
    } catch { on.event({ type: 'error', message: 'Brak połączenia z hostem.' }); }
    finally { busyStreams--; on.state({ busy: busyStreams > 0 }); refresh(); }
  }

  async function get(path) { const r = await fetch(path, { headers: H }); if (!r.ok) throw new Error(r.status); return r.json(); }
  const post = (path, body) => fetch(path, { method: 'POST', headers: H, body: JSON.stringify(body || {}) });
  const del = path => fetch(path, { method: 'DELETE', headers: H });
  const json = async r => { const j = await r.json().catch(() => ({})); if (!r.ok && !j.needsSetup && !j.needsToken) throw new Error(j.error || r.status); return j; };

  async function loadThreads(busy) {
    try {
      const r = await get('/api/threads');
      const o = {};
      for (const t of r.threads || []) o[t.id] = { title: t.title, updated: t.updated, busy: !!(t.busy || (busy && t.id === threadId)) };
      on.state({ threads: o });
    } catch {}
  }

  async function refresh() {
    try {
      const s = await get('/api/state');
      const busy = busyStreams > 0 || s.busy;
      on.state({ online: true, policies: s.policies, facts: Object.fromEntries(s.facts.map(f => [f.id, f.text])), pending: Object.fromEntries(s.pending.map(p => [p.id, p.summary])), busy });
      loadThreads(busy);
    } catch { on.state({ online: false }); }
  }

  async function loadHistory() {
    try {
      const h = await get('/api/history?thread=' + encodeURIComponent(threadId));
      h.messages.forEach(m => on.event({ type: m.role === 'user' ? 'user' : 'text', text: m.text, history: true, thread: threadId }));
    } catch {}
  }

  return {
    mode: 'local',
    get threadId() { return threadId; },
    async start() {
      setThreadId(threadId);
      await loadHistory();
      await refresh();
      this.listConnectors().catch(() => {});
      setInterval(() => { if (!document.hidden && !busyStreams) refresh(); }, 5000);
    },
    send(text) { stream('/api/chat', { text, thread: threadId }); },
    approve(id, yes) { stream('/api/approvals/' + id, { approve: yes }); },
    async setPolicy(action, policy) { await post('/api/policies', { action, policy }); refresh(); },
    async forget(id) { await del('/api/facts/' + id); refresh(); },
    async clear() { await post('/api/clear', { thread: threadId }); refresh(); },
    async pairingUrl() { const r = await get('/api/pair'); return r.url; },
    refresh,
    async listThreads() { const r = await get('/api/threads'); return r.threads || []; },
    async newThread() { const r = await post('/api/threads'); const j = await json(r); await loadThreads(false); return j.id; },
    async openThread(id) { threadId = id; setThreadId(id); await loadHistory(); loadThreads(busyStreams > 0); },
    async renameThread(id, title) { await post('/api/threads/' + encodeURIComponent(id) + '/rename', { title }); loadThreads(busyStreams > 0); },
    async deleteThread(id) { await del('/api/threads/' + encodeURIComponent(id)); loadThreads(busyStreams > 0); },
    async restoreThread(id) { await post('/api/threads/' + encodeURIComponent(id) + '/restore'); loadThreads(busyStreams > 0); },
    async getToday() { return get('/api/today'); },
    async getAvatar() { return get('/api/avatar'); },
    async setAvatar(a) { await post('/api/avatar', a); },
    async listConnectors() { const r = await get('/api/connectors'); if (r.labels) on.state({ labels: r.labels }); return r; },
    async connectConnector(id) { return json(await post('/api/connectors/' + encodeURIComponent(id) + '/connect')); },
    async setConnectorToken(id, tokenValue) { return json(await post('/api/connectors/' + encodeURIComponent(id) + '/token', { token: tokenValue })); },
    async setupConnector(id, values) { return json(await post('/api/connectors/' + encodeURIComponent(id) + '/setup', { values })); },
    async disconnectConnector(id) { return json(await post('/api/connectors/' + encodeURIComponent(id) + '/disconnect')); },
    async getPersona() { return get('/api/persona'); },
    async setPersona(persona) { const r = await post('/api/persona', { persona }); if (!r.ok) throw new Error(r.status); return r.json(); },
    async listSkills() { return get('/api/skills'); },
    async deleteSkill(name) { await del('/api/skills/' + encodeURIComponent(name)); },
    async listCards() { return get('/api/cards'); },
    async addCard(card) { const r = await post('/api/cards', card); const j = await r.json().catch(() => ({})); if (!r.ok) throw new Error(j.error || r.status); return j; },
    async deleteCard(id) { await del('/api/cards/' + encodeURIComponent(id)); },
  };
}
