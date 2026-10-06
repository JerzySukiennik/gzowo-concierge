// Gzowo Concierge - local transport: talks to the host that serves this page (Mac, loopback or LAN with token).
export function createHttp(on) {
  const qs = new URLSearchParams(location.search);
  if (qs.get('t')) { try { localStorage.setItem('ct', qs.get('t')); } catch {} history.replaceState(null, '', location.pathname); }
  const token = (() => { try { return localStorage.getItem('ct') || ''; } catch { return ''; } })();
  const H = { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) };
  let busyStreams = 0;

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

  async function refresh() {
    try {
      const s = await get('/api/state');
      on.state({ online: true, policies: s.policies, facts: Object.fromEntries(s.facts.map(f => [f.id, f.text])), pending: Object.fromEntries(s.pending.map(p => [p.id, p.summary])), busy: busyStreams > 0 || s.busy });
    } catch { on.state({ online: false }); }
  }

  return {
    mode: 'local',
    async start() {
      try {
        const h = await get('/api/history');
        h.messages.forEach(m => on.event({ type: m.role === 'user' ? 'user' : 'text', text: m.text, history: true }));
      } catch {}
      await refresh();
      setInterval(() => { if (!document.hidden && !busyStreams) refresh(); }, 5000);
    },
    send(text) { stream('/api/chat', { text }); },
    approve(id, yes) { stream('/api/approvals/' + id, { approve: yes }); },
    async setPolicy(action, policy) { await post('/api/policies', { action, policy }); refresh(); },
    async forget(id) { await fetch('/api/facts/' + id, { method: 'DELETE', headers: H }); refresh(); },
    async clear() { await post('/api/clear'); },
    async pairingUrl() { const r = await get('/api/pair'); return r.url; },
  };
}
