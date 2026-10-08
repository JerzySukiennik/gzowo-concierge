// Gzowo Concierge - Web Push sender (VAPID + RFC 8291 aes128gcm) with no dependencies; subscriptions live in settings.
import crypto from 'node:crypto';
import { store } from './db.mjs';
import { getSecret, putSecret } from './secrets.mjs';

const SUB = 'mailto:gzowotesla@gmail.com';
const b64 = buf => Buffer.from(buf).toString('base64url');
const unb64 = s => Buffer.from(String(s), 'base64url');

function vapid() {
  let k = getSecret('vapid');
  if (!k) {
    const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const jwk = privateKey.export({ format: 'jwk' });
    const pub = Buffer.concat([Buffer.from([4]), unb64(jwk.x), unb64(jwk.y)]);
    k = { d: jwk.d, x: jwk.x, y: jwk.y, pub: b64(pub) };
    putSecret('vapid', k);
  }
  return k;
}

export const vapidPublicKey = () => vapid().pub;

function jwt(audience) {
  const k = vapid();
  const head = b64(JSON.stringify({ typ: 'JWT', alg: 'ES256' }));
  const body = b64(JSON.stringify({ aud: audience, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: SUB }));
  const key = crypto.createPrivateKey({ key: { kty: 'EC', crv: 'P-256', d: k.d, x: k.x, y: k.y }, format: 'jwk' });
  const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key, dsaEncoding: 'ieee-p1363' });
  return `${head}.${body}.${b64(sig)}`;
}

export function encrypt(sub, payload) {
  const uaPub = unb64(sub.keys.p256dh), auth = unb64(sub.keys.auth);
  const ecdh = crypto.createECDH('prime256v1');
  const asPub = ecdh.generateKeys();
  const secret = ecdh.computeSecret(uaPub);
  const salt = crypto.randomBytes(16);
  const ikm = Buffer.from(crypto.hkdfSync('sha256', secret, auth, Buffer.concat([Buffer.from('WebPush: info\0'), uaPub, asPub]), 32));
  const cek = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: aes128gcm\0'), 16));
  const nonce = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: nonce\0'), 12));
  const cipher = crypto.createCipheriv('aes-128-gcm', cek, nonce);
  const enc = Buffer.concat([cipher.update(Buffer.concat([Buffer.from(payload), Buffer.from([2])])), cipher.final(), cipher.getAuthTag()]);
  const rs = Buffer.alloc(4); rs.writeUInt32BE(4096);
  return Buffer.concat([salt, rs, Buffer.from([asPub.length]), asPub, enc]);
}

export const subscriptions = () => store.getSetting('pushSubs', []);
const saveSubs = list => store.setSetting('pushSubs', list);

export function addSubscription(sub, ua = '') {
  if (!sub?.endpoint || !/^https:\/\//.test(sub.endpoint) || !sub.keys?.p256dh || !sub.keys?.auth) throw new Error('Nieprawidłowa subskrypcja powiadomień.');
  const list = subscriptions().filter(s => s.endpoint !== sub.endpoint);
  list.push({ endpoint: sub.endpoint, keys: { p256dh: sub.keys.p256dh, auth: sub.keys.auth }, ua: String(ua).slice(0, 120), ts: Date.now() });
  saveSubs(list.slice(-8));
  return list.length;
}

export function removeSubscription(endpoint) {
  const list = subscriptions();
  const next = list.filter(s => s.endpoint !== endpoint);
  saveSubs(next);
  return list.length - next.length;
}

async function sendOne(sub, message) {
  const url = new URL(sub.endpoint);
  const res = await fetch(sub.endpoint, {
    method: 'POST',
    headers: {
      authorization: `vapid t=${jwt(url.origin)}, k=${vapid().pub}`,
      'content-encoding': 'aes128gcm', 'content-type': 'application/octet-stream', ttl: '43200', urgency: 'normal',
    },
    body: encrypt(sub, JSON.stringify(message)),
    signal: AbortSignal.timeout(15000),
  });
  if (res.status === 404 || res.status === 410) { removeSubscription(sub.endpoint); return { ok: false, gone: true }; }
  if (!res.ok) return { ok: false, status: res.status, detail: (await res.text()).slice(0, 120) };
  return { ok: true };
}

export async function pushAll(message) {
  const results = await Promise.all(subscriptions().map(s => sendOne(s, message).catch(e => ({ ok: false, detail: String(e.message || e) }))));
  return { sent: results.filter(r => r.ok).length, failed: results.filter(r => !r.ok), total: results.length };
}
