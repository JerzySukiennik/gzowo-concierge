// Gzowo Concierge - demo transport: scripted fake conversation for UI work (?demo=1), no network, no model, no real data.
const POLICIES = { 'calendar.read': 'auto', 'calendar.write': 'ask', 'calendar.delete': 'ask', 'web.search': 'auto', 'memory.write': 'auto' };
const FACTS = { 1: 'Trening piłki w środy o 16:30', 2: 'Pianino we wtorki o 17:00', 3: 'Babcia mieszka w Gzowie, jeździmy tam w weekendy' };

const DEFAULT_PERSONA = 'Jesteś Concierge, spokojnym i zwięzłym asystentem Jurka. Mówisz po polsku, rzeczowo i uprzejmie. Najpierw działasz, potem krótko raportujesz. Przed rzeczami nieodwracalnymi pytasz o zgodę.';
const WEEK = 'W tym tygodniu masz trzy rzeczy:\n\n- **Wtorek 17:00**: pianino\n- **Środa 16:30**: trening piłki\n- **Piątek 18:00**: kolacja w Gzowie\n\nChcesz, żebym coś przesunął?';
const LONG = 'Jasne, rozpiszę to po kolei.\n\n## Plan na weekend\n\n1. **Sobota rano**: wyjazd do Gzowa, spakuj rakiety modelarskie i drukarkę 3D.\n2. **Sobota po południu**: start testowy rakiety na polu za domem, jeśli wiatr będzie poniżej 15 km/h.\n3. **Niedziela**: powrót do Warszawy przed 18:00, bo w poniedziałek masz sprawdzian z matmy.\n\nProgram lotu zapisałem w pliku `lot-test-3.ork`. Pogodę sprawdzisz tutaj: https://www.windy.com/pl, a opis silników jest w [katalogu Estes](https://www.estesrockets.com/).\n\n> Pamiętaj o zapasowym ładunku wyrzucającym. Zawsze.\n\n```\nsilnik: C6-5\nmasa startowa: 84 g\nwysokość: ~180 m\n```\n\nDługie_slowo_bez_spacji_które_nie_powinno_rozwalić_układu_na_wąskim_telefonie_ani_na_desktopie_nigdy.';

let current = null;

