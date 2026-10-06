// Gzowo Concierge - payment tools. The model only ever sees masked cards; paying is not wired yet and will always require approval.
import { listCards } from '../vault.mjs';

export const paymentTools = [
  {
    name: 'payment_methods',
    action: 'payment.read',
    policy: 'auto',
    hidden: true,
    description: 'List the cards saved in the vault: label, brand, last 4 digits and per-payment limit in PLN (0 means no limit set). Full card numbers are never available to you.',
    parameters: { type: 'object', properties: {} },
    summarize: () => 'Sprawdzam zapisane karty',
    run: async () => ({ cards: listCards() }),
  },
];
