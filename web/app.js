// Gzowo Concierge - web app shell: state, transport wiring, threads sidebar, composer with goo approvals, Today panel, settings pages, live voice entry, login gate, native shell bridge.
import { icon, paintIcons } from './ui/icons.js';
import { createThread } from './ui/thread.js';
import { createSheet } from './ui/sheet.js';
import { createSettings } from './ui/settings.js';
import { createLiveScreen } from './ui/live.js';
import { createThreads } from './ui/threads.js';
import { createToday } from './ui/today.js';
import { buildAsk } from './ui/ask.js';
import { initFx, initSheen, createGoo, gooOn } from './ui/glass.js';
import { probe, poke } from './ui/ticker.js';
import { createFace, followPointer } from './face.js';
import { report, isShell, post as shellPost } from './shell.js';
import { getAvatar, setAvatar, setRemote, paintOrbs, updateIcons } from './ui/avatar.js';

const $ = id => document.getElementById(id);
const app = $('app'), log = $('log'), input = $('input'), sendBtn = $('send'), pendingBox = $('pending'), banner = $('banner'), jump = $('jump'), dock = $('dock'), sheetEl = $('sheet'), sideEl = $('side'), todayEl = $('today'), stage = $('stage');
const reduce = matchMedia('(prefers-reduced-motion: reduce)');
const hoverDevice = matchMedia('(hover: hover) and (pointer: fine)');
const wideMq = matchMedia('(min-width: 980px)');
const root = document.documentElement;

const SUGGESTIONS = [['calendar', 'Co mam w tym tygodniu?'], ['calendarPlus', 'Dodaj sprawdzian z matmy w piątek o 8:00'], ['globe', 'Co nowego w Warszawie?']];

const state = { online: true, link: true, busy: false, policies: {}, facts: {}, pending: {}, overrides: {}, threads: {}, labels: {}, today: null, connectors: {} };
let transport = null, lastUserText = '', settling = true, settleTimer = 0, liveScreen = null, liveTimer = 0, booted = false, renaming = false, todayTimer = 0, lastToday = null, toastTimer = 0;
const queue = [];
const whenReady = fn => { if (booted) return fn(); queue.push(fn); };
const cap = t => t.charAt(0).toUpperCase() + t.slice(1);
const endLive = () => { if (liveScreen && liveScreen.isOpen) liveScreen.hide(); };
const tid = () => (transport && transport.threadId) || 'main';

paintIcons();
paintOrbs();
updateIcons();
initFx();
initSheen();
probe();

const thread = createThread({ log, root: $('thread'), onStick: s => jump.classList.toggle('on', !s && thread.hasContent()) });
const threadsUI = createThreads({ list: $('threadList'), searchWrap: $('sideSearch'), onOpen: id => { switchThread(id); }, onDelete: deleteThreadUI });
const todayUI = createToday({ body: $('todayBody'), onConnectors: () => openView('connectors') });
const dockGoo = createGoo($('dockInner'), { pad: 28 });

const settings = createSettings({
  body: $('sheetBody'), head: { title: $('sheetTitle'), back: $('sheetBack') }, toast: $('toast'), state, getTransport: () => transport,
  onCleared: () => { thread.clear(); lastUserText = ''; sheet.hide(); thread.showEmpty(SUGGESTIONS, submit); },
});

function syncInert() {
  const modal = (sheet.isOpen && sheet.modal) || (todaySheet.isOpen && todaySheet.modal) || (sideSheet.isOpen && sideSheet.modal);
  const liveOpen = !!liveScreen?.isOpen;
  app.inert = !!(modal || liveOpen);
  sideEl.inert = !!(liveOpen || (sheet.isOpen && sheet.modal) || (todaySheet.isOpen && todaySheet.modal));
}

let geo = { W: 0, sb: 0, colLeft: 0, colRight: 0 };
function measureGeo() {
  const W = innerWidth, sb = parseFloat(getComputedStyle(root).getPropertyValue('--sb')) || 0;
  const region = W - sb, col = Math.min(720, region - 48), cx = sb + region / 2;
  geo = { W, sb, colLeft: cx - col / 2, colRight: cx + col / 2 };
}

