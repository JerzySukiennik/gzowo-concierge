// Gzowo Concierge - connector registry: public listing, connect/setup/disconnect, activity checks and policy labels.
import { connectors, refreshGh, googleCallback } from './defs.mjs';

export { googleCallback };
const byId = Object.fromEntries(connectors.map(c => [c.id, c]));

const BASE_LABELS = {
  'calendar.read': 'Kalendarz: czytanie', 'calendar.write': 'Kalendarz: dodawanie i zmiany', 'calendar.delete': 'Kalendarz: usuwanie',
  'web.search': 'Wyszukiwanie w sieci', 'memory.write': 'Zapamiętywanie', 'skills.write': 'Umiejętności: zapisywanie',
};

export const connectorTools = connectors.flatMap(c => c.tools || []);
export const isActive = id => { const c = byId[id]; return !c || c.state() === 'connected'; };

export function policyLabels() {
  const labels = { ...BASE_LABELS };
  for (const t of connectorTools) if (t.label) labels[t.action] = t.label;
  return labels;
}

export function listConnectors() {
  return connectors.map(c => ({
    id: c.id, name: c.name, category: c.category, description: c.description, icon: c.icon || c.id, kind: c.kind,
    state: c.state(), account: c.account?.(), capabilities: c.capabilities || [], note: c.note,
    tools: (c.tools || []).map(t => ({ name: t.name, label: t.label, action: t.action, policy: t.policy })),
  }));
}

export function connectorSummary() {
  const states = {}, meta = {};
  for (const c of connectors) { states[c.id] = c.state(); meta[c.id] = { name: c.name, icon: c.icon || c.id, category: c.category || 'Inne' }; }
  return { states, meta };
}

export function activeConnectorLines() {
  return connectors.filter(c => c.state() === 'connected' && c.tools?.length).map(c => `- ${c.name}: ${c.tools.map(t => t.name).join(', ')}`);
}

export const plannedNames = () => connectors.filter(c => c.state() === 'planned').map(c => c.name);

export async function connect(id) {
  const c = byId[id];
  if (!c) throw new Error('Nieznany konektor.');
  if (c.state() === 'planned') throw new Error('Ten konektor jest jeszcze w planach.');
  return c.connect();
}

export async function setup(id, values) {
  const c = byId[id];
  if (!c?.setup) throw new Error('Ten konektor nie wymaga konfiguracji.');
  await c.setup(values);
  return { ok: true };
}

export async function disconnect(id) {
  const c = byId[id];
  if (!c) throw new Error('Nieznany konektor.');
  await c.disconnect();
  return { ok: true };
}

refreshGh();
setInterval(refreshGh, 120000).unref?.();
