// Gzowo Concierge - approval card markup shared by the dock and the live screen.
export function buildAsk(summary, onAnswer) {
  const c = document.createElement('div');
  c.className = 'ask';
  c.setAttribute('role', 'group');
  c.innerHTML = '<div class="ask-head"><span class="live-dot"></span><span>Czeka na Twoją zgodę</span></div><p class="ask-q"></p><div class="ask-btns"><button type="button" class="btn tonal" data-v="0">Nie</button><button type="button" class="btn ink" data-v="1">Tak</button></div>';
  c.querySelector('.ask-q').textContent = summary;
  c.setAttribute('aria-label', summary);
  c.querySelectorAll('button').forEach(b => { b.onclick = () => onAnswer(b.dataset.v === '1'); });
  return c;
}
