// Gzowo Concierge - announcements for the room speaker: queued here, fetched and spoken by MacPetite.
import crypto from 'node:crypto';

const queue = [];

export function announce(text) {
  const t = String(text || '').trim().slice(0, 400);
  if (!t) return null;
  const item = { id: crypto.randomUUID(), text: t, ts: Date.now() };
  queue.push(item);
  if (queue.length > 20) queue.shift();
  return item;
}

export function takeAnnouncements() {
  const fresh = queue.filter(a => Date.now() - a.ts < 30 * 60e3);
  queue.length = 0;
  return fresh;
}
