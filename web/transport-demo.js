// Gzowo Concierge - demo transport: scripted fake conversations, threads, today widgets and connectors for UI work (?demo=1), no network, no model, no real data.
import { getThreadId, setThreadId } from './thread-store.js';

const POLICIES = { 'calendar.read': 'auto', 'calendar.write': 'ask', 'calendar.delete': 'ask', 'web.search': 'auto', 'memory.write': 'auto', 'gmail.read': 'auto', 'gmail.send': 'ask', 'docs.read': 'auto', 'docs.write': 'ask', 'drive.read': 'auto', 'drive.write': 'ask', 'weather.read': 'auto', 'reminders.read': 'auto', 'reminders.write': 'ask', 'github.read': 'auto', 'tesla.read': 'auto', 'tesla.control': 'ask' };
const LABELS = { 'gmail.read': 'Gmail: czytanie poczty', 'gmail.send': 'Gmail: wysyłanie wiadomości', 'docs.read': 'Dokumenty: czytanie', 'docs.write': 'Dokumenty: edycja', 'drive.read': 'Dysk: czytanie plików', 'drive.write': 'Dysk: zapisywanie plików', 'weather.read': 'Pogoda: sprawdzanie', 'reminders.read': 'Przypomnienia: czytanie', 'reminders.write': 'Przypomnienia: dodawanie', 'github.read': 'GitHub: czytanie repozytoriów', 'tesla.read': 'Tesla: odczyt stanu auta', 'tesla.control': 'Tesla: sterowanie autem' };
const FACTS = { 1: 'Trening piłki w środy o 16:30', 2: 'Pianino we wtorki o 17:00', 3: 'Babcia mieszka w Gzowie, jeździmy tam w weekendy' };

const DEFAULT_PERSONA = 'Jesteś Concierge, spokojnym i zwięzłym asystentem Jurka. Mówisz po polsku, rzeczowo i uprzejmie. Najpierw działasz, potem krótko raportujesz. Przed rzeczami nieodwracalnymi pytasz o zgodę.';
const WEEK = 'W tym tygodniu masz trzy rzeczy:\n\n- **Wtorek 17:00**: pianino\n- **Środa 16:30**: trening piłki\n- **Piątek 18:00**: kolacja w Gzowie\n\nChcesz, żebym coś przesunął?';
const LONG = 'Jasne, rozpiszę to po kolei.\n\n## Plan na weekend\n\n1. **Sobota rano**: wyjazd do Gzowa, spakuj rakiety modelarskie i drukarkę 3D.\n2. **Sobota po południu**: start testowy rakiety na polu za domem, jeśli wiatr będzie poniżej 15 km/h.\n3. **Niedziela**: powrót do Warszawy przed 18:00, bo w poniedziałek masz sprawdzian z matmy.\n\nProgram lotu zapisałem w pliku `lot-test-3.ork`. Pogodę sprawdzisz tutaj: https://www.windy.com/pl, a opis silników jest w [katalogu Estes](https://www.estesrockets.com/).\n\n> Pamiętaj o zapasowym ładunku wyrzucającym. Zawsze.\n\n```\nsilnik: C6-5\nmasa startowa: 84 g\nwysokość: ~180 m\n```\n\nDługie_slowo_bez_spacji_które_nie_powinno_rozwalić_układu_na_wąskim_telefonie_ani_na_desktopie_nigdy.';

