// Gzowo Concierge - web app shell: state, transport wiring, composer, approvals, banner, live voice entry, login gate.
import { icon } from './ui/icons.js';
import { createThread } from './ui/thread.js';
import { createSheet } from './ui/sheet.js';
import { createSettings } from './ui/settings.js';
import { createLiveScreen } from './ui/live.js';

const $ = id => document.getElementById(id);
const app = $('app'), log = $('log'), input = $('input'), sendBtn = $('send'), pendingBox = $('pending'), banner = $('banner'), jump = $('jump'), dock = $('dock'), gear = $('gear'), sheetEl = $('sheet');
const reduce = matchMedia('(prefers-reduced-motion: reduce)');
const hoverDevice = matchMedia('(hover: hover) and (pointer: fine)');

const SUGGESTIONS = [['calendar', 'Co mam w tym tygodniu?'], ['calendarPlus', 'Dodaj sprawdzian z matmy w piątek o 8:00'], ['globe', 'Co nowego w Warszawie?']];


const state = { online: true, link: true, busy: false, policies: {}, facts: {}, pending: {}, overrides: {} };
let transport = null, lastUserText = '', settling = true, settleTimer = 0, liveScreen = null, liveTimer = 0;

const thread = createThread({ log, root: $('thread'), onStick: s => jump.classList.toggle('on', !s && thread.hasContent()) });

const settings = createSettings({ body: $('sheetBody'), toast: $('toast'), state, getTransport: () => transport, onCleared: () => { thread.clear(); lastUserText = ''; sheet.hide(); thread.showEmpty(SUGGESTIONS, submit); } });

const sheet = createSheet({
  el: sheetEl, body: $('sheetBody'), scrim: $('scrim'),
  shifts: [$('thread'), $('dockInner')],
  onOpen() {
    settings.build();
    gear.setAttribute('aria-expanded', 'true');
    if (!sheet.isWide) { app.inert = true; requestAnimationFrame(() => sheetEl.focus({ preventScroll: true })); }
  },
  onClose() {
    settings.commitUndo();
    gear.setAttribute('aria-expanded', 'false');
    app.inert = false;
    if (!sheet.isWide || sheetEl.contains(document.activeElement)) gear.focus({ preventScroll: true });
  },
});
gear.onclick = () => sheet.toggle();
$('sheetClose').onclick = () => sheet.hide();

function settle() {
  clearTimeout(settleTimer);
  settleTimer = setTimeout(() => {
    settling = false;
    thread.setAnimate(!reduce.matches);
    if (!thread.hasContent()) thread.showEmpty(SUGGESTIONS, submit);
  }, 450);
}

function onEvent(e) {
  if (settling) settle();
  if (e.type === 'user') { lastUserText = e.text; thread.addUser(e.text, e.cid, false); }
  else if (e.type === 'text') thread.addAssistant(e.text);
  else if (e.type === 'tool') thread.setStep((e.rid || '') + e.name + e.summary, e.name, e.summary, e.status, e.error);
  else if (e.type === 'error') thread.addError(e.message, !e.live && lastUserText && !/autoryzacji/.test(e.message) ? () => transport.send(lastUserText, crypto.randomUUID()) : null);
}

function renderBusy() { thread.setBusy(state.busy); }

function answer(id, yes) {
  delete state.pending[id];
  renderPending();
  liveScreen?.syncPending(state.pending);
  transport.approve(id, yes);
}