function shiftFor(panel) {
  const need = Math.max(0, geo.colRight - (geo.W - 12 - panel.offsetWidth - 16));
  const limit = document.body.classList.contains('tight') ? geo.colLeft - 16 : geo.colLeft - (geo.sb + 12);
  return Math.min(need, Math.max(0, limit));
}

function planTight(panel) {
  measureGeo();
  if (!wideMq.matches || !geo.sb || getComputedStyle(sideEl).display === 'none') { document.body.classList.remove('tight'); return; }
  const need = Math.max(0, geo.colRight - (geo.W - 12 - (panel.offsetWidth || 360) - 16));
  document.body.classList.toggle('tight', need > geo.colLeft - (geo.sb + 12));
}

const rightEdge = () => (wideMq.matches ? 'right' : 'bottom');
const shifts = [$('thread'), $('dockInner')];

const sheet = createSheet({
  el: sheetEl, body: $('sheetBody'), scrim: $('scrim'), shifts, edge: rightEdge, shiftPx: () => shiftFor(sheetEl),
  onOpen() {
    endLive();
    if (todaySheet.isOpen) todaySheet.hide();
    if (sideSheet.isOpen) sideSheet.hide();
    planTight(sheetEl);
    settings.build();
    $('sideGear').setAttribute('aria-expanded', 'true');
    document.body.classList.add('rpanel');
    syncInert();
    if (sheet.modal) requestAnimationFrame(() => sheetEl.focus({ preventScroll: true }));
  },
  onClose() {
    settings.commitUndo();
    $('sideGear').setAttribute('aria-expanded', 'false');
    if (!todaySheet.isOpen) { document.body.classList.remove('tight'); document.body.classList.remove('rpanel'); }
    syncInert();
    if (sheet.modal || sheetEl.contains(document.activeElement)) (wideMq.matches ? input : $('menu')).focus({ preventScroll: true });
  },
});

const todaySheet = createSheet({
  el: todayEl, body: $('todayBody'), scrim: $('scrimToday'), shifts, edge: rightEdge, shiftPx: () => shiftFor(todayEl),
  onOpen() {
    endLive();
    if (sheet.isOpen) sheet.hide();
    if (sideSheet.isOpen) sideSheet.hide();
    planTight(todayEl);
    $('todayBtn').setAttribute('aria-expanded', 'true');
    $('todayBtn').classList.add('on');
    document.body.classList.add('rpanel');
    $('todayDate').textContent = cap(new Date().toLocaleDateString('pl-PL', { weekday: 'long', day: 'numeric', month: 'long' }));
    syncInert();
    loadToday();
    clearInterval(todayTimer);
    todayTimer = setInterval(() => { if (!document.hidden) { if (Math.floor(Date.now() / 60000) % 10 === 0) loadToday(); else if (lastToday !== null || todayUI.loaded) todayUI.render(lastToday); } }, 60000);
    try { localStorage.setItem('ctoday', '1'); } catch {}
    if (todaySheet.modal) requestAnimationFrame(() => todayEl.focus({ preventScroll: true }));
  },
  onClose(m) {
    $('todayBtn').setAttribute('aria-expanded', 'false');
    $('todayBtn').classList.remove('on');
    if (!sheet.isOpen) document.body.classList.remove('rpanel');
    clearInterval(todayTimer);
    if (!sheet.isOpen) document.body.classList.remove('tight');
    syncInert();
    if (m !== null) { try { localStorage.setItem('ctoday', '0'); } catch {} }
    if (todaySheet.modal) $('todayBtn').focus({ preventScroll: true });
  },
});

const sideSheet = createSheet({
  el: sideEl, body: $('threadList'), scrim: $('scrimSide'), edge: () => (wideMq.matches ? null : 'left'),
  onOpen() { endLive(); if (sheet.isOpen) sheet.hide(); if (todaySheet.isOpen) todaySheet.hide(); $('menu').setAttribute('aria-expanded', 'true'); syncInert(); requestAnimationFrame(() => sideEl.querySelector('.s-act')?.focus({ preventScroll: true })); },
  onClose() { $('menu').setAttribute('aria-expanded', 'false'); syncInert(); },
});

