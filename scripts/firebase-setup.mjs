// Gzowo Concierge - one-time Firebase login setup: creates the host technical account and the owner account, grants both access, and mails the owner a password-setup link.
// Requires Email/Password sign-in to be enabled once in the Firebase console and a fresh `firebase` CLI login (any firebase command refreshes it).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const P = 'gzowo-concierge';
const DB = 'https://gzowo-concierge-default-rtdb.europe-west1.firebasedatabase.app';
const API_KEY = fs.readFileSync(path.join(ROOT, 'web', 'config.js'), 'utf8').match(/apiKey:\s*'([^']+)'/)[1];
const OWNER_EMAIL = process.argv[2];
if (!OWNER_EMAIL) { console.error('usage: node scripts/firebase-setup.mjs <owner e-mail>'); process.exit(1); }
const HOST_EMAIL = 'host@concierge.gzowo.fun';

const cli = JSON.parse(fs.readFileSync(process.env.HOME + '/.config/configstore/firebase-tools.json', 'utf8'));
const tok = cli.tokens.access_token;
if (Date.now() > cli.tokens.expires_at) { console.error('CLI token expired: run any `firebase` command first.'); process.exit(1); }
const H = { authorization: 'Bearer ' + tok, 'content-type': 'application/json', 'x-goog-user-project': P };

async function lookup(email) {
  const r = await fetch(`https://identitytoolkit.googleapis.com/v1/projects/${P}/accounts:lookup`, { method: 'POST', headers: H, body: JSON.stringify({ email: [email] }) });
  const j = await r.json();
  if (!r.ok) throw new Error('lookup: ' + (j.error?.message || r.status));
  return j.users?.[0]?.localId || null;
}

async function ensureUser(email, password) {
  const existing = await lookup(email);
  if (existing) return { uid: existing, created: false };
  const r = await fetch(`https://identitytoolkit.googleapis.com/v1/projects/${P}/accounts`, { method: 'POST', headers: H, body: JSON.stringify({ email, password, emailVerified: true }) });
  const j = await r.json();
  if (!r.ok) throw new Error('create ' + email + ': ' + (j.error?.message || r.status));
  return { uid: j.localId, created: true };
}

const rand = () => crypto.randomBytes(24).toString('base64url');

const host = await ensureUser(HOST_EMAIL, rand());
const envPaths = [path.join(ROOT, '.env'), path.join(process.env.HOME, '.gzowo-concierge', '.env')];
let hostPassword = null;
if (host.created) {
  hostPassword = rand();
  const r = await fetch(`https://identitytoolkit.googleapis.com/v1/projects/${P}/accounts:update`, { method: 'POST', headers: H, body: JSON.stringify({ localId: host.uid, password: hostPassword }) });
  if (!r.ok) throw new Error('set host password: ' + ((await r.json()).error?.message || r.status));
  for (const p of envPaths) {
    if (!fs.existsSync(p)) continue;
    const kept = fs.readFileSync(p, 'utf8').split('\n').filter(l => !/^HOST_(EMAIL|PASSWORD)=/.test(l)).join('\n').replace(/\n*$/, '\n');
    const kept2 = kept.split('\n').filter(l => !/^FIREBASE_API_KEY=/.test(l)).join('\n').replace(/\n*$/, '\n');
    fs.writeFileSync(p, `${kept2}FIREBASE_API_KEY=${API_KEY}\nHOST_EMAIL=${HOST_EMAIL}\nHOST_PASSWORD=${hostPassword}\n`, { mode: 0o600 });
  }
  console.log('host account created; credentials written to .env files (not printed)');
} else console.log('host account already exists (password unchanged; if .env lacks HOST_PASSWORD, delete the account in the console and rerun)');

const owner = await ensureUser(OWNER_EMAIL, rand());
console.log('owner account:', owner.created ? 'created' : 'exists', OWNER_EMAIL);

for (const [label, uid] of [['host', host.uid], ['owner', owner.uid]]) {
  const r = await fetch(`${DB}/acl/${uid}.json?access_token=${tok}`, { method: 'PUT', headers: { 'content-type': 'application/json' }, body: 'true' });
  console.log('acl', label, r.status);
}

const dis = await fetch(`https://identitytoolkit.googleapis.com/admin/v2/projects/${P}/config?updateMask=client.permissions`, { method: 'PATCH', headers: H, body: JSON.stringify({ client: { permissions: { disabledUserSignup: true } } }) });
console.log('disable public sign-up:', dis.status, dis.ok ? '' : '(not available on this plan; access is still limited by the ACL)');

if (owner.created) {
  const m = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${API_KEY}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ requestType: 'PASSWORD_RESET', email: OWNER_EMAIL }) });
  console.log('password setup email to', OWNER_EMAIL, m.status);
}
