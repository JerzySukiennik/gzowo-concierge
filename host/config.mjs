// Gzowo Concierge - config: loads .env, exposes constants shared by the host.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const envPath = path.join(ROOT, '.env');

function readEnv() {
  const env = {};
  if (!fs.existsSync(envPath)) return env;
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m) env[m[1]] = m[2];
  }
  return env;
}

const env = { ...readEnv(), ...process.env };

if (!env.CONCIERGE_TOKEN) {
  env.CONCIERGE_TOKEN = crypto.randomBytes(24).toString('hex');
  fs.appendFileSync(envPath, `CONCIERGE_TOKEN=${env.CONCIERGE_TOKEN}\n`, { mode: 0o600 });
}

if (!env.RELAY_SID) {
  env.RELAY_SID = crypto.randomBytes(32).toString('hex');
  fs.appendFileSync(envPath, `RELAY_SID=${env.RELAY_SID}\n`, { mode: 0o600 });
}

export const config = {
  apiKey: env.GEMINI_API_KEY || '',
  token: env.CONCIERGE_TOKEN,
  port: Number(env.PORT || 2040),
  host: env.HOST || '0.0.0.0',
  chatModel: env.CHAT_MODEL || 'gemini-3.5-flash-lite',
  smartModel: env.SMART_MODEL || 'gemini-3.5-flash',
  timezone: env.TZ_NAME || 'Europe/Warsaw',
  dataDir: path.join(ROOT, 'data'),
  calApp: path.join(ROOT, 'bin', 'ConciergeCal.app'),
  webDir: path.join(ROOT, 'web'),
  relay: {
    dbUrl: (env.FIREBASE_DB_URL || 'https://gzowo-concierge-default-rtdb.europe-west1.firebasedatabase.app').replace(/\/$/, ''),
    sid: env.RELAY_SID,
    hostingUrl: (env.HOSTING_URL || 'https://gzowo-concierge.web.app').replace(/\/$/, ''),
    enabled: env.RELAY !== 'off',
  },
};

fs.mkdirSync(config.dataDir, { recursive: true });