$('sideGear').onclick = () => { if (!wideMq.matches) sideSheet.hide(); sheet.toggle(); };
$('sheetClose').onclick = () => sheet.hide();
$('todayClose').onclick = () => todaySheet.hide();
$('sideClose').onclick = () => sideSheet.hide();
$('menu').onclick = () => sideSheet.show();
$('todayBtn').onclick = () => (todaySheet.isOpen ? todaySheet.hide() : todaySheet.show());

function openView(name) {
  endLive();
  if (name === 'today') { todaySheet.show(); return; }
  sideSheet.hide();
  const was = sheet.isOpen;
  if (!was) sheet.show();
  if (name && name !== 'settings') settings.go(name, !was);
}

$('actNew').onclick = () => { newThread(); };
$('actConn').onclick = () => openView('connectors');
$('actSkills').onclick = () => openView('skills');
$('actMem').onclick = () => openView('memory');

async function loadToday() {
  if (!transport || !transport.getToday) { todayUI.render(null); return; }
  try { lastToday = await transport.getToday(); todayUI.render(lastToday); } catch { todayUI.error(); }
}

function showToast(message, action, onAction) {
  const t = $('toast');
  clearTimeout(toastTimer);
  t.innerHTML = '<span></span>' + (action ? '<button type="button" class="pill">' + action + '</button>' : '');
  t.querySelector('span').textContent = message;
  if (action) t.querySelector('button').onclick = () => { clearTimeout(toastTimer); t.classList.remove('on'); onAction(); };
  t.classList.add('on');
  toastTimer = setTimeout(() => t.classList.remove('on'), 5000);
}

function updateTitle() {
  if (renaming) return;
  const t = threadsUI.title(tid());
  const v = t || (tid() === 'main' ? 'Rozmowa' : 'Nowa rozmowa');
  if ($('tbTitle').textContent !== v) $('tbTitle').textContent = v;
  document.title = v + ' · Concierge';
}

function startRename() {
  if (renaming || !transport) return;
  renaming = true;
  const h = $('tbTitle'), i = $('tbRename');
  i.value = h.textContent;
  h.hidden = true; i.hidden = false;
  i.focus(); i.select();
}

function endRename(commit) {
  if (!renaming) return;
  renaming = false;
  const h = $('tbTitle'), i = $('tbRename');
  const v = i.value.trim();
  i.hidden = true; h.hidden = false;
  if (commit && v && v !== h.textContent) {
    h.textContent = v;
    if (state.threads[tid()]) state.threads[tid()] = { ...state.threads[tid()], title: v };
    threadsUI.set(state.threads);
    transport.renameThread?.(tid(), v);
  }
  updateTitle();
}

$('tbTitle').ondblclick = startRename;
$('tbTitle').onkeydown = e => { if (e.key === 'Enter' || e.key === 'F2') { e.preventDefault(); startRename(); } };
$('tbRename').onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); endRename(true); $('tbTitle').focus(); } else if (e.key === 'Escape') { e.stopPropagation(); endRename(false); $('tbTitle').focus(); } };
$('tbRename').onblur = () => endRename(true);

async function switchThread(id, force) {
  if (!transport) return;
  endLive();
  if (id === tid() && !force) { if (sideSheet.isOpen) sideSheet.hide(); return; }
  endRename(false);
  thread.clear();
  lastUserText = '';
  settling = true; thread.setAnimate(false);
  await transport.openThread(id);
  threadsUI.setActive(id);
  updateTitle();
  reportShell();
  settle();
  if (sideSheet.isOpen) sideSheet.hide();
}

async function newThread() {
  if (!transport || !transport.newThread) return;
  endLive();
  const id = await transport.newThread();
  await switchThread(id, true);
  input.focus({ preventScroll: true });
}

