// Gzowo Concierge - settings pages: approvals, connectors, skills, memory, persona, cards (Mac only), iPhone QR, account, clear chat; pushed pages with spring transitions, undoable deletes.
import { icon } from './icons.js';
import { createConnectors } from './connectors.js';
import { EASE, SPRING, reduceMq } from './glass.js';

const LABELS = {
  'calendar.read': 'Kalendarz: czytanie',
  'calendar.write': 'Kalendarz: dodawanie i zmiany',
  'calendar.delete': 'Kalendarz: usuwanie',
  'web.search': 'Szukanie w sieci',
  'memory.write': 'Zapamiętywanie',
  'skills.write': 'Umiejętności: zapisywanie',
};

function el(tag, cls, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html != null) e.innerHTML = html;
  return e;
}

function loadScript(src) {
  return new Promise((res, rej) => {
    if (window.qrcode) return res();
    const s = document.createElement('script');
    s.src = src; s.onload = res; s.onerror = rej;
    document.head.appendChild(s);
  });
}

const ORDER = Object.keys(LABELS);
const rank = a => { const i = ORDER.indexOf(a); return i < 0 ? 99 : i; };
const localHost = /^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname);

function cardError(msg) {
  if (/number/i.test(msg)) return 'Numer karty jest nieprawidłowy.';
  if (/expiry/i.test(msg)) return 'Data ważności ma wyglądać tak: MM/RR.';
  if (/cvv/i.test(msg)) return 'CVV to 3 lub 4 cyfry.';
  if (/local|mac/i.test(msg)) return 'Kartę dodasz tylko na Macu.';
  return 'Nie udało się zapisać karty.';
}

