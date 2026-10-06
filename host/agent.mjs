// Gzowo Concierge - the agent loop: Gemini function calling with per-action approval.
import { generate, textOf } from './gemini.mjs';
import { store } from './db.mjs';
import { systemPrompt } from './prompt.mjs';
import { declarations, toolByName, policyFor } from './tools/index.mjs';

const MAX_STEPS = 8;

export async function callTool(thread, call, emit) {
  const tool = toolByName[call.name];
  const args = call.args || {};
  if (!tool) return { ok: false, error: 'unknown tool' };
  const summary = tool.summarize(args);
  if (policyFor(tool) === 'ask') {
    const ask = tool.askText ? tool.askText(args) : summary;
    const id = store.createApproval({ thread, action: tool.action, tool: tool.name, args, summary: ask });
    emit({ type: 'approval', id, summary: ask });
    return { ok: false, status: 'pending_approval', note: 'Waiting for the user to approve in the app.' };
  }
  emit({ type: 'tool', name: tool.name, summary, status: 'running' });
  const response = await executeTool(tool, args);
  emit({ type: 'tool', name: tool.name, summary, status: response.ok ? 'done' : 'failed', error: response.error });
  return response;
}

async function executeTool(tool, args) {
  try {
    const result = await tool.run(args);
    return { ok: true, ...(typeof result === 'object' && result !== null ? result : { result }) };
  } catch (err) {
    return { ok: false, error: String(err.message || err) };
  }
}

export async function run(thread, userText, emit) {
  store.addContent(thread, { role: 'user', parts: [{ text: userText }] });
  await loop(thread, emit);
}

async function loop(thread, emit) {
  for (let step = 0; step < MAX_STEPS; step++) {
    const contents = store.loadContents(thread).map(({ role, parts }) => ({ role, parts }));
    let res = await generate({ system: systemPrompt(), contents, tools: declarations() });
    let cand = res.candidates?.[0];
    let parts = cand?.content?.parts;
    for (let retry = 0; retry < 2 && !parts?.length; retry++) {
      const afterTool = contents.at(-1)?.parts.some(p => p.functionResponse);
      const extra = afterTool ? [{ role: 'user', parts: [{ text: '[System: tool calls are done. Now reply to the user briefly in Polish.]' }] }] : [];
      res = await generate({ system: systemPrompt(), contents: [...contents, ...extra], tools: declarations() });
      cand = res.candidates?.[0];
      parts = cand?.content?.parts;
    }
    if (!parts?.length) {
      const reason = cand?.finishReason || res.promptFeedback?.blockReason || 'empty response';
      emit({ type: 'error', message: `Model returned nothing (${reason})` });
      return;
    }
    store.addContent(thread, { role: 'model', parts });

    const text = textOf(parts);
    if (text.trim()) emit({ type: 'text', text });

    const calls = parts.filter(p => p.functionCall).map(p => p.functionCall);
    if (!calls.length) return;

    const responses = [];
    for (const call of calls) responses.push({ functionResponse: { name: call.name, response: await callTool(thread, call, emit) } });
    store.addContent(thread, { role: 'user', parts: responses });
  }
  emit({ type: 'error', message: 'Too many steps, stopped.' });
}

export async function resolveApproval(id, approve, emit, { quiet = false } = {}) {
  const a = store.getApproval(id);
  if (!a || a.status !== 'pending') throw new Error('approval not found or already resolved');
  const tool = toolByName[a.tool];
  if (!approve) {
    store.resolveApproval(id, 'denied');
    const note = `[System: the user DENIED this action: ${a.summary}. Do not retry it.]`;
    store.addContent(a.thread, { role: 'user', parts: [{ text: note }] });
    if (quiet) return { approved: false, summary: a.summary, note };
    await loop(a.thread, emit);
    return;
  }
  const doing = tool.summarize(a.args);
  emit({ type: 'tool', name: tool.name, summary: doing, status: 'running' });
  const response = await executeTool(tool, a.args);
  emit({ type: 'tool', name: tool.name, summary: doing, status: response.ok ? 'done' : 'failed', error: response.error });
  store.resolveApproval(id, response.ok ? 'done' : 'failed', response);
  const note = `[System: the user APPROVED "${a.summary}" and it was executed. Result: ${JSON.stringify(response)}]`;
  store.addContent(a.thread, { role: 'user', parts: [{ text: note }] });
  if (quiet) return { approved: true, ok: response.ok, summary: a.summary, note };
  await loop(a.thread, emit);
}
