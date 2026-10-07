// Gzowo Concierge - lazy Firebase SDK bootstrap shared by login and the relay transport.
import { firebaseConfig } from './config.js';

const SDK = 'https://www.gstatic.com/firebasejs/12.4.0/';
let cache = null;

export function getFb() {
  cache ||= (async () => {
    const [{ initializeApp }, authMod, dbMod] = await Promise.all([import(SDK + 'firebase-app.js'), import(SDK + 'firebase-auth.js'), import(SDK + 'firebase-database.js')]);
    const app = initializeApp(firebaseConfig);
    return { app, authMod, dbMod, auth: authMod.getAuth(app), db: dbMod.getDatabase(app) };
  })();
  return cache;
}
