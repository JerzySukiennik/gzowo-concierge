// Gzowo Concierge - stroke icon set in the SF Symbols idiom (24 grid, round caps, currentColor).
const P = {
  send: '<path d="M12 19V5.5M6 11.5l6-6 6 6"/>',
  sliders: '<path d="M4 7h8.5M17.5 7H20M4 17h2.5M11.5 17H20"/><circle cx="15" cy="7" r="2.5"/><circle cx="9" cy="17" r="2.5"/>',
  close: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
  calendar: '<rect x="4" y="5.5" width="16" height="14.5" rx="3.5"/><path d="M4 10.5h16M8.5 3.5v3.5M15.5 3.5v3.5"/>',
  calendarPlus: '<rect x="4" y="5.5" width="16" height="14.5" rx="3.5"/><path d="M4 10.5h16M8.5 3.5v3.5M15.5 3.5v3.5M12 13v5M9.5 15.5h5"/>',
  globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.4 2.3 3.6 5.1 3.6 8.5s-1.2 6.2-3.6 8.5c-2.4-2.3-3.6-5.1-3.6-8.5S9.6 5.8 12 3.5z"/>',
  bookmark: '<path d="M7.5 4.5h9A1.5 1.5 0 0 1 18 6v14l-6-4.3L6 20V6a1.5 1.5 0 0 1 1.5-1.5z"/>',
  spark: '<path d="M12 3.5l1.9 5.1 5.1 1.9-5.1 1.9L12 17.5l-1.9-5.1L5 10.5l5.1-1.9z"/><path d="M18.5 16.5v3M17 18h3"/>',
  card: '<rect x="3.5" y="6" width="17" height="12" rx="3"/><path d="M3.5 10.5h17M7 14.5h3"/>',
  check: '<path d="M5.5 12.5l4.3 4.3L18.5 8"/>',
  trash: '<path d="M5 7h14M9.5 7V5.2c0-.4.3-.7.7-.7h3.6c.4 0 .7.3.7.7V7M7 7l.8 11.2c.1.8.7 1.3 1.5 1.3h5.4c.8 0 1.4-.5 1.5-1.3L17 7M10.5 11v5M13.5 11v5"/>',
  down: '<path d="M12 5v13.5M6 12.5l6 6 6-6"/>',
  copy: '<rect x="8.5" y="8.5" width="11" height="11" rx="2.8"/><path d="M15.5 8.5V7a2.5 2.5 0 0 0-2.5-2.5H7A2.5 2.5 0 0 0 4.5 7v6A2.5 2.5 0 0 0 7 15.5h1.5"/>',
  phone: '<rect x="7" y="3" width="10" height="18" rx="2.8"/><path d="M10.8 17.6h2.4"/>',
  alert: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.6v5.2"/><circle cx="12" cy="16.2" r=".6" fill="currentColor"/>',
  retry: '<path d="M19.5 11A7.5 7.5 0 1 0 17.3 16.4"/><path d="M19.8 5v6h-6"/>',
  face: '<rect x="6.8" y="6.6" width="2.6" height="6" rx="1.3"/><rect x="14.6" y="6.6" width="2.6" height="6" rx="1.3"/><path d="M9.6 17h4.8"/>',
  mic: '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/>',
  micOff: '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5M4 4l16 16"/>',
  stop: '<rect x="7" y="7" width="10" height="10" rx="2.6"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  paste: '<rect x="6" y="5.5" width="12" height="15" rx="2.8"/><path d="M9.5 5.5V5a1.5 1.5 0 0 1 1.5-1.5h2A1.5 1.5 0 0 1 14.5 5v.5M9.5 11.5h5M9.5 15h3"/>',
};

export function icon(name, size = 20) {
  return `<svg class="ic" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${P[name] || P.spark}</svg>`;
}

export function toolIcon(name = '') {
  if (name.startsWith('calendar')) return 'calendar';
  if (name.startsWith('web')) return 'globe';
  if (name === 'remember' || name === 'forget') return 'bookmark';
  if (name.startsWith('payment')) return 'card';
  return 'spark';
}

export const orbSvg = (cls = '') => `<svg class="orb ${cls}" viewBox="0 0 32 32" aria-hidden="true" focusable="false"><circle class="o-ring" cx="16" cy="16" r="13"/><circle class="o-arc" cx="16" cy="16" r="13" pathLength="100"/><circle class="o-core" cx="16" cy="16" r="7"/></svg>`;