export function createDemo(on, { scene = 'chat', mode = 'local' } = {}) {
  const st = { online: true, link: true, busy: false, policies: { ...POLICIES }, facts: { ...FACTS }, pending: {} };
  const timers = new Set();
  let n = 0;
  const push = patch => { Object.assign(st, patch); on.state(JSON.parse(JSON.stringify(st))); };
  const later = (ms, fn) => { const t = setTimeout(() => { timers.delete(t); fn(); }, ms); timers.add(t); };
  const ev = (e, h) => on.event(h ? { ...e, history: true } : e);
  const rid = () => 'r' + (++n);

  function history() {
    const r1 = rid(), r2 = rid();
    ev({ type: 'user', text: 'Co mam w tym tygodniu?', cid: 'c1', rid: r1 }, 1);
    ev({ type: 'tool', name: 'calendar_list', summary: 'Przeczytałem kalendarz na 12-18 października', status: 'done', rid: r1 }, 1);
    ev({ type: 'text', text: WEEK, rid: r1 }, 1);
    ev({ type: 'user', text: 'Dodaj sprawdzian z matmy w piątek o 8:00', cid: 'c2', rid: r2 }, 1);
    ev({ type: 'tool', name: 'calendar_add', summary: 'Dodałem do kalendarza: Sprawdzian z matmy, piątek 8:00', status: 'done', rid: r2 }, 1);
    ev({ type: 'tool', name: 'remember', summary: 'Zapamiętałem: matma w piątek rano', status: 'done', rid: r2 }, 1);
    ev({ type: 'text', text: 'Gotowe. Sprawdzian z matmy jest w piątek o **8:00**. Przypomnę Ci w czwartek wieczorem.', rid: r2 }, 1);
  }

  function reply(text) {
    const r = rid();
    push({ busy: true });
    if (/b[łl][aą]d|error|nie dzia/i.test(text)) {
      later(500, () => ev({ type: 'tool', name: 'calendar_list', summary: 'Czytam kalendarz', status: 'running', rid: r }));
      later(1500, () => { ev({ type: 'tool', name: 'calendar_list', summary: 'Czytam kalendarz', status: 'failed', error: 'Kalendarz nie odpowiada. Spróbuj za chwilę.', rid: r }); ev({ type: 'error', message: 'Nie udało się przeczytać kalendarza.' }); push({ busy: false }); });
    } else if (/dłu|long|weekend|plan/i.test(text)) {
      later(900, () => { ev({ type: 'text', text: LONG, rid: r }); push({ busy: false }); });
    } else if (/doda|dodaj|przypomnij|przenie/i.test(text)) {
      const what = text.replace(/^(dodaj|przypomnij mi|przenieś)\s*/i, '');
      later(700, () => { ev({ type: 'text', text: 'Mogę to dodać. Potrzebuję Twojej zgody.', rid: r }); push({ busy: false, pending: { ['a' + r]: 'Dodać do kalendarza: ' + what + '?' } }); });
    } else if (/warszaw|nowego|szuka|pogod|news/i.test(text)) {
      later(500, () => ev({ type: 'tool', name: 'web_search', summary: 'Szukam w sieci: Warszawa dzisiaj', status: 'running', rid: r }));
      later(1700, () => ev({ type: 'tool', name: 'web_search', summary: 'Szukam w sieci: Warszawa dzisiaj', status: 'done', rid: r }));
      later(2300, () => { ev({ type: 'text', text: 'Dzisiaj w Warszawie:\n\n- Metro M2 jeździ rzadziej do 20:00 przez prace torowe.\n- Wieczorem **8°C** i przejaśnienia.\n- W Muzeum Techniki jest weekend z rakietami: https://muzeum.example.pl', rid: r }); push({ busy: false }); });
    } else if (/tydzie|kalendarz|mam |plan/i.test(text)) {
      later(500, () => ev({ type: 'tool', name: 'calendar_list', summary: 'Czytam kalendarz', status: 'running', rid: r }));
      later(1400, () => ev({ type: 'tool', name: 'calendar_list', summary: 'Przeczytałem kalendarz na 12-18 października', status: 'done', rid: r }));
      later(1900, () => { ev({ type: 'text', text: WEEK, rid: r }); push({ busy: false }); });
    } else {
      later(1200, () => { ev({ type: 'text', text: 'Jasne. Powiedz tylko, co dokładnie mam zrobić.', rid: r }); push({ busy: false }); });
    }
  }

  function buildScene() {
    if (scene === 'empty') return;
    if (scene === 'long') { ev({ type: 'user', text: 'Rozpisz mi plan na weekend w Gzowie', cid: 'c1' }, 1); ev({ type: 'text', text: LONG }, 1); return; }
    history();
    if (scene === 'approval') push({ pending: { a1: 'Dodać do kalendarza: Lekcja pianina, czwartek 17:00-17:45?' } });
    if (scene === 'approval2') push({ pending: { a1: 'Dodać do kalendarza: Lekcja pianina, czwartek 17:00-17:45?', a2: 'Usunąć z kalendarza: Trening piłki, środa 16:30?' } });
    if (scene === 'busy') { ev({ type: 'user', text: 'Co nowego w Warszawie?', cid: 'c3' }, 1); ev({ type: 'tool', name: 'web_search', summary: 'Szukam w sieci: Warszawa dzisiaj', status: 'running', rid: 'rb' }, 1); push({ busy: true }); }
    if (scene === 'thinking') { ev({ type: 'user', text: 'Zaplanuj mi tydzień', cid: 'c3' }, 1); push({ busy: true }); }
    if (scene === 'failed') { ev({ type: 'user', text: 'Usuń trening piłki w środę', cid: 'c3' }, 1); ev({ type: 'tool', name: 'calendar_delete', summary: 'Usuwam z kalendarza: Trening piłki', status: 'failed', error: 'Kalendarz nie odpowiada. Spróbuj za chwilę.', rid: 'rf' }, 1); ev({ type: 'error', message: 'Nie udało się usunąć wydarzenia.' }, 1); }
    if (scene === 'offline') push({ online: false });
    if (scene === 'nolink') push({ link: false, online: false });
    if (scene === 'queued') { on.queued('q1', 'Napisz do trenera, że spóźnię się 10 minut'); push({ online: false }); }
  }

  const persona = { text: DEFAULT_PERSONA, isDefault: true };
  const skills = [{ name: 'kalendarz-szkolny', description: 'Układa plan lekcji i sprawdziany w kalendarzu.', source: 'bundled' }, { name: 'rakiety-checklista', description: 'Lista kontrolna przed startem rakiety modelarskiej.', source: 'user' }, { name: 'szybka-notatka', description: 'Zapisuje krótką notatkę i przypomina o niej wieczorem.', source: 'user' }];
  const cards = [{ id: 'c1', label: 'Karta na gry', brand: 'Visa', last4: '4242', limitPln: 100 }];

  const self = {
    push, approveHook: null,
  };
  current = self;
  window.__demo = { push, on, st, reply };

  return {
    mode,
    async start() { push({}); buildScene(); },
    send(text, cid) {
      if (mode === 'relay') later(st.online ? 800 : 999999, () => ev({ type: 'user', text, cid }));
      reply(text);
    },
    approve(id, yes) {
      if (self.approveHook) { push({ pending: Object.fromEntries(Object.entries(st.pending).filter(([k]) => k !== id)) }); self.approveHook(yes); return; }
      const r = id.replace(/^a/, '');
      const summary = 'Dodaję do kalendarza';
      push({ pending: Object.fromEntries(Object.entries(st.pending).filter(([k]) => k !== id)) });
      if (!yes) { push({ busy: true }); later(500, () => { ev({ type: 'text', text: 'Dobra, nic nie zmieniam.', rid: r }); push({ busy: false }); }); return; }
      push({ busy: true });
      ev({ type: 'tool', name: 'calendar_add', summary, status: 'running', rid: r });
      later(1300, () => ev({ type: 'tool', name: 'calendar_add', summary, status: 'done', rid: r }));
      later(1800, () => { ev({ type: 'text', text: 'Gotowe, jest w kalendarzu.', rid: r }); push({ busy: false }); });
    },
    async setPolicy(action, policy) { later(300, () => push({ policies: { ...st.policies, [action]: policy } })); },
    async forget(id) { later(200, () => { const f = { ...st.facts }; delete f[id]; push({ facts: f }); }); },
    async clear() { timers.forEach(clearTimeout); timers.clear(); push({ busy: false, pending: {} }); },
    async pairingUrl() { return 'http://192.168.1.20:2040/?t=demo-token-not-real'; },
    async getPersona() { return { persona: persona.text, isDefault: persona.isDefault }; },
    async setPersona(text) { persona.text = text.trim() ? text : DEFAULT_PERSONA; persona.isDefault = !text.trim(); return { persona: persona.text, isDefault: persona.isDefault }; },
    async listSkills() { return skills.map(x => ({ ...x })); },
    async deleteSkill(name) { const i = skills.findIndex(x => x.name === name); if (i >= 0) skills.splice(i, 1); },
    async listCards() { return cards.map(x => ({ ...x })); },
    async addCard(c) { const d = String(c.pan || '').replace(/\D/g, ''); if (d.length < 13) throw new Error('Invalid card number'); cards.push({ id: 'c' + (cards.length + 2), label: c.label || 'Karta ' + d.slice(-4), brand: 'Visa', last4: d.slice(-4), limitPln: c.limitPln || 0 }); return cards[cards.length - 1]; },
    async deleteCard(id) { const i = cards.findIndex(x => x.id === id); if (i >= 0) cards.splice(i, 1); },
    refresh() {},
  };
}

