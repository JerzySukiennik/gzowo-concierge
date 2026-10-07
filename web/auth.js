// Gzowo Concierge - e-mail and password sign-in screen, session check, sign-out.
import { getFb } from './firebase.js';

const $ = id => document.getElementById(id);
const MESSAGES = {
  'auth/invalid-credential': 'Nieprawidłowy e-mail lub hasło.',
  'auth/wrong-password': 'Nieprawidłowy e-mail lub hasło.',
  'auth/user-not-found': 'Nieprawidłowy e-mail lub hasło.',
  'auth/invalid-email': 'Ten adres e-mail wygląda niepoprawnie.',
  'auth/too-many-requests': 'Za dużo prób. Odczekaj chwilę i spróbuj ponownie.',
  'auth/network-request-failed': 'Brak połączenia z internetem.',
  'auth/user-disabled': 'To konto jest wyłączone.',
};

export async function requireLogin(appEl) {
  const { auth, authMod } = await getFb();
  await auth.authStateReady();
  if (auth.currentUser) return auth.currentUser;
  const login = $('login'), form = $('loginForm'), email = $('loginEmail'), pass = $('loginPass'), err = $('loginErr'), go = $('loginGo'), reset = $('loginReset');
  login.classList.add('on');
  appEl.inert = true;
  return new Promise(resolve => {
    const say = (text, info) => { err.textContent = text; err.classList.toggle('info', !!info); };
    email.oninput = pass.oninput = () => { say(''); email.removeAttribute('aria-invalid'); pass.removeAttribute('aria-invalid'); };
    form.onsubmit = async e => {
      e.preventDefault();
      if (!email.value.trim() || !pass.value) { say('Wpisz e-mail i hasło.'); return; }
      go.disabled = true; say('');
      try {
        const cred = await authMod.signInWithEmailAndPassword(auth, email.value.trim(), pass.value);
        login.classList.remove('on'); appEl.inert = false; pass.value = '';
        resolve(cred.user);
      } catch (error) {
        say(MESSAGES[error.code] || 'Nie udało się zalogować. Spróbuj ponownie.');
        if (/credential|password|user-not-found/.test(error.code || '')) pass.setAttribute('aria-invalid', 'true');
        go.disabled = false; pass.focus();
      }
    };
    reset.onclick = async () => {
      const v = email.value.trim();
      if (!v) { say('Wpisz najpierw swój e-mail.'); email.focus(); return; }
      try { await authMod.sendPasswordResetEmail(auth, v); } catch (error) { if (error.code === 'auth/network-request-failed') { say(MESSAGES[error.code]); return; } }
      say('Jeśli to konto istnieje, wysłałem na nie link do ustawienia hasła. Sprawdź też spam.', true);
    };
    email.focus({ preventScroll: true });
  });
}

export async function accountEmail() {
  const { auth } = await getFb();
  return auth.currentUser ? auth.currentUser.email : null;
}

export async function signOutNow() {
  const { auth, authMod } = await getFb();
  await authMod.signOut(auth);
}
