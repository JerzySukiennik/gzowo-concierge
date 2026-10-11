// Gzowo Concierge - saved logins for the screen agent: encrypted at rest, never shown to the model, typed only by the Mac app on a matching domain.
import crypto from 'node:crypto';
import { getSecret, putSecret } from './secrets.mjs';

const all = () => getSecret('logins') || [];
const cleanSite = s => String(s || '').trim().toLowerCase().replace(/^https?:\/\//, '').replace(/^www\./, '').split('/')[0];

export const listLogins = () => all().map(({ id, site, username, ask }) => ({ id, site, username, ask: ask !== false }));

export function saveLogin({ id, site, username, password, ask }) {
  const s = cleanSite(site);
  if (!/^[a-z0-9.-]+\.[a-z]{2,}$/.test(s)) throw new Error('Podaj domenę, np. google.com');
  const list = all();
  const existing = id ? list.find(x => x.id === id) : list.find(x => x.site === s && x.username === String(username || '').trim());
  if (existing) {
    existing.site = s;
    if (username !== undefined) existing.username = String(username).trim();
    if (password) existing.password = String(password);
    if (ask !== undefined) existing.ask = !!ask;
  } else {
    if (!String(username || '').trim() || !password) throw new Error('Podaj login i hasło.');
    list.push({ id: crypto.randomUUID(), site: s, username: String(username).trim(), password: String(password), ask: ask !== false });
  }
  putSecret('logins', list);
  return listLogins();
}

export function removeLogin(id) {
  putSecret('logins', all().filter(x => x.id !== id));
  return listLogins();
}

export const findLogin = site => {
  const s = cleanSite(site);
  return all().find(x => x.site === s) || all().find(x => s.endsWith('.' + x.site) || x.site.endsWith('.' + s)) || null;
};

export const hostMatches = (url, site) => {
  try { const u = new URL(url); const h = u.hostname.toLowerCase(); return u.protocol === 'https:' && (h === site || h.endsWith('.' + site)); } catch { return false; }
};
