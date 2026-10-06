// Gzowo Concierge - live voice: bridges a browser WebSocket (/live) to Gemini Live with the same tools and approvals as text chat.
import { config } from './config.mjs';
import { store } from './db.mjs';
import { bus, THREAD, snapshot } from './commands.mjs';
import { callTool } from './agent.mjs';
import { systemPrompt } from './prompt.mjs';
import { declarations } from './tools/index.mjs';
import { acceptUpgrade } from './ws.mjs';
import { live } from './live-state.mjs';
import crypto from 'node:crypto';

const MODEL = process.env.LIVE_MODEL || 'models/gemini-3.8-live';
const VOICE = process.env.LIVE_VOICE || 'Puck';
const API = process.env.LIVE_API || 'v1beta';
const URL_BASE = `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.${API}.GenerativeService.BidiGenerateContent`;

const VOICE_RULES = `You are now in a live spoken conversation, so everything you say is read aloud. Speak natural, correct Polish in one to three short sentences. No lists, no markdown, no symbols or emoji; say dates, times and amounts the way a person says them. If you need a tool that takes a moment, begin with a very short acknowledgement such as "Już sprawdzam." Do not read out long results: give the essential answer and offer more. If a tool needs approval, say briefly that it waits for his approval on the screen.`;


export function handleLiveUpgrade(req, socket) {
  const rid = () => crypto.randomUUID();
  let upstream = null, ready = false, closed = false;
  let turn = { user: '', assistant: '', rid: rid() };
  let state = 'connecting';
  const pendingAudio = [];

  const conn = acceptUpgrade(req, socket, {
    onMessage: (data, binary) => {
      if (binary) { sendAudio(data); return; }
      let m; try { m = JSON.parse(data); } catch { return; }
      if (m.type === 'text' && typeof m.text === 'string' && m.text.trim()) sendUp({ realtimeInput: { text: m.text.trim() } });
      else if (m.type === 'end') close();
    },
    onClose: () => close(true),
  });
  if (!conn) return;
  const me = { notify: note => sendUp({ realtimeInput: { text: note } }) };
  live.sessions.add(me);

  const tell = o => conn.open && conn.sendText(JSON.stringify(o));
  const setState = s => { if (s !== state) { state = s; tell({ type: 'state', state: s }); } };
  const emit = e => { const ev = { ...e, rid: turn.rid }; tell(ev); bus.emit('event', ev); };

  function sendUp(o) { if (upstream?.readyState === 1 && ready) upstream.send(JSON.stringify(o)); }
  function sendAudio(buf) {
    if (!ready) { if (pendingAudio.length < 50) pendingAudio.push(buf); return; }
    sendUp({ realtimeInput: { audio: { mimeType: 'audio/pcm;rate=16000', data: Buffer.from(buf).toString('base64') } } });
  }

  function flushTurn() {
    const u = turn.user.trim(), a = turn.assistant.trim();
    if (u) { store.addContent(THREAD, { role: 'user', parts: [{ text: u }] }); bus.emit('event', { type: 'user', text: u, rid: turn.rid, cid: turn.rid }); }
    if (a) { store.addContent(THREAD, { role: 'model', parts: [{ text: a }] }); bus.emit('event', { type: 'text', text: a, rid: turn.rid }); }
    turn = { user: '', assistant: '', rid: rid() };
  }

  function connectUpstream() {
    upstream = new WebSocket(`${URL_BASE}?key=${encodeURIComponent(config.apiKey)}`);
    upstream.addEventListener('open', () => {
      upstream.send(JSON.stringify({
        setup: {
          model: MODEL,
          generationConfig: { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: VOICE } }, languageCode: 'pl-PL' } },
          systemInstruction: { parts: [{ text: `${systemPrompt()}\n\n${VOICE_RULES}` }] },
          tools: declarations(),
          inputAudioTranscription: {},
          outputAudioTranscription: {},
        },
      }));
    });
    upstream.addEventListener('message', async ev => {
      let m; try { m = JSON.parse(ev.data instanceof Blob ? await ev.data.text() : String(ev.data)); } catch { return; }
      onUpstream(m);
    });
    upstream.addEventListener('error', () => { tell({ type: 'error', message: 'Połączenie z modelem głosowym nie powiodło się.' }); });
    upstream.addEventListener('close', e => { if (!closed) { tell({ type: 'error', message: `Model głosowy rozłączył się (${e.code}${e.reason ? ': ' + e.reason.slice(0, 80) : ''}).` }); close(); } });
  }

  async function onUpstream(m) {
    if (m.setupComplete) {
      ready = true; tell({ type: 'ready' }); setState('listening');
      for (const b of pendingAudio.splice(0)) sendAudio(b);
      return;
    }
    if (m.toolCall) {
      setState('thinking');
      const responses = [];
      for (const call of m.toolCall.functionCalls || []) {
        const response = await callTool(THREAD, { name: call.name, args: call.args }, emit);
        responses.push({ id: call.id, name: call.name, response });
      }
      bus.emit('state'); tell({ type: 'pending', pending: Object.fromEntries(snapshot().pending.map(p => [p.id, p.summary])) });
      sendUp({ toolResponse: { functionResponses: responses } });
      return;
    }
    const sc = m.serverContent;
    if (!sc) return;
    if (sc.interrupted) { tell({ type: 'interrupted' }); setState('listening'); }
    for (const part of sc.modelTurn?.parts || []) {
      if (part.inlineData?.data) { setState('speaking'); conn.open && conn.sendBinary(Buffer.from(part.inlineData.data, 'base64')); }
    }
    if (sc.inputTranscription?.text) { turn.user += sc.inputTranscription.text; tell({ type: 'transcript', role: 'user', text: turn.user, final: false }); }
    if (sc.outputTranscription?.text) { turn.assistant += sc.outputTranscription.text; tell({ type: 'transcript', role: 'assistant', text: turn.assistant, final: false }); }
    if (sc.turnComplete) {
      tell({ type: 'transcript', role: 'assistant', text: turn.assistant, final: true });
      flushTurn(); setState('listening');
    }
  }

  function close(fromSocket) {
    if (closed) return;
    closed = true;
    flushTurn();
    live.sessions.delete(me);
    try { upstream?.close(1000); } catch {}
    if (!fromSocket) conn.close(1000);
  }

  if (!config.apiKey) { tell({ type: 'error', message: 'Brak klucza Gemini.' }); close(); return; }
  tell({ type: 'state', state: 'connecting' });
  connectUpstream();
}

bus.on('approval-result', r => {
  const verb = r.approved ? (r.ok === false ? 'was approved but failed' : 'was approved and executed') : 'was denied';
  for (const s of live.sessions) s.notify(`[System: the user's decision on "${r.summary}": it ${verb}. Tell him the outcome in one short sentence.]`);
});
