// Gzowo Concierge - live voice client: mic capture (AudioWorklet, 16 kHz PCM16), playback (24 kHz PCM16), WebSocket to the host at /live.
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

export function createLive({ onEvent = () => {}, onState = () => {}, onLevel = () => {}, onTranscript = () => {} } = {}) {
  let ctx = null, ws = null, stream = null, node = null, source = null, gain = null, analyser = null, timer = null;
  let hostState = 'idle', shown = 'idle', muted = false, playHead = 0, mic = 0, out = 0, stopping = false;
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

  function url() {
    let t = ''; try { t = localStorage.getItem('ct') || ''; } catch {}
    return `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/live${t ? '?t=' + encodeURIComponent(t) : ''}`;
  }

  function handle(m) {
    if (m.type === 'state') { hostState = m.state; publish(); }
    else if (m.type === 'ready') { hostState = 'listening'; publish(); }
    else if (m.type === 'interrupted') { flush(); publish(); }
    else if (m.type === 'transcript') onTranscript({ role: m.role, text: m.text, final: !!m.final });
    else if (m.type === 'error') { onEvent(m); stop(); }
    else onEvent(m);
  }

  async function start() {
    if (ws || stopping) return;
    hostState = 'connecting'; shown = 'idle'; ws = {};
    ctx = new (window.AudioContext || window.webkitAudioContext)({ latencyHint: 'interactive' });
    ctx.resume();
    publish();
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 } });
      const blob = URL.createObjectURL(new Blob([WORKLET], { type: 'text/javascript' }));
      await ctx.audioWorklet.addModule(blob);
      URL.revokeObjectURL(blob);
    } catch (e) {
      onEvent({ type: 'error', message: e && e.name === 'NotAllowedError' ? 'Brak zgody na mikrofon. Zezwól na dostęp w ustawieniach przeglądarki.' : 'Nie udało się uruchomić mikrofonu.' });
      stop(); return;
    }
    gain = ctx.createGain();
    analyser = ctx.createAnalyser(); analyser.fftSize = 512;
    gain.connect(analyser); analyser.connect(ctx.destination);
    source = ctx.createMediaStreamSource(stream);
    node = new AudioWorkletNode(ctx, 'mic-capture');
    source.connect(node);
    const socket = new WebSocket(url());
    socket.binaryType = 'arraybuffer';
    ws = socket;
    node.port.onmessage = e => {
      if (e.data.level !== undefined) { if (e.data.level > mic) mic = e.data.level; return; }
      if (e.data.pcm && !muted && socket.readyState === 1) socket.send(e.data.pcm);
    };
    socket.onmessage = ev => { if (typeof ev.data === 'string') { try { handle(JSON.parse(ev.data)); } catch {} } else play(ev.data); };
    socket.onclose = () => { if (ws === socket) stop(); };
    socket.onerror = () => { onEvent({ type: 'error', message: 'Brak połączenia z hostem głosowym.' }); };
    timer = setInterval(tick, 33);
  }

  function stop() {
    if (stopping) return;
    stopping = true;
    try { if (ws && ws.readyState === 1) { ws.send(JSON.stringify({ type: 'end' })); ws.close(); } } catch {}
    ws = null;
    clearInterval(timer); timer = null;
    flush();
    try { node && node.disconnect(); source && source.disconnect(); } catch {}
    try { stream && stream.getTracks().forEach(t => t.stop()); } catch {}
    try { ctx && ctx.close(); } catch {}
    ctx = stream = node = source = gain = analyser = null;
    hostState = 'idle'; mic = out = 0;
    onLevel({ mic: 0, out: 0 });
    shown = 'idle'; onState('idle');
    stopping = false;
  }

  return {
    start,
    stop,
    mute(on) { muted = !!on; if (stream) stream.getAudioTracks().forEach(t => { t.enabled = !muted; }); },
    sendText(text) { if (ws && ws.readyState === 1) ws.send(JSON.stringify({ type: 'text', text })); },
    get state() { return shown; },
  };
}