const tool = (id, name, label, action, policy) => ({ name, label, action, policy });
const CONNECTORS = [
  { id: 'gmail', name: 'Gmail', category: 'Google', icon: 'gmail', description: 'Czytam i podsumowuję pocztę, a po Twojej zgodzie wysyłam wiadomości.', state: 'available', kind: 'setup', capabilities: ['Czytanie i szukanie wiadomości', 'Podsumowania nieprzeczytanych', 'Wysyłanie po Twojej zgodzie'], tools: [tool(0, 'gmail_read', 'Czytanie poczty', 'gmail.read', 'auto'), tool(0, 'gmail_send', 'Wysyłanie wiadomości', 'gmail.send', 'ask')] },
  { id: 'docs', name: 'Dokumenty', category: 'Google', icon: 'docs', description: 'Otwieram dokumenty Google, streszczam je i dopisuję fragmenty.', state: 'available', kind: 'setup', capabilities: ['Czytanie dokumentów', 'Tworzenie notatek', 'Dopisywanie treści po zgodzie'], tools: [tool(0, 'docs_read', 'Czytanie dokumentów', 'docs.read', 'auto'), tool(0, 'docs_write', 'Edycja dokumentów', 'docs.write', 'ask')] },
  { id: 'drive', name: 'Dysk', category: 'Google', icon: 'drive', description: 'Szukam plików na Dysku Google i zapisuję nowe.', state: 'available', kind: 'setup', capabilities: ['Szukanie plików', 'Odczyt zawartości', 'Zapis nowych plików po zgodzie'], tools: [tool(0, 'drive_read', 'Czytanie plików', 'drive.read', 'auto'), tool(0, 'drive_write', 'Zapisywanie plików', 'drive.write', 'ask')] },
  { id: 'calendar', name: 'Kalendarz iCloud', category: 'Na Macu', icon: 'calendar', description: 'Wbudowany kalendarz z Maca: czytanie, dodawanie, zmiany i usuwanie wydarzeń.', state: 'connected', kind: 'builtin', account: 'Kalendarz na tym Macu', capabilities: ['Czytanie wydarzeń', 'Dodawanie i zmiany', 'Usuwanie po zgodzie'], tools: [tool(0, 'calendar_list', 'Czytanie', 'calendar.read', 'auto'), tool(0, 'calendar_add', 'Dodawanie i zmiany', 'calendar.write', 'ask'), tool(0, 'calendar_delete', 'Usuwanie', 'calendar.delete', 'ask')] },
  { id: 'reminders', name: 'Przypomnienia', category: 'Na Macu', icon: 'reminders', description: 'Listy przypomnień z Maca: sprawdzam, co masz do zrobienia, i dodaję nowe.', state: 'available', kind: 'local', capabilities: ['Czytanie list', 'Dodawanie przypomnień po zgodzie'], tools: [tool(0, 'reminders_read', 'Czytanie list', 'reminders.read', 'auto'), tool(0, 'reminders_add', 'Dodawanie przypomnień', 'reminders.write', 'ask')] },
  { id: 'notes', name: 'Notatki', category: 'Na Macu', icon: 'notes', description: 'Notatki z Maca.', state: 'planned', kind: 'local', note: 'Dostęp do Notatek na Macu jest w planach.', capabilities: [], tools: [] },
  { id: 'messages', name: 'Wiadomości', category: 'Na Macu', icon: 'messages', description: 'Czytanie i pisanie wiadomości z Maca.', state: 'planned', kind: 'local', note: 'Wymaga osobnych uprawnień systemowych, dlatego dojdzie później.', capabilities: [], tools: [] },
  { id: 'weather', name: 'Pogoda', category: 'Dom i auto', icon: 'weather', description: 'Prognoza dla Warszawy i okolic, bez klucza i bez konta.', state: 'connected', kind: 'builtin', capabilities: ['Pogoda teraz', 'Prognoza na kilka dni', 'Szansa na deszcz'], tools: [tool(0, 'weather_get', 'Sprawdzanie pogody', 'weather.read', 'auto')] },
  { id: 'tesla', name: 'Tesla', category: 'Dom i auto', icon: 'tesla', description: 'Stan auta, bateria i klimatyzacja. Sterowanie tylko po Twojej zgodzie.', state: 'available', kind: 'oauth', capabilities: ['Poziom baterii i zasięg', 'Lokalizacja auta', 'Włączenie klimatyzacji po zgodzie'], tools: [tool(0, 'tesla_status', 'Odczyt stanu auta', 'tesla.read', 'auto'), tool(0, 'tesla_command', 'Sterowanie autem', 'tesla.control', 'ask')] },
  { id: 'home', name: 'Dom', category: 'Dom i auto', icon: 'home', description: 'Światła, ogrzewanie i czujniki w domu.', state: 'planned', kind: 'setup', note: 'Czeka na wybór systemu inteligentnego domu.', capabilities: [], tools: [] },
  { id: 'spotify', name: 'Muzyka', category: 'Muzyka', icon: 'spotify', description: 'Sterowanie odtwarzaniem i playlistami.', state: 'planned', kind: 'oauth', note: 'Dojdzie po stabilnych Konektorach Google.', capabilities: [], tools: [] },
  { id: 'github', name: 'GitHub', category: 'Programowanie', icon: 'github', description: 'Czytam Twoje repozytoria, zgłoszenia i zmiany.', state: 'available', kind: 'token', capabilities: ['Lista repozytoriów', 'Czytanie zgłoszeń i zmian'], tools: [tool(0, 'github_read', 'Czytanie repozytoriów', 'github.read', 'auto')] },
  { id: 'notion', name: 'Notion', category: 'Notatki i zadania', icon: 'notion', description: 'Strony i bazy w Notion.', state: 'planned', kind: 'oauth', note: 'Jeszcze nie zbudowany.', capabilities: [], tools: [] },
  { id: 'todoist', name: 'Zadania', category: 'Notatki i zadania', icon: 'todoist', description: 'Lista zadań z zewnętrznej aplikacji.', state: 'planned', kind: 'token', note: 'Jeszcze nie zbudowany.', capabilities: [], tools: [] },
  { id: 'dropbox', name: 'Pliki w chmurze', category: 'Notatki i zadania', icon: 'dropbox', description: 'Pliki z chmury dyskowej.', state: 'planned', kind: 'oauth', note: 'Jeszcze nie zbudowany.', capabilities: [], tools: [] },
  { id: 'slack', name: 'Slack', category: 'Komunikatory', icon: 'slack', description: 'Wiadomości z przestrzeni roboczej.', state: 'planned', kind: 'oauth', note: 'Jeszcze nie zbudowany.', capabilities: [], tools: [] },
  { id: 'discord', name: 'Discord', category: 'Komunikatory', icon: 'discord', description: 'Serwery i wiadomości prywatne.', state: 'planned', kind: 'token', note: 'Jeszcze nie zbudowany.', capabilities: [], tools: [] },
  { id: 'strava', name: 'Aktywność', category: 'Sport', icon: 'strava', description: 'Treningi i trasy biegowe.', state: 'planned', kind: 'oauth', note: 'Jeszcze nie zbudowany.', capabilities: [], tools: [] },
];