async function deleteThreadUI(id, title) {
  if (!transport || id === 'main') return;
  const wasActive = id === tid();
  const next = threadsUI.firstOther(id);
  await transport.deleteThread(id);
  if (wasActive) await switchThread(next, true);
  showToast('Usunięto rozmowę', 'Cofnij', async () => { await transport.restoreThread(id); await switchThread(id, true); });
}

function settle() {
  clearTimeout(settleTimer);
  settleTimer = setTimeout(() => {
    settling = false;
    thread.setAnimate(!reduce.matches);
    if (!thread.hasContent()) thread.showEmpty(SUGGESTIONS, submit);
  }, 450);
}

function onEvent(e) {
  poke();
  if (e.thread && e.thread !== tid()) return;
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
  reportShell();
}

const askNodes = new Map();
function renderPending() {
  const cf = document.querySelector('.cfield');
  for (const [id, summary] of Object.entries(state.pending)) {
    if (askNodes.has(id)) continue;
    const c = buildAsk(summary, yes => answer(id, yes));
    askNodes.set(id, c);
    pendingBox.append(c);
    const live = !settling && !reduce.matches;
    if (live) c.classList.add('enter');
    dockGoo.track(c, { enter: live && gooOn(), from: cf });
  }
  for (const [id, c] of askNodes) {
    if (id in state.pending) continue;
    askNodes.delete(id);
    const quick = reduce.matches || settling;
    dockGoo.untrack(c, { leave: !quick, to: cf });
    if (quick) { c.remove(); continue; }
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
  if (msg) banner.querySelector('.b-t').textContent = msg;
  banner.classList.toggle('on', !!msg);
  app.classList.toggle('has-banner', !!msg);
  const st = !state.online || !state.link ? 'offline' : state.busy ? 'busy' : 'idle';
  app.dataset.state = st;
  $('tbSt').textContent = st === 'busy' ? 'Pracuję' : st === 'offline' ? 'Offline' : '';
  $('tbSt').dataset.s = st;
  fit();
}

function reportShell() {
  report({ online: !!(state.online && state.link), busy: !!state.busy, pending: Object.keys(state.pending).length, live: liveScreen ? liveScreen.shellState : 'idle', thread: tid() });
}

function mergeState(p) {
  if (p.pending || p.busy !== undefined && p.busy !== state.busy) poke();
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
  if (p.threads) { threadsUI.set(state.threads); updateTitle(); }
  if (p.avatar) setAvatar(p.avatar, { persist: false });
  if (p.today !== undefined && p.today !== null && todaySheet.isOpen) { lastToday = p.today; todayUI.render(p.today); }
  if (sheet.isOpen) settings.sync();
  if (p.connectors && sheet.isOpen) settings.loadConnectors();
  reportShell();
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
  if (todaySheet.isOpen) todaySheet.hide();
  if (sideSheet.isOpen) sideSheet.hide();
  root.dataset.live = '1';
  shellPost({ type: 'live-view', open: true });
  liveScreen.show();
  liveScreen.syncPending(state.pending);
  syncInert();
  clearInterval(liveTimer);
  if (transport.refresh) liveTimer = setInterval(() => transport.refresh(), 1500);
}

function closedLive() {
  clearInterval(liveTimer);
  shellPost({ type: 'live-view', open: false });
  delete root.dataset.live;
  syncInert();
  fit();
  reportShell();
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

const plus = $('plus'), menu = $('plusMenu');
function setMenu(on) {
  menu.hidden = !on;
  plus.setAttribute('aria-expanded', String(on));
  if (on) { requestAnimationFrame(() => menu.querySelector('button')?.focus({ preventScroll: true })); }
}
plus.onclick = e => { e.stopPropagation(); setMenu(menu.hidden); };
menu.onclick = e => {
  const b = e.target.closest('button[data-act]');
  if (!b) return;
  setMenu(false);
  const a = b.dataset.act;
  if (a === 'new') newThread(); else openView(a);
};
menu.onkeydown = e => {
  if (e.key === 'Escape') { e.stopPropagation(); setMenu(false); plus.focus(); return; }
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault();
    const items = [...menu.querySelectorAll('button')], i = items.indexOf(document.activeElement);
    items[(i + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length].focus();
  }
};
document.addEventListener('pointerdown', e => { if (!menu.hidden && !menu.contains(e.target) && e.target !== plus && !plus.contains(e.target)) setMenu(false); });

new ResizeObserver(() => {
  const h = dock.offsetHeight;
  log.style.paddingBottom = h + 48 + 'px';
  stage.style.setProperty('--dock-h', h + 'px');
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
    if (!menu.hidden) { setMenu(false); return; }
    if (sheet.isOpen) { if (settings.depth && e.target.closest && !e.target.closest('input, textarea')) { settings.back(); return; } sheet.hide(); return; }
    if (todaySheet.isOpen) { todaySheet.hide(); return; }
    if (sideSheet.isOpen) { sideSheet.hide(); return; }
  }
  if ((e.metaKey || e.ctrlKey) && e.key === ',') { e.preventDefault(); sheet.toggle(); return; }
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
  const make = cbs => factory({ ...cbs, thread: tid(), ...(direct ? { direct } : {}) });
  liveScreen = createLiveScreen({
    root: $('live'), factory: make,
    forward: e => onEvent({ ...e, live: true, thread: undefined }),
    approve: answer,
    getPending: () => state.pending,
    setPending: map => mergeState({ pending: map }),
    onFinal: (role, text) => { if (direct) return; if (role === 'user') { lastUserText = text; thread.addUser(text, null, false); } else thread.addAssistant(text); },
    onClose: closedLive,
    onShell: () => reportShell(),
  });
  fit();
}

window.conciergeShell = {
  openLive: () => whenReady(() => openLive()),
  closeLive: () => whenReady(() => liveScreen?.hide()),
  focusInput: () => whenReady(() => input.focus({ preventScroll: true })),
  openSettings: () => whenReady(() => openView('settings')),
  openThread: id => whenReady(() => switchThread(String(id))),
  newThread: () => whenReady(() => newThread()),
  openView: name => whenReady(() => openView(String(name))),
};

function loginFace() {
  const login = $('login');
  const f = createFace($('loginFace'));
  const follow = followPointer(f);
  const sync = () => { if (login.classList.contains('on')) { f.start(); } else { f.stop(); } };
  new MutationObserver(sync).observe(login, { attributes: true, attributeFilter: ['class'] });
  sync();
  return follow;
}

async function boot() {
  $('jump').innerHTML = icon('down', 20);
  $('sheetClose').innerHTML = icon('close', 20);
  $('todayClose').innerHTML = icon('close', 20);
  fit();
  loginFace();
  const qs = new URLSearchParams(location.search);
  const demo = qs.get('demo');
  const onHost = /^(localhost|127\.0\.0\.1|\[::1\]|192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|[\w-]+\.local)$/.test(location.hostname);
  const relay = !demo && (!onHost || qs.get('relay') === '1');
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
  setRemote(a => { if (transport.setAvatar) transport.setAvatar(a); });
  if (transport.getAvatar) transport.getAvatar().then(a => { if (a) setAvatar(a, { persist: false }); }).catch(() => {});
  const acct = transport.account && transport.account.email;
  $('sideAcct').textContent = acct || (transport.mode === 'local' ? 'Na tym Macu' : '');
  await transport.start();
  threadsUI.set(state.threads);
  threadsUI.setActive(tid());
  updateTitle();
  settle();
  setTimeout(() => { if (settling) { settling = false; thread.setAnimate(!reduce.matches); if (!thread.hasContent()) thread.showEmpty(SUGGESTIONS, submit); } }, 3500);
  if (hoverDevice.matches && !isShell()) input.focus({ preventScroll: true });
  await setupLive(!!demo);
  booted = true;
  reportShell();
  while (queue.length) { try { await queue.shift()(); } catch {} }
  if (demo && (qs.get('scene') === 'live' || qs.get('live') === '1')) openLive();
  const open = qs.get('open');
  if (open) openView(open);
  else if (wideMq.matches) { try { if (localStorage.getItem('ctoday') === '1') todaySheet.show(); } catch {} }
}

boot().catch(err => { thread.addError('Nie udało się uruchomić: ' + (err.message || err)); });
