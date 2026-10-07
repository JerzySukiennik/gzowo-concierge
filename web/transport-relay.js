// Gzowo Concierge - phone transport: Firebase Realtime Database relay (the Mac host connects outbound too); threads, today and connector statuses arrive through state.
import { getFb } from './firebase.js';
import { accountEmail, signOutNow } from './auth.js';
import { getThreadId, setThreadId } from './thread-store.js';

export async function createRelay(on) {
  const { dbMod, db: d } = await getFb();
  const { ref, push, onValue, onChildAdded, query, limitToLast, serverTimestamp } = dbMod;
  const root = 'u/main';
  let offset = 0, hostTs = 0, link = true, threadId = getThreadId(), feedOff = null;
  let threads = {}, today = null, connList = [], labels = {};

  const send = msg => push(ref(d, root + '/inbox'), { ...msg, ts: serverTimestamp() });
  const hostOnline = () => hostTs > 0 && Date.now() + offset - hostTs < 70000;
  const pushOnline = () => on.state({ online: link && hostOnline(), link });
  const pushThreads = () => on.state({ threads: { ...threads } });

  function subscribeFeed() {
    if (feedOff) { try { feedOff(); } catch {} }
    const id = threadId;
    feedOff = onChildAdded(query(ref(d, root + '/feed/' + id), limitToLast(200)), s => { if (id === threadId) on.event({ ...s.val(), history: true, thread: id }); });
  }

  onValue(ref(d, '.info/serverTimeOffset'), s => { offset = s.val() || 0; });
  onValue(ref(d, '.info/connected'), s => { link = !!s.val(); pushOnline(); });
  onValue(ref(d, root + '/state'), s => {
    const v = s.val() || {};
    hostTs = v.online || 0;
    const policies = {};
    for (const [k, val] of Object.entries(v.policies || {})) policies[k.replace('_', '.')] = val;
    threads = v.threads || {};
    labels = v.labels || {};
    const meta = v.connectorMeta || {}, st = v.connectors || {};
    connList = Object.keys({ ...meta, ...st }).map(id => ({ id, name: (meta[id] || {}).name || id, icon: (meta[id] || {}).icon || id, category: (meta[id] || {}).category || 'Inne', state: st[id] || 'available', capabilities: [], tools: [] }));
    try { today = v.todayJson ? JSON.parse(v.todayJson) : null; } catch { today = null; }
    on.state({ avatar: v.avatar || undefined, busy: !!v.busy, policies, facts: v.facts || {}, pending: v.pending || {}, online: link && hostOnline(), link, threads: { ...threads }, labels, connectors: st, today });
  });
  setInterval(pushOnline, 5000);
  subscribeFeed();
  onChildAdded(ref(d, root + '/inbox'), s => { const v = s.val(); if (v?.type === 'chat' && (v.thread || 'main') === threadId) on.queued(v.cid, v.text); });

  const once = (path, ms, label) => new Promise((resolve, reject) => {
    let off = null, done = false;
    const finish = (fn, v) => { if (done) return; done = true; clearTimeout(timer); if (off) off(); fn(v); };
    const timer = setTimeout(() => finish(reject, new Error(label)), ms);
    off = onValue(ref(d, path), s => { const v = s.val(); if (v) finish(resolve, v); });
    if (done) off();
  });

  async function openLive({ onEvent, onNotify, thread }) {
    const tid = thread || threadId;
    const cid = crypto.randomUUID();
    const base = root + '/live/' + cid;
    const unsub = [];
    send({ type: 'live-token', cid, thread: tid });
    let tok;
    try { tok = await once(base + '/token', 15000, 'Mac nie odpowiada, spróbuj za chwilę.'); }
    catch (e) { send({ type: 'live-end', cid }); throw e; }
    if (tok.error) { send({ type: 'live-end', cid }); throw new Error('Nie udało się uruchomić rozmowy: ' + tok.error); }
    unsub.push(onChildAdded(ref(d, base + '/ev'), s => onEvent(s.val())));
    unsub.push(onChildAdded(ref(d, base + '/notify'), s => { const v = s.val(); if (v && v.text) onNotify(v.text); }));
    return {
      token: tok.token,
      model: tok.model,
      async callTool(call) {
        const callId = crypto.randomUUID();
        const pending = once(base + '/res/' + callId, 90000, 'Narzędzie nie odpowiedziało na czas.');
        send({ type: 'live-tool', cid, callId, name: call.name, argsJson: JSON.stringify(call.args || {}) });
        const v = await pending;
        try { return JSON.parse(v.json); } catch { return { ok: false, error: 'Nieczytelna odpowiedź narzędzia.' }; }
      },
      turn(user, assistant) { if (user || assistant) send({ type: 'live-turn', cid, rid: crypto.randomUUID(), user, assistant, thread: tid }); },
      close() { unsub.forEach(u => { try { u(); } catch {} }); send({ type: 'live-end', cid }); },
    };
  }

  return {
    mode: 'relay',
    liveBridge: { open: openLive },
    account: { email: await accountEmail(), signOut: async () => { await signOutNow(); location.reload(); } },
    get threadId() { return threadId; },
    async start() { setThreadId(threadId); },
    send(text, cid) { send({ type: 'chat', text, cid, thread: threadId }); },
    approve(id, yes) { send({ type: 'approval', id, approve: yes }); },
    setPolicy(action, policy) { send({ type: 'policy', action, policy }); },
    forget(id) { send({ type: 'forget', id }); },
    clear() { send({ type: 'clear', thread: threadId }); },
    async pairingUrl() { return null; },
    async listThreads() { return Object.entries(threads).map(([id, t]) => ({ id, ...t })).sort((a, b) => b.updated - a.updated); },
    async newThread() {
      const id = crypto.randomUUID();
      send({ type: 'thread-new', thread: id });
      threads = { ...threads, [id]: { title: 'Nowa rozmowa', updated: Date.now(), busy: false } };
      pushThreads();
      return id;
    },
    async openThread(id) { threadId = id; setThreadId(id); subscribeFeed(); },
    async renameThread(id, title) { send({ type: 'thread-rename', thread: id, title }); if (threads[id]) { threads = { ...threads, [id]: { ...threads[id], title } }; pushThreads(); } },
    async deleteThread(id) { send({ type: 'thread-delete', thread: id }); const n = { ...threads }; delete n[id]; threads = n; pushThreads(); },
    async restoreThread(id) { send({ type: 'thread-restore', thread: id }); },
    async getToday() { return today; },
    setAvatar(a) { send({ type: 'avatar', shape: a.shape, color: a.color }); },
    async listConnectors() { return { connectors: connList, labels }; },
  };
}