const askNodes = new Map();
function renderPending() {
  for (const [id, summary] of Object.entries(state.pending)) {
    if (askNodes.has(id)) continue;
    const c = document.createElement('div');
    c.className = 'ask';
    c.innerHTML = '<div class="ask-head"><span class="live-dot"></span><span>Czeka na Twoją zgodę</span></div><p class="ask-q"></p><div class="ask-btns"><button type="button" class="btn tonal" data-v="0">Nie</button><button type="button" class="btn ink" data-v="1">Tak</button></div>';
    c.querySelector('.ask-q').textContent = summary;
    c.querySelectorAll('button').forEach(b => b.onclick = () => answer(id, b.dataset.v === '1'));
    askNodes.set(id, c);
    pendingBox.append(c);
    if (!settling && !reduce.matches) c.classList.add('enter');
  }
  for (const [id, c] of askNodes) {
    if (id in state.pending) continue;
    askNodes.delete(id);
    if (reduce.matches || settling) { c.remove(); continue; }
    c.classList.remove('enter'); c.classList.add('leave');
    c.addEventListener('animationend', () => c.remove(), { once: true });
    setTimeout(() => c.remove(), 400);
  }
}

function renderBanner() {
  let msg = '';
  if (transport?.mode === 'relay') {
    if (!state.link) msg = 'Brak internetu na telefonie.';
    else if (!state.online) msg = 'Mac jest teraz niedostępny. Wiadomości poczekają do 10 minut.';
  } else if (!state.online) msg = 'Concierge nie odpowiada. Sprawdź, czy działa na Macu.';
  if (msg) banner.querySelector('span').textContent = msg;
  banner.classList.toggle('on', !!msg);
  app.dataset.state = !state.online || !state.link ? 'offline' : state.busy ? 'busy' : 'idle';
  fit();
}

function mergeState(p) {
  if (p.policies) {
    const now = Date.now(), merged = { ...p.policies };
    for (const [a, t] of Object.entries(state.overrides)) {
      if (now - t > 4000 || merged[a] === state.policies[a]) delete state.overrides[a];
      else if (state.policies[a]) merged[a] = state.policies[a];
    }
    p = { ...p, policies: merged };
  }
  Object.assign(state, p);
  renderBusy(); renderPending(); renderBanner();
  if (p.pending) liveScreen?.syncPending(state.pending);
  if (sheet.isOpen) settings.sync();
}

function submit(text) {
  text = (text ?? input.value).trim();
  if (!text) return;
  input.value = ''; fit();
  const cid = crypto.randomUUID();
  lastUserText = text;
  if (transport.mode === 'relay') thread.addUser(text, cid, true); else thread.addUser(text, null, false);
  transport.send(text, cid);
  if (!hoverDevice.matches) input.focus({ preventScroll: true });
}

function openLive() {
  if (!liveScreen) return;
  if (sheet.isOpen) sheet.hide();
  app.inert = true;
  liveScreen.show();
  clearInterval(liveTimer);
  if (transport.refresh) liveTimer = setInterval(() => transport.refresh(), 1500);
}

function closedLive() {
  clearInterval(liveTimer);
  app.inert = false;
  fit();
  if (hoverDevice.matches) input.focus({ preventScroll: true }); else sendBtn.focus({ preventScroll: true });
}

$('form').onsubmit = e => {
  e.preventDefault();
  if (!input.value.trim() && liveScreen) { openLive(); return; }
  submit();
};
input.onkeydown = e => { if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && hoverDevice.matches) { e.preventDefault(); submit(); } };
function fit() {
  input.style.height = 'auto';
  const h = Math.min(input.scrollHeight, 168);
  input.style.height = h + 'px';
  input.style.overflowY = input.scrollHeight > 168 ? 'auto' : 'hidden';
  const has = !!input.value.trim();
  const mode = !has && liveScreen && state.online ? 'live' : 'send';
  if (sendBtn.dataset.mode !== mode) { sendBtn.dataset.mode = mode; sendBtn.setAttribute('aria-label', mode === 'live' ? 'Rozmowa na żywo' : 'Wyślij'); }
  sendBtn.disabled = mode === 'send' && !has;
  sendBtn.classList.toggle('ready', has);
}
input.oninput = fit;

