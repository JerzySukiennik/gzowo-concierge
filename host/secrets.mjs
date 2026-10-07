// Gzowo Concierge - encrypted secret storage for connector tokens (same AES-GCM and Keychain key as the card vault).
import { store } from './db.mjs';
import { sealJson, openJson } from './vault.mjs';

export const putSecret = (key, value) => store.setSetting(`secret:${key}`, sealJson(value));
export const delSecret = key => store.setSetting(`secret:${key}`, null);
export function getSecret(key) {
  const sealed = store.getSetting(`secret:${key}`, null);
  if (!sealed) return null;
  try { return openJson(sealed); } catch { return null; }
}
