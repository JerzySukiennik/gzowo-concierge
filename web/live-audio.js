// Gzowo Concierge - live voice client: mic capture (AudioWorklet, 16 kHz PCM16), playback (24 kHz PCM16); host WebSocket (Mac) or direct Gemini session with relayed tools (phone).
const WORKLET = `
class MicCapture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.step = sampleRate / 16000;
    this.phase = 0; this.acc = 0; this.cnt = 0;
    this.out = new Int16Array(640); this.n = 0;
    this.sum = 0; this.seen = 0;
  }
  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (!ch) return true;
    for (let i = 0; i < ch.length; i++) {
      const x = ch[i];
      this.sum += x * x; this.seen++;
      this.acc += x; this.cnt++;
      this.phase += 1;
      if (this.phase >= this.step) {
        this.phase -= this.step;
        const v = Math.max(-1, Math.min(1, this.acc / this.cnt));
        this.acc = 0; this.cnt = 0;
        this.out[this.n++] = v < 0 ? v * 32768 : v * 32767;
        if (this.n === 640) { const b = this.out.buffer; this.port.postMessage({ pcm: b }, [b]); this.out = new Int16Array(640); this.n = 0; }
      }
    }
    if (this.seen >= 1024) { this.port.postMessage({ level: Math.sqrt(this.sum / this.seen) }); this.sum = 0; this.seen = 0; }
    return true;
  }
}
registerProcessor('mic-capture', MicCapture);
`;

const DIRECT_URL = 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained';

function toB64(buf) {
  const u = new Uint8Array(buf);
  let s = '';
  for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));
  return btoa(s);
}

function fromB64(str) {
  const bin = atob(str);
  const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u.buffer;
}

