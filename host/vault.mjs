// Gzowo Concierge - card vault: AES-256-GCM blobs in SQLite, master key in the macOS Keychain.
// Full card data never leaves this module except through revealForCheckout(), which only the local payment executor may call.
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { store } from './db.mjs';

const SERVICE = 'fun.gzowo.concierge.vault';
const ACCOUNT = 'master';
let keyCache = null;

function masterKey() {
  if (keyCache) return keyCache;
  try {
    keyCache = Buffer.from(execFileSync('security', ['find-generic-password', '-s', SERVICE, '-a', ACCOUNT, '-w'], { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(), 'hex');
  } catch {
    const hex = crypto.randomBytes(32).toString('hex');
    execFileSync('security', ['add-generic-password', '-s', SERVICE, '-a', ACCOUNT, '-w', hex, '-U'], { stdio: 'ignore' });
    keyCache = Buffer.from(hex, 'hex');
  }
  if (keyCache.length !== 32) throw new Error('Vault key in Keychain is invalid');
  return keyCache;
}

function seal(obj) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', masterKey(), iv);
  const ct = Buffer.concat([c.update(JSON.stringify(obj), 'utf8'), c.final()]);
  return Buffer.concat([iv, c.getAuthTag(), ct]).toString('base64');
}

function open(b64) {
  const buf = Buffer.from(b64, 'base64');
  const d = crypto.createDecipheriv('aes-256-gcm', masterKey(), buf.subarray(0, 12));
  d.setAuthTag(buf.subarray(12, 28));
  return JSON.parse(Buffer.concat([d.update(buf.subarray(28)), d.final()]).toString('utf8'));
}

function luhn(pan) {
  let sum = 0, alt = false;
  for (let i = pan.length - 1; i >= 0; i--) { let n = +pan[i]; if (alt) { n *= 2; if (n > 9) n -= 9; } sum += n; alt = !alt; }
  return sum % 10 === 0;
}

function brandOf(pan) {
  if (/^4/.test(pan)) return 'Visa';
  if (/^(5[1-5]|2(2[2-9]|[3-6]\d|7[01]|720))/.test(pan)) return 'Mastercard';
  if (/^3[47]/.test(pan)) return 'Amex';
  return 'Karta';
}

export function listCards() {
  return store.cards();
}

export function addCard({ label, holder, pan, exp, cvv, limitPln }) {
  pan = String(pan || '').replace(/[\s-]/g, '');
  if (!/^\d{13,19}$/.test(pan) || !luhn(pan)) throw new Error('Invalid card number');
  const m = String(exp || '').match(/^(\d{2})\s*\/\s*(\d{2}|\d{4})$/);
  if (!m || +m[1] < 1 || +m[1] > 12) throw new Error('Expiry must look like MM/YY');
  cvv = String(cvv || '').trim();
  if (!/^\d{3,4}$/.test(cvv)) throw new Error('Invalid CVV');
  label = String(label || '').trim().slice(0, 40) || `${brandOf(pan)} ${pan.slice(-4)}`;
  const id = crypto.randomUUID();
  const entry = { id, label, brand: brandOf(pan), last4: pan.slice(-4), limitPln: Math.max(0, Math.floor(Number(limitPln) || 0)) };
  store.addCard({ ...entry, enc: seal({ pan, exp: `${m[1]}/${m[2].slice(-2)}`, cvv, holder: String(holder || '').trim().slice(0, 60) }) });
  return entry;
}

export function removeCard(id) {
  return store.removeCard(id);
}

export function revealForCheckout(id) {
  const enc = store.cardSecret(id);
  if (!enc) throw new Error('Card not found');
  return open(enc);
}
