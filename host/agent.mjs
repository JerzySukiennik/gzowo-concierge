// Gzowo Concierge - the agent loop: Gemini function calling with per-action approval.
import { generate, textOf } from './gemini.mjs';
import { store } from './db.mjs';
import { config } from './config.mjs';
import { declarations, toolByName, policyFor } from './tools/index.mjs';

const MAX_STEPS = 8;

function nowLine() {
  const d = new Date();
  const fmt = (o) => new Intl.DateTimeFormat('pl-PL', { timeZone: config.timezone, ...o }).format(d);
  const iso = new Intl.DateTimeFormat('sv-SE', {
    timeZone: config.timezone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  }).format(d).replace(' ', 'T');
  return `${fmt({ weekday: 'long' })}, ${iso} (${config.timezone})`;
}

function systemPrompt() {
  const facts = store.facts();
  const memory = facts.length ? facts.map(f => `[${f.id}] ${f.text}`).join('\n') : '(empty)';
  return `You are Gzowo Concierge, Jurek's personal assistant. You get things done for him; you are not a chatbot that explains what it could do.

Jurek is 14, lives in Warsaw. Reply in Polish unless he writes in another language. Casual and concise, like a capable friend. No filler, no disclaimers, no apologies, no "Jasne!" openers. Plain text only, no markdown headings, no bold. Short lists are fine. Do not use dashes as sentence punctuation (use commas, periods or colons).

What you can do right now: read, add, edit and delete events in his iCloud calendar (with optional alarms), search the live web, and remember facts about him.
What you cannot do yet: send iMessages, order food, make phone calls, pay for anything, read email, or manage tasks outside the calendar. If he asks for something you cannot do, say so in one short sentence and offer the closest thing you can do. When he asks what you can do, list only the real capabilities above in two or three short lines. Never claim abilities you do not have (for example planning lessons or study schedules beyond putting events in the calendar).

Rules:
- Act first. If a request is clear enough, use your tools immediately instead of asking. Ask one short question only when a missing detail would make the action wrong.
- Never claim you did something unless a tool result confirmed it. If a tool fails, say so plainly and what you tried. If web_search fails, do NOT answer the factual question from memory as if it were checked: say you could not check live, and if you still give a figure, label it as unverified and possibly outdated.
- For the calendar, use local times without timezone. Whenever you mention a date, compare it with the current time below: say "jutro", "od jutra" or the weekday for future dates, and never describe something that starts in the future as happening now. Resolve relative dates ("jutro", "w piątek", "za tydzień") from the current time below. When he asks about "this week" or "tomorrow", look at the calendar before answering.
- If a tool returns status "pending_approval", tell him in one short sentence that it waits for his OK in the app. Do not retry it.
- Save durable facts about Jurek with the remember tool when he states them (not temporary things). Mention it only with a few words at the end of your reply (for example "Zapamiętane.").

Current time: ${nowLine()}

What you remember about Jurek:
${memory}`;
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
    if (!parts?.length && contents.at(-1)?.parts.some(p => p.functionResponse)) {
      const nudge = [...contents, { role: 'user', parts: [{ text: '[System: tool calls are done. Now reply to the user briefly in Polish.]' }] }];
      res = await generate({ system: systemPrompt(), contents: nudge, tools: declarations() });
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
    for (const call of calls) {
      const tool = toolByName[call.name];
      const args = call.args || {};
      if (!tool) {
        responses.push({ functionResponse: { name: call.name, response: { ok: false, error: 'unknown tool' } } });
        continue;
      }
      const summary = tool.summarize(args);
      if (policyFor(tool) === 'ask') {
        const ask = tool.askText ? tool.askText(args) : summary;
        const id = store.createApproval({ thread, action: tool.action, tool: tool.name, args, summary: ask });
        emit({ type: 'approval', id, summary: ask });
        responses.push({ functionResponse: { name: call.name, response: { ok: false, status: 'pending_approval', note: 'Waiting for the user to approve in the app.' } } });
        continue;
      }
      emit({ type: 'tool', name: tool.name, summary, status: 'running' });
      const response = await executeTool(tool, args);
      emit({ type: 'tool', name: tool.name, summary, status: response.ok ? 'done' : 'failed', error: response.error });
      responses.push({ functionResponse: { name: call.name, response } });
    }
    store.addContent(thread, { role: 'user', parts: responses });
  }
  emit({ type: 'error', message: 'Too many steps, stopped.' });
}

export async function resolveApproval(id, approve, emit) {
  const a = store.getApproval(id);
  if (!a || a.status !== 'pending') throw new Error('approval not found or already resolved');
  const tool = toolByName[a.tool];
  if (!approve) {
    store.resolveApproval(id, 'denied');
    store.addContent(a.thread, { role: 'user', parts: [{ text: `[System: the user DENIED this action: ${a.summary}. Do not retry it.]` }] });
    await loop(a.thread, emit);
    return;
  }
  const doing = tool.summarize(a.args);
  emit({ type: 'tool', name: tool.name, summary: doing, status: 'running' });
  const response = await executeTool(tool, a.args);
  emit({ type: 'tool', name: tool.name, summary: doing, status: response.ok ? 'done' : 'failed', error: response.error });
  store.resolveApproval(id, response.ok ? 'done' : 'failed', response);
  store.addContent(a.thread, { role: 'user', parts: [{ text: `[System: the user APPROVED "${a.summary}" and it was executed. Result: ${JSON.stringify(response)}]` }] });
  await loop(a.thread, emit);
}
