// Gzowo Concierge - phone transport: Firebase Realtime Database relay (the Mac host connects outbound too).
import { firebaseConfig } from './config.js';

const SDK = 'https://www.gstatic.com/firebasejs/12.4.0/';

export async function createRelay(sid, on) {
  const [{ initializeApp }, db] = await Promise.all([import(SDK + 'firebase-app.js'), import(SDK + 'firebase-database.js')]);
  const { getDatabase, ref, push, onValue, onChildAdded, onChildRemoved, query, limitToLast, serverTimestamp } = db;
  const d = getDatabase(initializeApp(firebaseConfig));
  const root = 'c/' + sid;
  let offset = 0, hostTs = 0, link = true;

  const send = msg => push(ref(d, root + '/inbox'), { ...msg, ts: serverTimestamp() });
  const hostOnline = () => hostTs > 0 && Date.now() + offset - hostTs < 70000;
  const pushOnline = () => on.state({ online: link && hostOnline(), link });

  onValue(ref(d, '.info/serverTimeOffset'), s => { offset = s.val() || 0; });
  onValue(ref(d, '.info/connected'), s => { link = !!s.val(); pushOnline(); });
  onValue(ref(d, root + '/state'), s => {
    const v = s.val() || {};
    hostTs = v.online || 0;
    const policies = {};
    for (const [k, val] of Object.entries(v.policies || {})) policies[k.replace('_', '.')] = val;
    on.state({ busy: !!v.busy, policies, facts: v.facts || {}, pending: v.pending || {}, online: link && hostOnline(), link });
  });
  setInterval(pushOnline, 5000);
  onChildAdded(query(ref(d, root + '/feed'), limitToLast(200)), s => on.event({ ...s.val(), history: true }, s.key));
  onChildAdded(ref(d, root + '/inbox'), s => { const v = s.val(); if (v?.type === 'chat') on.queued(v.cid, v.text); });

  return {
    mode: 'relay',
    async start() {},
    send(text, cid) { send({ type: 'chat', text, cid }); },
    approve(id, yes) { send({ type: 'approval', id, approve: yes }); },
    setPolicy(action, policy) { send({ type: 'policy', action, policy }); },
    forget(id) { send({ type: 'forget', id }); },
    clear() { send({ type: 'clear' }); },
    async pairingUrl() { return null; },
  };
}