let current = null;

function iso(base, plusMin) { return new Date(base.getTime() + plusMin * 60000).toISOString(); }

function todayData(scene) {
  const n = new Date();
  const d0 = new Date(n.getFullYear(), n.getMonth(), n.getDate());
  const at = (dayOffset, h, m) => new Date(d0.getFullYear(), d0.getMonth(), d0.getDate() + dayOffset, h, m).toISOString();
  const calendar = [
    { title: 'Lekcja angielskiego', start: iso(n, -20), end: iso(n, 25), allDay: false, calendar: 'Szkoła' },
    { title: 'Trening piłki', start: iso(n, 95), end: iso(n, 155), allDay: false, calendar: 'Sport' },
    { title: 'Kolacja u babci', start: iso(n, 270), end: iso(n, 350), allDay: false, calendar: 'Rodzina' },
    { title: 'Sprawdzian z matmy', start: at(1, 8, 0), end: at(1, 8, 45), allDay: false, calendar: 'Szkoła' },
    { title: 'Dzień Nauczyciela', start: at(1, 0, 0), end: at(1, 23, 59), allDay: true, calendar: 'Szkoła' },
    { title: 'Pianino', start: at(1, 17, 0), end: at(1, 17, 45), allDay: false, calendar: 'Muzyka' },
  ];
  const day = i => at(i, 12, 0).slice(0, 10);
  const weather = scene === 'today-null' ? null : { place: 'Warszawa', now: { temp: 8, feelsLike: 5, sky: 'Przejaśnienia', wind_kmh: 14, rain_mm: 0 }, days: [{ date: day(0), min: 4, max: 9, rain_mm: 0.2, sky: 'Przejaśnienia' }, { date: day(1), min: 3, max: 7, rain_mm: 3.4, sky: 'Deszcz' }, { date: day(2), min: 2, max: 8, rain_mm: 0, sky: 'Pochmurno' }] };
  const reminders = scene === 'today-null' ? null : [{ title: 'Kupić taśmę do rakiet', due: at(0, 18, 0), list: 'Zakupy' }, { title: 'Oddać książki do biblioteki', due: at(1, 10, 0), list: 'Szkoła' }, { title: 'Naładować baterie do drukarki', due: null, list: 'Dom' }];
  return { generatedAt: n.toISOString(), calendar, weather, reminders };
}

