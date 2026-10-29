// Gzowo Concierge - sends WhatsApp messages from Jurek's WhatsApp on the main Mac, through the Concierge Mac app, with the signature added in code.
import { waSend } from '../whatsapp.mjs';

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
    run: ({ to, text }) => waSend({ to, text }),
  },
];
