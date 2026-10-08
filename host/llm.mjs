// Gzowo Concierge - chat model switch: Gemini (default) or Claude Haiku 5.5, behind the same Gemini-shaped request/response used by the agent loop.
import { generate as gemini } from './gemini.mjs';
import { store } from './db.mjs';
import { getSecret, putSecret, delSecret } from './secrets.mjs';

const HAIKU = 'claude-haiku-5-5';
const SKIP_SIG = 'skip_thought_signature_validator';

export const anthropicReady = () => !!getSecret('anthropic')?.apiKey;

export function getChatModel() {
  return store.getSetting('chatModel', 'gemini') === 'haiku' && anthropicReady() ? 'haiku' : 'gemini';
}

export function modelInfo() {
  return { chat: getChatModel(), haikuReady: anthropicReady(), models: { gemini: 'Gemini 3.5 Flash Lite', haiku: 'Claude Haiku 5.5' } };
}

export function setChatModel(m) {
  if (!['gemini', 'haiku'].includes(m)) throw new Error('Nieznany model.');
  if (m === 'haiku' && !anthropicReady()) throw new Error('Najpierw zapisz klucz Anthropic.');
  store.setSetting('chatModel', m);
  return modelInfo();
}

async function call(body, secret) {
  let lastErr;
  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json', 'x-api-key': secret.apiKey, 'anthropic-version': '2023-06-01',
        ...(secret.workspaceId ? { 'anthropic-workspace-id': secret.workspaceId } : {}),
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(60000),
    });
    if (res.ok) return res.json();
    const text = await res.text();
    let msg = text.slice(0, 300);
    try { msg = JSON.parse(text).error?.message || msg; } catch {}
    lastErr = new Error(`Claude ${res.status}: ${msg}`);
    lastErr.status = res.status;
    if (![429, 500, 502, 503, 529].includes(res.status)) break;
    await new Promise(r => setTimeout(r, 800 * (attempt + 1) ** 2));
  }
  throw lastErr;
}

export async function saveAnthropicKey({ apiKey, workspaceId }) {
  const key = String(apiKey || '').trim(), ws = String(workspaceId || '').trim();
  if (!/^sk-ant-[\w-]{20,}$/.test(key)) throw new Error('To nie wygląda na klucz Anthropic.');
  const secret = { apiKey: key, ...(ws ? { workspaceId: ws } : {}) };
  await call({ model: HAIKU, max_tokens: 8, messages: [{ role: 'user', content: 'ok' }] }, secret);
  putSecret('anthropic', secret);
  return modelInfo();
}

export function removeAnthropicKey() {
  delSecret('anthropic');
  if (store.getSetting('chatModel', 'gemini') === 'haiku') store.setSetting('chatModel', 'gemini');
  return modelInfo();
}

const safeId = s => String(s).replace(/[^\w-]/g, '_').slice(0, 64);

export function toMessages(contents) {
  const messages = [];
  let pending = [];
  contents.forEach((c, ci) => {
    const blocks = [];
    const results = [];
    let n = 0;
    for (const p of c.parts || []) {
      if (p.thought) continue;
      if (p.text && p.text.trim()) blocks.push({ type: 'text', text: p.text });
      else if (p.functionCall) {
        const id = safeId(p.functionCall.id || `toolu_${ci}_${n++}`);
        blocks.push({ type: 'tool_use', id, name: p.functionCall.name, input: p.functionCall.args || {} });
        pending.push({ id, name: p.functionCall.name });
      } else if (p.functionResponse) {
        const i = Math.max(0, pending.findIndex(x => x.name === p.functionResponse.name));
        const hit = pending.splice(i, 1)[0];
        if (hit) results.push({ type: 'tool_result', tool_use_id: hit.id, content: JSON.stringify(p.functionResponse.response ?? {}) });
      }
    }
    const content = [...results, ...blocks];
    if (!content.length) return;
    const role = c.role === 'model' ? 'assistant' : 'user';
    const last = messages.at(-1);
    if (last && last.role === role) last.content.push(...content); else messages.push({ role, content });
  });
  return messages;
}

async function claude({ system, contents, tools }) {
  const secret = getSecret('anthropic');
  if (!secret?.apiKey) throw new Error('Brak klucza Anthropic.');
  const decls = (tools?.[0]?.functionDeclarations || []).map(d => ({ name: d.name, description: d.description, input_schema: d.parameters || { type: 'object', properties: {} } }));
  const body = { model: HAIKU, max_tokens: 2048, system, messages: toMessages(contents) };
  if (decls.length) body.tools = decls;
  const res = await call(body, secret);
  const parts = [];
  for (const b of res.content || []) {
    if (b.type === 'text' && b.text) parts.push({ text: b.text });
    else if (b.type === 'tool_use') parts.push({ functionCall: { name: b.name, args: b.input || {}, id: b.id }, thoughtSignature: SKIP_SIG });
  }
  return { candidates: [{ content: { role: 'model', parts }, finishReason: res.stop_reason }], usage: res.usage };
}

export function chatGenerate(args) {
  return getChatModel() === 'haiku' ? claude(args) : gemini(args);
}
