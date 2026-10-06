// Gzowo Concierge - web app: chat UI, approvals, settings. Picks a transport: local host (Mac) or Firebase relay (phone).
const $ = id => document.getElementById(id);
const log = $('log'), input = $('input'), sendBtn = $('send'), pendingBox = $('pending'), banner = $('banner'), sheet = $('sheet'), scrim = $('scrim');

const LABELS = {
  'calendar.read': 'Kalendarz: czytanie',
  'calendar.write': 'Kalendarz: dodawanie i zmiany',
  'calendar.delete': 'Kalendarz: usuwanie',
  'web.search': 'Szukanie w sieci',
  'memory.write': 'Zapamiętywanie',
};
const SUGGESTIONS = ['Co mam w tym tygodniu?', 'Dodaj sprawdzian z matmy w piątek o 8:00', 'Co nowego w Warszawie?'];

const ls = { get: k => { try { return localStorage.getItem(k); } catch { return null; } }, set: (k, v) => { try { localStorage.setItem(k, v); } catch {} } };

const state = { online: true, link: true, busy: false, policies: {}, facts: {}, pending: {} };
let transport = null;
let dots = null;
const chips = new Map();
const bubbles = new Map();

function nearBottom() { return log.scrollHeight - log.scrollTop - log.clientHeight < 90; }
function scroll(force) { if (force || stick) log.scrollTop = log.scrollHeight; }
let stick = true;
log.addEventListener('scroll', () => { stick = nearBottom(); }, { passive: true });

function clearEmpty() { const e = $('empty'); if (e) e.remove(); }
function row(cls) {
  clearEmpty();
  const r = document.createElement('div'); r.className = 'row ' + (cls || '');
  log.appendChild(r);
  if (dots?.isConnected) log.appendChild(dots);
  return r;
}

function addUser(text, cid, queued) {
  if (cid && bubbles.has(cid)) { const b = bubbles.get(cid); if (!queued) b.classList.remove('queued'); return; }
  const r = row('user'); const b = document.createElement('div');
  b.className = 'bubble' + (queued ? ' queued' : ''); b.textContent = text; r.appendChild(b);
  if (cid) bubbles.set(cid, b);
  scroll(true);
}
function addAssistant(text) { const r = row(); const d = document.createElement('div'); d.className = 'assistant'; d.textContent = text; r.appendChild(d); scroll(); }
function addError(msg) { const r = row(); const d = document.createElement('div'); d.className = 'error'; d.textContent = msg; r.appendChild(d); scroll(); }
function setChip(key, text, status) {
  let c = chips.get(key);
  if (!c) { const r = row(); c = document.createElement('div'); c.innerHTML = '<i></i><span class="t"></span>'; r.appendChild(c); chips.set(key, c); }
  c.className = 'chip ' + status; c.querySelector('.t').textContent = text; scroll();
}

function onEvent(e) {
  if (e.type === 'user') addUser(e.text, e.cid, false);
  else if (e.type === 'text') addAssistant(e.text);
  else if (e.type === 'tool') setChip((e.rid || '') + e.name + e.summary, e.summary, e.status);
  else if (e.type === 'error') addError(e.message);
}

function renderEmpty() {
  if (log.children.length) return;
  const e = document.createElement('div'); e.id = 'empty';
  e.innerHTML = '<h2>Co mam dla Ciebie zrobić?</h2><div id="suggest"></div>';
  SUGGESTIONS.forEach(s => { const b = document.createElement('button'); b.textContent = s; b.onclick = () => submit(s); e.querySelector('#suggest').appendChild(b); });
  log.appendChild(e);
}

function renderBusy() {
  if (state.busy && !dots) { dots = document.createElement('div'); dots.className = 'dots'; dots.innerHTML = '<b></b><b></b><b></b>'; clearEmpty(); log.appendChild(dots); scroll(); }
  else if (!state.busy && dots) { dots.remove(); dots = null; }
}

