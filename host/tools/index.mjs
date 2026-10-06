// Gzowo Concierge - tool registry and per-action approval policy.
import { store } from '../db.mjs';
import { calendarTools } from './calendar.mjs';
import { webTools } from './web.mjs';
import { memoryTools } from './memory.mjs';

export const tools = [...calendarTools, ...webTools, ...memoryTools];
export const toolByName = Object.fromEntries(tools.map(t => [t.name, t]));

export const declarations = () => [{
  functionDeclarations: tools.map(t => ({ name: t.name, description: t.description, parameters: t.parameters })),
}];

export function policyFor(tool) {
  const overrides = store.getSetting('policies', {});
  return overrides[tool.action] || tool.policy;
}

export function listPolicies() {
  const overrides = store.getSetting('policies', {});
  const actions = {};
  for (const t of tools) actions[t.action] = overrides[t.action] || t.policy;
  return actions;
}

export function setPolicy(action, policy) {
  if (!['auto', 'ask'].includes(policy)) throw new Error('policy must be auto or ask');
  if (!tools.some(t => t.action === action)) throw new Error(`unknown action ${action}`);
  const overrides = store.getSetting('policies', {});
  overrides[action] = policy;
  store.setSetting('policies', overrides);
  return listPolicies();
}
