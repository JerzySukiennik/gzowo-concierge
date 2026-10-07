// Gzowo Concierge - conversation list for the sidebar: recency groups, search when many, unread dot, running ring, delete for the open conversation.
import { icon } from './icons.js';
import { relTime, toMs } from './glass.js';

const SEEN = 'cseen';
const load = () => { try { return JSON.parse(localStorage.getItem(SEEN) || '{}'); } catch { return {}; } };
const save = o => { try { localStorage.setItem(SEEN, JSON.stringify(o)); } catch {} };

export function createThreads({ list, searchWrap, onOpen, onDelete }) {
  const input = searchWrap.querySelector('input');
  let data = {}, active = 'main', sig = '', filter = '', seen = load(), first = true;

  function entries() {
    return Object.entries(data).map(([id, t]) => ({ id, title: t.title || 'Rozmowa', updated: toMs(t.updated), busy: !!t.busy })).sort((a, b) => b.updated - a.updated);
  }

  function group(ms, now) {
    const d = new Date(now), t0 = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    return ms >= t0 ? 'Dzisiaj' : ms >= t0 - 86400000 ? 'Wczoraj' : 'Wcześniej';
  }

  function isUnread(t) { return t.id !== active && seen[t.id] != null && t.updated > seen[t.id]; }

  function render(force) {
    const now = Date.now();
    const all = entries();
    if (first && all.length) { all.forEach(t => { if (seen[t.id] == null) seen[t.id] = t.updated; }); save(seen); first = false; }
    const many = all.length > 8;
    searchWrap.hidden = !many;
    const f = many ? filter.trim().toLowerCase() : '';
    const items = all.filter(t => !f || t.title.toLowerCase().includes(f));
    const s = JSON.stringify([items.map(t => [t.id, t.title, t.busy, isUnread(t), relTime(t.updated, now)]), active, f]);
    if (!force && s === sig) return;
    sig = s;
    list.textContent = '';
    if (!items.length) { const p = document.createElement('p'); p.className = 'foot flush'; p.textContent = f ? 'Nic nie pasuje do "' + filter.trim() + '".' : 'Brak rozmów.'; list.append(p); return; }
    let cur = '';
    items.forEach(t => {
      const g = group(t.updated, now);
      if (g !== cur) { cur = g; const h = document.createElement('h3'); h.className = 'tgroup'; h.textContent = g; list.append(h); }
      const row = document.createElement('div');
      row.className = 'trow' + (t.id === active ? ' active' : '');
      row.setAttribute('role', 'listitem');
      const b = document.createElement('button');
      b.type = 'button'; b.className = 't-main';
      b.setAttribute('aria-current', t.id === active ? 'true' : 'false');
      b.innerHTML = '<span class="t-title"></span><span class="t-meta"><span class="t-time"></span><span class="t-st" aria-hidden="true"></span></span>';
      b.querySelector('.t-title').textContent = t.title;
      b.querySelector('.t-time').textContent = relTime(t.updated, now);
      const st = b.querySelector('.t-st');
      if (t.busy) { st.innerHTML = '<i class="spin"></i>'; b.setAttribute('aria-label', t.title + ', w toku'); }
      else if (isUnread(t)) { st.innerHTML = '<i class="t-dot"></i>'; b.setAttribute('aria-label', t.title + ', nowe'); }
      b.onclick = () => onOpen(t.id);
      row.append(b);
      if (t.id === active && t.id !== 'main') {
        const d = document.createElement('button');
        d.type = 'button'; d.className = 't-del icon-btn small'; d.setAttribute('aria-label', 'Usuń rozmowę: ' + t.title);
        d.innerHTML = icon('trash', 16);
        d.onclick = () => onDelete(t.id, t.title);
        row.append(d);
      }
      list.append(row);
    });
  }

  input.oninput = () => { filter = input.value; render(true); };
  setInterval(() => { if (!document.hidden) render(); }, 30000);

  return {
    set(threads) { data = threads || {}; render(); },
    setActive(id) {
      active = id;
      const t = data[id]; if (t) { seen[id] = toMs(t.updated); save(seen); }
      render(true);
    },
    markSeen() { const t = data[active]; if (t) { seen[active] = toMs(t.updated); save(seen); } },
    title: id => (data[id] && data[id].title) || '',
    has: id => id in data,
    firstOther: id => entries().find(t => t.id !== id)?.id || 'main',
  };
}