new ResizeObserver(() => {
  const h = dock.offsetHeight;
  log.style.paddingBottom = h + 16 + 'px';
  if (thread.stick) thread.toEnd(false);
}).observe(dock);

jump.onclick = () => thread.toEnd(true);

const vv = window.visualViewport;
if (vv) {
  const sync = () => { app.style.height = vv.height + 'px'; app.style.top = vv.offsetTop + 'px'; app.style.bottom = 'auto'; app.classList.toggle('kb', innerHeight - vv.height > 120); if (thread.stick) thread.toEnd(false); };
  vv.addEventListener('resize', sync); vv.addEventListener('scroll', sync);
}

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    if (liveScreen?.isOpen) { liveScreen.hide(); return; }
    if (sheet.isOpen) { sheet.hide(); return; }
  }
  if ((e.metaKey || e.ctrlKey) && e.key === ',' && !liveScreen?.isOpen) { e.preventDefault(); sheet.toggle(); return; }
  const t = e.target;
  if (hoverDevice.matches && !sheet.isOpen && !liveScreen?.isOpen && e.key.length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey && !/^(INPUT|TEXTAREA|BUTTON|SELECT|A)$/.test(t.tagName) && !$('login').classList.contains('on')) input.focus({ preventScroll: true });
});

async function setupLive(demo) {
  const direct = transport.mode === 'relay' && !demo ? transport.liveBridge : null;
  if (transport.mode !== 'local' && !direct) return;
  if (!demo && !(window.isSecureContext && navigator.mediaDevices?.getUserMedia && 'WebSocket' in window)) return;
  let factory = null;
  try { factory = (await import(demo ? './transport-demo.js' : './live-audio.js')).createLive; } catch { return; }
  if (typeof factory !== 'function') return;
  const make = direct ? cbs => factory({ ...cbs, direct }) : factory;
  liveScreen = createLiveScreen({
    root: $('live'), factory: make,
    forward: e => onEvent({ ...e, live: true }),
    approve: answer,
    getPending: () => state.pending,
    setPending: map => mergeState({ pending: map }),
    onFinal: (role, text) => { if (direct) return; if (role === 'user') { lastUserText = text; thread.addUser(text, null, false); } else thread.addAssistant(text); },
    onClose: closedLive,
  });
  fit();
}

async function boot() {
  $('jump').innerHTML = icon('down', 20);
  $('sheetClose').innerHTML = icon('close', 20);
  fit();
  const qs = new URLSearchParams(location.search);
  const demo = qs.get('demo');
  const relay = !demo && (/(\.web\.app|\.firebaseapp\.com)$/.test(location.hostname) || qs.get('relay') === '1');
  const on = { event: onEvent, state: mergeState, queued: (cid, text) => { if (cid) thread.addUser(text, cid, true); } };
  if (demo === 'login') { $('login').classList.add('on'); app.inert = true; return; }
  if (demo) {
    const { createDemo } = await import('./transport-demo.js');
    transport = createDemo(on, { scene: demo === '1' ? (qs.get('scene') || 'chat') : demo, mode: qs.get('mode') === 'relay' ? 'relay' : 'local' });
  } else if (relay) {
    const { requireLogin } = await import('./auth.js');
    await requireLogin(app);
    const { createRelay } = await import('./transport-relay.js');
    transport = await createRelay(on);
  } else {
    const { createHttp } = await import('./transport-http.js');
    transport = createHttp(on);
  }
  await transport.start();
  settle();
  setTimeout(() => { if (settling) { settling = false; thread.setAnimate(!reduce.matches); if (!thread.hasContent()) thread.showEmpty(SUGGESTIONS, submit); } }, 3500);
  if (hoverDevice.matches) input.focus({ preventScroll: true });
  await setupLive(!!demo);
  if (demo && (qs.get('scene') === 'live' || qs.get('live') === '1')) openLive();
}

boot().catch(err => { thread.addError('Nie udało się uruchomić: ' + (err.message || err)); });
