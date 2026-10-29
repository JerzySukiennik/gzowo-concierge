// Gzowo Concierge - sends WhatsApp messages from Jurek's WhatsApp on the main Mac, through the Concierge Mac app, with the signature added in code.
import { macRequest } from '../mac-link.mjs';
import { waFindChat, isClassGroup } from '../whatsapp.mjs';
import { DISCLAIMER, SIGNATURE } from '../classplan-render.mjs';

export function signed(chat, text) {
  const body = String(text || '').trim();
  return isClassGroup(chat) ? `${body}\n\n_${DISCLAIMER}_\n${SIGNATURE}` : `${body}\n\n${SIGNATURE}`;
}

export const whatsappTools = [
  {
    name: 'whatsapp_send',
    action: 'whatsapp.send',
    policy: 'auto',
    description: "Send a WhatsApp message from Jurek's own WhatsApp on the main Mac to a person or a group, picked by the chat name as he says it (contact name, group name or phone number). It goes out right away: he decided he does not want to confirm messages. Write only what he wants to say, in Polish, in his voice; the signature is added automatically, never add one yourself. If the result lists several chats, ask him which one he means and call again with that exact name.",
    parameters: { type: 'object', properties: {
      to: { type: 'string', description: 'Chat name as he said it, or an exact name from a previous candidates list' },
      text: { type: 'string', description: 'The message text, without any signature' },
    }, required: ['to', 'text'] },
    summarize: a => `Wysyłam na WhatsAppie do ${a.to}`,
    async run({ to, text }) {
      if (!String(text || '').trim()) throw new Error('Pusta wiadomość.');
      const found = waFindChat(to);
      if (!found.chat) {
        if (!found.candidates.length) throw new Error(`Nie mam w WhatsAppie czatu „${to}”.`);
        if (found.duplicate) throw new Error(`W WhatsAppie są co najmniej dwa czaty o nazwie „${found.candidates[0].name}”, nie umiem ich rozróżnić.`);
        return { sent: false, candidates: found.candidates.map(c => `${c.name} (${c.kind === 'group' ? 'grupa' : 'osoba'})`), note: 'Ask him which one he means, then call again with that exact name.' };
      }
      const message = signed(found.chat.name, text);
      await macRequest('whatsapp', { query: found.chat.name, target: found.chat.name, text: message }, 45000);
      return { sent: true, to: found.chat.name, kind: found.chat.kind, text: message };
    },
  },
];
