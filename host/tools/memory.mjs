// Gzowo Concierge - long-term memory tools (facts about the user, injected into every prompt).
import { store } from '../db.mjs';

export const memoryTools = [
  {
    name: 'remember',
    action: 'memory.write',
    policy: 'auto',
    description: 'Save a durable fact about the user or their life (preferences, people, routines, addresses, allergies). One short self-contained sentence. Do not store temporary things.',
    parameters: { type: 'object', properties: { fact: { type: 'string' } }, required: ['fact'] },
    summarize: a => `Remember: ${a.fact}`,
    run: async ({ fact }) => ({ ok: true, id: store.addFact(fact) }),
  },
  {
    name: 'forget',
    action: 'memory.write',
    policy: 'auto',
    description: 'Delete a saved fact by its id (ids are shown in the memory list of the system prompt).',
    parameters: { type: 'object', properties: { id: { type: 'number' } }, required: ['id'] },
    summarize: a => `Forget fact ${a.id}`,
    run: async ({ id }) => ({ ok: store.removeFact(id) }),
  },
];