export function createDemo(on, { scene = 'chat', mode = 'local' } = {}) {
  const now0 = Date.now();
  const st = { online: true, link: true, busy: false, policies: { ...POLICIES }, facts: { ...FACTS }, pending: {}, labels: { ...LABELS }, threads: {} };
  const timers = new Set();
  const conns = CONNECTORS.map(c => ({ ...c }));
  const pendingConn = { google: false };
  let threadId = getThreadId(), n = 0, counter = 0;
  const threads = {
    main: { title: 'Rozmowa z Concierge', updated: now0 - 4 * 60000, busy: false },
    t2: { title: 'Plan weekendu w Gzowie', updated: now0 - 3 * 3600000, busy: scene === 'threads' },
    t3: { title: 'Sprawdzian z matmy', updated: now0 - 26 * 3600000, busy: false },
    t4: { title: 'Silnik C6 czy D12', updated: now0 - 30 * 3600000, busy: false },
    t5: { title: 'Zakupy do drukarki 3D', updated: now0 - 4 * 86400000, busy: false },
    t6: { title: 'Pomysł na lot z kamerą', updated: now0 - 9 * 86400000, busy: false },
  };
  if (scene === 'many') for (let i = 7; i <= 13; i++) threads['t' + i] = { title: ['Pianino: repertuar na koncert', 'Trasa do Gzowa', 'Rozkład lekcji', 'Prezent dla babci', 'Notatki z fizyki', 'Projekt G-Micro', 'Biblioteka szkolna'][i - 7], updated: now0 - i * 86400000 * 1.4, busy: false };
  const HIST = {
    t2: [['u', 'Co zabrać do Gzowa na weekend?'], ['b', 'Rakiety modelarskie, drukarkę 3D i zapasowy ładunek wyrzucający. Pogoda w sobotę ma być spokojna.']],
    t3: [['u', 'Kiedy mam sprawdzian z matmy?'], ['b', 'W piątek o **8:00**. Przypomnę Ci w czwartek wieczorem.']],
    t4: [['u', 'Silnik C6 czy D12 do tej rakiety?'], ['b', 'Dla tej masy startowej bezpieczniejszy jest **C6-5**. D12 dałby za duże przyspieszenie.']],
  };
  const push = patch => { Object.assign(st, patch); on.state(JSON.parse(JSON.stringify(st))); };
  const pushThreads = () => push({ threads: JSON.parse(JSON.stringify(threads)) });
  const later = (ms, fn) => { const t = setTimeout(() => { timers.delete(t); fn(); }, ms); timers.add(t); };
  const ev = (e, h) => on.event({ ...e, thread: threadId, ...(h ? { history: true } : {}) });
  const rid = () => 'r' + (++n);
  const touch = () => { if (threads[threadId]) { threads[threadId].updated = Date.now(); threads[threadId].busy = false; } };
  const autoTitle = text => { const t = threads[threadId]; if (t && t.title === 'Nowa rozmowa') t.title = text.length > 34 ? text.slice(0, 33).trim() + '…' : text; };

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

  function historyOf(id) {
    if (id === 'main') { history(); return; }
    (HIST[id] || []).forEach(([role, text], i) => { if (role === 'u') ev({ type: 'user', text, cid: id + i }, 1); else ev({ type: 'text', text }, 1); });
  }

  function reply(text) {
    const r = rid();
    autoTitle(text);
    push({ busy: true });
    const done = () => { touch(); pushThreads(); push({ busy: false }); };
    if (/b[łl][aą]d|error|nie dzia/i.test(text)) {
      later(500, () => ev({ type: 'tool', name: 'calendar_list', summary: 'Czytam kalendarz', status: 'running', rid: r }));
      later(1500, () => { ev({ type: 'tool', name: 'calendar_list', summary: 'Czytam kalendarz', status: 'failed', error: 'Kalendarz nie odpowiada. Spróbuj za chwilę.', rid: r }); ev({ type: 'error', message: 'Nie udało się przeczytać kalendarza.' }); done(); });
    } else if (/dłu|long|weekend|plan/i.test(text)) {
      later(900, () => { ev({ type: 'text', text: LONG, rid: r }); done(); });
    } else if (/doda|dodaj|przypomnij|przenie/i.test(text)) {
      const what = text.replace(/^(dodaj|przypomnij mi|przenieś)\s*/i, '');
      later(700, () => { ev({ type: 'text', text: 'Mogę to dodać. Potrzebuję Twojej zgody.', rid: r }); touch(); pushThreads(); push({ busy: false, pending: { ['a' + r]: 'Dodać do kalendarza: ' + what + '?' } }); });
    } else if (/warszaw|nowego|szuka|pogod|news/i.test(text)) {
      later(500, () => ev({ type: 'tool', name: 'web_search', summary: 'Szukam w sieci: Warszawa dzisiaj', status: 'running', rid: r }));
      later(1700, () => ev({ type: 'tool', name: 'web_search', summary: 'Szukam w sieci: Warszawa dzisiaj', status: 'done', rid: r }));
      later(2300, () => { ev({ type: 'text', text: 'Dzisiaj w Warszawie:\n\n- Metro M2 jeździ rzadziej do 20:00 przez prace torowe.\n- Wieczorem **8°C** i przejaśnienia.\n- W Muzeum Techniki jest weekend z rakietami: https://muzeum.example.pl', rid: r }); done(); });
    } else if (/tydzie|kalendarz|mam |plan/i.test(text)) {
      later(500, () => ev({ type: 'tool', name: 'calendar_list', summary: 'Czytam kalendarz', status: 'running', rid: r }));
      later(1400, () => ev({ type: 'tool', name: 'calendar_list', summary: 'Przeczytałem kalendarz na 12-18 października', status: 'done', rid: r }));
      later(1900, () => { ev({ type: 'text', text: WEEK, rid: r }); done(); });
    } else {
      later(800, () => { ev({ type: 'text', text: 'Rozumiem. Mogę to zrobić albo wyszukać więcej szczegółów. Daj znać, co wolisz.', rid: r }); done(); });
    }
  }

  function buildScene() {
    if (threadId !== 'main') { historyOf(threadId); return; }
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

  const self = { push, approveHook: null };
  current = self;
  window.__demo = { push, on, st, reply, threads };

  const find = id => conns.find(c => c.id === id);
  const setGoogle = s => conns.filter(c => c.category === 'Google').forEach(c => { c.state = s; c.account = s === 'connected' ? 'jurek.demo@example.com' : undefined; });
  const view = c => ({ ...c });
  const stripped = c => ({ id: c.id, name: c.name, icon: c.icon, category: c.category, state: c.state, capabilities: [], tools: [] });

  const api = {
    mode,
    get threadId() { return threadId; },
    async start() { push({}); pushThreads(); setThreadId(threadId); buildScene(); },
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
    async listThreads() { return Object.entries(threads).map(([id, t]) => ({ id, ...t })).sort((a, b) => b.updated - a.updated); },
    async newThread() { const id = 'n' + (++counter); threads[id] = { title: 'Nowa rozmowa', updated: Date.now(), busy: false }; pushThreads(); return id; },
    async openThread(id) { timers.forEach(clearTimeout); timers.clear(); threadId = id; setThreadId(id); push({ busy: false }); historyOf(id); },
    async renameThread(id, title) { if (threads[id]) { threads[id].title = title; pushThreads(); } },
    async deleteThread(id) { delete threads[id]; pushThreads(); },
    async restoreThread(id) { threads[id] = threads[id] || { title: 'Przywrócona rozmowa', updated: Date.now(), busy: false }; pushThreads(); },
    async getToday() { return todayData(scene); },
    async listConnectors() { return { connectors: mode === 'relay' ? conns.map(stripped) : conns.map(view), labels: { ...LABELS } }; },
    async getPersona() { return { persona: persona.text, isDefault: persona.isDefault }; },
    async setPersona(text) { persona.text = text.trim() ? text : DEFAULT_PERSONA; persona.isDefault = !text.trim(); return { persona: persona.text, isDefault: persona.isDefault }; },
    async listSkills() { return skills.map(x => ({ ...x })); },
    async deleteSkill(name) { const i = skills.findIndex(x => x.name === name); if (i >= 0) skills.splice(i, 1); },
    async listCards() { return cards.map(x => ({ ...x })); },
    async addCard(c) { const d = String(c.pan || '').replace(/\D/g, ''); if (d.length < 13) throw new Error('Invalid card number'); cards.push({ id: 'c' + (cards.length + 2), label: c.label || 'Karta ' + d.slice(-4), brand: 'Visa', last4: d.slice(-4), limitPln: c.limitPln || 0 }); return cards[cards.length - 1]; },
    async deleteCard(id) { const i = cards.findIndex(x => x.id === id); if (i >= 0) cards.splice(i, 1); },
    refresh() {},
  };

  if (mode !== 'relay') {
    api.connectConnector = async id => {
      const c = find(id);
      await new Promise(r => setTimeout(r, 450));
      if (c.category === 'Google') {
        if (!pendingConn.google) return { needsSetup: true, help: 'Jednorazowa konfiguracja Google:\n1. Wejdź do konsoli Google Cloud i utwórz klienta OAuth typu "Aplikacja na komputer".\n2. Skopiuj identyfikator klienta i klucz tajny.\n3. Wklej je poniżej.\nhttps://console.cloud.google.com/apis/credentials', fields: [{ key: 'clientId', label: 'Identyfikator klienta', secret: false }, { key: 'clientSecret', label: 'Klucz tajny klienta', secret: true }] };
        setGoogle('connected');
        return { ok: true };
      }
      if (c.kind === 'token') return { needsToken: true, help: 'Wygeneruj osobisty token dostępu w ustawieniach konta i wklej go poniżej. Wystarczy uprawnienie tylko do odczytu.' };
      if (c.kind === 'oauth') { setTimeout(() => { c.state = 'connected'; c.account = 'jurek.demo@example.com'; }, 3500); return { authUrl: 'about:blank#demo' }; }
      c.state = 'connected'; c.account = 'Dostęp przyznany';
      return { ok: true };
    };
    api.setConnectorToken = async (id, token) => { const c = find(id); if (!token) throw new Error('empty'); c.state = 'connected'; c.account = 'Token zapisany'; return { ok: true }; };
    api.setupConnector = async (id, values) => { if (!values.clientId) throw new Error('missing'); pendingConn.google = true; return { ok: true }; };
    api.disconnectConnector = async id => { const c = find(id); if (c.category === 'Google') setGoogle('available'); else { c.state = 'available'; c.account = undefined; } return { ok: true }; };
  }
  return api;
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
