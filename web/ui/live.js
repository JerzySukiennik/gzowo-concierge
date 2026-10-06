// Gzowo Concierge - live voice screen: face, status, transcript, tool and approval cards with face gaze, mic controls.
import { createFace } from '../face.js';
import { createThread } from './thread.js';
import { icon } from './icons.js';

const STATUS = {
  idle: ['Dotknij mikrofonu, żeby zacząć', 'Najlepiej działa na słuchawkach.'],
  connecting: ['Łączę…', ''],
  listening: ['Słucham', ''],
  thinking: ['Myślę', ''],
  speaking: ['Mówię', ''],
  working: ['Pracuję', ''],
  alert: ['Czekam na Twoją zgodę', ''],
  error: ['Coś poszło nie tak', ''],
};

export function createLiveScreen({ root, factory, forward, approve, getPending, setPending, onFinal, onClose }) {
  const q = s => root.querySelector(s);
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const face = createFace(q('#faceCanvas'));
  const cards = q('.live-cards'), pendingBox = q('#livePending');
  const steps = createThread({ log: cards, root: q('#liveSteps') });
  const status = q('#liveStatus'), hint = q('#liveHint'), txUser = q('#txUser'), txBot = q('#txBot');
  const micBtn = q('#liveMic'), muteBtn = q('#liveMute'), ring = q('.ring');
  const asks = new Map(), answered = new Map(), stepState = new Map();
  let live = null, liveState = 'idle', muted = false, open = false, errFlash = false, errTimer = 0, holdTimer = 0;
  let focusNode = null, holdNode = null, holdUntil = 0, lastTarget = null, lastRole = '', pendingUser = '', ringLevel = -1;

  micBtn.querySelector('.glyph').innerHTML = icon('mic', 28);
  muteBtn.querySelector('.glyph').innerHTML = icon('mic', 22);
  q('#liveClose').querySelector('.glyph').innerHTML = icon('close', 22);
  steps.setAnimate(!reduce.matches);

  const runningCount = () => { let n = 0; stepState.forEach(s => { if (s === 'running') n++; }); return n; };

  function paint(name) {
    const [a, b] = STATUS[name] || STATUS.idle;
    if (status.textContent !== a) status.textContent = a;
    hint.textContent = b;
  }

  function refresh() {
    const ask = asks.values().next().value || null;
    const running = runningCount() > 0;
    const now = performance.now();
    const target = ask || (running ? focusNode : (holdNode && now < holdUntil ? holdNode : null));
    if (target !== lastTarget) { lastTarget = target; face.lookAt(target); }
    let fs;
    if (errFlash) fs = 'error';
    else if (ask) fs = 'alert';
    else if (running && liveState !== 'speaking') fs = 'working';
    else fs = liveState === 'connecting' || liveState === 'idle' ? 'idle' : liveState;
    face.setState(fs);
    paint(fs);
    const active = liveState !== 'idle';
    micBtn.classList.toggle('active', active);
    micBtn.querySelector('.glyph').innerHTML = icon(active ? 'stop' : 'mic', 28);
    micBtn.querySelector('.lbl').textContent = active ? 'Zakończ' : 'Zacznij';
    micBtn.setAttribute('aria-label', active ? 'Zakończ rozmowę' : 'Zacznij rozmowę');
    cards.classList.toggle('has', asks.size > 0 || stepState.size > 0 || !!cards.querySelector('.note'));
  }

  function hold(node, ms) {
    holdNode = node; holdUntil = performance.now() + ms;
    clearTimeout(holdTimer);
    holdTimer = setTimeout(refresh, ms + 30);
  }

  function flashError(node) {
    face.pulse('error');
    errFlash = true; clearTimeout(errTimer);
    errTimer = setTimeout(() => { errFlash = false; refresh(); }, 1500);
    if (node) hold(node, 1500);
  }

  function onEvent(e) {
    if (e.type === 'tool') {
      const key = (e.rid || '') + e.name + e.summary;
      const prev = stepState.get(key);
      const node = steps.setStep(key, e.name, e.summary, e.status, e.error);
      stepState.set(key, e.status);
      if (e.status === 'running') { focusNode = node; holdNode = null; }
      else if (prev === 'running' || !prev) {
        if (e.status === 'failed') { face.pulse('wince'); hold(node, 1200); }
        else { if (runningCount() === 0) face.pulse('ok'); hold(node, 900); }
      }
      forward(e);
    } else if (e.type === 'error') {
      const row = steps.addError(e.message);
      flashError(row);
      forward(e);
    } else if (e.type === 'approval') {
      setPending({ ...getPending(), [e.id]: e.summary });
    } else if (e.type === 'pending') {
      setPending(e.pending || {});
    }
    refresh();
  }

  function syncPending(pending) {
    for (const [id, summary] of Object.entries(pending)) {
      if (asks.has(id)) continue;
      const c = document.createElement('div');
      c.className = 'ask' + (reduce.matches ? '' : ' enter');
      c.innerHTML = '<div class="ask-head"><span class="live-dot"></span><span>Czeka na Twoją zgodę</span></div><p class="ask-q"></p><div class="ask-btns"><button type="button" class="btn tonal" data-v="0">Nie</button><button type="button" class="btn ink" data-v="1">Tak</button></div>';
      c.querySelector('.ask-q').textContent = summary;
      c.querySelectorAll('button').forEach(b => b.onclick = () => { const yes = b.dataset.v === '1'; answered.set(id, yes); approve(id, yes); });
      asks.set(id, c);
      pendingBox.append(c);
      if (open) requestAnimationFrame(() => c.scrollIntoView({ block: 'nearest', behavior: reduce.matches ? 'auto' : 'smooth' }));
    }
    for (const [id, c] of asks) {
      if (id in pending) continue;
      asks.delete(id);
      const yes = answered.get(id); answered.delete(id);
      if (open) face.pulse(yes === false ? 'blink' : 'nod');
      if (reduce.matches || !open) c.remove();
      else { c.classList.remove('enter'); c.classList.add('leave'); c.addEventListener('animationend', () => c.remove(), { once: true }); setTimeout(() => c.remove(), 400); }
    }
    refresh();
  }

  function onState(s) {
    liveState = s;
    if (s === 'idle') { face.setLevel(0, 0); setRing(0); }
    refresh();
  }

  function setRing(m) {
    if (Math.abs(m - ringLevel) < 0.02) return;
    ringLevel = m;
    ring.style.transform = 'scale(' + (1 + m * 0.5).toFixed(3) + ')';
    ring.style.opacity = liveState !== 'idle' ? (0.1 + m * 0.5).toFixed(2) : '0';
  }

  function onLevel(l) {
    face.setLevel(l.mic, l.out);
    setRing(l.mic);
  }

  function flushUser() {
    if (pendingUser) { onFinal('user', pendingUser); pendingUser = ''; }
  }

  function onTranscript(t) {
    if (t.role === 'user') {
      if (lastRole === 'assistant') { txBot.textContent = ''; }
      txUser.textContent = t.text;
      pendingUser = t.text;
    } else {
      flushUser();
      txBot.textContent = t.text;
      if (t.final && t.text) onFinal('assistant', t.text);
    }
    lastRole = t.role;
  }

  function ensureLive() {
    if (live || !factory) return live;
    live = factory({ onEvent, onState, onLevel, onTranscript });
    return live;
  }

  micBtn.onclick = () => {
    const l = ensureLive();
    if (!l) return;
    if (liveState === 'idle') { l.mute(muted); l.start(); } else { l.stop(); flushUser(); }
  };

  muteBtn.onclick = () => {
    muted = !muted;
    muteBtn.setAttribute('aria-pressed', String(muted));
    muteBtn.querySelector('.glyph').innerHTML = icon(muted ? 'micOff' : 'mic', 22);
    muteBtn.querySelector('.lbl').textContent = muted ? 'Wyciszony' : 'Wycisz';
    live?.mute(muted);
  };

  function show() {
    if (open) return;
    open = true;
    root.classList.add('on');
    root.removeAttribute('inert');
    face.start();
    ensureLive();
    refresh();
    requestAnimationFrame(() => root.focus({ preventScroll: true }));
  }

  function hide() {
    if (!open) return;
    open = false;
    live?.stop();
    flushUser();
    root.classList.remove('on');
    root.setAttribute('inert', '');
    face.stop();
    onClose?.();
  }

  q('#liveClose').onclick = hide;
  q('#liveCloseTop').onclick = hide;
  q('.live-scrim').onclick = hide;
  root.setAttribute('inert', '');
  face.setLevel(0, 0);

  return {
    show, hide, syncPending, onEvent,
    get isOpen() { return open; },
    get face() { return face; },
  };
}
