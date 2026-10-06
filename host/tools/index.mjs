// Gzowo Concierge - tool registry and per-action approval policy.
import { store } from '../db.mjs';
import { calendarTools } from './calendar.mjs';
import { webTools } from './web.mjs';
import { memoryTools } from './memory.mjs';
import { skillTools } from './skills.mjs';
import { paymentTools } from './payment.mjs';

export const tools = [...calendarTools, ...webTools, ...memoryTools, ...skillTools, ...paymentTools];

export const LOCKED_ASK = new Set(['payment.pay', 'message.new_contact']);
export const toolByName = Object.fromEntries(tools.map(t => [t.name, t]));

export const declarations = () => [{
  functionDeclarations: tools.map(t => ({ name: t.name, description: t.description, parameters: t.parameters })),
}];

export function policyFor(tool) {
  if (LOCKED_ASK.has(tool.action)) return 'ask';
  const overrides = store.getSetting('policies', {});
  return overrides[tool.action] || tool.policy;
}

export function listPolicies() {
  const overrides = store.getSetting('policies', {});
  const actions = {};
  for (const t of tools) if (!t.hidden) actions[t.action] = LOCKED_ASK.has(t.action) ? 'ask' : overrides[t.action] || t.policy;
  return actions;
}

export function setPolicy(action, policy) {
  if (!['auto', 'ask'].includes(policy)) throw new Error('policy must be auto or ask');
  if (LOCKED_ASK.has(action) && policy === 'auto') throw new Error('This action always needs approval.');
  if (!tools.some(t => t.action === action)) throw new Error(`unknown action ${action}`);
  const overrides = store.getSetting('policies', {});
  overrides[action] = policy;
  store.setSetting('policies', overrides);
  return listPolicies();
}
