// Gzowo Concierge - feeds a 16 kHz mono WAV to the live host as if it came from the mic; prints what the model heard and answered.
import fs from 'node:fs';
const port = process.argv[2] || 2040, file = process.argv[3];
const wav = fs.readFileSync(file);
const pcm = wav.subarray(44);
const ws = new WebSocket(`ws://localhost:${port}/live`);
ws.binaryType = 'arraybuffer';
const t0 = Date.now(), log = (...a) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1)}s]`, ...a);
let heard = '', said = '', audio = 0;
ws.onmessage = async ev => {
  if (typeof ev.data !== 'string') { audio += ev.data.byteLength; return; }
  const m = JSON.parse(ev.data);
  if (m.type === 'ready') {
    log('ready, streaming', (pcm.length / 32000).toFixed(1) + 's of speech');
    for (let i = 0; i < pcm.length; i += 1280) { ws.send(pcm.subarray(i, i + 1280)); await new Promise(r => setTimeout(r, 40)); }
    const silence = Buffer.alloc(1280);
    for (let i = 0; i < 75; i++) { ws.send(silence); await new Promise(r => setTimeout(r, 40)); }
    log('audio sent');
  } else if (m.type === 'transcript') { if (m.role === 'user') heard = m.text; else said = m.text; if (m.final) log('turn final'); }
  else if (m.type === 'tool') log('tool', m.status, m.summary);
  else if (m.type === 'error') log('ERROR', m.message);
};
setTimeout(() => { log('HEARD :', JSON.stringify(heard)); log('SAID  :', JSON.stringify(said)); log(`audio out ${(audio / 48000).toFixed(1)}s`); process.exit(0); }, 45000);