export function createSettings({ body, head, toast, state, getTransport, onCleared }) {
  const rows = new Map(), facts = new Map();
  const hiddenFacts = new Set();
  const regs = new Map();
  let rootEl = null, polList = null, memList = null, memEmpty = null, undo = null, token = 0, stack = [], heroSub = null, heroIcons = null, memSub = null, skillSub = null;

  const conn = createConnectors({
    getTransport, state,
    policyRow: (action, label, fallback) => policyRow(action, label, fallback),
    onChange: () => { refreshHero(); stack[stack.length - 1]?.view?.update?.(); sync(); },
  });

  const labelFor = a => (state.labels && state.labels[a]) || conn.store.labels[a] || LABELS[a] || a;
  const isAsk = (a, fb) => (state.policies[a] ?? fb) === 'ask';

  function section(title, ic, into = rootEl) {
    const s = el('section', 'grp');
    const h = el('h3', null, ic ? `<span class="h-ic">${icon(ic, 14)}</span><span></span>` : '<span></span>');
    h.lastChild.textContent = title;
    s.append(h);
    into.append(s);
    return s;
  }

  function makeSwitch(label, on, onToggle) {
    const b = el('button', 'switch', '<span class="track"><span class="knob"></span></span>');
    b.type = 'button'; b.setAttribute('role', 'switch'); b.setAttribute('aria-label', label);
    b.setAttribute('aria-checked', String(on));
    b.onclick = () => { const next = b.getAttribute('aria-checked') !== 'true'; b.setAttribute('aria-checked', String(next)); onToggle(next); };
    return b;
  }

  function subtitle(row, ask) { row.querySelector('.i-sub').textContent = ask ? 'Zapytam o zgodę' : 'Zrobię sam'; }

  function policyRow(action, labelOverride, fallback) {
    const label = labelOverride || labelFor(action);
    const row = el('div', 'item');
    const txt = el('div', 'item-t', '<span class="i-main"></span><span class="i-sub"></span>');
    txt.querySelector('.i-main').textContent = label;
    const sw = makeSwitch('Pytaj o zgodę: ' + label, isAsk(action, fallback), next => {
      getTransport().setPolicy(action, next ? 'ask' : 'auto');
      state.policies[action] = next ? 'ask' : 'auto';
      state.overrides[action] = Date.now();
      (regs.get(action) || []).forEach(r => { if (r.sw !== sw) r.sw.setAttribute('aria-checked', String(next)); subtitle(r.row, next); });
    });
    row.append(txt, sw);
    subtitle(row, isAsk(action, fallback));
    const r = { row, sw, override: !!labelOverride, fallback };
    if (!regs.has(action)) regs.set(action, []);
    regs.get(action).push(r);
    return r;
  }

  function delButton(label, onClick) {
    const b = el('button', 'icon-btn small', icon('trash', 18));
    b.type = 'button'; b.setAttribute('aria-label', label);
    b.onclick = onClick;
    return b;
  }

  function factRow(id) {
    const row = el('div', 'item');
    row.append(el('div', 'item-t', '<span class="i-main"></span>'));
    const del = delButton('Usuń z pamięci: ' + state.facts[id], () => queueDelete('Usunięto z pamięci', () => { hiddenFacts.add(id); sync(); }, () => { hiddenFacts.delete(id); sync(); }, () => getTransport().forget(Number(id))));
    row.append(del);
    return { row, del };
  }

  function commitUndo() {
    if (!undo) return;
    clearTimeout(undo.timer);
    const u = undo;
    undo = null;
    toast.classList.remove('on');
    u.commit();
  }

  function queueDelete(message, hide, restore, commit) {
    commitUndo();
    hide();
    toast.innerHTML = '<span></span><button type="button" class="pill">Cofnij</button>';
    toast.querySelector('span').textContent = message;
    toast.querySelector('button').onclick = () => {
      if (!undo) return;
      clearTimeout(undo.timer);
      undo = null; toast.classList.remove('on'); restore();
    };
    toast.classList.add('on');
    undo = { commit, timer: setTimeout(() => { undo = null; toast.classList.remove('on'); commit(); }, 5000) };
  }

  function sync() {
    if (polList) {
      const own = conn.owned();
      const actions = Object.keys(state.policies).filter(a => !own.has(a)).sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
      const keep = new Set(actions);
      rows.forEach((r, a) => { if (!keep.has(a)) { r.row.remove(); rows.delete(a); regs.set(a, (regs.get(a) || []).filter(x => x !== r)); } });
      actions.forEach((a, i) => {
        let r = rows.get(a);
        if (!r) { r = policyRow(a); rows.set(a, r); }
        if (polList.children[i] !== r.row) polList.insertBefore(r.row, polList.children[i] || null);
      });
      polList.parentElement.hidden = actions.length === 0;
    }
    regs.forEach((list, action) => list.forEach(r => {
      const ask = isAsk(action, r.fallback);
      if (r.sw.getAttribute('aria-checked') !== String(ask)) { r.sw.setAttribute('aria-checked', String(ask)); subtitle(r.row, ask); }
      if (!r.override) { const t = labelFor(action); const m = r.row.querySelector('.i-main'); if (m.textContent !== t) m.textContent = t; }
    }));
    const ids = Object.keys(state.facts).filter(id => !hiddenFacts.has(id));
    if (memList) {
      facts.forEach((f, id) => { if (!ids.includes(id)) { f.row.remove(); facts.delete(id); } });
      ids.forEach((id, i) => {
        let f = facts.get(id);
        if (!f) { f = factRow(id); facts.set(id, f); f.row.querySelector('.i-main').textContent = state.facts[id]; }
        if (memList.children[i] !== f.row) memList.insertBefore(f.row, memList.children[i] || null);
      });
      memEmpty.hidden = ids.length > 0;
      memList.hidden = ids.length === 0;
    }
    if (memSub) memSub.textContent = ids.length ? ids.length + ' ' + (ids.length === 1 ? 'zapamiętana rzecz' : ids.length < 5 ? 'zapamiętane rzeczy' : 'zapamiętanych rzeczy') : 'Jeszcze nic';
  }

  function refreshHero() {
    if (!heroSub) return;
    const s = conn.summary();
    heroSub.textContent = s.loaded ? 'Połączono ' + s.n + ' z ' + s.total : 'Wczytuję…';
    heroIcons.innerHTML = s.icons.map(i => `<span class="stk">${i}</span>`).join('');
  }

  function navRow(ic, title, subEl, onClick) {
    const b = el('button', 'navrow', `<span class="n-tile">${icon(ic, 20)}</span><span class="n-t"><span class="n-main"></span><span class="n-sub"></span></span><span class="n-ch">${icon('chevR', 18)}</span>`);
    b.type = 'button';
    b.querySelector('.n-main').textContent = title;
    if (subEl) b.querySelector('.n-sub').replaceWith(subEl);
    b.onclick = onClick;
    return b;
  }

  function updateHead() {
    const top = stack[stack.length - 1];
    head.title.textContent = top ? top.title : 'Ustawienia';
    head.back.hidden = !top;
    head.back.setAttribute('aria-label', 'Wróć');
  }

  function swap(from, to, dir, instant) {
    to.hidden = false;
    if (reduceMq.matches || instant || !from.animate) { from.hidden = true; return; }
    const out = from.animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: `translate3d(${-dir * 26}px,0,0)` }], { duration: 170, easing: EASE, fill: 'forwards' });
    out.onfinish = () => { from.hidden = true; out.cancel(); };
    to.animate([{ opacity: 0, transform: `translate3d(${dir * 40}px,0,0)` }, { opacity: 1, transform: 'none' }], { duration: 520, easing: SPRING });
  }

  function push(title, builder, instant) {
    const from = stack.length ? stack[stack.length - 1].el : rootEl;
    if (stack.length) stack[stack.length - 1].scroll = body.scrollTop; else rootEl._scroll = body.scrollTop;
    const page = el('div', 'page');
    page.hidden = true;
    body.append(page);
    const view = builder(page, push) || {};
    stack.push({ el: page, title, view, scroll: 0 });
    swap(from, page, 1, instant);
    body.scrollTop = 0;
    updateHead();
  }

  function pop() {
    if (!stack.length) return;
    const top = stack.pop();
    top.view.destroy?.();
    const to = stack.length ? stack[stack.length - 1].el : rootEl;
    to.hidden = false;
    const scroll = stack.length ? stack[stack.length - 1].scroll : rootEl._scroll || 0;
    if (reduceMq.matches || !top.el.animate) { top.el.remove(); }
    else {
      const out = top.el.animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translate3d(40px,0,0)' }], { duration: 190, easing: EASE, fill: 'forwards' });
      out.onfinish = () => top.el.remove();
      to.animate([{ opacity: 0, transform: 'translate3d(-26px,0,0)' }, { opacity: 1, transform: 'none' }], { duration: 480, easing: SPRING });
    }
    body.scrollTop = scroll;
    updateHead();
  }

  function personaSection(t, my) {
    const s = section('Osobowość', 'face');
    const field = el('div', 'field-row');
    field.style.marginTop = '0';
    const ta = el('textarea', 'in');
    ta.rows = 6; ta.setAttribute('aria-label', 'Osobowość Concierge'); ta.spellcheck = false;
    field.append(ta);
    const tag = el('span', 'tag', 'domyślna'); tag.hidden = true;
    s.querySelector('h3').append(tag);
    const btns = el('div', 'row-btns');
    const reset = el('button', 'btn tonal small', 'Przywróć'); reset.type = 'button';
    const save = el('button', 'btn ink small', 'Zapisz'); save.type = 'button'; save.disabled = true;
    btns.append(reset, save);
    s.append(field, el('p', 'foot', 'Tak Concierge ma się zachowywać i mówić.'), btns);
    let base = '';
    const apply = r => { base = r.persona || ''; ta.value = base; tag.hidden = !r.isDefault; save.disabled = true; reset.disabled = !!r.isDefault; };
    t.getPersona().then(r => { if (my === token) apply(r); }).catch(() => { ta.placeholder = 'Nie udało się wczytać.'; });
    ta.oninput = () => { save.disabled = ta.value === base; };
    save.onclick = async () => { save.disabled = true; try { apply(await t.setPersona(ta.value)); save.textContent = 'Zapisano'; setTimeout(() => { save.textContent = 'Zapisz'; }, 1500); } catch { save.textContent = 'Nie udało się'; save.disabled = false; setTimeout(() => { save.textContent = 'Zapisz'; }, 1800); } };
    reset.onclick = async () => { try { apply(await t.setPersona('')); } catch {} };
  }

  function skillsPage(page) {
    const t = getTransport(), my = token;
    const list = el('div', 'list'); list.hidden = true;
    const empty = el('p', 'foot flush', 'Brak umiejętności. Poproś Concierge, żeby nauczył się czegoś nowego.');
    page.append(list, empty);
    const hidden = new Set();
    let data = [];
    const render = () => {
      list.textContent = '';
      const shown = data.filter(x => !hidden.has(x.name));
      shown.forEach(x => {
        const row = el('div', 'item');
        const txt = el('div', 'item-t', '<span class="i-main"></span><span class="i-sub"></span>');
        txt.querySelector('.i-main').textContent = x.name;
        txt.querySelector('.i-sub').textContent = x.description || '';
        row.append(txt);
        if (x.source === 'user') row.append(delButton('Usuń umiejętność: ' + x.name, () => queueDelete('Usunięto umiejętność', () => { hidden.add(x.name); render(); }, () => { hidden.delete(x.name); render(); }, () => t.deleteSkill(x.name))));
        else row.append(el('span', 'tag', 'wbudowana'));
        list.append(row);
      });
      list.hidden = !shown.length; empty.hidden = !!shown.length;
      if (skillSub) skillSub.textContent = data.length ? data.length + ' ' + (data.length === 1 ? 'umiejętność' : data.length < 5 ? 'umiejętności' : 'umiejętności') : 'Brak';
    };
    if (!t.listSkills) { empty.textContent = 'Umiejętności są dostępne na Macu.'; return {}; }
    t.listSkills().then(r => { if (my === token) { data = r; render(); } }).catch(() => { empty.textContent = 'Nie udało się wczytać umiejętności.'; });
    return {};
  }

  function memoryPage(page) {
    memList = el('div', 'list');
    memEmpty = el('p', 'foot flush', 'Jeszcze nic. Powiedz mi coś o sobie, a zapamiętam.');
    page.append(memList, memEmpty);
    facts.clear();
    sync();
    return { destroy() { memList = null; memEmpty = null; facts.clear(); } };
  }

  function cardsPage(page) {
    const t = getTransport(), my = token;
    const s = page;
    const list = el('div', 'list'); list.hidden = true;
    const empty = el('p', 'foot flush', 'Brak kart. Concierge nie zapłaci za nic, dopóki jakiejś nie dodasz.');
    s.append(list, empty);
    const hidden = new Set();
    let data = [];
    const render = () => {
      list.textContent = '';
      const shown = data.filter(x => !hidden.has(x.id));
      shown.forEach(x => {
        const row = el('div', 'item');
        const txt = el('div', 'item-t', '<span class="i-main"></span><span class="i-sub"></span>');
        txt.querySelector('.i-main').textContent = x.label;
        txt.querySelector('.i-sub').textContent = (x.brand || 'Karta') + ' •••• ' + x.last4 + (x.limitPln ? ', limit ' + x.limitPln + ' zł' : '');
        row.append(txt, delButton('Usuń kartę: ' + x.label, () => queueDelete('Usunięto kartę', () => { hidden.add(x.id); render(); }, () => { hidden.delete(x.id); render(); }, () => t.deleteCard(x.id))));
        list.append(row);
      });
      list.hidden = !shown.length; empty.hidden = !!shown.length;
    };
    const load = () => t.listCards().then(r => { if (my === token) { data = r; render(); } }).catch(() => { empty.textContent = 'Nie udało się wczytać kart.'; });
    load();

    const open = el('button', 'pill block', icon('plus', 18) + '<span>Dodaj kartę</span>');
    open.type = 'button';
    const form = el('form', 'sub-block'); form.hidden = true; form.autocomplete = 'on';
    const input = (id, label, attrs) => {
      const r = el('div', 'field-row');
      const l = el('label', null, label); l.htmlFor = id;
      const i = el('input', 'in'); i.id = id; i.type = 'text';
      Object.assign(i, attrs);
      r.append(l, i);
      return { r, i };
    };
    const fLabel = input('cardLabel', 'Nazwa', { placeholder: 'Np. Karta na gry', autocomplete: 'off', maxLength: 40 });
    const fHolder = input('cardHolder', 'Imię i nazwisko na karcie', { autocomplete: 'cc-name', autocapitalize: 'words', maxLength: 60 });
    const fPan = input('cardPan', 'Numer karty', { autocomplete: 'cc-number', inputMode: 'numeric', maxLength: 23, placeholder: '0000 0000 0000 0000' });
    const fExp = input('cardExp', 'Ważna do', { autocomplete: 'cc-exp', inputMode: 'numeric', maxLength: 5, placeholder: 'MM/RR' });
    const fCvv = input('cardCvv', 'CVV', { autocomplete: 'cc-csc', inputMode: 'numeric', maxLength: 4, placeholder: '000' });
    fCvv.i.type = 'password';
    const fLimit = input('cardLimit', 'Limit na jedną płatność (zł)', { autocomplete: 'off', inputMode: 'numeric', maxLength: 6, placeholder: '0' });
    const two = el('div', 'two'); two.append(fExp.r, fCvv.r);
    fExp.r.style.marginTop = fCvv.r.style.marginTop = '12px';
    fPan.i.oninput = () => { const d = fPan.i.value.replace(/\D/g, '').slice(0, 19); fPan.i.value = d.replace(/(.{4})/g, '$1 ').trim(); };
    fExp.i.oninput = () => { const d = fExp.i.value.replace(/\D/g, '').slice(0, 4); fExp.i.value = d.length > 2 ? d.slice(0, 2) + '/' + d.slice(2) : d; };
    fCvv.i.oninput = () => { fCvv.i.value = fCvv.i.value.replace(/\D/g, '').slice(0, 4); };
    fLimit.i.oninput = () => { fLimit.i.value = fLimit.i.value.replace(/\D/g, '').slice(0, 6); };
    const err = el('p', 'note-err'); err.setAttribute('role', 'alert');
    const btns = el('div', 'row-btns');
    const cancel = el('button', 'btn tonal small', 'Anuluj'); cancel.type = 'button';
    const submit = el('button', 'btn ink small', 'Zapisz kartę'); submit.type = 'submit';
    btns.append(cancel, submit);
    form.append(fLabel.r, fHolder.r, fPan.r, two, fLimit.r, el('p', 'foot', 'Numer karty wpisujesz tylko tutaj, na Macu. Potem Concierge pokaże tylko nazwę, markę i 4 ostatnie cyfry.'), err, btns);
    const wipe = () => { [fLabel, fHolder, fPan, fExp, fCvv, fLimit].forEach(f => { f.i.value = ''; }); err.textContent = ''; };
    cancel.onclick = () => { wipe(); form.hidden = true; open.hidden = false; };
    open.onclick = () => { form.hidden = false; open.hidden = true; fLabel.i.focus({ preventScroll: false }); };
    form.onsubmit = async e => {
      e.preventDefault();
      err.textContent = ''; submit.disabled = true;
      try {
        await t.addCard({ label: fLabel.i.value, holder: fHolder.i.value, pan: fPan.i.value.replace(/\s/g, ''), exp: fExp.i.value, cvv: fCvv.i.value, limitPln: Number(fLimit.i.value) || 0 });
        wipe(); form.hidden = true; open.hidden = false;
        await load();
      } catch (ex) { err.textContent = cardError(String(ex && ex.message || '')); }
      submit.disabled = false;
    };
    s.append(open, form);
    return { destroy() { wipe(); } };
  }

  async function phoneSection() {
    const transport = getTransport();
    if (transport.mode !== 'local') return;
    const s = section('iPhone', 'phone');
    s.append(el('p', 'foot flush', 'Zeskanuj kod aparatem iPhone\'a, otwórz stronę w Safari, zaloguj się i dodaj ją do ekranu początkowego.'));
    const qr = el('div', 'qr');
    const copy = el('button', 'pill block', icon('copy', 18) + '<span>Kopiuj link</span>');
    copy.type = 'button';
    s.append(qr, copy);
    try {
      const url = await transport.pairingUrl();
      copy.onclick = async () => {
        try { await navigator.clipboard.writeText(url); copy.querySelector('span').textContent = 'Skopiowano'; setTimeout(() => { copy.querySelector('span').textContent = 'Kopiuj link'; }, 1600); }
        catch { copy.querySelector('span').textContent = 'Nie udało się skopiować'; }
      };
      await loadScript('https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js');
      const q = window.qrcode(0, 'M'); q.addData(url); q.make();
      qr.innerHTML = q.createSvgTag({ cellSize: 4, margin: 0, scalable: true });
      qr.setAttribute('role', 'img'); qr.setAttribute('aria-label', 'Kod QR do połączenia z iPhonem');
    } catch { qr.classList.add('off'); qr.textContent = 'Kod QR niedostępny.'; }
  }

  function accountSection() {
    const acc = getTransport().account;
    if (!acc) return;
    const s = section('Konto', 'user');
    if (acc.email) s.append(el('p', 'foot flush', 'Zalogowano jako ' + acc.email + '.'));
    const out = el('button', 'pill block', '<span>Wyloguj to urządzenie</span>');
    out.type = 'button';
    out.onclick = async () => { out.disabled = true; await acc.signOut(); };
    s.append(out);
  }

  function chatSection() {
    const s = section('Rozmowa', 'chat');
    const wrap = el('div', 'confirm');
    const first = el('button', 'pill block', icon('trash', 18) + '<span>Wyczyść tę rozmowę</span>');
    first.type = 'button';
    const pair = el('div', 'pair-btns');
    pair.hidden = true;
    const no = el('button', 'btn tonal', 'Anuluj'); no.type = 'button';
    const yes = el('button', 'btn ink', 'Wyczyść'); yes.type = 'button';
    pair.append(no, yes);
    let t;
    const reset = () => { clearTimeout(t); pair.hidden = true; first.hidden = false; };
    first.onclick = () => { first.hidden = true; pair.hidden = false; yes.focus({ preventScroll: true }); t = setTimeout(reset, 5000); };
    no.onclick = reset;
    yes.onclick = async () => { reset(); await getTransport().clear(); onCleared(); };
    wrap.append(first, pair);
    s.append(wrap);
  }

  function build() {
    commitUndo();
    conn.stopPoll();
    stack.forEach(x => x.view.destroy?.());
    stack = [];
    const my = ++token;
    const t = getTransport();
    body.textContent = '';
    rows.clear(); facts.clear(); regs.clear();
    memList = null;
    rootEl = el('div', 'page');
    body.append(rootEl);

    heroSub = el('span', 'n-sub'); heroIcons = el('span', 'stack');
    const hero = el('button', 'navrow feat', `<span class="n-tile big"></span><span class="n-t"><span class="n-main">Konektory</span></span><span class="n-ch">${icon('chevR', 18)}</span>`);
    hero.type = 'button';
    hero.querySelector('.n-tile').replaceWith(heroIcons);
    hero.querySelector('.n-t').append(heroSub);
    hero.onclick = () => push('Konektory', page => conn.gallery(page, push));
    const hs = el('section', 'grp'); hs.append(hero); rootEl.append(hs);
    refreshHero();

    const sp = section('Pytaj o zgodę', 'shield');
    polList = el('div', 'list');
    sp.append(polList, el('p', 'foot', 'Włączone: zapytam, zanim coś zrobię. Wyłączone: zrobię sam.'));

    const sn = section('Wiedza', 'bookmark');
    const nav = el('div', 'list nav');
    skillSub = el('span', 'n-sub'); memSub = el('span', 'n-sub');
    skillSub.textContent = 'Co Concierge potrafi';
    nav.append(
      navRow('spark', 'Umiejętności', skillSub, () => push('Umiejętności', skillsPage)),
      navRow('bookmark', 'Pamięć', memSub, () => push('Pamięć', memoryPage)),
    );
    if (t.listCards && localHost) { const cs = el('span', 'n-sub'); cs.textContent = 'Tylko na tym Macu'; nav.append(navRow('card', 'Karty', cs, () => push('Karty', cardsPage))); }
    sn.append(nav);

    if (t.getPersona) personaSection(t, my);
    phoneSection();
    chatSection();
    accountSection();
    updateHead();
    sync();
    conn.load();
    if (t.listSkills) t.listSkills().then(r => { if (my === token && skillSub) skillSub.textContent = r.length ? 'Zapisane: ' + r.length : 'Brak'; }).catch(() => {});
  }

  function go(name, instant) {
    if (!rootEl) return;
    while (stack.length) pop();
    const t = getTransport();
    if (name === 'connectors') push('Konektory', page => conn.gallery(page, push), instant);
    else if (name === 'skills') push('Umiejętności', skillsPage, instant);
    else if (name === 'memory') push('Pamięć', memoryPage, instant);
    else if (name === 'cards' && t.listCards) push('Karty', cardsPage, instant);
  }

  head.back.onclick = () => pop();

  return { build, sync, commitUndo, go, back: pop, get depth() { return stack.length; }, loadConnectors: () => conn.load(), connectors: conn };
}
