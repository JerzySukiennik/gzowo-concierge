// Gzowo Concierge - "Awatar" studio: live preview that follows the cursor, shape grid, sixteen face previews, black/white/auto ink control, motion chips and a random-shape button.
import { createFace, followPointer } from '../face.js';
import { drawStatic } from '../bot-paint.js';
import { SHAPES, COLORS, FACE_ORDER, FACES } from '../bot-data.js';
import { getAvatar, setAvatar, randomAvatar, onAvatar } from './avatar.js';

const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const MOVES = [['hop', 'Skok'], ['nod', 'Kiwnięcie'], ['blink', 'Mrugnięcie'], ['wiggle', 'Wiwat'], ['startle', 'Zdziwienie']];

export function avatarPage(page) {
  const wrap = el('div', 'studio');
  const stage = el('div', 'st-stage glass', '<canvas class="st-face" aria-hidden="true"></canvas><p class="st-hint">Patrzy na Twój kursor. Dotknij go, żeby go szturchnąć.</p>');
  wrap.append(stage);
  const face = createFace(stage.querySelector('.st-face'), { autoSleep: false, greet: false });
  const follow = followPointer(face);

  const thumbs = [];
  function tile(label, pressed, onPick, opts) {
    const b = el('button', 'st-tile', '<canvas aria-hidden="true"></canvas><span></span>');
    b.type = 'button'; b.setAttribute('aria-pressed', String(pressed)); b.setAttribute('aria-label', label);
    b.querySelector('span').textContent = label;
    const cv = b.querySelector('canvas');
    cv.dataset.size = '56';
    b.onclick = onPick;
    thumbs.push({ cv, opts });
    return b;
  }
  const section = (title, node, note) => {
    const s = el('section', 'st-sec', '<h3></h3>');
    s.querySelector('h3').textContent = title;
    s.append(node);
    if (note) { const p = el('p', 'foot'); p.textContent = note; s.append(p); }
    wrap.append(s);
  };

  const shapeGrid = el('div', 'st-grid');
  const shapeBtns = SHAPES.map(s => { const b = tile(s.name, getAvatar().shape === s.id, () => setAvatar({ shape: s.id }), a => ({ shape: s.id, color: a.color, face: 'neutral', ground: false })); b.dataset.k = s.id; shapeGrid.append(b); return b; });
  section('Kształt', shapeGrid);

  let faceTimer = 0, picked = '';
  const faceGrid = el('div', 'st-grid');
  const faceBtns = FACE_ORDER.map(f => {
    const b = tile(FACES[f].name, false, () => {
      clearTimeout(faceTimer);
      if (picked === f) { picked = ''; face.setFace(null); sync(); return; }
      picked = f; face.setFace(f); sync();
      faceTimer = setTimeout(() => { picked = ''; face.setFace(null); sync(); }, 4200);
    }, a => ({ shape: a.shape, color: a.color, face: f, ground: false }));
    b.dataset.k = f; faceGrid.append(b); return b;
  });
  section('Miny', faceGrid, 'Mina zmienia się sama, zależnie od tego, co robię. Tu możesz je tylko obejrzeć.');

  const seg = el('div', 'st-seg');
  seg.setAttribute('role', 'group'); seg.setAttribute('aria-label', 'Kolor awatara');
  const swBtns = COLORS.map(c => {
    const b = el('button', null, '<span></span>');
    b.type = 'button'; b.setAttribute('aria-pressed', 'false'); b.dataset.k = c.id;
    b.firstChild.textContent = c.name;
    b.onclick = () => setAvatar({ color: c.id });
    seg.append(b);
    return b;
  });
  section('Kolor', seg, 'Auto: czarny w jasnym trybie, biały w ciemnym.');

  const moves = el('div', 'st-moves');
  MOVES.forEach(([k, label]) => {
    const b = el('button', 'pill', '<span></span>');
    b.type = 'button'; b.firstChild.textContent = label;
    b.onclick = () => face.pulse(k);
    moves.append(b);
  });
  section('Ruch', moves);

  const surprise = el('button', 'btn ink wide', icon2() + '<span>Losowy kształt</span>');
  surprise.type = 'button';
  surprise.onclick = () => { setAvatar(randomAvatar()); face.pulse('hop'); };
  wrap.append(surprise);
  wrap.append(el('p', 'foot', 'Wybór zapisuje się na Macu i na telefonie.'));
  page.append(wrap);

  function sync() {
    const a = getAvatar();
    shapeBtns.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.k === a.shape)));
    swBtns.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.k === a.color)));
    faceBtns.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.k === picked)));
  }

  function paintThumbs() {
    const a = getAvatar();
    thumbs.forEach(t => drawStatic(t.cv, t.opts(a)));
    sync();
  }

  const unsub = onAvatar(paintThumbs);
  face.start();
  requestAnimationFrame(() => requestAnimationFrame(paintThumbs));

  return { destroy() { clearTimeout(faceTimer); unsub(); follow(); face.destroy(); } };
}

function icon2() {
  return '<svg class="ic" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10.75 4.75l1.55 4.45 4.45 1.55-4.45 1.55-1.55 4.45-1.55-4.45L4.75 10.75l4.45-1.55z"/><path d="M18 3.75v3M16.5 5.25h3M17.5 15.75v3M16 17.25h3"/></svg>';
}