export function createLive({ onEvent = () => {}, onState = () => {}, onLevel = () => {}, onTranscript = () => {}, direct = null, thread = 'main' } = {}) {
  let ctx = null, micCtx = null, ws = null, stream = null, node = null, source = null, gain = null, analyser = null, timer = null, session = null;
  let hostState = 'idle', shown = 'idle', muted = false, playHead = 0, mic = 0, out = 0, stopping = false, ready = false;
  let turn = { user: '', assistant: '' }, chain = Promise.resolve();
  const sources = new Set();
  const scratch = new Float32Array(512);

  const effective = () => {
    if (!ws) return 'idle';
    if (hostState === 'connecting') return 'connecting';
    if (sources.size > 0) return 'speaking';
    return hostState === 'thinking' ? 'thinking' : 'listening';
  };
  const publish = () => { const s = effective(); if (s !== shown) { shown = s; onState(s); } };

  function flush() {
    for (const s of sources) { try { s.stop(); } catch {} }
    sources.clear(); playHead = 0;
  }

  function play(ab) {
    if (!ctx || ab.byteLength < 2) return;
    const i16 = new Int16Array(ab, 0, ab.byteLength >> 1);
    const buf = ctx.createBuffer(1, i16.length, 24000);
    const ch = buf.getChannelData(0);
    for (let i = 0; i < i16.length; i++) ch[i] = i16[i] / 32768;
    const s = ctx.createBufferSource();
    s.buffer = buf; s.connect(gain);
    const at = Math.max(ctx.currentTime + 0.04, playHead);
    s.start(at); playHead = at + buf.duration;
    sources.add(s);
    s.onended = () => { sources.delete(s); publish(); };
    publish();
  }

  function tick() {
    if (analyser) {
      analyser.getFloatTimeDomainData(scratch);
      let sum = 0;
      for (let i = 0; i < scratch.length; i++) sum += scratch[i] * scratch[i];
      const raw = Math.min(1, Math.sqrt(sum / scratch.length) * 5);
      out = raw > out ? raw : out * 0.82 + raw * 0.18;
    }
    mic *= 0.85;
    onLevel({ mic: muted ? 0 : Math.min(1, mic * 6), out: sources.size ? out : 0 });
    publish();
  }

  function hostUrl() {
    let t = ''; try { t = localStorage.getItem('ct') || ''; } catch {}
    const q = new URLSearchParams({ thread: thread || 'main' });
    if (t) q.set('t', t);
    return `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/live?${q}`;
  }

  function handleHost(m) {
    if (m.type === 'state') { hostState = m.state; publish(); }
    else if (m.type === 'ready') { hostState = 'listening'; publish(); }
    else if (m.type === 'interrupted') { flush(); publish(); }
    else if (m.type === 'transcript') onTranscript({ role: m.role, text: m.text, final: !!m.final });
    else if (m.type === 'error') { onEvent(m); stop(); }
    else onEvent(m);
  }

  const sendUp = o => { if (ws && ws.readyState === 1 && ready) ws.send(JSON.stringify(o)); };

  async function runTools(calls) {
    const responses = [];
    for (const call of calls) {
      let response;
      try { response = await session.callTool({ name: call.name, args: call.args }); }
      catch (e) { response = { ok: false, error: String((e && e.message) || e) }; }
      responses.push({ id: call.id, name: call.name, response });
    }
    sendUp({ toolResponse: { functionResponses: responses } });
  }

  function handleDirect(m) {
    if (m.setupComplete) { ready = true; hostState = 'listening'; publish(); return; }
    if (m.toolCall) { hostState = 'thinking'; publish(); runTools(m.toolCall.functionCalls || []); return; }
    const sc = m.serverContent;
    if (!sc) return;
    if (sc.interrupted) { flush(); hostState = 'listening'; publish(); }
    for (const part of (sc.modelTurn && sc.modelTurn.parts) || []) {
      if (part.inlineData && part.inlineData.data) { hostState = 'speaking'; play(fromB64(part.inlineData.data)); }
    }
    if (sc.inputTranscription && sc.inputTranscription.text) { turn.user += sc.inputTranscription.text; onTranscript({ role: 'user', text: turn.user, final: false }); }
    if (sc.outputTranscription && sc.outputTranscription.text) { turn.assistant += sc.outputTranscription.text; onTranscript({ role: 'assistant', text: turn.assistant, final: false }); }
    if (sc.turnComplete) {
      onTranscript({ role: 'assistant', text: turn.assistant, final: true });
      if (session) session.turn(turn.user.trim(), turn.assistant.trim());
      turn = { user: '', assistant: '' };
      hostState = 'listening'; publish();
    }
  }

  async function connectHost() {
    const socket = new WebSocket(hostUrl());
    socket.binaryType = 'arraybuffer';
    ws = socket; ready = true;
    node.port.onmessage = e => {
      if (e.data.level !== undefined) { if (e.data.level > mic) mic = e.data.level; return; }
      if (e.data.pcm && !muted && socket.readyState === 1) socket.send(e.data.pcm);
    };
    socket.onmessage = ev => { if (typeof ev.data === 'string') { try { handleHost(JSON.parse(ev.data)); } catch {} } else play(ev.data); };
    socket.onclose = () => { if (ws === socket) stop(); };
    socket.onerror = () => { onEvent({ type: 'error', message: 'Brak połączenia z hostem głosowym.' }); };
  }

  async function connectDirect() {
    try {
      session = await direct.open({
        onEvent: ev => onEvent(ev),
        onNotify: text => sendUp({ realtimeInput: { text } }),
        thread: thread || 'main',
      });
    } catch (e) {
      onEvent({ type: 'error', message: (e && e.message) || 'Nie udało się uruchomić rozmowy.' });
      stop(); return;
    }
    if (!ws) { try { session.close(); } catch {} session = null; return; }
    const socket = new WebSocket(`${DIRECT_URL}?access_token=${encodeURIComponent(session.token)}`);
    ws = socket; ready = false;
    node.port.onmessage = e => {
      if (e.data.level !== undefined) { if (e.data.level > mic) mic = e.data.level; return; }
      if (e.data.pcm && !muted && ready && socket.readyState === 1) socket.send(JSON.stringify({ realtimeInput: { audio: { mimeType: 'audio/pcm;rate=16000', data: toB64(e.data.pcm) } } }));
    };
    socket.onopen = () => socket.send(JSON.stringify({ setup: { model: session.model } }));
    socket.onmessage = ev => {
      chain = chain.then(async () => {
        try {
          const text = typeof ev.data === 'string' ? ev.data : await ev.data.text();
          handleDirect(JSON.parse(text));
        } catch {}
      });
    };
    socket.onclose = ev => {
      if (ws !== socket) return;
      if (!stopping && ev.code !== 1000) onEvent({ type: 'error', message: `Połączenie z modelem głosowym zostało zamknięte (${ev.code}${ev.reason ? ': ' + ev.reason.slice(0, 80) : ''}).` });
      stop();
    };
    socket.onerror = () => { onEvent({ type: 'error', message: 'Brak połączenia z modelem głosowym.' }); };
  }

  async function start() {
    if (ws || stopping) return;
    hostState = 'connecting'; shown = 'idle'; ws = {}; ready = false;
    turn = { user: '', assistant: '' }; chain = Promise.resolve();
    const AC = window.AudioContext || window.webkitAudioContext;
    ctx = new AC({ latencyHint: 'interactive' });
    ctx.resume();
    try { micCtx = new AC({ sampleRate: 16000, latencyHint: 'interactive' }); } catch { micCtx = ctx; }
    micCtx.resume();
    publish();
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 } });
      const blob = URL.createObjectURL(new Blob([WORKLET], { type: 'text/javascript' }));
      await micCtx.audioWorklet.addModule(blob);
      URL.revokeObjectURL(blob);
    } catch (e) {
      onEvent({ type: 'error', message: e && e.name === 'NotAllowedError' ? 'Brak zgody na mikrofon. Zezwól na dostęp w ustawieniach przeglądarki.' : 'Nie udało się uruchomić mikrofonu.' });
      stop(); return;
    }
    if (!ws) { stop(); return; }
    gain = ctx.createGain();
    analyser = ctx.createAnalyser(); analyser.fftSize = 512;
    gain.connect(analyser); analyser.connect(ctx.destination);
    source = micCtx.createMediaStreamSource(stream);
    node = new AudioWorkletNode(micCtx, 'mic-capture');
    source.connect(node);
    timer = setInterval(tick, 33);
    if (direct) await connectDirect(); else await connectHost();
  }

  function stop() {
    if (stopping) return;
    stopping = true;
    try { if (ws && ws.readyState === 1) { if (!direct) ws.send(JSON.stringify({ type: 'end' })); ws.close(); } } catch {}
    ws = null; ready = false;
    try { if (session) session.close(); } catch {}
    session = null;
    clearInterval(timer); timer = null;
    flush();
    try { node && node.disconnect(); source && source.disconnect(); } catch {}
    try { stream && stream.getTracks().forEach(t => t.stop()); } catch {}
    try { if (micCtx && micCtx !== ctx) micCtx.close(); } catch {}
    try { ctx && ctx.close(); } catch {}
    ctx = micCtx = stream = node = source = gain = analyser = null;
    hostState = 'idle'; mic = out = 0;
    onLevel({ mic: 0, out: 0 });
    shown = 'idle'; onState('idle');
    stopping = false;
  }

  return {
    start,
    stop,
    mute(on) { muted = !!on; if (stream) stream.getAudioTracks().forEach(t => { t.enabled = !muted; }); },
    sendText(text) {
      if (!ws || ws.readyState !== 1) return;
      if (direct) sendUp({ realtimeInput: { text } }); else ws.send(JSON.stringify({ type: 'text', text }));
    },
    get state() { return shown; },
  };
}
