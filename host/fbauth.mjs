// Gzowo Concierge - Firebase Auth for the host: signs in a technical account with email and password and keeps the ID token fresh.
const SIGN_IN = 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
const REFRESH = 'https://securetoken.googleapis.com/v1/token';

export function createAuth({ apiKey, email, password }) {
  let idToken = null, refreshToken = null, expiresAt = 0, inflight = null;

  async function signIn() {
    const res = await fetch(`${SIGN_IN}?key=${apiKey}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }), signal: AbortSignal.timeout(15000) });
    const j = await res.json();
    if (!res.ok) throw new Error(`Firebase sign-in failed: ${j.error?.message || res.status}`);
    idToken = j.idToken; refreshToken = j.refreshToken; expiresAt = Date.now() + Number(j.expiresIn) * 1000 - 120000;
  }

  async function refresh() {
    const res = await fetch(`${REFRESH}?key=${apiKey}`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `grant_type=refresh_token&refresh_token=${encodeURIComponent(refreshToken)}`, signal: AbortSignal.timeout(15000) });
    const j = await res.json();
    if (!res.ok) { refreshToken = null; throw new Error(j.error?.message || `refresh ${res.status}`); }
    idToken = j.id_token; refreshToken = j.refresh_token; expiresAt = Date.now() + Number(j.expires_in) * 1000 - 120000;
  }

  return {
    async token() {
      if (idToken && Date.now() < expiresAt) return idToken;
      inflight ||= (async () => { try { if (refreshToken) { try { await refresh(); return; } catch {} } await signIn(); } finally { inflight = null; } })();
      await inflight;
      return idToken;
    },
    invalidate() { expiresAt = 0; },
  };
}