export function createLive({ onEvent = () => {}, onState = () => {}, onLevel = () => {}, onTranscript = () => {} } = {}) {
  let running = false, muted = false, t0 = 0, tick = 0, user = false, bot = false;
  const T = new Set();
  let state = 'idle';
  const at = (ms, fn) => { const t = setTimeout(() => { T.delete(t); if (running) fn(); }, ms); T.add(t); };
  const set = s => { state = s; onState(s); };
  const words = (role, text, per, done) => {
    const w = text.split(' ');
    w.forEach((_, i) => at(i * per, () => onTranscript({ role, text: w.slice(0, i + 1).join(' '), final: false })));
    at(w.length * per + 80, () => { onTranscript({ role, text, final: true }); done?.(); });
    return w.length * per + 80;
  };

  function levels() {
    const t = (performance.now() - t0) / 1000;
    const mic = muted ? 0 : user ? Math.min(1, 0.25 + 0.6 * Math.abs(Math.sin(t * 9)) * (0.6 + 0.4 * Math.abs(Math.sin(t * 2.3)))) : 0.02 + Math.random() * 0.03;
    const out = bot ? Math.min(1, 0.15 + 0.7 * Math.abs(Math.sin(t * 7.5)) * (0.55 + 0.45 * Math.abs(Math.sin(t * 1.7)))) : 0;
    onLevel({ mic, out });
  }

  function speak(text) {
    set('speaking'); bot = true;
    const d = words('assistant', text, 230, () => { bot = false; set('listening'); });
    return d;
  }

  function respond(text) {
    set('thinking');
    const r = 'lv' + Date.now();
    if (/b[łl][aą]d|error/i.test(text)) {
      at(900, () => onEvent({ type: 'tool', name: 'calendar_list', summary: 'Czytam kalendarz', status: 'running', rid: r }));
      at(2200, () => { onEvent({ type: 'tool', name: 'calendar_list', summary: 'Czytam kalendarz', status: 'failed', error: 'Kalendarz nie odpowiada. Spróbuj za chwilę.', rid: r }); });
      at(2600, () => speak('Nie udało mi się przeczytać kalendarza. Spróbuję za chwilę.'));
    } else if (/doda|dodaj|przypomnij/i.test(text)) {
      at(900, () => onEvent({ type: 'tool', name: 'calendar_list', summary: 'Sprawdzam, czy czwartek jest wolny', status: 'running', rid: r }));
      at(2100, () => onEvent({ type: 'tool', name: 'calendar_list', summary: 'Sprawdzam, czy czwartek jest wolny', status: 'done', rid: r }));
      at(2500, () => {
        const p = { lv1: 'Dodać do kalendarza: Lekcja pianina, czwartek 17:00-17:45?' };
        current?.push({ pending: p }); onEvent({ type: 'pending', pending: p });
        if (current) current.approveHook = yes => {
          current.approveHook = null;
          onEvent({ type: 'pending', pending: {} });
          if (!yes) { at(300, () => speak('Dobrze, nic nie dodaję.')); return; }
          onEvent({ type: 'tool', name: 'calendar_add', summary: 'Dodaję lekcję pianina', status: 'running', rid: r });
          at(1300, () => onEvent({ type: 'tool', name: 'calendar_add', summary: 'Dodaję lekcję pianina', status: 'done', rid: r }));
          at(1900, () => speak('Gotowe. Lekcja pianina jest w czwartek o siedemnastej.'));
        };
      });
    } else {
      at(900, () => onEvent({ type: 'tool', name: 'web_search', summary: 'Szukam w sieci', status: 'running', rid: r }));
      at(2000, () => onEvent({ type: 'tool', name: 'web_search', summary: 'Szukam w sieci', status: 'done', rid: r }));
      at(2400, () => speak('W Warszawie jest dzisiaj osiem stopni i przejaśnienia. Metro dwójka jeździ rzadziej do dwudziestej.'));
    }
  }

  return {
    get state() { return state; },
    start() {
      if (running) return;
      running = true; t0 = performance.now();
      tick = setInterval(levels, 33);
      set('connecting');
      at(800, () => set('listening'));
      at(2200, () => {
        user = true;
        const d = words('user', 'Dodaj lekcję pianina w czwartek o 17:00', 260, () => { user = false; respond('Dodaj lekcję pianina'); });
      });
    },
    stop() {
      if (!running) return;
      running = false; user = bot = false;
      T.forEach(clearTimeout); T.clear(); clearInterval(tick);
      onLevel({ mic: 0, out: 0 });
      if (current) current.approveHook = null;
      state = 'idle'; onState('idle');
    },
    mute(b) { muted = !!b; },
    sendText(text) { if (running) respond(text); },
  };
}
