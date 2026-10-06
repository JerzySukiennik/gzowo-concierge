// Gzowo Concierge - tiny safe markdown renderer (DOM nodes only, no innerHTML): paragraphs, lists, code, bold, italic, links.
const INLINE = /(`[^`\n]+`)|(\*\*[^*\n]+\*\*)|(\*[^*\s][^*\n]*\*)|(\[[^\]\n]+\]\(https?:\/\/[^)\s]+\))|(https?:\/\/[^\s)<]+)/;

function inline(parent, text) {
  let last = 0, m;
  const re = new RegExp(INLINE.source, 'g');
  while ((m = re.exec(text))) {
    if (m.index > last) parent.append(text.slice(last, m.index));
    const t = m[0];
    let el;
    if (m[1]) { el = document.createElement('code'); el.textContent = t.slice(1, -1); }
    else if (m[2]) { el = document.createElement('strong'); inline(el, t.slice(2, -2)); }
    else if (m[3]) { el = document.createElement('em'); inline(el, t.slice(1, -1)); }
    else if (m[4]) {
      const i = t.indexOf('](');
      el = link(t.slice(i + 2, -1), t.slice(1, i));
    } else el = link(t.replace(/[.,;:!?]+$/, ''), null);
    parent.append(el);
    if (m[5]) { const trail = t.slice(t.replace(/[.,;:!?]+$/, '').length); if (trail) parent.append(trail); }
    last = m.index + t.length;
  }
  if (last < text.length) parent.append(text.slice(last));
}

function link(href, label) {
  const a = document.createElement('a');
  a.href = href; a.target = '_blank'; a.rel = 'noopener noreferrer';
  a.textContent = label ?? href.replace(/^https?:\/\//, '');
  return a;
}

const isBullet = l => /^\s*[-*•]\s+/.test(l);
const isOrdered = l => /^\s*\d+[.)]\s+/.test(l);
const isHead = l => /^#{1,3}\s+/.test(l);
const isQuote = l => /^>\s?/.test(l);
const isRule = l => /^\s*(-{3,}|\*{3,})\s*$/.test(l);
const isFence = l => /^\s*```/.test(l);

export function renderMarkdown(src) {
  const frag = document.createDocumentFragment();
  const lines = String(src).replace(/\r/g, '').split('\n');
  let i = 0;
  while (i < lines.length) {
    const l = lines[i];
    if (!l.trim()) { i++; continue; }
    if (isFence(l)) {
      const buf = []; i++;
      while (i < lines.length && !isFence(lines[i])) buf.push(lines[i++]);
      i++;
      const pre = document.createElement('pre'), code = document.createElement('code');
      code.textContent = buf.join('\n'); pre.append(code); frag.append(pre);
    } else if (isRule(l)) { frag.append(document.createElement('hr')); i++; }
    else if (isHead(l)) {
      const p = document.createElement('p'); p.className = 'h';
      inline(p, l.replace(/^#{1,3}\s+/, '')); frag.append(p); i++;
    } else if (isBullet(l) || isOrdered(l)) {
      const ordered = isOrdered(l);
      const list = document.createElement(ordered ? 'ol' : 'ul');
      while (i < lines.length && (ordered ? isOrdered(lines[i]) : isBullet(lines[i]))) {
        const li = document.createElement('li');
        inline(li, lines[i].replace(ordered ? /^\s*\d+[.)]\s+/ : /^\s*[-*•]\s+/, ''));
        list.append(li); i++;
      }
      frag.append(list);
    } else if (isQuote(l)) {
      const bq = document.createElement('blockquote'), buf = [];
      while (i < lines.length && isQuote(lines[i])) buf.push(lines[i++].replace(/^>\s?/, ''));
      inline(bq, buf.join('\n')); frag.append(bq);
    } else {
      const p = document.createElement('p'), buf = [];
      while (i < lines.length && lines[i].trim() && !isFence(lines[i]) && !isHead(lines[i]) && !isBullet(lines[i]) && !isOrdered(lines[i]) && !isQuote(lines[i]) && !isRule(lines[i])) buf.push(lines[i++]);
      buf.forEach((b, n) => { if (n) p.append(document.createElement('br')); inline(p, b); });
      frag.append(p);
    }
  }
  return frag;
}
