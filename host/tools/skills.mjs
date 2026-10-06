// Gzowo Concierge - tools that let the agent load and teach itself skills.
import { listSkills, getSkill, createSkill, deleteSkill } from '../skills.mjs';

export const skillTools = [
  {
    name: 'use_skill',
    action: 'skills.read',
    policy: 'auto',
    hidden: true,
    description: 'Load the full instructions of a skill. Call this first whenever the request matches a skill from the skills list in the system prompt, then follow the instructions.',
    parameters: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] },
    summarize: a => `Wczytuję umiejętność: ${a.name}`,
    run: async ({ name }) => {
      const s = getSkill(name);
      if (!s) return { ok: false, error: `No skill "${name}". Available: ${listSkills().map(x => x.name).join(', ')}` };
      return { instructions: s.body };
    },
  },
  {
    name: 'create_skill',
    action: 'skills.write',
    policy: 'auto',
    description: 'Save a new reusable skill when Jurek teaches you a routine or a way of doing something he wants repeated ("zawsze rób tak", "nauczę cię jak..."). Write the instructions as clear imperative steps that a future you can follow without this conversation.',
    parameters: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Slug: lowercase letters, digits, hyphens' },
        description: { type: 'string', description: 'One line: when to use this skill' },
        instructions: { type: 'string', description: 'Step by step instructions' },
      },
      required: ['name', 'description', 'instructions'],
    },
    summarize: a => `Zapisuję umiejętność: ${a.name}`,
    run: async a => ({ ok: true, ...createSkill(a) }),
  },
  {
    name: 'delete_skill',
    action: 'skills.write',
    policy: 'auto',
    description: 'Delete a skill that Jurek created (built-in skills cannot be deleted).',
    parameters: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] },
    summarize: a => `Usuwam umiejętność: ${a.name}`,
    run: async ({ name }) => ({ ok: deleteSkill(name) }),
  },
];
