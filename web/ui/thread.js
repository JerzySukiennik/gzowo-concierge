// Gzowo Concierge - conversation thread: messages, goo-merged tool step groups, errors, working indicator, living empty state, stick-to-bottom scrolling.
import { icon, toolIcon, orbSvg } from './icons.js';
import { renderMarkdown } from './markdown.js';
import { createGoo, gooOn } from './glass.js';
import { createFace, followPointer } from '../face.js';

const STATUS_TEXT = { running: 'w toku', done: 'gotowe', failed: 'nie udało się' };

function greeting() {
  const h = new Date().getHours();
  return h < 5 ? 'Dobrej nocy' : h < 12 ? 'Dzień dobry' : h < 18 ? 'Miłego popołudnia' : 'Dobry wieczór';
}

export function createThread({ log, root, onStick }) {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const steps = new Map();
  const bubbles = new Map();
  let stick = true, animate = false, busy = false, lockUntil = 0, lastGroup = null, working = null, empty = null, emptyFace = null, emptyFollow = null;

  const nearBottom = () => log.scrollHeight - log.scrollTop - log.clientHeight < 80;
  log.addEventListener('scroll', () => {
    if (performance.now() < lockUntil) return;
    const s = nearBottom();
    if (s !== stick) { stick = s; onStick?.(s); }
  }, { passive: true });

  function toEnd(smooth) {
    const top = log.scrollHeight;
    if (smooth && animate && !reduce.matches) { lockUntil = performance.now() + 600; log.scrollTo({ top, behavior: 'smooth' }); }
    else log.scrollTop = top;
    if (!stick) { stick = true; onStick?.(true); }
  }

  function el(tag, cls, html) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html != null) e.innerHTML = html;
    return e;
  }

  function dropEmpty() {
    if (emptyFollow) { emptyFollow(); emptyFollow = null; }
    if (emptyFace) { emptyFace.destroy(); emptyFace = null; }
    if (empty) { empty.remove(); empty = null; }
  }

  function place(node, kind, force) {
    dropEmpty();
    if (kind !== 'steps') lastGroup = null;
    if (animate) node.classList.add('enter');
    root.insertBefore(node, working);
    if (force || stick) toEnd(true);
  }

  function addUser(text, cid, queued) {
    if (cid && bubbles.has(cid)) {
      if (!queued) { const b = bubbles.get(cid); b.classList.remove('queued'); b.querySelector('.qs')?.remove(); }
      return;
    }
    const row = el('div', 'row user');
    const b = el('div', 'bubble' + (queued ? ' queued' : ''));
    b.textContent = text;
    row.append(b);
    if (queued) b.append(el('span', 'qs', 'Czeka na wysłanie'));
    if (cid) bubbles.set(cid, b);
    place(row, 'user', true);
  }

  function addAssistant(text) {
    const row = el('div', 'row bot');
    const md = el('div', 'md');
    md.append(renderMarkdown(text));
    const copy = el('button', 'copy', icon('copy', 16));
    copy.type = 'button'; copy.setAttribute('aria-label', 'Kopiuj odpowiedź');
    copy.onclick = async () => {
      try { await navigator.clipboard.writeText(text); } catch { return; }
      copy.innerHTML = icon('check', 16); copy.classList.add('ok');
      setTimeout(() => { copy.innerHTML = icon('copy', 16); copy.classList.remove('ok'); }, 1400);
    };
    row.append(md, copy);
    place(row, 'bot');
    return row;
  }

  function addError(message, retry) {
    root.querySelectorAll('.retry').forEach(b => b.remove());
    const row = el('div', 'row note');
    row.setAttribute('role', 'alert');
    row.append(el('span', 'n-ic', icon('alert', 18, true)));
    const t = el('span', 'n-t'); t.textContent = message; row.append(t);
    if (retry) {
      const b = el('button', 'retry pill', icon('retry', 16) + '<span>Ponów</span>');
      b.type = 'button'; b.onclick = () => { row.remove(); retry(); };
      row.append(b);
    }
    place(row, 'note');
    return row;
  }

  function glyph(status) {
    if (status === 'running') return '<i class="spin"></i>';
    if (status === 'failed') return icon('close', 16);
    return icon('check', 16);
  }

  function setStep(key, name, summary, status, error) {
    let s = steps.get(key);
    if (!s) {
      const node = el('div', 'step', `<span class="s-ic">${icon(toolIcon(name), 17)}</span><span class="s-body"><span class="s-t"></span><span class="s-err"></span></span><span class="s-st" aria-hidden="true"></span><span class="sr"></span>`);
      node.setAttribute('role', 'listitem');
      let first = false;
      if (!lastGroup || !lastGroup.isConnected) {
        lastGroup = el('div', 'steps');
        lastGroup.setAttribute('role', 'list');
        lastGroup.setAttribute('aria-label', 'Kroki Concierge');
        lastGroup._goo = createGoo(lastGroup);
        lastGroup.append(node);
        place(lastGroup, 'steps');
        first = true;
      } else {
        if (animate) node.classList.add('enter');
        lastGroup.append(node);
        if (stick) toEnd(true);
      }
      lastGroup._goo.track(node, { enter: animate && !first && gooOn() });
      s = { node, status: '' };
      steps.set(key, s);
    }
    s.node.querySelector('.s-t').textContent = summary;
    const err = s.node.querySelector('.s-err');
    err.textContent = status === 'failed' && error ? error : '';
    if (s.status !== status) {
      s.status = status;
      s.node.className = 'step ' + status + (s.node.classList.contains('enter') ? ' enter' : '');
      s.node.querySelector('.s-st').innerHTML = glyph(status);
      s.node.querySelector('.sr').textContent = STATUS_TEXT[status] || '';
    }
    refreshWorking();
    return s.node;
  }

  function runningCount() { let n = 0; steps.forEach(s => { if (s.status === 'running') n++; }); return n; }

  function refreshWorking() {
    const show = busy && runningCount() === 0;
    if (show && !working) {
      dropEmpty();
      working = el('div', 'working', orbSvg('mini') + '<span>Pracuję</span>');
      working.setAttribute('role', 'status');
      if (animate) working.classList.add('enter');
      root.append(working);
      lastGroup = null;
      if (stick) toEnd(true);
    } else if (!show && working) { working.remove(); working = null; }
  }

  function setBusy(b) { busy = !!b; refreshWorking(); }

  function showEmpty(suggestions, pick) {
    if (root.children.length || empty) return;
    empty = el('div', 'empty');
    empty.innerHTML = `<div class="hero"><canvas class="hero-face" aria-hidden="true"></canvas></div><p class="hello">${greeting()}</p><h2>Co mam dla Ciebie zrobić?</h2>`;
    const list = el('div', 'suggest');
    list.setAttribute('role', 'list');
    suggestions.forEach(([ic, text]) => {
      const b = el('button', 'sug glass', `<span class="sug-ic">${icon(ic, 20)}</span><span class="sug-t"></span>`);
      b.type = 'button'; b.setAttribute('role', 'listitem');
      b.querySelector('.sug-t').textContent = text;
      b.onclick = () => pick(text);
      list.append(b);
    });
    empty.append(list);
    root.append(empty);
    emptyFace = createFace(empty.querySelector('.hero-face'));
    emptyFace.start();
    emptyFollow = followPointer(emptyFace);
  }

  function clear() {
    dropEmpty();
    root.querySelectorAll('.steps').forEach(g => g._goo?.destroy());
    root.textContent = '';
    steps.clear(); bubbles.clear();
    lastGroup = null; working = null; stick = true; onStick?.(true);
    refreshWorking();
  }

  return {
    addUser, addAssistant, addError, setStep, setBusy, showEmpty, clear, toEnd,
    get stick() { return stick; },
    hasContent: () => root.children.length > 0 && !empty,
    setAnimate(v) { animate = v; },
  };
}
