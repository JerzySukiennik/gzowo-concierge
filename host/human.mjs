// Gzowo Concierge - human-friendly Polish date formatting for status lines.
const MON = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
const DOW = ['nd', 'pn', 'wt', 'śr', 'czw', 'pt', 'sob'];

function parse(s) {
  const m = String(s || '').match(/^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?/);
  if (!m) return null;
  return { y: +m[1], mo: +m[2] - 1, d: +m[3], h: m[4] === undefined ? null : +m[4], mi: m[4] === undefined ? null : +m[5], s: +(m[6] || 0) };
}

export function day(s) {
  const p = parse(s);
  if (!p) return String(s || '');
  return `${p.d} ${MON[p.mo]}`;
}

export function when(s) {
  const p = parse(s);
  if (!p) return String(s || '');
  const dow = DOW[new Date(p.y, p.mo, p.d).getDay()];
  const t = p.h === null ? '' : `, ${String(p.h).padStart(2, '0')}:${String(p.mi).padStart(2, '0')}`;
  return `${dow} ${p.d} ${MON[p.mo]}${t}`;
}

export function range(from, to) {
  const a = parse(from), b = parse(to);
  if (!a || !b) return `${from} - ${to}`;
  let end = new Date(b.y, b.mo, b.d, b.h || 0, b.mi || 0, b.s || 0);
  if (!b.h || (b.h === 0 && b.mi === 0 && b.s === 0)) end = new Date(end.getTime() - 1000);
  const start = new Date(a.y, a.mo, a.d);
  const same = start.getFullYear() === end.getFullYear() && start.getMonth() === end.getMonth() && start.getDate() === end.getDate();
  const e = `${end.getDate()} ${MON[end.getMonth()]}`;
  return same ? day(from) : `${day(from)} - ${e}`;
}