function renderPending() {
  pendingBox.textContent = '';
  for (const [id, summary] of Object.entries(state.pending)) {
    const c = document.createElement('div'); c.className = 'card';
    c.innerHTML = '<div class="q"></div><div class="btns"><button data-v="0">Nie</button><button data-v="1" class="go">Tak</button></div>';
    c.querySelector('.q').textContent = summary;
    c.querySelectorAll('button').forEach(b => b.onclick = () => { delete state.pending[id]; renderPending(); transport.approve(id, b.dataset.v === '1'); });
    pendingBox.appendChild(c);
  }
}

function renderBanner() {
  let msg = '';
  if (transport?.mode === 'relay') {
    if (!state.link) msg = 'Brak internetu na telefonie.';
    else if (!state.online) msg = 'Mac jest teraz niedostępny. Wiadomości poczekają do 10 minut.';
  } else if (!state.online) msg = 'Brak połączenia z hostem.';
  banner.textContent = msg; banner.classList.toggle('on', !!msg);
}

function mergeState(p) {
  Object.assign(state, p);
  renderBusy(); renderPending(); renderBanner();
  if (sheet.classList.contains('on')) renderSheet();
}

function submit(text) {
  text = (text ?? input.value).trim();
  if (!text) return;
  input.value = ''; fit();
  const cid = crypto.randomUUID();
  stick = true;
  if (transport.mode === 'relay') addUser(text, cid, true); else addUser(text, null, false);
  transport.send(text, cid);
}
$('form').onsubmit = e => { e.preventDefault(); submit(); };
input.onkeydown = e => { if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && matchMedia('(hover: hover)').matches) { e.preventDefault(); submit(); } };
function fit() { input.style.height = 'auto'; input.style.height = Math.min(input.scrollHeight, 140) + 'px'; input.style.overflowY = input.scrollHeight > 140 ? 'auto' : 'hidden'; sendBtn.disabled = !input.value.trim(); }
input.oninput = fit;

const vv = window.visualViewport;
if (vv) {
  const app = $('app');
  const sync = () => { app.style.height = vv.height + 'px'; app.style.top = vv.offsetTop + 'px'; app.style.bottom = 'auto'; scroll(); };
  vv.addEventListener('resize', sync); vv.addEventListener('scroll', sync);
}

function seg(options, value, onPick) {
  const s = document.createElement('div'); s.className = 'seg';
  options.forEach(([v, label]) => { const b = document.createElement('button'); b.type = 'button'; b.textContent = label; if (v === value) b.className = 'on'; b.onclick = () => onPick(v); s.appendChild(b); });
  return s;
}
function openSheet() { renderSheet(); sheet.classList.add('on'); scrim.classList.add('on'); }
function closeSheet() { sheet.classList.remove('on'); scrim.classList.remove('on'); }
$('gear').onclick = openSheet; scrim.onclick = closeSheet;

