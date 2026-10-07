// Gzowo Concierge - settings content: approval switches, memory, persona, skills, cards (Mac only), iPhone QR link, clear chat; deletes are undoable.
import { icon } from './icons.js';

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

export function createSettings({ body, toast, state, getTransport, onCleared }) {
  const rows = new Map(), facts = new Map();
  const hiddenFacts = new Set();
  let polList, memList, memEmpty, undo = null, token = 0;

  function section(title) {
    const s = el('section', 'grp');
    s.append(el('h3', null, title));
    body.append(s);
    return s;
  }

  function makeSwitch(label, on, onToggle) {
    const b = el('button', 'switch', '<span class="track"><span class="knob"></span></span>');
    b.type = 'button'; b.setAttribute('role', 'switch'); b.setAttribute('aria-label', label);
    b.setAttribute('aria-checked', String(on));
    b.onclick = () => { const next = b.getAttribute('aria-checked') !== 'true'; b.setAttribute('aria-checked', String(next)); onToggle(next); };
    return b;
  }

  function policyRow(action) {
    const label = LABELS[action] || action;
    const row = el('div', 'item');
    const txt = el('div', 'item-t', '<span class="i-main"></span><span class="i-sub"></span>');
    txt.querySelector('.i-main').textContent = label;
    const sw = makeSwitch('Pytaj o zgodę: ' + label, state.policies[action] === 'ask', next => {
      getTransport().setPolicy(action, next ? 'ask' : 'auto');
      state.policies[action] = next ? 'ask' : 'auto';
      state.overrides[action] = Date.now();
      subtitle(row, next);
    });
    row.append(txt, sw);
    subtitle(row, state.policies[action] === 'ask');
    return { row, sw };
  }

  function subtitle(row, ask) { row.querySelector('.i-sub').textContent = ask ? 'Zapytam o zgodę' : 'Zrobię sam'; }

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
    if (!polList) return;
    const actions = Object.keys(state.policies).sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
    actions.forEach((a, i) => {
      let r = rows.get(a);
      if (!r) { r = policyRow(a); rows.set(a, r); }
      const ask = state.policies[a] === 'ask';
      if (r.sw.getAttribute('aria-checked') !== String(ask)) { r.sw.setAttribute('aria-checked', String(ask)); subtitle(r.row, ask); }
      if (polList.children[i] !== r.row) polList.insertBefore(r.row, polList.children[i] || null);
    });
    const ids = Object.keys(state.facts).filter(id => !hiddenFacts.has(id));
    facts.forEach((f, id) => { if (!ids.includes(id)) { f.row.remove(); facts.delete(id); } });
    ids.forEach((id, i) => {
      let f = facts.get(id);
      if (!f) { f = factRow(id); facts.set(id, f); f.row.querySelector('.i-main').textContent = state.facts[id]; }
      if (memList.children[i] !== f.row) memList.insertBefore(f.row, memList.children[i] || null);
    });
    memEmpty.hidden = ids.length > 0;
    memList.hidden = ids.length === 0;
    polList.parentElement.hidden = actions.length === 0;
  }

  function personaSection(t, my) {
    const s = section('Osobowość');
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

  function skillsSection(t, my) {
    const s = section('Umiejętności');
    const list = el('div', 'list'); list.hidden = true;
    const empty = el('p', 'foot flush', 'Brak umiejętności. Poproś Concierge, żeby nauczył się czegoś nowego.');
    s.append(list, empty);
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
    };
    t.listSkills().then(r => { if (my === token) { data = r; render(); } }).catch(() => { empty.textContent = 'Nie udało się wczytać umiejętności.'; });
  }

  function cardsSection(t, my) {
    const s = section('Karty');
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
  }

  async function phoneSection() {
    const transport = getTransport();
    if (transport.mode !== 'local') return;
    const s = section('iPhone');
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
    const s = section('Konto');
    if (acc.email) s.append(el('p', 'foot flush', 'Zalogowano jako ' + acc.email + '.'));
    const out = el('button', 'pill block', '<span>Wyloguj to urządzenie</span>');
    out.type = 'button';
    out.onclick = async () => { out.disabled = true; await acc.signOut(); };
    s.append(out);
  }

  function chatSection() {
    const s = section('Rozmowa');
    const wrap = el('div', 'confirm');
    const first = el('button', 'pill block', icon('trash', 18) + '<span>Wyczyść rozmowę</span>');
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
    const my = ++token;
    const t = getTransport();
    body.textContent = '';
    rows.clear(); facts.clear();
    const sp = section('Pytaj o zgodę');
    polList = el('div', 'list');
    sp.append(polList, el('p', 'foot', 'Włączone: zapytam, zanim coś zrobię. Wyłączone: zrobię sam.'));
    const sm = section('Pamięć');
    memList = el('div', 'list');
    memEmpty = el('p', 'foot flush', 'Jeszcze nic. Powiedz mi coś o sobie, a zapamiętam.');
    sm.append(memList, memEmpty);
    if (t.getPersona) personaSection(t, my);
    if (t.listSkills) skillsSection(t, my);
    if (t.listCards && localHost) cardsSection(t, my);
    phoneSection();
    chatSection();
    accountSection();
    sync();
  }

  return { build, sync, commitUndo };
}
