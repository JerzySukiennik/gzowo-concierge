// Gzowo Concierge - phone live voice smoke test: acts like the phone (token via relay, direct Gemini session, tools via relay).
import crypto from 'node:crypto';
const DB = process.env.DB || 'https://gzowo-concierge-default-rtdb.europe-west1.firebasedatabase.app';
const SID = process.env.SID;
if (!SID) { console.error('SID env required (use a test sid, not the real one)'); process.exit(1); }
const base = `${DB}/c/${SID}`;
const text = process.argv[2] || 'Co mam jutro w kalendarzu?';
const t0 = Date.now();
const log = (...a) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1)}s]`, ...a);
const rest = async (method, path, body) => { const r = await fetch(`${base}/${path}.json`, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) }); return r.json(); };
const send = msg => rest('POST', 'inbox', { ...msg, ts: { '.sv': 'timestamp' } });
const waitFor = async (path, ms) => { const end = Date.now() + ms; while (Date.now() < end) { const v = await rest('GET', path); if (v) return v; await new Promise(r => setTimeout(r, 150)); } throw new Error('timeout ' + path); };

const cid = crypto.randomUUID();
await send({ type: 'live-token', cid });
const tok = await waitFor(`live/${cid}/token`, 15000);
if (tok.error) { log('token error', tok.error); process.exit(1); }
log('token minted via relay, model', tok.model);

const ws = new WebSocket(`wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained?access_token=${encodeURIComponent(tok.token)}`);
let audio = 0, user = '', assistant = '', done = false;
const up = o => ws.send(JSON.stringify(o));
ws.onopen = () => up({ setup: { model: tok.model } });
ws.onerror = () => log('socket error');
ws.onclose = e => { log('closed', e.code, (e.reason || '').slice(0, 100)); if (!done) process.exit(1); };
ws.onmessage = async ev => {
  const m = JSON.parse(typeof ev.data === 'string' ? ev.data : await ev.data.text());
  if (m.setupComplete) { log('setup complete; asking:', text); up({ realtimeInput: { text } }); }
  if (m.toolCall) {
    const responses = [];
    for (const c of m.toolCall.functionCalls) {
      const callId = crypto.randomUUID();
      log('toolCall', c.name, JSON.stringify(c.args));
      await send({ type: 'live-tool', cid, callId, name: c.name, argsJson: JSON.stringify(c.args || {}) });
      const res = await waitFor(`live/${cid}/res/${callId}`, 60000);
      const response = JSON.parse(res.json);
      log('tool result ok=', response.ok, response.status || '');
      responses.push({ id: c.id, name: c.name, response });
    }
    up({ toolResponse: { functionResponses: responses } });
  }
  const sc = m.serverContent;
  if (sc) {
    for (const p of sc.modelTurn?.parts || []) if (p.inlineData?.data) audio += Buffer.from(p.inlineData.data, 'base64').length;
    if (sc.inputTranscription?.text) user += sc.inputTranscription.text;
    if (sc.outputTranscription?.text) assistant += sc.outputTranscription.text;
    if (sc.turnComplete && assistant) {
      done = true;
      log(`turn complete. audio ${(audio / 48000).toFixed(1)}s. said: ${assistant}`);
      await send({ type: 'live-turn', cid, rid: crypto.randomUUID(), user: text, assistant });
      await new Promise(r => setTimeout(r, 2500));
      const evs = await rest('GET', `live/${cid}/ev`);
      log('relay events seen by phone:', Object.values(evs || {}).map(e => `${e.type}${e.status ? ':' + e.status : ''}`).join(', '));
      const feed = await rest('GET', 'feed');
      log('feed types:', Object.values(feed || {}).map(e => e.type).join(', '));
      await send({ type: 'live-end', cid });
      await new Promise(r => setTimeout(r, 1500));
      log('live node after end:', JSON.stringify(await rest('GET', `live/${cid}`)));
      process.exit(0);
    }
  }
};
setTimeout(() => { log('overall timeout'); process.exit(1); }, 90000);
