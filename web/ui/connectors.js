// Gzowo Concierge - connectors: category gallery of glass cards, detail page with connect, setup and token flows, polling, and per-connector approval switches.
import { icon, connIcon } from './icons.js';

const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const CHIP = { connected: 'Połączono', available: 'Połącz', planned: 'Wkrótce', error: 'Błąd' };
const ORDER = { error: 0, connected: 1, available: 2, planned: 3 };
const GOOGLE = new Set(['gmail', 'docs', 'drive']);

export function createConnectors({ getTransport, state, policyRow, onChange }) {
  const store = { list: [], labels: {}, loaded: false, failed: false };
  let pollTimer = 0, pollEnd = 0;

  const readOnly = () => typeof getTransport().connectConnector !== 'function';
  const find = id => store.list.find(c => c.id === id);

  async function load() {
    try {
      const r = await getTransport().listConnectors();
      store.list = r.connectors || []; store.labels = r.labels || {}; store.loaded = true; store.failed = false;
    } catch { store.failed = true; }
    onChange?.();
  }

  function stopPoll() { clearInterval(pollTimer); pollTimer = 0; }
  function startPoll(id, done) {
    stopPoll();
    pollEnd = Date.now() + 120000;
    pollTimer = setInterval(async () => {
      await load();
      const c = find(id);
      if (c && c.state === 'connected') { stopPoll(); done(true); }
      else if (Date.now() > pollEnd) { stopPoll(); done(false); }
    }, 1500);
  }

  function summary() {
    const conn = store.list.filter(c => c.state === 'connected');
    return { n: conn.length, total: store.list.length, icons: conn.slice(0, 4).map(c => connIcon(c.icon, c.name, 18)), loaded: store.loaded };
  }

  function owned() {
    const s = new Set();
    store.list.forEach(c => { if (c.kind !== 'builtin') (c.tools || []).forEach(t => s.add(t.action)); });
    return s;
  }

  function chip(c) {
    const s = el('span', 'chip s-' + c.state, '<span></span>');
    s.lastChild.textContent = CHIP[c.state] || c.state;
    return s;
  }

  function gallery(container, go) {
    container.textContent = '';
    const page = el('div', 'cpage');
    let filter = '';
    const bodyEl = el('div', 'cbody');
    if (readOnly()) page.append(el('div', 'cnote glass', icon('link', 18) + '<p>Połącz na Macu. Tutaj widzisz tylko statusy konektorów.</p>'));
    let search = null;
    function paint() {
      bodyEl.textContent = '';
      if (!store.loaded) { bodyEl.append(el('p', 'foot flush', store.failed ? 'Nie udało się wczytać konektorów.' : 'Wczytuję konektory…')); return; }
      const f = filter.trim().toLowerCase();
      const items = store.list.filter(c => !f || (c.name + ' ' + c.category + ' ' + (c.description || '')).toLowerCase().includes(f));
      if (!items.length) { bodyEl.append(el('p', 'foot flush', 'Nic nie pasuje do "' + filter.trim() + '".')); return; }
      const cats = [];
      items.forEach(c => { if (!cats.includes(c.category)) cats.push(c.category); });
      cats.forEach(cat => {
        const g = el('section', 'cgroup');
        const h = el('h3'); h.textContent = cat;
        const grid = el('div', 'cgrid');
        items.filter(c => c.category === cat).sort((a, b) => (ORDER[a.state] ?? 9) - (ORDER[b.state] ?? 9)).forEach(c => {
          const b = el('button', 'ccard glass', '<span class="ctile"></span><span class="cname"></span><span class="cdesc"></span>');
          b.type = 'button'; b.dataset.state = c.state; b.dataset.id = c.id;
          b.querySelector('.ctile').innerHTML = connIcon(c.icon, c.name, 22);
          b.querySelector('.cname').textContent = c.name;
          b.querySelector('.cdesc').textContent = c.description || '';
          b.querySelector('.ctile').after(chip(c));
          b.setAttribute('aria-label', c.name + ', ' + (CHIP[c.state] || c.state));
          b.onclick = () => go(c.name, box => detail(box, c.id, go));
          grid.append(b);
        });
        g.append(h, grid);
        bodyEl.append(g);
      });
    }
    if (store.list.length > 8 || !store.loaded) {
      search = el('label', 'csearch', icon('search', 18) + '<input type="search" placeholder="Szukaj konektorów" aria-label="Szukaj konektorów" autocomplete="off" spellcheck="false">');
      search.querySelector('input').oninput = e => { filter = e.target.value; paint(); };
      search.hidden = store.loaded && store.list.length <= 8;
      page.append(search);
    }
    page.append(bodyEl);
    container.append(page);
    paint();
    return { update() { if (search) search.hidden = store.loaded && store.list.length <= 8; paint(); }, destroy() {} };
  }

  function helpBlock(text) {
    const wrap = el('div', 'chelp');
    const m = /https?:\/\/[^\s)]+/.exec(text || '');
    const body = (text || '').replace(m ? m[0] : '', '').trim();
    const p = el('p'); p.textContent = body;
    wrap.append(p);
    if (m) {
      const b = el('button', 'pill', icon('external', 16) + '<span>Otwórz stronę</span>');
      b.type = 'button'; b.onclick = () => window.open(m[0], '_blank', 'noopener');
      wrap.append(b);
    }
    return wrap;
  }

  function detail(container, id, go) {
    container.textContent = '';
    const page = el('div', 'cpage cdetail');
    container.append(page);
    let flow = { k: 'idle' };
    let confirming = false;

    function field(key, label, secret) {
      const r = el('div', 'field-row');
      const l = el('label'); l.textContent = label;
      const i = el('input', 'in');
      i.type = secret ? 'password' : 'text';
      i.autocomplete = 'off'; i.spellcheck = false; i.autocapitalize = 'off'; i.autocorrect = 'off'; i.value = '';
      i.id = 'cf-' + id + '-' + key; l.htmlFor = i.id; i.dataset.key = key;
      r.append(l, i);
      return { r, i };
    }

    async function connect(c) {
      flow = { k: 'busy' }; paint();
      try {
        const r = await getTransport().connectConnector(c.id);
        if (r.authUrl) { window.open(r.authUrl, '_blank', 'noopener'); flow = { k: 'wait' }; startPoll(c.id, ok => { flow = ok ? { k: 'idle' } : { k: 'error', msg: 'Nie doczekałem się logowania. Spróbuj ponownie.' }; paint(); }); }
        else if (r.needsSetup) flow = { k: 'setup', r };
        else if (r.needsToken) flow = { k: 'token', r };
        else { await load(); flow = { k: 'idle' }; }
      } catch { flow = { k: 'error', msg: 'Nie udało się połączyć. Spróbuj ponownie.' }; }
      paint();
    }

    function actions(c) {
      const a = el('div', 'cact');
      if (c.state === 'planned') return null;
      if (readOnly()) { a.append(el('div', 'cnote glass', icon('link', 18) + '<p>Połącz na Macu.</p>')); return a; }
      if (c.kind === 'builtin') { a.append(el('p', 'foot flush', 'Wbudowany konektor, zawsze dostępny.')); return a; }
      if (flow.k === 'busy') { const b = el('button', 'btn ink wide', '<i class="spin on-ink"></i><span>Łączę…</span>'); b.disabled = true; a.append(b); return a; }
      if (flow.k === 'wait') {
        a.append(el('div', 'cwait glass', '<i class="spin"></i><p>Czekam na zalogowanie w przeglądarce.</p>'));
        const cancel = el('button', 'btn tonal wide', 'Anuluj'); cancel.type = 'button';
        cancel.onclick = () => { stopPoll(); flow = { k: 'idle' }; paint(); };
        a.append(cancel); return a;
      }
      if (flow.k === 'setup' || flow.k === 'token') {
        const form = el('form', 'cform glass'); form.autocomplete = 'off';
        form.append(helpBlock(flow.r.help));
        const fields = flow.k === 'token' ? [{ key: 'token', label: 'Token', secret: true }] : (flow.r.fields || []);
        const made = fields.map(f => field(f.key, f.label, f.secret !== false && (f.secret || flow.k === 'token')));
        made.forEach(m => form.append(m.r));
        const err = el('p', 'note-err'); err.setAttribute('role', 'alert'); err.textContent = flow.msg || '';
        const row = el('div', 'row-btns');
        const cancel = el('button', 'btn tonal small', 'Anuluj'); cancel.type = 'button';
        const save = el('button', 'btn ink small', flow.k === 'token' ? 'Zapisz token' : 'Zapisz i połącz'); save.type = 'submit';
        row.append(cancel, save);
        form.append(err, row);
        cancel.onclick = () => { made.forEach(m => { m.i.value = ''; }); flow = { k: 'idle' }; paint(); };
        form.onsubmit = async e => {
          e.preventDefault();
          const values = {};
          made.forEach(m => { values[m.i.dataset.key] = m.i.value.trim(); });
          if (made.some(m => !m.i.value.trim())) { err.textContent = 'Uzupełnij wszystkie pola.'; return; }
          save.disabled = true; err.textContent = '';
          try {
            if (flow.k === 'token') { await getTransport().setConnectorToken(c.id, values.token); made.forEach(m => { m.i.value = ''; }); await load(); flow = { k: 'idle' }; paint(); }
            else { await getTransport().setupConnector(c.id, values); made.forEach(m => { m.i.value = ''; }); await connect(c); }
          } catch { made.forEach(m => { m.i.value = ''; }); err.textContent = 'Nie udało się zapisać. Sprawdź dane i spróbuj ponownie.'; save.disabled = false; }
        };
        a.append(form); return a;
      }
      if (c.state === 'connected') {
        if (!confirming) {
          const b = el('button', 'btn tonal wide', 'Rozłącz'); b.type = 'button';
          b.onclick = () => { confirming = true; paint(); };
          a.append(b);
        } else {
          a.append(el('p', 'foot flush', GOOGLE.has(c.id) ? 'Rozłączę Gmail, Dokumenty i Dysk naraz.' : 'Rozłączyć ' + c.name + '?'));
          const row = el('div', 'pair-btns');
          const no = el('button', 'btn tonal', 'Anuluj'); no.type = 'button';
          const yes = el('button', 'btn ink', 'Rozłącz'); yes.type = 'button';
          no.onclick = () => { confirming = false; paint(); };
          yes.onclick = async () => { yes.disabled = true; try { await getTransport().disconnectConnector(c.id); confirming = false; await load(); } catch { flow = { k: 'error', msg: 'Nie udało się rozłączyć.' }; confirming = false; } paint(); };
          row.append(no, yes); a.append(row);
        }
        return a;
      }
      if (flow.k === 'error') { const p = el('p', 'note-err'); p.setAttribute('role', 'alert'); p.textContent = flow.msg; a.append(p); }
      if (c.state === 'error' && flow.k !== 'error') { const p = el('p', 'note-err'); p.setAttribute('role', 'alert'); p.textContent = c.note || 'Połączenie przestało działać.'; a.append(p); }
      const b = el('button', 'btn ink wide', c.state === 'error' ? 'Połącz ponownie' : 'Połącz'); b.type = 'button';
      b.onclick = () => connect(c);
      a.append(b);
      return a;
    }

    function paint() {
      const c = find(id);
      page.textContent = '';
      if (!c) { page.append(el('p', 'foot flush', 'Nie znaleziono konektora.')); return; }
      const head = el('div', 'chead', '<span class="ctile big"></span><div class="chead-t"><h3></h3><p></p></div>');
      head.querySelector('.ctile').innerHTML = connIcon(c.icon, c.name, 30);
      head.querySelector('h3').textContent = c.name;
      head.querySelector('p').textContent = c.category;
      head.append(chip(c));
      page.append(head);
      if (c.description) { const d = el('p', 'cdesc-full'); d.textContent = c.description; page.append(d); }
      if (c.state === 'planned') page.append(el('div', 'cnote glass', icon('spark', 18) + '<p></p>'));
      if (c.state === 'planned') page.querySelector('.cnote p').textContent = c.note || 'Ten konektor jest w planach.';
      if (c.state === 'connected' && c.account) { const r = el('div', 'cacct', icon('user', 16, true) + '<span></span>'); r.lastChild.textContent = c.account; page.append(r); }
      if (GOOGLE.has(c.id)) page.append(el('p', 'foot', 'To samo konto Google dla Gmail, Docs i Drive.'));
      if (c.capabilities && c.capabilities.length) {
        const blk = el('section', 'cblock', '<h4>Co potrafię</h4>');
        const ul = el('ul', 'caps');
        c.capabilities.forEach(x => { const li = el('li', null, icon('check', 15) + '<span></span>'); li.lastChild.textContent = x; ul.append(li); });
        blk.append(ul); page.append(blk);
      }
      const act = actions(c);
      if (act) page.append(act);
      if (c.state !== 'planned' && c.tools && c.tools.length) {
        const blk = el('section', 'cblock', '<h4>Zgody</h4>');
        const list = el('div', 'list');
        c.tools.forEach(t => list.append(policyRow(t.action, t.label, t.policy).row));
        blk.append(list, el('p', 'foot', 'Włączone: zapytam o zgodę. Wyłączone: zrobię sam.'));
        page.append(blk);
      }
    }
    paint();
    return { update() { if (flow.k === 'setup' || flow.k === 'token') return; paint(); }, destroy() { stopPoll(); page.querySelectorAll('input').forEach(i => { i.value = ''; }); } };
  }

  return { load, gallery, detail, summary, owned, stopPoll, get store() { return store; }, find };
}
