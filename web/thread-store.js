// Gzowo Concierge - active conversation id, remembered in localStorage and in the URL hash (#t=<id>) without touching other hash params.
const KEY = 'cthread';

function params() { return new URLSearchParams(location.hash.replace(/^#/, '')); }

export function getThreadId() {
  const h = params().get('t');
  if (h) return h;
  try { return localStorage.getItem(KEY) || 'main'; } catch { return 'main'; }
}

export function setThreadId(id) {
  try { localStorage.setItem(KEY, id); } catch {}
  const p = params();
  p.set('t', id);
  try { history.replaceState(null, '', location.pathname + location.search + '#' + p.toString()); } catch {}
}