async function renderSheet() {
  const keep = sheet.scrollTop;
  sheet.textContent = '';
  const add = el => sheet.appendChild(el);
  const h = t => { const e = document.createElement('h3'); e.textContent = t; add(e); };
  const g = document.createElement('div'); g.className = 'grab'; add(g);

  h('Kiedy pytać o zgodę');
  const actions = Object.keys(state.policies).sort();
  actions.forEach(a => {
    const l = document.createElement('div'); l.className = 'line';
    const t = document.createElement('span'); t.textContent = LABELS[a] || a; l.appendChild(t);
    l.appendChild(seg([['auto', 'Rób sam'], ['ask', 'Pytaj']], state.policies[a], v => { state.policies[a] = v; renderSheet(); transport.setPolicy(a, v); }));
    add(l);
  });

  h('Pamięć');
  const ids = Object.keys(state.facts);
  if (!ids.length) { const m = document.createElement('div'); m.className = 'muted'; m.textContent = 'Jeszcze nic. Powiedz mi coś o sobie, a zapamiętam.'; add(m); }
  ids.forEach(id => {
    const l = document.createElement('div'); l.className = 'line';
    const t = document.createElement('span'); t.textContent = state.facts[id]; l.appendChild(t);
    const b = document.createElement('button'); b.className = 'mini danger'; b.textContent = 'Usuń'; b.onclick = () => { delete state.facts[id]; renderSheet(); transport.forget(Number(id)); };
    l.appendChild(b); add(l);
  });

  if (transport.mode === 'local') {
    h('iPhone');
    const m = document.createElement('div'); m.className = 'muted'; m.textContent = 'Zeskanuj aparatem iPhone\'a, otwórz link w Safari i dodaj do ekranu początkowego.'; add(m);
    const q = document.createElement('div'); q.id = 'qr'; add(q);
    const copy = document.createElement('button'); copy.className = 'mini'; copy.textContent = 'Kopiuj link'; add(copy);
    try {
      const url = await transport.pairingUrl();
      copy.onclick = async () => { try { await navigator.clipboard.writeText(url); copy.textContent = 'Skopiowano'; } catch { copy.textContent = url; } };
      await loadScript('https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js');
      const qr = window.qrcode(0, 'M'); qr.addData(url); qr.make();
      q.innerHTML = qr.createSvgTag({ cellSize: 4, margin: 0, scalable: true });
    } catch { q.textContent = 'Kod QR niedostępny.'; }
  }

  h('Rozmowa');
  const clr = document.createElement('button'); clr.className = 'mini danger'; clr.textContent = 'Wyczyść rozmowę';
  clr.onclick = async () => { await transport.clear(); log.textContent = ''; chips.clear(); bubbles.clear(); renderEmpty(); closeSheet(); };
  add(clr);
  sheet.scrollTop = keep;
}
function loadScript(src) {
  return new Promise((res, rej) => { if (window.qrcode) return res(); const s = document.createElement('script'); s.src = src; s.onload = res; s.onerror = rej; document.head.appendChild(s); });
}

function sidFromHash() {
  const m = location.hash.match(/s=([A-Za-z0-9_-]{40,})/);
  return m ? m[1] : null;
}
function pinManifest(sid) {
  try {
    const base = location.origin + location.pathname.replace(/[^/]*$/, '');
    const man = { name: 'Gzowo Concierge', short_name: 'Concierge', start_url: base + '#s=' + sid, scope: base, display: 'standalone', background_color: '#0b0b0c', theme_color: '#0b0b0c', icons: [{ src: base + 'icon-192.png', sizes: '192x192', type: 'image/png' }, { src: base + 'icon-512.png', sizes: '512x512', type: 'image/png' }] };
    $('manifest').href = URL.createObjectURL(new Blob([JSON.stringify(man)], { type: 'application/manifest+json' }));
  } catch {}
}

function showPair() {
  $('pair').classList.add('on');
  const go = () => {
    const m = $('pairInput').value.match(/s=([A-Za-z0-9_-]{40,})/) || $('pairInput').value.trim().match(/^([A-Za-z0-9_-]{40,})$/);
    if (!m) { $('pairErr').textContent = 'To nie wygląda jak link do połączenia.'; return; }
    ls.set('sid', m[1]); location.hash = 's=' + m[1]; location.reload();
  };
  $('pairGo').onclick = go;
  $('pairInput').onkeydown = e => { if (e.key === 'Enter') go(); };
}

async function boot() {
  fit();
  const qs = new URLSearchParams(location.search);
  const relay = /(\.web\.app|\.firebaseapp\.com)$/.test(location.hostname) || qs.get('relay') === '1';
  const on = {
    event: onEvent,
    state: mergeState,
    queued: (cid, text) => { if (cid) addUser(text, cid, true); },
  };
  if (relay) {
    const sid = sidFromHash() || ls.get('sid');
    if (!sid) { showPair(); return; }
    ls.set('sid', sid);
    if (!location.hash.includes(sid)) history.replaceState(null, '', location.pathname + location.search + '#s=' + sid);
    pinManifest(sid);
    const { createRelay } = await import('./transport-relay.js');
    transport = await createRelay(sid, on);
  } else {
    const { createHttp } = await import('./transport-http.js');
    transport = createHttp(on);
  }
  await transport.start();
  setTimeout(renderEmpty, 600);
  input.focus({ preventScroll: true });
}
boot().catch(err => { addError('Nie udało się uruchomić: ' + (err.message || err)); });
