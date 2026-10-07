// Gzowo Concierge - live voice smoke test: connects like a browser, sends a text turn, reports what comes back.
const port = process.argv[2] || 2040;
const text = process.argv[3] || 'Co mam jutro w kalendarzu?';
const ws = new WebSocket(`ws://localhost:${port}/live`);
ws.binaryType = 'arraybuffer';
let audio = 0, chunks = 0;
const t0 = Date.now();
const log = (...a) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1)}s]`, ...a);
ws.onopen = () => log('socket open');
ws.onmessage = ev => {
  if (typeof ev.data !== 'string') { audio += ev.data.byteLength; chunks++; return; }
  const m = JSON.parse(ev.data);
  if (m.type === 'ready') { log('ready'); ws.send(JSON.stringify({ type: 'text', text })); log('sent:', text); }
  else if (m.type === 'transcript') { if (m.final || m.role === 'user') log('transcript', m.role, m.final ? '(final)' : '', m.text); }
  else if (m.type === 'tool') log('tool', m.status, m.summary, 'rid=' + String(m.rid).slice(0, 8));
  else log(m.type, m.state || m.message || '');
};
ws.onerror = e => log('socket error', e.message || '');
ws.onclose = e => { log('closed', e.code, `audio ${(audio / 48000).toFixed(1)}s in ${chunks} chunks`); process.exit(0); };
setTimeout(() => { log(`done waiting. audio ${(audio / 48000).toFixed(1)}s (24kHz mono) in ${chunks} chunks`); ws.send(JSON.stringify({ type: 'end' })); setTimeout(() => process.exit(0), 500); }, 30000);
