// Gzowo Concierge - icon set in the SF Symbols idiom: 24 grid, 1.75 stroke, round caps, outline plus filled variants, original connector pictograms, bot mini-logo markup.
const MIC = '<rect x="9.25" y="2.75" width="5.5" height="11" rx="2.75"/><path d="M6 11v.5a6 6 0 0 0 12 0V11M12 17.5v3M8.75 20.75h6.5"/>';
let uid = 0;

const P = {
  send: { o: '<path d="M12 19.25V5.25M5.75 11.25 12 5l6.25 6.25"/>' },
  wave: { o: '<path d="M4.5 9.75v4.5M8.25 6.5v11M12 3.5v17M15.75 7.5v9M19.5 10v4"/>', weight: 2.2, f: '<path d="M4.5 9.75v4.5M8.25 6.5v11M12 3.5v17M15.75 7.5v9M19.5 10v4"/>', fw: 2.7 },
  sliders: { o: '<path d="M4 7h8.5M17.5 7H20M4 17h2.5M11.5 17H20"/><circle cx="15" cy="7" r="2.5"/><circle cx="9" cy="17" r="2.5"/>', f: '<path d="M4 7h8.5M17.5 7H20M4 17h2.5M11.5 17H20"/><circle cx="15" cy="7" r="2.75"/><circle cx="9" cy="17" r="2.75"/>' },
  close: { o: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>' },
  calendar: { o: '<rect x="4" y="5.5" width="16" height="14.5" rx="4"/><path d="M4 10.5h16M8.5 3.5v3M15.5 3.5v3"/>', f: '<path d="M4 9.1V9a3.5 3.5 0 0 1 3.5-3.5h9A3.5 3.5 0 0 1 20 9v.1z"/><path d="M4 11.4h16v5.1A3.5 3.5 0 0 1 16.5 20h-9A3.5 3.5 0 0 1 4 16.5z"/><rect x="7.75" y="3" width="1.5" height="4" rx=".75"/><rect x="14.75" y="3" width="1.5" height="4" rx=".75"/>', fw: 0 },
  calendarPlus: { o: '<rect x="4" y="5.5" width="16" height="14.5" rx="4"/><path d="M4 10.5h16M8.5 3.5v3M15.5 3.5v3M12 13.25v4.5M9.75 15.5h4.5"/>' },
  globe: { o: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.4 2.3 3.6 5.1 3.6 8.5s-1.2 6.2-3.6 8.5c-2.4-2.3-3.6-5.1-3.6-8.5S9.6 5.8 12 3.5z"/>' },
  bookmark: { o: '<path d="M8 4.5h8A1.5 1.5 0 0 1 17.5 6v13.75l-5.5-4.1-5.5 4.1V6A1.5 1.5 0 0 1 8 4.5z"/>', f: '<path d="M8 4.5h8A1.5 1.5 0 0 1 17.5 6v13.75l-5.5-4.1-5.5 4.1V6A1.5 1.5 0 0 1 8 4.5z"/>' },
  spark: { o: '<path d="M10.75 4.75l1.55 4.45 4.45 1.55-4.45 1.55-1.55 4.45-1.55-4.45L4.75 10.75l4.45-1.55z"/><path d="M18 3.75v3M16.5 5.25h3M17.5 15.75v3M16 17.25h3"/>', f: '<path d="M10.75 4.75l1.55 4.45 4.45 1.55-4.45 1.55-1.55 4.45-1.55-4.45L4.75 10.75l4.45-1.55z"/><path d="M18 3.75v3M16.5 5.25h3M17.5 15.75v3M16 17.25h3"/>' },
  card: { o: '<rect x="3.5" y="6" width="17" height="12" rx="3.5"/><path d="M3.5 10.25h17M7 14.5h3"/>', f: '<path d="M3.5 9.4A3.5 3.5 0 0 1 7 6h10a3.5 3.5 0 0 1 3.5 3.4z"/><path d="M3.5 11.6h17v2.9A3.5 3.5 0 0 1 17 18H7a3.5 3.5 0 0 1-3.5-3.5z"/>', fw: 0 },
  check: { o: '<path d="M5.5 12.5l4.3 4.3L18.5 8"/>' },
  trash: { o: '<path d="M5 7h14M9.5 7V5.2c0-.4.3-.7.7-.7h3.6c.4 0 .7.3.7.7V7M7 7l.8 11.2c.1.8.7 1.3 1.5 1.3h5.4c.8 0 1.4-.5 1.5-1.3L17 7M10.5 11v5M13.5 11v5"/>' },
  down: { o: '<path d="M12 5v13.5M6.25 12.75 12 18.5l5.75-5.75"/>' },
  copy: { o: '<rect x="8.5" y="8.5" width="11" height="11" rx="3"/><path d="M15.5 8.5V7A2.5 2.5 0 0 0 13 4.5H7A2.5 2.5 0 0 0 4.5 7v6A2.5 2.5 0 0 0 7 15.5h1.5"/>' },
  phone: { o: '<rect x="7" y="3" width="10" height="18" rx="3"/><path d="M10.8 17.6h2.4"/>', f: '<rect x="7" y="3" width="10" height="18" rx="3"/>' },
  alert: { o: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.75v5"/><circle cx="12" cy="16.2" r=".55" fill="currentColor"/>', f: '<path fill-rule="evenodd" d="M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17zm0 4.1a.95.95 0 0 1 .95.95v4a.95.95 0 0 1-1.9 0v-4A.95.95 0 0 1 12 7.6zm0 7.95a1.1 1.1 0 1 1 0 2.2 1.1 1.1 0 0 1 0-2.2z"/>', fw: 0 },
  retry: { o: '<path d="M19.5 11A7.5 7.5 0 1 0 17.3 16.4"/><path d="M19.8 5v6h-6"/>' },
  mic: { o: MIC, f: '<rect x="9.25" y="2.75" width="5.5" height="11" rx="2.75"/><path fill="none" d="M6 11v.5a6 6 0 0 0 12 0V11M12 17.5v3M8.75 20.75h6.5"/>' },
  micOff: { slash: 'M4.5 4 19.5 20', o: MIC, f: '<rect x="9.25" y="2.75" width="5.5" height="11" rx="2.75"/><path fill="none" d="M6 11v.5a6 6 0 0 0 12 0V11M12 17.5v3M8.75 20.75h6.5"/>' },
  stop: { o: '<rect x="7" y="7" width="10" height="10" rx="2.8"/>', solid: true },
  plus: { o: '<path d="M12 5.5v13M5.5 12h13"/>' },
  paste: { o: '<rect x="6" y="5.5" width="12" height="15" rx="3"/><path d="M9.5 5.5V5A1.5 1.5 0 0 1 11 3.5h2A1.5 1.5 0 0 1 14.5 5v.5M9.5 11.5h5M9.5 15h3"/>' },
  face: { o: '<circle cx="12" cy="12" r="8.5"/><path d="M8.75 14.1a4 4 0 0 0 6.5 0"/><circle cx="9.25" cy="10" r=".7" fill="currentColor"/><circle cx="14.75" cy="10" r=".7" fill="currentColor"/>' },
  shield: { o: '<path d="M12 3.5l6.5 2.5v5.25c0 4.1-2.7 7.3-6.5 9.25-3.8-1.95-6.5-5.15-6.5-9.25V6z"/><path d="M9 12l2.2 2.2L15.2 10"/>' },
  user: { o: '<circle cx="12" cy="8.5" r="3.75"/><path d="M4.75 19.5c.9-3.6 3.9-5.5 7.25-5.5s6.35 1.9 7.25 5.5"/>', f: '<circle cx="12" cy="8.5" r="3.9"/><path d="M4.5 19.75c.8-3.7 3.9-5.9 7.5-5.9s6.7 2.2 7.5 5.9z"/>' },
  chat: { o: '<path d="M5 7A3 3 0 0 1 8 4h8a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3h-5.25L7 19.5V16A3 3 0 0 1 5 13z"/>' },
  compose: { o: '<path d="M11 5H8a3.5 3.5 0 0 0-3.5 3.5v7A3.5 3.5 0 0 0 8 19h7a3.5 3.5 0 0 0 3.5-3.5V13"/><path d="M17.9 3.9a1.9 1.9 0 0 1 2.7 2.7l-7.3 7.3-3.4.7.7-3.4z"/>' },
  menu: { o: '<path d="M4.5 8h15M4.5 16h10"/>' },
  sidebar: { o: '<rect x="3.5" y="4.5" width="17" height="15" rx="4"/><path d="M9.5 4.5v15"/>' },
  sun: { o: '<circle cx="12" cy="12" r="3.75"/><path d="M12 3.5v2M12 18.5v2M3.5 12h2M18.5 12h2M6 6l1.4 1.4M16.6 16.6L18 18M18 6l-1.4 1.4M7.4 16.6L6 18"/>', f: '<circle cx="12" cy="12" r="4.25"/><path d="M12 3.5v2M12 18.5v2M3.5 12h2M18.5 12h2M6 6l1.4 1.4M16.6 16.6L18 18M18 6l-1.4 1.4M7.4 16.6L6 18"/>' },
  cloud: { o: '<path d="M7.75 18.5h8.5a4 4 0 0 0 .6-7.95 5.5 5.5 0 0 0-10.5 1.6A3.25 3.25 0 0 0 7.75 18.5z"/>', f: '<path d="M7.75 18.5h8.5a4 4 0 0 0 .6-7.95 5.5 5.5 0 0 0-10.5 1.6A3.25 3.25 0 0 0 7.75 18.5z"/>' },
  cloudSun: { o: '<circle cx="8.25" cy="8.5" r="2.5"/><path d="M8.25 3.5v1M3.5 8.5h1M4.9 5.15l.7.7M11.6 5.15l-.7.7"/><path d="M9 19.5h7.5a3.75 3.75 0 0 0 .5-7.46 5 5 0 0 0-9.5 1.46A3.1 3.1 0 0 0 9 19.5z"/>' },
  rain: { o: '<path d="M7.75 15.5h8.5a4 4 0 0 0 .6-7.95 5.5 5.5 0 0 0-10.5 1.6A3.25 3.25 0 0 0 7.75 15.5z"/><path d="M8.5 18.5l-.75 2M12.5 18.5l-.75 2M16.5 18.5l-.75 2"/>' },
  snow: { o: '<path d="M7.75 15.5h8.5a4 4 0 0 0 .6-7.95 5.5 5.5 0 0 0-10.5 1.6A3.25 3.25 0 0 0 7.75 15.5z"/><path d="M8.25 18.75h.01M12 19.75h.01M15.75 18.75h.01"/>' },
  wind: { o: '<path d="M4.5 9.5h9a2.5 2.5 0 1 0-2.4-3.2M4.5 14h12a2.5 2.5 0 1 1-2.3 3.4M4.5 11.75h6"/>' },
  drop: { o: '<path d="M12 3.75c3 3.4 5 6 5 8.9a5 5 0 0 1-10 0c0-2.9 2-5.5 5-8.9z"/>' },
  mail: { o: '<rect x="3.5" y="5.5" width="17" height="13" rx="3.5"/><path d="M4.5 8.25L12 13.5l7.5-5.25"/>', f: '<path fill-rule="evenodd" d="M7 5.5h10A3.5 3.5 0 0 1 20.5 9v6a3.5 3.5 0 0 1-3.5 3.5H7A3.5 3.5 0 0 1 3.5 15V9A3.5 3.5 0 0 1 7 5.5zM5.1 8.1l6.3 4.4a1 1 0 0 0 1.2 0l6.3-4.4-.9-1.3L12 11.3 6 6.8z"/>', fw: 0 },
  doc: { o: '<path d="M8 3.5h5.5L19 9v8.5a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3v-11a3 3 0 0 1 3-3z"/><path d="M13.5 3.5V8a1 1 0 0 0 1 1H19M8.5 13h7M8.5 16.5h4.5"/>' },
  drive: { o: '<rect x="3.5" y="13" width="17" height="6.5" rx="3"/><path d="M5.5 13l1.9-6.9a2 2 0 0 1 1.9-1.45h5.4a2 2 0 0 1 1.9 1.45L18.5 13M7.5 16.25h.01M10.5 16.25h.01"/>' },
  car: { o: '<path d="M3.75 15.25v-1.8c0-.55.2-1.1.55-1.5l1.9-2.2a2.7 2.7 0 0 1 2.1-1h6.4c.75 0 1.45.3 1.95.85l2.1 2.35c.35.4.55.9.55 1.45v1.85M3.75 15.25h2.4M9.35 15.25h5.3M17.85 15.25h2.4"/><circle cx="7.75" cy="15.75" r="1.6"/><circle cx="16.25" cy="15.75" r="1.6"/><path d="M8.25 8.75l-1.1 3.25h10.2"/>' },
  branch: { o: '<circle cx="7" cy="6" r="2.25"/><circle cx="7" cy="18" r="2.25"/><circle cx="17" cy="9" r="2.25"/><path d="M7 8.25v7.5M17 11.25c0 3-3.5 3.25-8.5 5"/>' },
  bell: { o: '<path d="M6.5 16.5V11a5.5 5.5 0 0 1 11 0v5.5l1.25 1.5H5.25z"/><path d="M10 20.25a2 2 0 0 0 4 0"/>', f: '<path d="M6.5 16.5V11a5.5 5.5 0 0 1 11 0v5.5l1.25 1.5H5.25z"/><path d="M10 20.25a2 2 0 0 0 4 0"/>' },
  note: { o: '<rect x="4.5" y="4.5" width="15" height="15" rx="4"/><path d="M8.5 9h7M8.5 12.5h7M8.5 16h3.5"/>' },
  music: { o: '<path d="M9.5 17.5V6.25l9-2v11.25"/><circle cx="7" cy="17.5" r="2.5"/><circle cx="16.5" cy="15.5" r="2.5"/>' },
  headphones: { o: '<path d="M4.5 15v-3a7.5 7.5 0 0 1 15 0v3"/><rect x="3.5" y="14.5" width="4" height="6" rx="2"/><rect x="16.5" y="14.5" width="4" height="6" rx="2"/>' },
  cube: { o: '<path d="M12 3.5l7.5 4.25v8.5L12 20.5l-7.5-4.25v-8.5z"/><path d="M4.5 7.75L12 12l7.5-4.25M12 12v8.5"/>' },
  hash: { o: '<path d="M9.25 4.5l-1.5 15M16.25 4.5l-1.5 15M4.5 9h15M4 15h15"/>' },
  gamepad: { o: '<path d="M7.5 7.5h9a4.5 4.5 0 0 1 4.4 3.6l.8 4a2.6 2.6 0 0 1-4.5 2.2l-1.7-2H8.5l-1.7 2a2.6 2.6 0 0 1-4.5-2.2l.8-4a4.5 4.5 0 0 1 4.4-3.6z"/><path d="M8 11v3M6.5 12.5h3M16 12h.01M18 13.5h.01"/>' },
  listCheck: { o: '<path d="M4.5 7l1.5 1.5L8.75 5.5M4.5 16.5L6 18l2.75-3M12 7.5h7.5M12 17h7.5"/>' },
  route: { o: '<circle cx="6.5" cy="17.5" r="2"/><circle cx="17.5" cy="6.5" r="2"/><path d="M8.5 17.5h5.25a3 3 0 0 0 0-6h-3.5a3 3 0 0 1 0-6H15.5"/>' },
  home: { o: '<path d="M4.5 11.25L12 4.5l7.5 6.75V18a2 2 0 0 1-2 2h-3.5v-5h-4v5H6.5a2 2 0 0 1-2-2z"/>' },
  box: { o: '<path d="M3.75 9.5l2-4h12.5l2 4M3.75 9.5V18a2 2 0 0 0 2 2h12.5a2 2 0 0 0 2-2V9.5zM9.5 13h5"/>' },
  link: { o: '<path d="M10 14a3.5 3.5 0 0 0 5 0l3-3a3.5 3.5 0 0 0-5-5l-.75.75M14 10a3.5 3.5 0 0 0-5 0l-3 3a3.5 3.5 0 0 0 5 5l.75-.75"/>' },
  key: { o: '<circle cx="8" cy="15.5" r="3.5"/><path d="M10.5 13l8-8M15.5 8l2.5 2.5M13.5 10l1.5 1.5"/>' },
  search: { o: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/>' },
  chevR: { o: '<path d="M9.5 6l6 6-6 6"/>' },
  chevL: { o: '<path d="M14.5 6l-6 6 6 6"/>' },
  external: { o: '<path d="M8 16L16.5 7.5M9.5 7.5h7v7"/>' },
  keyboard: { o: '<rect x="3.5" y="6.5" width="17" height="11" rx="3.5"/><path d="M7.5 10.25h.01M10.5 10.25h.01M13.5 10.25h.01M16.5 10.25h.01M8 14h8"/>' },
  dots: { o: '<path d="M6 12h.01M12 12h.01M18 12h.01"/>', weight: 2.6 },
};

const CONN = { gmail: 'mail', docs: 'doc', drive: 'drive', tesla: 'car', weather: 'cloudSun', github: 'branch', reminders: 'bell', notes: 'note', music: 'music', spotify: 'headphones', notion: 'cube', slack: 'hash', discord: 'gamepad', todoist: 'listCheck', strava: 'route', home: 'home', messages: 'chat', dropbox: 'box', calendar: 'calendar', web: 'globe', memory: 'bookmark', cards: 'card' };

export function icon(name, size = 20, filled = false, weight) {
  const d = P[name] || P.spark;
  const f = (filled && d.f) || null;
  const sw = weight || (f && d.fw !== undefined ? d.fw : d.solid ? 0 : d.weight || 1.75);
  const fill = f || d.solid ? 'currentColor' : 'none';
  let body = f || d.o;
  if (d.slash) {
    const id = 'im' + (++uid);
    body = `<mask id="${id}" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff"/><path d="${d.slash}" fill="none" stroke="#000" stroke-width="4.6" stroke-linecap="round"/></mask><g mask="url(#${id})">${body}</g><path fill="none" d="${d.slash}"/>`;
  }
  return `<svg class="ic" width="${size}" height="${size}" viewBox="0 0 24 24" fill="${fill}" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${body}</svg>`;
}

export function paintIcons(root = document) {
  root.querySelectorAll('[data-ic]').forEach(n => {
    n.innerHTML = icon(n.dataset.ic, Number(n.dataset.size) || 20, n.dataset.filled === '1');
    n.removeAttribute('data-ic');
  });
}

export function connIcon(key = '', name = '', size = 22) {
  if (CONN[key] && P[CONN[key]]) return icon(CONN[key], size);
  const ch = (name || key || '?').trim().charAt(0).toUpperCase() || '?';
  return `<span class="mono" style="font-size:${Math.round(size * 0.82)}px" aria-hidden="true">${ch.replace(/[<>&]/g, '')}</span>`;
}

export function toolIcon(name = '') {
  if (name.startsWith('calendar')) return 'calendar';
  if (name.startsWith('web')) return 'globe';
  if (name === 'remember' || name === 'forget' || name.startsWith('memory')) return 'bookmark';
  if (name.startsWith('payment')) return 'card';
  const base = name.split(/[._]/)[0];
  if (CONN[base]) return CONN[base];
  return 'spark';
}

export function skyIcon(sky = '') {
  const s = String(sky).toLowerCase();
  if (/snow|śnieg|snieg/.test(s)) return 'snow';
  if (/rain|deszcz|opad|ulew|shower|drizzle|burz|storm/.test(s)) return 'rain';
  if (/clear|sun|słon|slon|bezchmur|pogod/.test(s) && !/part|cloud|zachm|pochm/.test(s)) return 'sun';
  if (/part|przej|cloud|zachm|pochm|mglis|fog|mgł|overcast/.test(s)) return /part|przej/.test(s) ? 'cloudSun' : 'cloud';
  return 'cloudSun';
}

export const orbSvg = (cls = '', face = 'neutral') => `<span class="orb ${cls}" aria-hidden="true"><i class="ob-arc"></i><canvas class="orb-c" data-face="${face}"></canvas></span>`;
