// Gzowo Concierge - immersive live screen: the bot, voice glow, one status word, one fading transcript line, floating tool chips and approval cards, mute and end buttons.
import { createFace, followPointer } from '../face.js';
import { createGlow } from './glow.js';
import { buildAsk } from './ask.js';
import { icon, toolIcon } from './icons.js';
import { hold as holdAwake } from './ticker.js';

const STATUS = {
  idle: '',
  connecting: 'Łączę',
  listening: 'Słucham',
  thinking: 'Myślę',
  speaking: 'Mówię',
  working: 'Pracuję',
  alert: 'Czekam na zgodę',
  error: 'Coś poszło nie tak',
};

const tail = t => { const s = t.replace(/\s+/g, ' ').trim(); if (s.length <= 72) return s; const c = s.slice(-72); const i = c.indexOf(' '); return '… ' + (i > 0 && i < 24 ? c.slice(i + 1) : c); };

export function createLiveScreen({ root, factory, forward, approve, getPending, setPending, onFinal, onClose, onShell }) {
  const q = s => root.querySelector(s);
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const face = createFace(q('#faceCanvas'), { autoSleep: false, greet: false });
  const glow = createGlow(q('#liveGlow'));
  const floatBox = q('#liveSteps'), pendingBox = q('#livePending');
  const status = q('#liveStatus'), line = q('#liveLine');
  const muteBtn = q('#liveMute'), endBtn = q('#liveClose');
  const asks = new Map(), answered = new Map(), chips = new Map();
  let live = null, liveState = 'idle', muted = false, open = false, errFlash = false, errTimer = 0, holdTimer = 0, unfollow = null, lineTimer = 0, endTimer = 0;
  let focusNode = null, holdNode = null, holdUntil = 0, lastTarget = null, lastRole = '', pendingUser = '', lastShell = '', seenActive = false;

  muteBtn.querySelector('.glyph').innerHTML = icon('mic', 24, true);
  endBtn.querySelector('.glyph').innerHTML = icon('close', 24, false, 2);

  const running = () => { let n = 0; chips.forEach(c => { if (c.status === 'running') n++; }); return n; };

  function refresh() {
    const ask = asks.values().next().value || null;
    const busy = running() > 0;
    const now = performance.now();
    const target = ask || (busy ? focusNode : (holdNode && holdNode.isConnected && now < holdUntil ? holdNode : null));
    if (target !== lastTarget) { lastTarget = target; face.lookAt(target); }
    let fs;
    if (errFlash) fs = 'error';
    else if (ask) fs = 'alert';
    else if (busy && liveState !== 'speaking') fs = 'working';
    else fs = liveState === 'connecting' || liveState === 'idle' ? 'idle' : liveState;
    face.setState(fs);
    glow.setState(liveState === 'connecting' ? 'connecting' : fs);
    const word = STATUS[fs] ?? '';
    if (status.textContent !== word) status.textContent = word;
    root.dataset.s = fs;
    const sh = !open ? 'idle' : ask ? 'alert' : busy && liveState !== 'speaking' ? 'thinking' : liveState;
    if (sh !== lastShell) { lastShell = sh; onShell?.(sh); }
  }

  function hold(node, ms) {
    holdNode = node; holdUntil = performance.now() + ms;
    clearTimeout(holdTimer);
    holdTimer = setTimeout(refresh, ms + 30);
  }

  function flashError() {
    face.pulse('error');
    errFlash = true; clearTimeout(errTimer);
    errTimer = setTimeout(() => { errFlash = false; refresh(); }, 1500);
  }

  function dropChip(key, ms) {
    const c = chips.get(key);
    if (!c) return;
    clearTimeout(c.timer);
    c.timer = setTimeout(() => {
      c.node.classList.add('out');
      setTimeout(() => { c.node.remove(); chips.delete(key); if (holdNode === c.node) holdNode = null; refresh(); }, reduce.matches ? 60 : 520);
    }, ms);
  }

  function stepChip(e) {
    const key = (e.rid || '') + e.name + e.summary;
    let c = chips.get(key);
    if (!c) {
      const node = document.createElement('div');
      node.className = 'lchip glass';
      node.innerHTML = `<span class="s-ic">${icon(toolIcon(e.name), 15)}</span><span class="lt"></span><span class="s-st" aria-hidden="true"></span>`;
      node.setAttribute('role', 'status');
      floatBox.append(node);
      c = { node, status: '', timer: 0 };
      chips.set(key, c);
    }
    c.node.querySelector('.lt').textContent = e.summary;
    clearTimeout(c.timer);
    if (c.status !== e.status) {
      c.status = e.status;
      c.node.classList.toggle('run', e.status === 'running');
      c.node.classList.toggle('fail', e.status === 'failed');
      c.node.querySelector('.s-st').innerHTML = e.status === 'running' ? '<i class="spin"></i>' : icon(e.status === 'failed' ? 'close' : 'check', 14);
    }
    if (e.status !== 'running') dropChip(key, e.status === 'failed' ? 3600 : 2200);
    return c;
  }

  function onEvent(e) {
    if (e.type === 'tool') {
      const prev = chips.get((e.rid || '') + e.name + e.summary)?.status;
      const c = stepChip(e);
      if (e.status === 'running') { focusNode = c.node; holdNode = null; }
      else if (prev === 'running' || !prev) {
        if (e.status === 'failed') { face.pulse('wince'); hold(c.node, 1500); }
        else { if (running() === 0) face.pulse('ok'); hold(c.node, 1100); }
      }
      forward(e);
    } else if (e.type === 'error') {
      const node = document.createElement('div');
      node.className = 'lchip glass note';
      node.setAttribute('role', 'alert');
      node.innerHTML = `<span class="s-ic">${icon('alert', 15, true)}</span><span class="lt"></span>`;
      node.querySelector('.lt').textContent = e.message;
      floatBox.append(node);
      setTimeout(() => { node.classList.add('out'); setTimeout(() => node.remove(), 520); }, 4200);
      flashError();
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
      const c = buildAsk(summary, yes => { answered.set(id, yes); approve(id, yes); });
      c.classList.add('live-ask');
      if (!reduce.matches) c.classList.add('enter');
      asks.set(id, c);
      pendingBox.append(c);
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
    if (s !== 'idle') seenActive = true;
    if (s === 'idle') {
      face.setLevel(0, 0); glow.setLevel(0, 0);
      if (open && seenActive) {
        status.textContent = 'Rozmowa zakończona';
        clearTimeout(endTimer);
        endTimer = setTimeout(() => { if (open && liveState === 'idle') hide(); }, 1100);
        return;
      }
    }
    refresh();
  }

  function onLevel(l) {
    face.setLevel(l.mic, l.out);
    glow.setLevel(l.mic, l.out);
  }

  function showLine(text, role) {
    const t = tail(text);
    if (!t) return;
    line.textContent = t;
    line.classList.toggle('user', role === 'user');
    line.classList.add('on');
    clearTimeout(lineTimer);
    lineTimer = setTimeout(() => line.classList.remove('on'), 4200);
  }

  function flushUser() {
    if (pendingUser) { onFinal('user', pendingUser); pendingUser = ''; }
  }

  function onTranscript(t) {
    if (t.role === 'user') {
      pendingUser = t.text;
      showLine(t.text, 'user');
    } else {
      flushUser();
      showLine(t.text, 'assistant');
      if (t.final && t.text) onFinal('assistant', t.text);
    }
    lastRole = t.role;
  }

  function ensureLive() {
    if (live || !factory) return live;
    live = factory({ onEvent, onState, onLevel, onTranscript });
    return live;
  }

  muteBtn.onclick = () => {
    muted = !muted;
    muteBtn.setAttribute('aria-pressed', String(muted));
    muteBtn.setAttribute('aria-label', muted ? 'Włącz mikrofon' : 'Wycisz mikrofon');
    muteBtn.querySelector('.glyph').innerHTML = muted ? icon('micOff', 24, true) : icon('mic', 24, true);
    live?.mute(muted);
  };

  function show() {
    if (open) return;
    open = true; seenActive = false; errFlash = false;
    clearTimeout(endTimer);
    root.classList.add('on');
    root.removeAttribute('inert');
    holdAwake(true);
    face.start();
    glow.start();
    if (!unfollow) unfollow = followPointer(face);
    status.textContent = STATUS.connecting;
    const l = ensureLive();
    if (l) { l.mute(muted); l.start(); }
    refresh();
    requestAnimationFrame(() => root.focus({ preventScroll: true }));
  }

  function hide() {
    if (!open) return;
    open = false;
    clearTimeout(endTimer); clearTimeout(lineTimer);
    live?.stop();
    flushUser();
    root.classList.remove('on');
    root.setAttribute('inert', '');
    holdAwake(false);
    face.stop();
    glow.stop();
    if (unfollow) { unfollow(); unfollow = null; }
    line.classList.remove('on');
    chips.forEach(c => { clearTimeout(c.timer); c.node.remove(); });
    chips.clear();
    floatBox.textContent = '';
    focusNode = holdNode = null;
    refresh();
    onClose?.();
  }

  endBtn.onclick = hide;
  q('.live-scrim').onclick = hide;
  root.setAttribute('inert', '');
  face.setLevel(0, 0);

  return {
    show, hide, syncPending, onEvent,
    get isOpen() { return open; },
    get face() { return face; },
    get shellState() { return lastShell || 'idle'; },
  };
}
