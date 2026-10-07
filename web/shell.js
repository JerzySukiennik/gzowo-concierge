// Gzowo Concierge - bridge to the native macOS shell: post() to WKWebView, debounced state reports that only fire on change.
const handler = () => window.webkit?.messageHandlers?.concierge;
const cur = { online: true, busy: false, pending: 0, live: 'idle', thread: 'main' };
let timer = 0, lastKey = '';

export function post(obj) {
  try { handler()?.postMessage(obj); } catch {}
}

export const isShell = () => document.documentElement.dataset.shell === 'mac';

export function report(patch) {
  Object.assign(cur, patch);
  clearTimeout(timer);
  timer = setTimeout(() => {
    const key = JSON.stringify(cur);
    if (key === lastKey) return;
    lastKey = key;
    post({ type: 'state', online: !!cur.online, busy: !!cur.busy, pending: cur.pending | 0, live: cur.live, thread: cur.thread });
  }, 120);
}
